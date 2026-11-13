//
//  LocalAudioServer.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 13.11.26.
//  Copyright (c) 2026 Chrizz Gelbach. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import Network

// MARK: - LocalAudioServer

/// Minimal HTTP/1.1 file server on the loopback interface for player integration tests.
///
/// Supports `GET`/`HEAD` with single byte ranges and can simulate network faults:
/// going offline (open connections are reset, new ones refused), cutting a response
/// after a number of bytes, throttling the transfer rate and answering with an HTTP error.
final class LocalAudioServer: @unchecked Sendable {
  struct Request: CustomStringConvertible {
    let method: String
    let path: String
    let range: String?
    let date: Date

    var description: String { "\(method) \(path) \(range ?? "-")" }
  }

  private struct File {
    let data: Data
    let contentType: String
  }

  private let queue = DispatchQueue(label: "LocalAudioServer")
  private let lock = NSLock()
  private var listener: NWListener?
  private var files = [String: File]()
  private var connections = [ObjectIdentifier: NWConnection]()
  private var _requests = [Request]()
  private var _isOffline = false
  private var _bytesPerSecond: Int?
  private var _dropAfterBytes: Int?
  private var _httpStatus: Int?
  private(set) var port: UInt16 = 0

  static let chunkSize = 4096

  // MARK: Lifecycle

  func start() async throws {
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    parameters.allowLocalEndpointReuse = true
    let listener = try NWListener(using: parameters, on: .any)
    self.listener = listener
    listener.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(), Error>) in
      let once = Once()
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          once.run { continuation.resume() }
        case let .failed(error):
          once.run { continuation.resume(throwing: error) }
        case let .waiting(error):
          // e.g. no loopback interface, fail instead of hanging the test run
          listener.cancel()
          once.run { continuation.resume(throwing: error) }
        case .cancelled:
          once.run { continuation.resume(throwing: CancellationError()) }
        default:
          break
        }
      }
      listener.start(queue: queue)
    }
    port = listener.port?.rawValue ?? 0
  }

  func stop() {
    listener?.cancel()
    listener = nil
    resetAllConnections()
  }

  // MARK: Content

  func serve(path: String, data: Data, contentType: String) {
    lock.withLock { files[path] = File(data: data, contentType: contentType) }
  }

  func url(path: String) -> URL {
    URL(string: "http://127.0.0.1:\(port)\(path)")!
  }

  var requests: [Request] { lock.withLock { _requests } }

  // MARK: Faults

  /// Offline resets all open connections and refuses new ones
  var isOffline: Bool {
    get { lock.withLock { _isOffline } }
    set {
      // flag and snapshot under one lock, so a connection accepted meanwhile is either refused or reset
      let open = lock.withLock {
        _isOffline = newValue
        return newValue ? takeAllConnections() : []
      }
      open.forEach { $0.forceCancel() }
    }
  }

  /// Limits the transfer rate of every response, `nil` sends as fast as possible
  var bytesPerSecond: Int? {
    get { lock.withLock { _bytesPerSecond } }
    set { lock.withLock { _bytesPerSecond = newValue } }
  }

  /// Resets the connection of the next response with a larger body once it has sent this many
  /// body bytes (one-shot, the 2-byte probe requests don't use it up)
  var dropAfterBytes: Int? {
    get { lock.withLock { _dropAfterBytes } }
    set { lock.withLock { _dropAfterBytes = newValue } }
  }

  /// Answers every request with this status and no body, `nil` serves the files
  var httpStatus: Int? {
    get { lock.withLock { _httpStatus } }
    set { lock.withLock { _httpStatus = newValue } }
  }

  // MARK: Connection handling

  private func accept(_ connection: NWConnection) {
    let id = ObjectIdentifier(connection)
    let isAccepted = lock.withLock {
      guard !_isOffline else { return false }
      connections[id] = connection
      return true
    }
    guard isAccepted else {
      connection.forceCancel()
      return
    }
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .cancelled, .failed:
        _ = lock.withLock { self.connections.removeValue(forKey: id) }
      default:
        break
      }
    }
    connection.start(queue: queue)
    receiveHeader(connection, buffer: Data())
  }

  private func resetAllConnections() {
    let open = lock.withLock { takeAllConnections() }
    open.forEach { $0.forceCancel() }
  }

  /// Call with the lock held
  private func takeAllConnections() -> [NWConnection] {
    let open = Array(connections.values)
    connections.removeAll()
    return open
  }

  private func receiveHeader(_ connection: NWConnection, buffer: Data) {
    connection
      .receive(
        minimumIncompleteLength: 1,
        maximumLength: 16 * 1024
      ) { [weak self] data, _, isComplete, error in
        guard let self else { return }
        var buffer = buffer
        if let data { buffer.append(data) }
        if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
          let header = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
          respond(connection, header: header)
        } else if error == nil, !isComplete {
          receiveHeader(connection, buffer: buffer)
        } else {
          connection.cancel()
        }
      }
  }

  private func respond(_ connection: NWConnection, header: String) {
    let lines = header.components(separatedBy: "\r\n")
    let requestLine = lines.first?.split(separator: " ") ?? []
    guard requestLine.count >= 2 else {
      sendHead(connection, status: 400, headers: [:], then: { connection.cancel() })
      return
    }
    let method = String(requestLine[0])
    let path = String(requestLine[1])
    let range = lines.dropFirst().first { $0.lowercased().hasPrefix("range:") }
      .map { $0.dropFirst("range:".count).trimmingCharacters(in: .whitespaces) }
    let (file, status) = lock.withLock {
      _requests.append(Request(method: method, path: path, range: range, date: Date()))
      return (files[path], _httpStatus)
    }
    if let status {
      sendHead(connection, status: status, headers: ["Content-Length": "0"]) {
        connection.cancel()
      }
      return
    }
    guard let file else {
      sendHead(connection, status: 404, headers: ["Content-Length": "0"]) {
        connection.cancel()
      }
      return
    }

    let total = file.data.count
    var lower = 0
    var upper = total - 1
    var isPartial = false
    if let range {
      guard let bounds = Self.parse(range: range, total: total) else {
        // an unsatisfiable range must not silently restart the file from byte 0
        sendHead(connection, status: 416, headers: [
          "Content-Length": "0",
          "Content-Range": "bytes */\(total)",
        ]) {
          connection.cancel()
        }
        return
      }
      (lower, upper) = bounds
      isPartial = true
    }
    var headers = [
      "Content-Type": file.contentType,
      "Accept-Ranges": "bytes",
      "Content-Length": "\(upper - lower + 1)",
    ]
    if isPartial {
      headers["Content-Range"] = "bytes \(lower)-\(upper)/\(total)"
    }
    let body = file.data.subdata(in: lower ..< upper + 1)
    sendHead(connection, status: isPartial ? 206 : 200, headers: headers) { [weak self] in
      guard let self else { return }
      if method == "HEAD" {
        connection.cancel()
      } else {
        let dropAfter = lock.withLock { () -> Int? in
          guard let dropAfter = self._dropAfterBytes, body.count > dropAfter else { return nil }
          self._dropAfterBytes = nil
          return dropAfter
        }
        sendBody(connection, body: body, offset: 0, dropAfter: dropAfter)
      }
    }
  }

  private func sendHead(
    _ connection: NWConnection,
    status: Int,
    headers: [String: String],
    then completion: @escaping @Sendable () -> ()
  ) {
    var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
    for (key, value) in headers { head += "\(key): \(value)\r\n" }
    head += "Connection: close\r\n\r\n"
    connection.send(content: Data(head.utf8), completion: .contentProcessed { error in
      if error == nil { completion() }
    })
  }

  private func sendBody(_ connection: NWConnection, body: Data, offset: Int, dropAfter: Int?) {
    guard offset < body.count else {
      connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
        connection.cancel()
      })
      return
    }
    if let dropAfter, offset >= dropAfter {
      connection.forceCancel()
      return
    }
    var end = min(offset + Self.chunkSize, body.count)
    if let dropAfter, offset < dropAfter { end = min(end, dropAfter) }
    let chunk = body.subdata(in: offset ..< end)
    connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
      guard let self, error == nil else { return }
      if let rate = bytesPerSecond, rate > 0 {
        let delay = Double(chunk.count) / Double(rate)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
          self?.sendBody(connection, body: body, offset: end, dropAfter: dropAfter)
        }
      } else {
        sendBody(connection, body: body, offset: end, dropAfter: dropAfter)
      }
    })
  }

  // MARK: Helper

  /// Parses `bytes=a-b`, `bytes=a-` and `bytes=-n`
  static func parse(range: String, total: Int) -> (Int, Int)? {
    guard range.hasPrefix("bytes="), total > 0 else { return nil }
    let parts = range.dropFirst("bytes=".count)
      .split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    if parts[0].isEmpty, let suffix = Int(parts[1]) {
      return (max(0, total - suffix), total - 1)
    }
    guard let lower = Int(parts[0]), lower < total else { return nil }
    let upper = Int(parts[1]).map { min($0, total - 1) } ?? total - 1
    return lower <= upper ? (lower, upper) : nil
  }

  static func reason(_ status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 206: return "Partial Content"
    case 400: return "Bad Request"
    case 404: return "Not Found"
    case 416: return "Range Not Satisfiable"
    case 500: return "Internal Server Error"
    case 503: return "Service Unavailable"
    default: return "Status"
    }
  }

  /// 16-bit mono PCM WAV file with a sine tone
  static func makeWav(seconds: Double, sampleRate: Int = 22050, frequency: Double = 440) -> Data {
    let sampleCount = Int(seconds * Double(sampleRate))
    let dataSize = sampleCount * 2
    var data = Data(capacity: 44 + dataSize)
    func append<T: FixedWidthInteger>(_ value: T) {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36 + dataSize))
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    append(UInt32(16))
    append(UInt16(1)) // PCM
    append(UInt16(1)) // mono
    append(UInt32(sampleRate))
    append(UInt32(sampleRate * 2)) // byte rate
    append(UInt16(2)) // block align
    append(UInt16(16)) // bits per sample
    data.append(contentsOf: Array("data".utf8))
    append(UInt32(dataSize))
    for i in 0 ..< sampleCount {
      let value = sin(2 * Double.pi * frequency * Double(i) / Double(sampleRate)) * 0.2
      append(Int16(value * Double(Int16.max)))
    }
    return data
  }
}

// MARK: - Once

private final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var isDone = false

  func run(_ block: () -> ()) {
    let shouldRun = lock.withLock {
      defer { isDone = true }
      return !isDone
    }
    if shouldRun { block() }
  }
}

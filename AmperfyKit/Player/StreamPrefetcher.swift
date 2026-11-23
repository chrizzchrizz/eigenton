//
//  StreamPrefetcher.swift
//  AmperfyKit
//
//  Created by Chrizz Gelbach on 23.11.26.
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

import CoreData
import Foundation
import os.log

// MARK: - PrefetchedFile

/// An upcoming playable, downloaded as it would be streamed
struct PrefetchedFile {
  let fileURL: URL
  let streamingMaxBitrate: StreamingMaxBitratePreference
  let transcodingFormat: StreamingFormatPreference
}

// MARK: - PrefetchRequest

struct PrefetchRequest {
  let url: URL
  let httpHeaders: [String: String]
  /// Account whose client certificate is presented on mTLS challenges
  let clientCertificateAccountIdent: String?
  let streamingMaxBitrate: StreamingMaxBitratePreference
  let transcodingFormat: StreamingFormatPreference
}

typealias ProvidePrefetchRequestCallback = @MainActor (AbstractPlayable) async throws
  -> PrefetchRequest

// MARK: - StreamPrefetcher

/// Downloads the next playables of the queue while one is playing, in the format they would be
/// streamed in, so playback continues through network dead zones (e.g. in the car).
/// The files are temporary and not part of the library cache: a file is deleted as soon as its
/// playable is neither upcoming nor in the player anymore. One download runs at a time.
@MainActor
final class StreamPrefetcher {
  /// A failed download is retried after this time while its playable is still upcoming
  static let retryDelay: TimeInterval = 30
  static let defaultDirectory = FileManager.default
    .urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("StreamPrefetch", isDirectory: true)

  private let directory: URL
  private let log = OSLog(subsystem: "Amperfy", category: "StreamPrefetcher")
  private var files = [NSManagedObjectID: PrefetchedFile]()
  private var activeDownload: (objectID: NSManagedObjectID, task: Task<(), Never>)?
  private var failedDownloads = [NSManagedObjectID: Date]()

  init(directory: URL = StreamPrefetcher.defaultDirectory) {
    self.directory = directory
    Self.removeFilesOfEarlierRun(directory: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  /// Files of an earlier app run don't belong to any queue anymore. The directory is moved
  /// away and deleted in the background, so the app launch doesn't wait for it.
  private static func removeFilesOfEarlierRun(directory: URL) {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    let trash = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(directory.lastPathComponent)-\(UUID().uuidString)")
    do {
      try FileManager.default.moveItem(at: directory, to: trash)
      Task.detached(priority: .background) {
        try? FileManager.default.removeItem(at: trash)
      }
    } catch {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  /// The downloaded file of the playable, if it is complete
  func file(for playable: AbstractPlayable) -> PrefetchedFile? {
    guard let file = files[playable.objectID] else { return nil }
    guard FileManager.default.fileExists(atPath: file.fileURL.path) else {
      files[playable.objectID] = nil
      return nil
    }
    return file
  }

  func isDownloading(_ playable: AbstractPlayable) -> Bool {
    activeDownload?.objectID == playable.objectID
  }

  /// Stops downloading the playable, e.g. because it is streamed now
  func cancelDownload(of playable: AbstractPlayable) {
    guard let activeDownload, activeDownload.objectID == playable.objectID else { return }
    os_log("Cancel: %s", log: log, type: .info, playable.displayString)
    activeDownload.task.cancel()
    self.activeDownload = nil
  }

  /// Deletes the file of the playable, e.g. after its data couldn't be decoded
  func discard(_ playable: AbstractPlayable) {
    guard let file = files.removeValue(forKey: playable.objectID) else { return }
    try? FileManager.default.removeItem(at: file.fileURL)
  }

  /// Keeps the files of `upcoming` and `inUse`, deletes all others and downloads the first
  /// upcoming playable that has no file yet
  /// - Parameters:
  ///   - upcoming: playables to download, in the order they will play
  ///   - inUse: playables whose files the player may be reading
  ///   - isDownloadAllowed: false keeps the current state without starting a download
  func update(
    upcoming: [AbstractPlayable],
    inUse: [AbstractPlayable],
    isDownloadAllowed: Bool,
    provideRequest: @escaping ProvidePrefetchRequestCallback
  ) {
    let upcomingIDs = Set(upcoming.map { $0.objectID })
    let keptIDs = upcomingIDs.union(inUse.map { $0.objectID })
    for (objectID, file) in files where !keptIDs.contains(objectID) {
      files[objectID] = nil
      try? FileManager.default.removeItem(at: file.fileURL)
    }
    failedDownloads = failedDownloads.filter { upcomingIDs.contains($0.key) }
    if let activeDownload, !upcomingIDs.contains(activeDownload.objectID) {
      os_log("Cancel: no longer upcoming", log: log, type: .info)
      activeDownload.task.cancel()
      self.activeDownload = nil
    }

    guard isDownloadAllowed, activeDownload == nil else { return }
    let now = Date()
    guard let playable = upcoming.first(where: { playable in
      guard file(for: playable) == nil else { return false }
      guard let failedDate = failedDownloads[playable.objectID] else { return true }
      return now.timeIntervalSince(failedDate) >= Self.retryDelay
    }) else { return }
    startDownload(of: playable, provideRequest: provideRequest)
  }

  private func startDownload(
    of playable: AbstractPlayable,
    provideRequest: @escaping ProvidePrefetchRequestCallback
  ) {
    let objectID = playable.objectID
    let title = playable.displayString
    let fallbackContentType = playable.contentType
    os_log("Fetching %s ...", log: log, type: .info, title)
    let task = Task { @MainActor in
      do {
        let request = try await provideRequest(playable)
        try Task.checkCancellation()
        let fileURL = try await download(
          request: request,
          fallbackContentType: fallbackContentType
        )
        // canceled meanwhile: the playable isn't upcoming anymore or is streamed now
        guard !Task.isCancelled, activeDownload?.objectID == objectID else {
          try? FileManager.default.removeItem(at: fileURL)
          return
        }
        os_log(
          "Fetching %s SUCCESS (%{iec-bytes}d)",
          log: log,
          type: .info,
          title,
          CacheFileManager.shared.getFileSize(url: fileURL) ?? 0
        )
        files[objectID] = PrefetchedFile(
          fileURL: fileURL,
          streamingMaxBitrate: request.streamingMaxBitrate,
          transcodingFormat: request.transcodingFormat
        )
      } catch {
        guard !Task.isCancelled, activeDownload?.objectID == objectID else { return }
        os_log(
          "Fetching %s FAILED: %s",
          log: log,
          type: .info,
          title,
          error.localizedDescription
        )
        failedDownloads[objectID] = Date()
      }
      activeDownload = nil
    }
    activeDownload = (objectID: objectID, task: task)
  }

  private func download(request: PrefetchRequest, fallbackContentType: String?) async throws
    -> URL {
    var urlRequest = URLRequest(url: request.url)
    for (field, value) in request.httpHeaders {
      urlRequest.setValue(value, forHTTPHeaderField: field)
    }
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    let credential = ClientCertificateManager.shared
      .credential(accountIdent: request.clientCertificateAccountIdent)
    let session = URLSession(
      configuration: configuration,
      delegate: credential.map { ClientCertificateURLSessionDelegate(credential: $0) },
      delegateQueue: nil
    )
    defer { session.finishTasksAndInvalidate() }
    let (tempURL, response) = try await session.download(for: urlRequest)
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try Task.checkCancellation()

    let fileSize = CacheFileManager.shared.getFileSize(url: tempURL) ?? 0
    guard fileSize > 0 else { throw DownloadError.emptyFile }
    if let responseError = DownloadManager.validatePlayableResponse(
      statusCode: (response as? HTTPURLResponse)?.statusCode,
      mimeType: response.mimeType,
      fileSize: fileSize,
      cleansedURL: nil
    ) {
      throw responseError
    }
    // the player determines the audio format by the file extension
    let fileExtension = Self.fileExtension(
      mimeType: response.mimeType,
      transcodingFormat: request.transcodingFormat,
      fallbackContentType: fallbackContentType
    )
    let fileURL = directory.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(fileExtension)
    try FileManager.default.moveItem(at: tempURL, to: fileURL)
    return fileURL
  }

  static func fileExtension(
    mimeType: String?,
    transcodingFormat: StreamingFormatPreference,
    fallbackContentType: String?
  )
    -> String {
    if let mimeType, mimeType.lowercased().hasPrefix("audio/") {
      let fileExtension = MimeFileConverter.getFilenameExtension(mimeType: mimeType)
      if fileExtension != MimeFileConverter.filenameExtensionUnknown {
        return fileExtension
      }
    }
    switch transcodingFormat {
    case .mp3: return "mp3"
    case .aac: return "aac"
    case .raw, .serverConfig:
      return MimeFileConverter.getFilenameExtension(mimeType: fallbackContentType)
    }
  }
}

//
//  StreamPrefetcherTest.swift
//  AmperfyKitTests
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

@testable import AmperfyKit
import XCTest

@MainActor
final class StreamPrefetcherTest: XCTestCase {
  var cdHelper: CoreDataHelper!
  var library: LibraryStorage!
  var server: LocalAudioServer!
  var directory: URL!
  var prefetcher: StreamPrefetcher!
  var songA: Song!
  var songB: Song!
  var songC: Song!

  let dataA = Data(repeating: 0xA1, count: 20_000)
  let dataB = Data(repeating: 0xB2, count: 20_000)

  override func setUp() async throws {
    cdHelper = CoreDataHelper()
    library = cdHelper.createSeededStorage()
    let account = library.getAccount(info: TestAccountInfo.create1())
    songA = library.getSong(for: account, id: cdHelper.seeder.songs[0].id)
    songB = library.getSong(for: account, id: cdHelper.seeder.songs[1].id)
    songC = library.getSong(for: account, id: cdHelper.seeder.songs[2].id)
    server = LocalAudioServer()
    try await server.start()
    server.serve(path: "/a", data: dataA, contentType: "audio/mpeg")
    server.serve(path: "/b", data: dataB, contentType: "audio/mpeg")
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("StreamPrefetcherTest-\(UUID().uuidString)", isDirectory: true)
    prefetcher = StreamPrefetcher(directory: directory)
  }

  override func tearDown() async throws {
    server.stop()
    try? FileManager.default.removeItem(at: directory)
  }

  private func path(for playable: AbstractPlayable) -> String {
    playable == songA ? "/a" : playable == songB ? "/b" : "/c"
  }

  private func update(
    upcoming: [AbstractPlayable],
    inUse: [AbstractPlayable] = [],
    isDownloadAllowed: Bool = true
  ) {
    prefetcher.update(
      upcoming: upcoming,
      inUse: inUse,
      isDownloadAllowed: isDownloadAllowed
    ) { [server] playable in
      PrefetchRequest(
        url: server!.url(path: self.path(for: playable)),
        httpHeaders: [:],
        clientCertificateAccountIdent: nil,
        streamingMaxBitrate: .limit128,
        transcodingFormat: .mp3
      )
    }
  }

  private func waitUntil(
    timeout: TimeInterval = 5,
    _ condition: () -> Bool
  ) async {
    let end = Date().addingTimeInterval(timeout)
    while !condition(), Date() < end {
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  func testDownload_StoresFileInStreamingFormat() async throws {
    update(upcoming: [songA])
    XCTAssertTrue(prefetcher.isDownloading(songA))
    await waitUntil { prefetcher.file(for: songA) != nil }

    let file = try XCTUnwrap(prefetcher.file(for: songA))
    XCTAssertEqual(file.fileURL.pathExtension, "mp3")
    XCTAssertEqual(try Data(contentsOf: file.fileURL), dataA)
    XCTAssertEqual(file.streamingMaxBitrate, .limit128)
    XCTAssertEqual(file.transcodingFormat, .mp3)
    XCTAssertFalse(prefetcher.isDownloading(songA))
  }

  func testDownload_OneAtATimeInQueueOrder() async {
    update(upcoming: [songA, songB])
    XCTAssertTrue(prefetcher.isDownloading(songA))
    XCTAssertFalse(prefetcher.isDownloading(songB))
    await waitUntil { prefetcher.file(for: songA) != nil }

    update(upcoming: [songA, songB])
    XCTAssertTrue(prefetcher.isDownloading(songB))
    await waitUntil { prefetcher.file(for: songB) != nil }
    XCTAssertEqual(server.requests.map { $0.path }, ["/a", "/b"])
  }

  func testDownload_NotAllowed_StartsNothing() async {
    update(upcoming: [songA], isDownloadAllowed: false)
    XCTAssertFalse(prefetcher.isDownloading(songA))
    XCTAssertTrue(server.requests.isEmpty)
  }

  func testUpdate_KeepsFilesInUseAndDeletesTheOthers() async throws {
    update(upcoming: [songA, songB])
    await waitUntil { prefetcher.file(for: songA) != nil }
    update(upcoming: [songA, songB])
    await waitUntil { prefetcher.file(for: songB) != nil }
    let fileA = try XCTUnwrap(prefetcher.file(for: songA)).fileURL
    let fileB = try XCTUnwrap(prefetcher.file(for: songB)).fileURL

    // songA plays now, songB was removed from the queue
    update(upcoming: [], inUse: [songA], isDownloadAllowed: false)
    XCTAssertNotNil(prefetcher.file(for: songA))
    XCTAssertTrue(FileManager.default.fileExists(atPath: fileA.path))
    XCTAssertNil(prefetcher.file(for: songB))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileB.path))

    // songA has played
    update(upcoming: [], inUse: [], isDownloadAllowed: false)
    XCTAssertNil(prefetcher.file(for: songA))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileA.path))
  }

  func testUpdate_CancelsDownloadThatIsNoLongerUpcoming() async {
    server.bytesPerSecond = 4_000
    update(upcoming: [songA])
    XCTAssertTrue(prefetcher.isDownloading(songA))

    update(upcoming: [songB], isDownloadAllowed: false)
    XCTAssertFalse(prefetcher.isDownloading(songA))
    try? await Task.sleep(for: .seconds(1))
    XCTAssertNil(prefetcher.file(for: songA))
  }

  func testCancelDownload_OfStreamedPlayable() async {
    server.bytesPerSecond = 4_000
    update(upcoming: [songA])
    prefetcher.cancelDownload(of: songA)
    XCTAssertFalse(prefetcher.isDownloading(songA))
    try? await Task.sleep(for: .seconds(1))
    XCTAssertNil(prefetcher.file(for: songA))
  }

  func testFailedDownload_IsRetriedOnlyAfterDelay() async {
    server.httpStatus = 503
    update(upcoming: [songA])
    await waitUntil { !prefetcher.isDownloading(songA) }
    XCTAssertNil(prefetcher.file(for: songA))

    // the next timer tick doesn't hit the server again
    update(upcoming: [songA])
    XCTAssertFalse(prefetcher.isDownloading(songA))
    // the queue moves on to the following playable meanwhile
    update(upcoming: [songA, songB])
    XCTAssertTrue(prefetcher.isDownloading(songB))
  }

  func testFailedDownload_ErrorPageIsNotStored() async {
    server.serve(path: "/c", data: Data("<error/>".utf8), contentType: "application/xml")
    update(upcoming: [songC])
    await waitUntil { !prefetcher.isDownloading(songC) }
    XCTAssertNil(prefetcher.file(for: songC))
  }

  func testDiscard_DeletesFile() async throws {
    update(upcoming: [songA])
    await waitUntil { prefetcher.file(for: songA) != nil }
    let fileA = try XCTUnwrap(prefetcher.file(for: songA)).fileURL
    prefetcher.discard(songA)
    XCTAssertNil(prefetcher.file(for: songA))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileA.path))
  }

  func testInit_RemovesFilesOfEarlierRun() throws {
    let leftover = directory.appendingPathComponent("old.mp3")
    try Data([1, 2, 3]).write(to: leftover)
    prefetcher = StreamPrefetcher(directory: directory)
    XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
  }

  func testFileExtension() {
    XCTAssertEqual(
      StreamPrefetcher.fileExtension(
        mimeType: "audio/mpeg",
        transcodingFormat: .serverConfig,
        fallbackContentType: nil
      ),
      "mp3"
    )
    XCTAssertEqual(
      StreamPrefetcher.fileExtension(
        mimeType: "application/octet-stream",
        transcodingFormat: .aac,
        fallbackContentType: "audio/flac"
      ),
      "aac"
    )
    XCTAssertEqual(
      StreamPrefetcher.fileExtension(
        mimeType: "application/octet-stream",
        transcodingFormat: .raw,
        fallbackContentType: "audio/flac"
      ),
      "flac"
    )
    XCTAssertEqual(
      StreamPrefetcher.fileExtension(
        mimeType: nil,
        transcodingFormat: .mp3,
        fallbackContentType: "audio/flac"
      ),
      "mp3"
    )
  }
}

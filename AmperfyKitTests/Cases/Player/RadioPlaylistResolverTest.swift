//
//  RadioPlaylistResolverTest.swift
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

@testable import AmperfyKit
import XCTest

// MARK: - RadioPlaylistResolverTest

final class RadioPlaylistResolverTest: XCTestCase {
  let base = URL(string: "https://radio.example/stream/station.m3u")!

  // MARK: Parsing

  func testM3U_ExtendedWithComments_ReturnsFirstURL() {
    // the playlist from issue #777
    let content = "#EXTM3U\n#EXTINF:-1,Le Son Parisien\nhttp://stream.lesonparisien.com/hi.mp3\n"
    XCTAssertEqual(
      RadioPlaylistResolver.streamURL(in: content, format: .m3u, baseURL: base)?.absoluteString,
      "http://stream.lesonparisien.com/hi.mp3"
    )
  }

  func testM3U_WindowsLineEndingsAndBOM() {
    let content = "\u{FEFF}https://a.example/live\r\nhttps://b.example/live\r\n"
    XCTAssertEqual(
      RadioPlaylistResolver.streamURL(in: content, format: .m3u, baseURL: base)?.absoluteString,
      "https://a.example/live"
    )
  }

  func testM3U_RelativeEntry_ResolvedAgainstPlaylist() {
    XCTAssertEqual(
      RadioPlaylistResolver.streamURL(in: "live.mp3\n", format: .m3u, baseURL: base)?
        .absoluteString,
      "https://radio.example/stream/live.mp3"
    )
  }

  func testM3U_OnlyComments_ReturnsNil() {
    XCTAssertNil(RadioPlaylistResolver.streamURL(in: "#EXTM3U\n\n", format: .m3u, baseURL: base))
  }

  func testM3U_SkipsNonHTTPEntries() {
    let content = "file:///etc/hosts\nmailto:x@example.com\nhttps://ok.example/live\n"
    XCTAssertEqual(
      RadioPlaylistResolver.streamURL(in: content, format: .m3u, baseURL: base)?.absoluteString,
      "https://ok.example/live"
    )
  }

  func testPLS_ReturnsLowestFileNumber() {
    let content = """
    [playlist]
    NumberOfEntries=2
    File2=https://backup.example/live
    Title2=Backup
    File1=https://main.example/live
    Title1=Main
    Version=2
    """
    XCTAssertEqual(
      RadioPlaylistResolver.streamURL(in: content, format: .pls, baseURL: base)?.absoluteString,
      "https://main.example/live"
    )
  }

  func testPLS_NoFileEntries_ReturnsNil() {
    XCTAssertNil(RadioPlaylistResolver.streamURL(
      in: "[playlist]\nNumberOfEntries=0\n",
      format: .pls,
      baseURL: base
    ))
  }

  func testFormatOfURL() {
    XCTAssertEqual(RadioPlaylistResolver.format(ofURL: URL(string: "http://a/b.M3U")!), .m3u)
    XCTAssertEqual(RadioPlaylistResolver.format(ofURL: URL(string: "http://a/b.pls?x=1")!), .pls)
    // HLS is a different format
    XCTAssertNil(RadioPlaylistResolver.format(ofURL: URL(string: "http://a/b.m3u8")!))
    XCTAssertNil(RadioPlaylistResolver.format(ofURL: URL(string: "http://a/hi.mp3")!))
  }

  func testLooksLikePlaylist() {
    XCTAssertTrue(RadioPlaylistResolver.looksLikePlaylist(Data("#EXTM3U\n".utf8)))
    XCTAssertTrue(RadioPlaylistResolver.looksLikePlaylist(Data("[playlist]\n".utf8)))
    XCTAssertTrue(RadioPlaylistResolver.looksLikePlaylist(Data("\u{FEFF}http://a/b".utf8)))
    XCTAssertFalse(RadioPlaylistResolver.looksLikePlaylist(Data([0xFF, 0xFB, 0x90, 0x64, 0x00])))
    XCTAssertFalse(RadioPlaylistResolver.looksLikePlaylist(Data("ID3\u{04}".utf8)))
  }

  // MARK: Network

  var server: LocalAudioServer!

  override func setUp() async throws {
    server = LocalAudioServer()
    try await server.start()
  }

  override func tearDown() async throws {
    server.stop()
    server = nil
  }

  func testResolve_PlainStreamURL_Unchanged() async throws {
    let url = server.url(path: "/live.mp3")
    let resolved = try await RadioPlaylistResolver.resolve(url: url)
    XCTAssertEqual(resolved, url)
    XCTAssertTrue(server.requests.isEmpty, "no request for a stream URL")
  }

  func testResolve_M3U_ReturnsStreamURL() async throws {
    let stream = server.url(path: "/live.wav")
    server.serve(
      path: "/station.m3u",
      data: Data("#EXTM3U\n#EXTINF:-1,Station\n\(stream.absoluteString)\n".utf8),
      contentType: "audio/mpegurl"
    )
    let resolved = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.m3u"))
    XCTAssertEqual(resolved, stream)
  }

  func testResolve_PLSPointingToM3U_ResolvesBoth() async throws {
    server.serve(
      path: "/station.pls",
      data: Data("[playlist]\nFile1=/inner.m3u\n".utf8),
      contentType: "audio/x-scpls"
    )
    server.serve(path: "/inner.m3u", data: Data("/live.wav\n".utf8), contentType: "text/plain")
    let resolved = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.pls"))
    XCTAssertEqual(resolved, server.url(path: "/live.wav"))
  }

  func testResolve_PlaylistLabeledAsAudio_IsParsed() async throws {
    server.serve(
      path: "/station.m3u",
      data: Data("http://stream.example/hi.mp3\n".utf8),
      contentType: "audio/mpeg"
    )
    let resolved = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.m3u"))
    XCTAssertEqual(resolved.absoluteString, "http://stream.example/hi.mp3")
  }

  func testResolve_AudioBehindPlaylistExtension_ReturnsURL() async throws {
    server.serve(
      path: "/station.m3u",
      data: LocalAudioServer.makeWav(seconds: 2),
      contentType: "audio/wav"
    )
    let url = server.url(path: "/station.m3u")
    let resolved = try await RadioPlaylistResolver.resolve(url: url)
    XCTAssertEqual(resolved, url)
  }

  func testResolve_ServerError_Throws() async {
    server.httpStatus = 404
    do {
      _ = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.m3u"))
      XCTFail("expected an error")
    } catch {}
  }

  func testResolve_TemporaryServerError_ThrowsRetryableError() async {
    server.httpStatus = 503
    do {
      _ = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.m3u"))
      XCTFail("expected an error")
    } catch {
      // a temporary server error goes through the player's error handling, not the invalid URL path
      XCTAssertFalse(error is RadioPlaylistResolver.InvalidPlaylistError)
    }
  }

  func testResolve_EmptyPlaylist_Throws() async {
    server.serve(path: "/station.m3u", data: Data("#EXTM3U\n".utf8), contentType: "audio/x-mpegurl")
    do {
      _ = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.m3u"))
      XCTFail("expected an error")
    } catch {}
  }

  func testResolve_EndlessPlaylistLoop_ThrowsAtMaxDepth() async {
    server.serve(
      path: "/station.m3u",
      data: Data("/station.m3u\n".utf8),
      contentType: "audio/x-mpegurl"
    )
    do {
      _ = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.m3u"))
      XCTFail("expected an error")
    } catch {
      XCTAssertTrue(error is RadioPlaylistResolver.InvalidPlaylistError)
    }
    XCTAssertEqual(server.requests.count, RadioPlaylistResolver.maxDepth)
  }

  func testResolve_StreamAsOctetStreamBehindPlaylistExtension_ReturnsURL() async throws {
    var mp3Frames = Data([0xFF, 0xFB, 0x90, 0x64])
    mp3Frames.append(Data(count: 200_000))
    server.serve(path: "/live.m3u", data: mp3Frames, contentType: "application/octet-stream")
    let url = server.url(path: "/live.m3u")
    let resolved = try await RadioPlaylistResolver.resolve(url: url)
    XCTAssertEqual(resolved, url)
  }

  func testResolve_PLSExtensionWithM3UContent_IsParsed() async throws {
    server.serve(
      path: "/station.pls",
      data: Data("#EXTM3U\nhttp://stream.example/live\n".utf8),
      contentType: "audio/x-scpls"
    )
    let resolved = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.pls"))
    XCTAssertEqual(resolved.absoluteString, "http://stream.example/live")
  }

  func testResolve_HTMLPageBehindPlaylistExtension_ThrowsInvalidPlaylist() async {
    server.serve(
      path: "/station.m3u",
      data: Data("<!DOCTYPE html>\n<html>\n<body>Station moved</body>\n</html>\n".utf8),
      contentType: "text/html; charset=utf-8"
    )
    do {
      _ = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.m3u"))
      XCTFail("expected an error")
    } catch {
      XCTAssertTrue(error is RadioPlaylistResolver.InvalidPlaylistError)
    }
  }

  func testResolve_HTMLPageWithoutContentType_ThrowsInvalidPlaylist() async {
    server.serve(
      path: "/station.pls",
      data: Data("<html><head><title>Login</title></head></html>".utf8),
      contentType: "application/octet-stream"
    )
    do {
      _ = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.pls"))
      XCTFail("expected an error")
    } catch {
      XCTAssertTrue(error is RadioPlaylistResolver.InvalidPlaylistError)
    }
  }

  func testResolve_M3UTitleContainingPlaylistHeader_IsParsedAsM3U() async throws {
    server.serve(
      path: "/station.m3u",
      data: Data("#EXTM3U\n#EXTINF:-1,Best of [Playlist] Radio\nhttp://stream.example/live\n".utf8),
      contentType: "audio/x-mpegurl"
    )
    let resolved = try await RadioPlaylistResolver.resolve(url: server.url(path: "/station.m3u"))
    XCTAssertEqual(resolved.absoluteString, "http://stream.example/live")
  }

  func testResolve_NotFound_ThrowsInvalidPlaylist() async {
    do {
      _ = try await RadioPlaylistResolver.resolve(url: server.url(path: "/missing.m3u"))
      XCTFail("expected an error")
    } catch {
      XCTAssertTrue(error is RadioPlaylistResolver.InvalidPlaylistError)
    }
  }

  func testFormatOfContent() {
    XCTAssertEqual(RadioPlaylistResolver.format(ofContent: "[playlist]\nFile1=http://a"), .pls)
    XCTAssertEqual(RadioPlaylistResolver.format(ofContent: "File1=http://a\n"), .pls)
    XCTAssertEqual(RadioPlaylistResolver.format(ofContent: "#EXTM3U\nhttp://a\n"), .m3u)
    XCTAssertEqual(
      RadioPlaylistResolver.format(ofContent: "\u{FEFF}[Playlist]\r\nFile1=http://a"),
      .pls
    )
    XCTAssertEqual(
      RadioPlaylistResolver.format(ofContent: "numberofentries=1\nFile2=http://a"),
      .pls
    )
    XCTAssertEqual(
      RadioPlaylistResolver.format(ofContent: "#EXTM3U\n#EXTINF:-1,My [Playlist]\nhttp://a\n"),
      .m3u
    )
    XCTAssertEqual(RadioPlaylistResolver.format(ofContent: "http://a/file1=b\n"), .m3u)
  }

  func testLooksLikeMarkup() {
    XCTAssertTrue(RadioPlaylistResolver.looksLikeMarkup(Data("  <!DOCTYPE html>".utf8)))
    XCTAssertTrue(RadioPlaylistResolver.looksLikeMarkup(Data("\u{FEFF}<?xml version".utf8)))
    XCTAssertFalse(RadioPlaylistResolver.looksLikeMarkup(Data("#EXTM3U\n".utf8)))
    XCTAssertFalse(RadioPlaylistResolver.looksLikeMarkup(Data([0xFF, 0xFB, 0x90, 0x64])))
  }
}

// MARK: - RadioPlaylistPlayerTest

/// The player side of radio playlists: requests and preloads that wait for a playlist
@MainActor
final class RadioPlaylistPlayerTest: XCTestCase {
  var cdHelper: CoreDataHelper!
  var library: LibraryStorage!
  var account: Account!
  var mockAudioStreamingPlayer: MOCK_AudioStreamingPlayer!
  var backendPlayer: BackendAudioPlayer!
  var server: LocalAudioServer!
  var nextPlayable: AbstractPlayable?

  override func setUp() async throws {
    server = LocalAudioServer()
    try await server.start()

    cdHelper = CoreDataHelper()
    library = cdHelper.createSeededStorage()
    account = library.getAccount(info: TestAccountInfo.create1())
    mockAudioStreamingPlayer = MOCK_AudioStreamingPlayer()
    let storage = PersistentStorage(
      coreDataManager: MOCK_CoreDataManager(persistentContainer: cdHelper.persistentContainer)
    )
    let backendApi = MOCK_BackendApi()
    backendPlayer = BackendAudioPlayer(
      createAudioStreamingPlayerCB: { self.mockAudioStreamingPlayer },
      audioSessionHandler: AudioSessionHandler(),
      eventLogger: EventLogger(storage: storage),
      getBackendApiCB: { _ in backendApi },
      networkMonitor: MOCK_NetworkMonitor(),
      cacheProxy: library,
      userStatistics: library.getUserStatistics(appVersion: "")
    )
    backendPlayer.nextPlayablePreloadCB = { [weak self] in self?.nextPlayable }
  }

  override func tearDown() async throws {
    server.stop()
    server = nil
  }

  func url(path: String) -> URL {
    server.url(path: path)
  }

  var requestCount: Int {
    server.requests.count
  }

  func createRadio(url: URL) -> Radio {
    let radio = library.createRadio(account: account)
    radio.url = url.absoluteString
    return radio
  }

  /// A radio behind a .m3u link, answered after `delay`
  func createPlaylistRadio(path: String, stream: URL, delay: TimeInterval = 0) -> Radio {
    server.serve(
      path: path,
      data: Data("\(stream.absoluteString)\n".utf8),
      contentType: "audio/x-mpegurl"
    )
    if delay > 0 {
      server.delayResponses(path: path, by: delay)
    }
    return createRadio(url: url(path: path))
  }

  func play(_ playable: AbstractPlayable) {
    backendPlayer.requestToPlay(playable: playable, playbackRate: .one, autoStartPlayback: true)
  }

  func waitUntil(
    timeout: TimeInterval = 3,
    _ condition: @escaping () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
  }

  func wait(seconds: TimeInterval) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
  }

  func testPlay_SlowPlaylistReplacedByNewerRequest_DoesNotTakeOver() async {
    let slowStream = url(path: "/slow.mp3")
    let slowRadio = createPlaylistRadio(path: "/slow.m3u", stream: slowStream, delay: 0.3)
    let fastStream = url(path: "/fast.mp3")
    play(slowRadio)
    play(createRadio(url: fastStream))
    await waitUntil { self.mockAudioStreamingPlayer.playedURLs.contains(fastStream) }
    // the slow playlist answers after the newer request started
    await wait(seconds: 0.6)
    XCTAssertEqual(mockAudioStreamingPlayer.playedURLs, [fastStream])
  }

  func testPlay_PreloadedRadioStillLoadingWhenSongEnds_IsPlayed() async {
    play(createRadio(url: url(path: "/current.mp3")))
    let nextStream = url(path: "/next.mp3")
    let nextRadio = createPlaylistRadio(path: "/next.m3u", stream: nextStream, delay: 0.3)
    nextPlayable = nextRadio
    backendPlayer.preloadNextPlayable()
    // the current item ends before the playlist of the preload is read
    play(nextRadio)
    await waitUntil { self.mockAudioStreamingPlayer.playedURLs.contains(nextStream) }
    XCTAssertEqual(mockAudioStreamingPlayer.playedURLs.last, nextStream)
    // the late preload must not be queued behind the stream that is playing now
    await wait(seconds: 0.4)
    XCTAssertTrue(mockAudioStreamingPlayer.queuedURLs.isEmpty)
  }

  func testPreload_FailedPlaylist_NotRepeatedUntilNextRequest() async {
    play(createRadio(url: url(path: "/current.mp3")))
    server.httpStatus = 503
    nextPlayable = createPlaylistRadio(path: "/next.m3u", stream: url(path: "/next.mp3"))
    backendPlayer.preloadNextPlayable()
    await waitUntil { self.requestCount == 1 }
    await wait(seconds: 0.1)
    // further timer ticks within the preload window
    backendPlayer.preloadNextPlayable()
    backendPlayer.preloadNextPlayable()
    await wait(seconds: 0.2)
    XCTAssertEqual(requestCount, 1)

    // a new request allows the next preload to try again
    play(createRadio(url: url(path: "/other.mp3")))
    backendPlayer.preloadNextPlayable()
    await waitUntil { self.requestCount == 2 }
    XCTAssertEqual(requestCount, 2)
  }
}

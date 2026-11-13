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
  }
}

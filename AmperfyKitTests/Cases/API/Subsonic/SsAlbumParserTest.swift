//
//  SsAlbumParserTest.swift
//  AmperfyKitTests
//
//  Created by Maximilian Bauer on 01.06.21.
//  Copyright (c) 2021 Maximilian Bauer. All rights reserved.
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

class SsAlbumParserTest: AbstractSsParserTest {
  override func setUp() async throws {
    try await super.setUp()
    xmlData = getTestFileData(name: "artist_example_1")
  }

  override func createParserDelegate() {
    let prefetch = library.getElements(
      account: account,
      prefetchIDs: ssIdParserDelegate.prefetchIDs
    )
    ssParserDelegate = SsAlbumParserDelegate(
      performanceMonitor: MOCK_PerformanceMonitor(), prefetch: prefetch, account: account,
      library: library,
      parseNotifier: nil
    )
  }

  override func checkCorrectParsing() {
    prefetchIdTester.checkPrefetchIdCounts(
      artworkCount: 16,
      artistCount: 1,
      albumCount: 15,
      artworkFetchCount: 15 // artist artwork is not created
    )

    let albums = library.getAlbums(for: account).sorted(by: { Int($0.id)! < Int($1.id)! })
    XCTAssertEqual(albums.count, 15)

    var album = albums[1]
    XCTAssertEqual(album.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.id, "11047")
    XCTAssertEqual(album.name, "Back In Black")
    XCTAssertEqual(album.rating, 1)
    XCTAssertEqual(album.artist?.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.artist?.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.artist?.id, "5432") // Artist not pre created
    XCTAssertEqual(album.artist?.name, "AC/DC")
    XCTAssertEqual(album.year, 0)
    XCTAssertFalse(album.isCached)
    XCTAssertEqual(album.duration, 2534)
    XCTAssertEqual(album.remoteDuration, 2534)
    XCTAssertEqual(album.remoteSongCount, 10)
    XCTAssertNil(album.genre)
    XCTAssertEqual(album.artwork?.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.artwork?.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.artwork?.type, "")
    XCTAssertEqual(album.artwork?.id, "al-11047")

    album = albums[6]
    XCTAssertEqual(album.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.id, "11052")
    XCTAssertEqual(album.name, "For Those About To Rock")
    XCTAssertEqual(album.rating, 0)
    XCTAssertEqual(album.artist?.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.artist?.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.artist?.id, "5432")
    XCTAssertEqual(album.artist?.name, "AC/DC")
    XCTAssertEqual(album.year, 0)
    XCTAssertFalse(album.isCached)
    XCTAssertEqual(album.duration, 2403)
    XCTAssertEqual(album.remoteDuration, 2403)
    XCTAssertEqual(album.remoteSongCount, 10)
    XCTAssertNil(album.genre)
    XCTAssertEqual(album.artwork?.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.artwork?.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.artwork?.type, "")
    XCTAssertEqual(album.artwork?.id, "al-11052")

    album = albums[7]
    XCTAssertEqual(album.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.id, "11053")
    XCTAssertEqual(album.name, "High Voltage")
    XCTAssertEqual(album.rating, 0)
    XCTAssertEqual(album.artist?.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.artist?.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.artist?.id, "5432")
    XCTAssertEqual(album.artist?.name, "AC/DC")
    XCTAssertEqual(album.year, 0)
    XCTAssertFalse(album.isCached)
    XCTAssertEqual(album.duration, 2414)
    XCTAssertEqual(album.remoteDuration, 2414)
    XCTAssertEqual(album.remoteSongCount, 8)
    XCTAssertNil(album.genre)
    XCTAssertEqual(album.artwork?.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.artwork?.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.artwork?.type, "")
    XCTAssertEqual(album.artwork?.id, "al-11053")

    album = albums[14]
    XCTAssertEqual(album.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.id, "11061")
    XCTAssertEqual(album.name, "Who Made Who")
    XCTAssertEqual(album.rating, 5)
    XCTAssertEqual(album.artist?.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.artist?.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.artist?.id, "5432")
    XCTAssertEqual(album.artist?.name, "AC/DC")
    XCTAssertEqual(album.year, 0)
    XCTAssertFalse(album.isCached)
    XCTAssertEqual(album.duration, 2291)
    XCTAssertEqual(album.remoteDuration, 2291)
    XCTAssertEqual(album.remoteSongCount, 9)
    XCTAssertNil(album.genre)
    XCTAssertEqual(album.artwork?.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.artwork?.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.artwork?.type, "")
    XCTAssertEqual(album.artwork?.id, "al-11061")
  }

  func testReleaseSortDate() throws {
    // 1: full release date, even though one of its songs has another one
    // 2: only a year as release date, month and day default to the first
    // 3: no release date, falls back to created (without fractional seconds)
    //    (created with fractional seconds is parsed too, see 5)
    // 4: neither
    let xml = """
    <subsonic-response xmlns="http://subsonic.org/restapi" status="ok" version="1.16.1">
    <albumList2>
    <album id="1" name="A" artist="X" artistId="9" songCount="1" duration="10" created="2026-10-07T19:58:00.9769407Z" year="2025">
      <releaseDate year="2025" month="11" day="6"></releaseDate>
      <song id="11" title="S" albumId="1" artistId="9" duration="10" created="2026-10-07T19:58:00Z">
        <releaseDate year="1999" month="1" day="2"></releaseDate>
      </song>
    </album>
    <album id="2" name="B" artist="X" artistId="9" songCount="1" duration="10" created="2026-10-07T19:58:00.9769407Z" year="2026">
      <releaseDate year="2026"></releaseDate>
    </album>
    <album id="3" name="C" artist="X" artistId="9" songCount="1" duration="10" created="2004-11-27T20:23:32Z" year="2012"></album>
    <album id="5" name="E" artist="X" artistId="9" songCount="1" duration="10" created="2026-10-07T19:58:00.9769407Z" year="2026"></album>
    <album id="4" name="D" artist="X" artistId="9" songCount="1" duration="10" year="2012"></album>
    </albumList2>
    </subsonic-response>
    """
    xmlData = Data(xml.utf8)
    reParse()

    let albums = Dictionary(
      uniqueKeysWithValues: library.getAlbums(for: account).map { ($0.id, $0) }
    )
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

    let released = try XCTUnwrap(albums["1"]?.releaseSortDate)
    XCTAssertEqual(
      utc.dateComponents([.year, .month, .day, .hour], from: released),
      DateComponents(year: 2025, month: 11, day: 6, hour: 0)
    )
    let yearOnly = try XCTUnwrap(albums["2"]?.releaseSortDate)
    XCTAssertEqual(
      utc.dateComponents([.year, .month, .day, .hour], from: yearOnly),
      DateComponents(year: 2026, month: 1, day: 1, hour: 0)
    )
    let createdWithFraction = try XCTUnwrap(albums["5"]?.releaseSortDate)
    XCTAssertEqual(
      utc.dateComponents([.year, .month, .day, .hour, .minute], from: createdWithFraction),
      DateComponents(year: 2026, month: 10, day: 7, hour: 19, minute: 58)
    )
    let createdPlain = try XCTUnwrap(albums["3"]?.releaseSortDate)
    XCTAssertEqual(
      utc.dateComponents([.year, .month, .day], from: createdPlain),
      DateComponents(year: 2004, month: 11, day: 27)
    )
    XCTAssertNil(albums["4"]?.releaseSortDate)

    // the added date is always the created attribute, also if a release date exists
    XCTAssertEqual(albums["5"]?.addedDate, createdWithFraction)
    XCTAssertEqual(albums["3"]?.addedDate, createdPlain)
    XCTAssertNil(albums["4"]?.addedDate)
  }

  private func reParse() {
    guard let data = xmlData else { XCTFail(); return }
    let idParser = XMLParser(data: data)
    idParser.delegate = ssIdParserDelegate
    idParser.parse()
    createParserDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = ssParserDelegate
    parser.parse()
    XCTAssertNil(ssParserDelegate?.error)
  }
}

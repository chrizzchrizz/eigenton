//
//  LibraryDisplaySettingsTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 26.10.26.
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
class LibraryDisplaySettingsTest: XCTestCase {
  func testInUseInitDropsTabTypes() {
    let settings = LibraryDisplaySettings(
      inUse: [.playlists, .albums, .artists],
      excluded: LibraryDisplaySettings.tabTypes
    )
    XCTAssertEqual(settings.inUse, [.albums, .artists])
    XCTAssertFalse(settings.order.contains(.playlists))
    XCTAssertFalse(settings.isVisible(libraryType: .playlists))
  }

  func testOrderInitDropsTabTypes() {
    let settings = LibraryDisplaySettings(
      order: [.songs, .playlists, .albums],
      inUse: [.playlists, .albums],
      excluded: LibraryDisplaySettings.tabTypes
    )
    XCTAssertFalse(settings.order.contains(.playlists))
    XCTAssertFalse(settings.notUsed.contains(.playlists))
    XCTAssertEqual(settings.inUse, [.albums])
  }

  func testDefaultSettingsDoNotContainPlaylists() {
    let settings = LibraryDisplaySettings.defaultSettings
    XCTAssertFalse(settings.order.contains(.playlists))
    XCTAssertEqual(settings.inUse, [.albums, .artists, .songs, .compilations])
  }

  func testAddToPlaylistSettingsKeepPlaylists() {
    XCTAssertTrue(LibraryDisplaySettings.addToPlaylistSettings.inUse.contains(.playlists))
  }

  func testDecodingStoredSettingsWithPlaylistsDropsThem() throws {
    // format stored before playlists moved to their own tab
    let json = """
    {"combined": [[5, 1, 0], [2]], "order": [5, 1, 0, 2]}
    """
    let settings = try JSONDecoder().decode(
      LibraryDisplaySettings.self,
      from: Data(json.utf8)
    )
    XCTAssertFalse(settings.order.contains(.playlists))
    XCTAssertEqual(settings.inUse, [.albums, .artists])
    XCTAssertTrue(settings.notUsed.contains(.songs))
  }

  func testLibraryExcludedTypesContainTabAndNavigationBarTypes() {
    XCTAssertTrue(LibraryDisplaySettings.libraryExcludedTypes.contains(.playlists))
    XCTAssertTrue(LibraryDisplaySettings.libraryExcludedTypes.contains(.downloads))
  }

  func testDefaultSettingsDoNotContainDownloads() {
    XCTAssertFalse(LibraryDisplaySettings.defaultSettings.order.contains(.downloads))
  }

  func testDecodingStoredSettingsWithDownloadsDropsThem() throws {
    // downloads in use and as not used entry: format stored before they moved to the nav bar
    for json in [
      #"{"combined": [[7, 1, 0], [2]], "order": [7, 1, 0, 2]}"#,
      #"{"combined": [[1, 0], [7, 2]], "order": [1, 0, 7, 2]}"#,
    ] {
      let settings = try JSONDecoder().decode(
        LibraryDisplaySettings.self,
        from: Data(json.utf8)
      )
      XCTAssertFalse(settings.order.contains(.downloads))
      XCTAssertFalse(settings.isVisible(libraryType: .downloads))
      XCTAssertEqual(settings.inUse, [.albums, .artists])
    }
  }
}

//
//  SettingsDecodingTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 27.10.26.
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

// MARK: - NestedTestSettings

private struct NestedTestSettings: Codable, Equatable {
  var volume: Int = 5
  var isNewNested: Bool = true
}

// MARK: - TestSettings

private struct TestSettings: Codable, Equatable {
  var name: String = "default"
  var isNew: Bool = true
  var nested = NestedTestSettings()
}

// MARK: - SettingsDecodingTest

class SettingsDecodingTest: XCTestCase {
  func testDecodeComplete() throws {
    let data = Data(
      #"{"name":"stored","isNew":false,"nested":{"volume":1,"isNewNested":false}}"#
        .utf8
    )
    let settings = try AmperfySettings.decode(
      TestSettings.self,
      from: data,
      defaults: TestSettings()
    )
    XCTAssertEqual(
      settings,
      TestSettings(
        name: "stored",
        isNew: false,
        nested: NestedTestSettings(volume: 1, isNewNested: false)
      )
    )
  }

  func testDecodeKeepsStoredValuesWhenKeysAreMissing() throws {
    let data = Data(#"{"name":"stored","nested":{"volume":1}}"#.utf8)
    let settings = try AmperfySettings.decode(
      TestSettings.self,
      from: data,
      defaults: TestSettings()
    )
    XCTAssertEqual(settings.name, "stored")
    XCTAssertEqual(settings.isNew, true)
    XCTAssertEqual(settings.nested.volume, 1)
    XCTAssertEqual(settings.nested.isNewNested, true)
  }

  func testDecodeStoresMergedSettings() throws {
    let key = "SettingsDecodingTest"
    defer { UserDefaults.standard.removeObject(forKey: key) }
    let data = Data(#"{"name":"stored"}"#.utf8)
    _ = try AmperfySettings.decode(
      TestSettings.self,
      from: data,
      defaults: TestSettings(),
      storeMergedForKey: key
    )
    let storedData = try XCTUnwrap(UserDefaults.standard.data(forKey: key))
    XCTAssertEqual(
      try JSONDecoder().decode(TestSettings.self, from: storedData),
      TestSettings(name: "stored")
    )
  }

  func testDecodeThrowsOnInvalidType() {
    let data = Data(#"{"name":1}"#.utf8)
    XCTAssertThrowsError(
      try AmperfySettings.decode(TestSettings.self, from: data, defaults: TestSettings())
    )
  }

  func testDecodeRemovedEnumCaseFallsBackToDefault() throws {
    let removedAutoRawValue = Data("3".utf8)
    XCTAssertEqual(
      try JSONDecoder().decode(StreamingFormatPreference.self, from: removedAutoRawValue),
      .defaultValue
    )
    XCTAssertEqual(
      try JSONDecoder().decode(
        CacheTranscodingFormatPreference.self,
        from: removedAutoRawValue
      ),
      .defaultValue
    )
    XCTAssertEqual(
      try JSONDecoder().decode(StreamingFormatPreference.self, from: Data("1".utf8)),
      .raw
    )
  }

  func testAacFormatIsStoredAndDecoded() throws {
    // must not reuse 3, the raw value of the removed `auto` case
    XCTAssertEqual(StreamingFormatPreference.aac.rawValue, 4)
    XCTAssertEqual(CacheTranscodingFormatPreference.aac.rawValue, 4)
    let encoded = try JSONEncoder().encode(StreamingFormatPreference.aac)
    XCTAssertEqual(try JSONDecoder().decode(StreamingFormatPreference.self, from: encoded), .aac)
    XCTAssertEqual(
      try JSONDecoder().decode(CacheTranscodingFormatPreference.self, from: Data("4".utf8)),
      .aac
    )
  }

  func testStreamingFormatQueryValue() {
    XCTAssertEqual(StreamingFormatPreference.mp3.formatQueryValue, "mp3")
    XCTAssertEqual(StreamingFormatPreference.aac.formatQueryValue, "aac")
    XCTAssertEqual(StreamingFormatPreference.raw.formatQueryValue, "raw")
    XCTAssertNil(StreamingFormatPreference.serverConfig.formatQueryValue)
  }

  func testStreamingFormatIsTranscodingCertain() {
    XCTAssertTrue(StreamingFormatPreference.mp3.isTranscodingCertain)
    XCTAssertTrue(StreamingFormatPreference.aac.isTranscodingCertain)
    XCTAssertFalse(StreamingFormatPreference.raw.isTranscodingCertain)
    XCTAssertFalse(StreamingFormatPreference.serverConfig.isTranscodingCertain)
  }
}

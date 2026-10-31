//
//  SwipeActionSettingsTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 30.10.26.
//  Copyright (c) THEYEAR Chrizz Gelbach. All rights reserved.
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

class SwipeActionSettingsTest: XCTestCase {
  func testSimplifiedQueueIsEnabledByDefault() {
    XCTAssertTrue(UserSettings().isSimplifiedQueueEnabled)
  }

  func testDefaultSettingsOfferNoUserQueueActionsWhenSimplified() {
    let settings = SwipeActionSettings.defaultSettings.normalized(isSimplifiedQueue: true)
    let all = settings.leading + settings.trailing + settings.notUsed
    XCTAssertTrue(all.allSatisfy { $0.isSelectable(isSimplifiedQueue: true) })
    XCTAssertEqual(settings.leading, [.insertContextQueue, .appendContextQueue])
  }

  func testUserQueueActionsAreReplacedByContextQueueActionsWhenSimplified() {
    let settings = SwipeActionSettings(
      leading: [.insertUserQueue, .download],
      trailing: [.appendUserQueue, .insertContextQueue]
    ).normalized(isSimplifiedQueue: true)
    XCTAssertEqual(settings.leading, [.insertContextQueue, .download])
    XCTAssertEqual(settings.trailing, [.appendContextQueue])
    XCTAssertFalse(settings.notUsed.contains(.insertUserQueue))
    XCTAssertFalse(settings.notUsed.contains(.appendUserQueue))
  }

  func testAllActionsAreOfferedWhenNotSimplified() {
    let stored = SwipeActionSettings(
      leading: [.insertUserQueue, .download],
      trailing: [.appendUserQueue, .insertContextQueue]
    )
    let settings = stored.normalized(isSimplifiedQueue: false)
    XCTAssertEqual(settings.leading, [.insertUserQueue, .download])
    XCTAssertEqual(settings.trailing, [.appendUserQueue, .insertContextQueue])
    XCTAssertTrue(settings.notUsed.contains(.appendContextQueue))
    XCTAssertFalse(settings.notUsed.contains(.insertUserQueue))
  }

  func testNormalizingDoesNotChangeStoredSettings() {
    let stored = SwipeActionSettings(leading: [.insertUserQueue], trailing: [])
    _ = stored.normalized(isSimplifiedQueue: true)
    XCTAssertEqual(stored.leading, [.insertUserQueue])
  }

  func testStoredSettingsWithUserQueueActionsAreKeptAndNormalizedOnDemand() throws {
    var combined = SwipeActionSettings(leading: [.favorite], trailing: [.play]).combined
    combined[0] = [.appendUserQueue, .insertUserQueue, .favorite]
    combined[2].append(.insertUserQueue)
    let data = try JSONEncoder().encode(["combined": combined])
    let decoded = try JSONDecoder().decode(SwipeActionSettings.self, from: data)
    XCTAssertEqual(decoded.leading, [.appendUserQueue, .insertUserQueue, .favorite])
    let simplified = decoded.normalized(isSimplifiedQueue: true)
    XCTAssertEqual(simplified.leading, [.appendContextQueue, .insertContextQueue, .favorite])
    XCTAssertEqual(simplified.trailing, [.play])
    XCTAssertTrue(simplified.notUsed.allSatisfy { $0.isSelectable(isSimplifiedQueue: true) })
  }

  func testNamesDependOnSimplifiedQueue() {
    XCTAssertEqual(
      SwipeActionType.insertContextQueue.displayName(isSimplifiedQueue: true),
      "Insert"
    )
    XCTAssertEqual(
      SwipeActionType.insertContextQueue.displayName(isSimplifiedQueue: false),
      "Insert Context Queue"
    )
    XCTAssertEqual(
      SwipeActionType.appendContextQueue.settingsName(isSimplifiedQueue: true),
      "Append to Queue"
    )
    XCTAssertEqual(
      SwipeActionType.appendContextQueue.settingsName(isSimplifiedQueue: false),
      "Append to Context Queue"
    )
  }
}

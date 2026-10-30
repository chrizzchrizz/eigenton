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
  func testDefaultSettingsOfferNoUserQueueActions() {
    let settings = SwipeActionSettings.defaultSettings
    let all = settings.leading + settings.trailing + settings.notUsed
    XCTAssertTrue(all.allSatisfy { $0.isSelectable })
    XCTAssertTrue(settings.leading.contains(.insertContextQueue))
    XCTAssertTrue(settings.leading.contains(.appendContextQueue))
  }

  func testUserQueueActionsAreReplacedByContextQueueActions() {
    let settings = SwipeActionSettings(
      leading: [.insertUserQueue, .download],
      trailing: [.appendUserQueue, .insertContextQueue]
    )
    XCTAssertEqual(settings.leading, [.insertContextQueue, .download])
    XCTAssertEqual(settings.trailing, [.appendContextQueue])
    XCTAssertFalse(settings.notUsed.contains(.insertUserQueue))
    XCTAssertFalse(settings.notUsed.contains(.appendUserQueue))
  }

  func testStoredSettingsWithUserQueueActionsAreMigrated() throws {
    let stored = SwipeActionSettings(leading: [.favorite], trailing: [.play])
    var combined = stored.combined
    combined[0] = [.appendUserQueue, .insertUserQueue, .favorite]
    combined[2].append(.insertUserQueue)
    let data = try JSONEncoder().encode(["combined": combined])
    let decoded = try JSONDecoder().decode(SwipeActionSettings.self, from: data)
    XCTAssertEqual(decoded.leading, [.appendContextQueue, .insertContextQueue, .favorite])
    XCTAssertEqual(decoded.trailing, [.play])
    XCTAssertTrue(decoded.notUsed.allSatisfy { $0.isSelectable })
  }
}

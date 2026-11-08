//
//  EventLoggerTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 20.10.26.
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
class EventLoggerTest: XCTestCase {
  func testURLErrorIsNetworkError() {
    XCTAssertTrue(EventLogger.isNetworkError(URLError(.notConnectedToInternet)))
  }

  func testTimeoutIsNetworkError() {
    XCTAssertTrue(EventLogger.isNetworkError(URLError(.timedOut)))
  }

  func testCertificateAndCancelAreNoNetworkError() {
    XCTAssertFalse(EventLogger.isNetworkError(URLError(.serverCertificateUntrusted)))
    XCTAssertFalse(EventLogger.isNetworkError(URLError(.cancelled)))
  }

  func testOtherErrorIsNoNetworkError() {
    let error = NSError(domain: "Amperfy", code: 1)
    XCTAssertFalse(EventLogger.isNetworkError(error))
  }
}

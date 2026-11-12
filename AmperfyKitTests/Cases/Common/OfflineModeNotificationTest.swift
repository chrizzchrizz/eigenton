//
//  OfflineModeNotificationTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 19.10.26.
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

// MARK: - OfflineModeObserver

/// Records .offlineModeChanged notifications; the observer runs synchronously while posting.
private final class OfflineModeObserver: @unchecked Sendable {
  private let storage: PersistentStorage
  private var token: NSObjectProtocol?
  private(set) var observedOfflineModes = [Bool]()

  init(storage: PersistentStorage) {
    self.storage = storage
    self.token = NotificationCenter.default.addObserver(
      forName: .offlineModeChanged,
      object: nil,
      queue: nil
    ) { [unowned self] _ in
      // reading settings here must not conflict with the ongoing write
      observedOfflineModes.append(self.storage.settings.user.isOfflineMode)
    }
  }

  deinit {
    if let token {
      NotificationCenter.default.removeObserver(token)
    }
  }
}

// MARK: - OfflineModeNotificationTest

@MainActor
class OfflineModeNotificationTest: XCTestCase {
  let userSettingsKey = PersistentStorage.UserDefaultsKey.SettingsUser.rawValue
  var savedUserSettings: Data?
  var cdHelper: CoreDataHelper!
  var storage: PersistentStorage!

  override func setUp() async throws {
    savedUserSettings = UserDefaults.standard.data(forKey: userSettingsKey)
    UserDefaults.standard.removeObject(forKey: userSettingsKey)
    AmperfySettings.reloadFromUserDefaults()
    cdHelper = CoreDataHelper()
    storage = PersistentStorage(
      coreDataManager: MOCK_CoreDataManager(persistentContainer: cdHelper.persistentContainer)
    )
  }

  override func tearDown() async throws {
    UserDefaults.standard.set(savedUserSettings, forKey: userSettingsKey)
    AmperfySettings.reloadFromUserDefaults()
  }

  func testChangePostsNotification() {
    let observer = OfflineModeObserver(storage: storage)
    storage.settings.user.isOfflineMode = true
    XCTAssertEqual(observer.observedOfflineModes, [true])
    storage.settings.user.isOfflineMode = false
    XCTAssertEqual(observer.observedOfflineModes, [true, false])
  }

  func testSameValuePostsNoNotification() {
    let observer = OfflineModeObserver(storage: storage)
    storage.settings.user.isOfflineMode = false
    XCTAssertEqual(observer.observedOfflineModes, [])
    storage.settings.user.isOfflineMode = true
    storage.settings.user.isOfflineMode = true
    XCTAssertEqual(observer.observedOfflineModes, [true])
  }

  func testOtherSettingPostsNoNotification() {
    let observer = OfflineModeObserver(storage: storage)
    storage.settings.user.isHapticsEnabled.toggle()
    XCTAssertEqual(observer.observedOfflineModes, [])
  }
}

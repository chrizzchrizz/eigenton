//
//  LibraryChangeSyncerTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 25.11.26.
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
import CoreData
import XCTest

// MARK: - MOCK_SwitchableNetworkMonitor

final class MOCK_SwitchableNetworkMonitor: NetworkMonitorFacade {
  nonisolated(unsafe) var isConnected = true
  var connectionTypeChangedCB: ConnectionTypeChangedCallack? { get { nil } set {} }
  var isConnectedToNetwork: Bool { isConnected }
  var isCellular: Bool { false }
  var isWifiOrEthernet: Bool { isConnected }
}

// MARK: - LibraryChangeSyncerTest

@MainActor
class LibraryChangeSyncerTest: XCTestCase {
  var cdHelper: CoreDataHelper!
  var library: LibraryStorage!
  var account: Account!
  var storage: PersistentStorage!
  var librarySyncer: MOCK_LibrarySyncer!
  var networkMonitor: MOCK_SwitchableNetworkMonitor!
  var testSyncer: LibraryChangeSyncer!
  var song: Song!
  var album: Album!
  var artist: Artist!

  override func setUp() async throws {
    cdHelper = CoreDataHelper()
    library = cdHelper.createSeededStorage()
    account = library.getAccount(info: TestAccountInfo.create1())
    storage = PersistentStorage(
      coreDataManager: MOCK_CoreDataManager(persistentContainer: cdHelper.persistentContainer)
    )
    preserveStoredUserSettings()
    librarySyncer = MOCK_LibrarySyncer()
    networkMonitor = MOCK_SwitchableNetworkMonitor()
    testSyncer = LibraryChangeSyncer(
      account: account,
      storage: storage,
      librarySyncer: librarySyncer,
      networkMonitor: networkMonitor,
      eventLogger: EventLogger(storage: storage),
      retryDelay: .milliseconds(200)
    )
    testSyncer.start()
    song = library.getSong(for: account, id: "3")
    album = library.getAlbum(for: account, id: "12", isDetailFaultResolution: false)
    artist = library.getArtist(for: account, id: "4")
    XCTAssertNotNil(song)
    XCTAssertNotNil(album)
    XCTAssertNotNil(artist)
  }

  /// The settings (UserDefaults) are shared with the host app: restored afterwards
  private func preserveStoredUserSettings() {
    let userKey = PersistentStorage.UserDefaultsKey.SettingsUser.rawValue
    let savedUserData = UserDefaults.standard.data(forKey: userKey)
    addTeardownBlock { @MainActor in
      UserDefaults.standard.set(savedUserData, forKey: userKey)
      // the settings are cached in memory
      AmperfySettings.reloadFromUserDefaults()
    }
  }

  private var pendingCount: Int {
    library.getPendingLibraryChangeCount(for: account)
  }

  /// The upload runs in a task
  private func waitUntil(
    _ condition: () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0 ..< 200 {
      if condition() { return }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("condition not met", file: file, line: line)
  }

  /// Gives a started upload time to send requests that must not be sent
  private func settle() async {
    for _ in 0 ..< 20 {
      await Task.yield()
    }
  }

  func testOffline_ChangesAreSetLocallyAndKept() async {
    storage.settings.user.isOfflineMode = true
    testSyncer.setFavorite(song, isFavorite: true)
    testSyncer.setRating(album, rating: 4)
    testSyncer.toggleFavorite(artist)
    await settle()

    XCTAssertTrue(song.isFavorite)
    XCTAssertNotNil(song.starredDate)
    XCTAssertEqual(album.rating, 4)
    XCTAssertTrue(artist.isFavorite)
    XCTAssertEqual(pendingCount, 3)
    XCTAssertEqual(librarySyncer.libraryChangeRequests, [])
  }

  func testOffline_LastChangeOfAnEntityWins() async {
    storage.settings.user.isOfflineMode = true
    testSyncer.setFavorite(song, isFavorite: true)
    testSyncer.setFavorite(song, isFavorite: false)
    testSyncer.setRating(song, rating: 2)
    testSyncer.setRating(song, rating: 5)

    XCTAssertFalse(song.isFavorite)
    XCTAssertNil(song.starredDate)
    XCTAssertEqual(song.rating, 5)
    // one favorite and one rating change
    XCTAssertEqual(pendingCount, 2)

    storage.settings.user.isOfflineMode = false
    testSyncer.requestUpload()
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(
      librarySyncer.libraryChangeRequests,
      ["favorite song 3 false", "rating song 3 5"]
    )
  }

  func testGoingOnline_UploadsInChangeOrder() async {
    storage.settings.user.isOfflineMode = true
    testSyncer.setRating(artist, rating: 3)
    testSyncer.setFavorite(album, isFavorite: true)
    testSyncer.setFavorite(song, isFavorite: true)

    storage.settings.user.isOfflineMode = false
    testSyncer.requestUpload()
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(librarySyncer.libraryChangeRequests, [
      "rating artist 4 3",
      "favorite album 12 true",
      "favorite song 3 true",
    ])
  }

  func testOnlineWithoutNetwork_UploadsWhenNetworkIsBack() async {
    storage.settings.user.isOfflineMode = false
    networkMonitor.isConnected = false
    testSyncer.setFavorite(song, isFavorite: true)
    await settle()
    XCTAssertEqual(pendingCount, 1)
    XCTAssertEqual(librarySyncer.libraryChangeRequests, [])

    networkMonitor.isConnected = true
    testSyncer.requestUpload()
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(librarySyncer.libraryChangeRequests, ["favorite song 3 true"])
  }

  func testOnline_ChangeIsUploadedRightAway() async {
    storage.settings.user.isOfflineMode = false
    testSyncer.setRating(song, rating: 1)
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(librarySyncer.libraryChangeRequests, ["rating song 3 1"])
    XCTAssertEqual(song.rating, 1)
  }

  func testFailedUpload_ChangeIsKept() async {
    storage.settings.user.isOfflineMode = false
    librarySyncer.libraryChangeError = URLError(.timedOut)
    testSyncer.setFavorite(song, isFavorite: true)
    await settle()
    XCTAssertEqual(pendingCount, 1)
    XCTAssertTrue(song.isFavorite)

    librarySyncer.libraryChangeError = nil
    testSyncer.requestUpload()
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(librarySyncer.libraryChangeRequests, ["favorite song 3 true"])
  }

  func testRejectedChange_IsDroppedAndTheNextOnesAreUploaded() async {
    storage.settings.user.isOfflineMode = true
    librarySyncer.libraryChangeErrors["rating artist 4 3"] = ResponseError(
      type: .api,
      statusCode: SubsonicServerApi.SubsonicError.userIsNotAuthorized.rawValue
    )
    testSyncer.setRating(artist, rating: 3)
    testSyncer.setFavorite(song, isFavorite: true)

    storage.settings.user.isOfflineMode = false
    testSyncer.requestUpload()
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(librarySyncer.libraryChangeRequests, ["favorite song 3 true"])
  }

  func testFailedChange_DoesNotBlockTheNextOnesAndIsRetried() async {
    storage.settings.user.isOfflineMode = true
    librarySyncer.libraryChangeErrors["rating artist 4 3"] = ResponseError(type: .xml)
    testSyncer.setRating(artist, rating: 3)
    testSyncer.setFavorite(song, isFavorite: true)

    storage.settings.user.isOfflineMode = false
    testSyncer.requestUpload()
    await waitUntil { librarySyncer.libraryChangeRequests == ["favorite song 3 true"] }
    XCTAssertEqual(pendingCount, 1)

    // retried after the retry delay
    librarySyncer.libraryChangeErrors = [:]
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(
      librarySyncer.libraryChangeRequests,
      ["favorite song 3 true", "rating artist 4 3"]
    )
  }

  func testServerUnavailable_IsRetriedWithoutANewChange() async {
    storage.settings.user.isOfflineMode = false
    librarySyncer.libraryChangeError = URLError(.cannotConnectToHost)
    testSyncer.setFavorite(album, isFavorite: true)
    await settle()
    XCTAssertEqual(pendingCount, 1)

    librarySyncer.libraryChangeError = nil
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(librarySyncer.libraryChangeRequests, ["favorite album 12 true"])
  }

  func testStopped_ChangesAreRecordedButNotUploaded() async {
    storage.settings.user.isOfflineMode = false
    testSyncer.stop()
    testSyncer.setFavorite(song, isFavorite: true)
    testSyncer.requestUpload()
    await settle()
    XCTAssertTrue(song.isFavorite)
    XCTAssertEqual(pendingCount, 1)
    XCTAssertEqual(librarySyncer.libraryChangeRequests, [])

    testSyncer.start()
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(librarySyncer.libraryChangeRequests, ["favorite song 3 true"])
  }

  func testFailureClassification() {
    XCTAssertEqual(LibraryChangeSyncer.failure(of: URLError(.timedOut)), .serverUnavailable)
    XCTAssertEqual(
      LibraryChangeSyncer.failure(of: BackendError.noNetworkConnection),
      .serverUnavailable
    )
    XCTAssertEqual(
      LibraryChangeSyncer.failure(of: ResponseError(type: .api, statusCode: 40)),
      .serverUnavailable
    )
    XCTAssertEqual(
      LibraryChangeSyncer.failure(of: ResponseError(type: .api, statusCode: 4701)),
      .serverUnavailable
    )
    XCTAssertEqual(
      LibraryChangeSyncer.failure(of: ResponseError(type: .api, statusCode: 70)),
      .changeRejected
    )
    XCTAssertEqual(
      LibraryChangeSyncer.failure(of: ResponseError(type: .api, statusCode: 4704)),
      .changeRejected
    )
    XCTAssertEqual(
      LibraryChangeSyncer.failure(of: ResponseError(type: .api, statusCode: 0)),
      .changeFailed
    )
    XCTAssertEqual(LibraryChangeSyncer.failure(of: ResponseError(type: .xml)), .changeFailed)
  }

  func testEntityGoneFromServer_ChangeIsDropped() async {
    storage.settings.user.isOfflineMode = false
    librarySyncer.libraryChangeError = ResponseError(
      type: .api,
      statusCode: SubsonicServerApi.SubsonicError.requestedDataNotFound.rawValue
    )
    testSyncer.setFavorite(song, isFavorite: true)
    await waitUntil { pendingCount == 0 }
    XCTAssertEqual(librarySyncer.libraryChangeRequests, [])
  }

  func testUpload_SetsTheChangeAgainAfterAServerSyncOverwroteIt() async {
    storage.settings.user.isOfflineMode = true
    testSyncer.setFavorite(song, isFavorite: true)
    // a server sync with the server's old value
    song.isFavorite = false

    storage.settings.user.isOfflineMode = false
    testSyncer.requestUpload()
    await waitUntil { pendingCount == 0 }
    XCTAssertTrue(song.isFavorite)
  }

  func testApplyPendingChanges_RestoresChangesAfterAServerSync() {
    storage.settings.user.isOfflineMode = true
    testSyncer.setFavorite(album, isFavorite: true)
    testSyncer.setRating(artist, rating: 2)
    // the favorite sync writes the server's state
    album.isFavorite = false
    album.starredDate = nil
    artist.rating = 0

    library.applyPendingLibraryChanges(account: account)
    XCTAssertTrue(album.isFavorite)
    XCTAssertNotNil(album.starredDate)
    XCTAssertEqual(artist.rating, 2)
    XCTAssertEqual(pendingCount, 2)
  }

  func testNonLibraryEntities_AreIgnored() async {
    storage.settings.user.isOfflineMode = true
    testSyncer.toggleFavorite(library.createPlaylist(account: account))
    testSyncer.toggleFavorite(library.createGenre(account: account))
    XCTAssertEqual(pendingCount, 0)
  }
}

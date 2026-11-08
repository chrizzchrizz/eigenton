//
//  ArtworkTest.swift
//  AmperfyKitTests
//
//  Created by Maximilian Bauer on 01.01.20.
//  Copyright (c) 2020 Maximilian Bauer. All rights reserved.
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

@MainActor
class ArtworkTest: XCTestCase {
  var cdHelper: CoreDataHelper!
  var library: LibraryStorage!
  var account: Account!
  var testArtwork: Artwork!

  override func setUp() async throws {
    cdHelper = CoreDataHelper()
    library = cdHelper.createSeededStorage()
    account = library.getAccount(info: TestAccountInfo.create1())
    testArtwork = library.createArtwork(account: account)
  }

  override func tearDown() {}

  func testCreation() {
    let artwork = library.createArtwork(account: account)
    XCTAssertEqual(artwork.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(artwork.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(artwork.status.rawValue, ImageStatus.IsDefaultImage.rawValue)
    XCTAssertEqual(artwork.id, "")
    XCTAssertEqual(artwork.type, "")
    XCTAssertNil(artwork.imagePath)
    XCTAssertEqual(artwork.owners.count, 0)
  }

  func testStatus() {
    testArtwork.status = ImageStatus.FetchError
    XCTAssertEqual(testArtwork.status, ImageStatus.FetchError)
    guard let artist1 = library.getArtist(for: account, id: cdHelper.seeder.artists[0].id)
    else { XCTFail(); return }
    artist1.managedObject.artwork = testArtwork.managedObject
    library.saveContext()
    guard let artistFetched = library.getArtist(for: account, id: cdHelper.seeder.artists[0].id)
    else { XCTFail(); return }
    XCTAssertEqual(artistFetched.artwork?.status, ImageStatus.FetchError)
  }

  func testImageWithCorrectStatus() {
    testArtwork.status = ImageStatus.CustomImage
    let testData = Data(base64Encoded: "Test", options: .ignoreUnknownCharacters)!
    let relFilePath = URL(string: "testArtwork")!
    let absFilePath = CacheFileManager.shared.getAbsoluteAmperfyPath(relFilePath: relFilePath)!
    try! CacheFileManager.shared.writeDataExcludedFromBackup(
      data: testData,
      to: absFilePath,
      accountInfo: account.info
    )
    testArtwork.relFilePath = relFilePath
    XCTAssertEqual(testArtwork.status, ImageStatus.CustomImage)
    XCTAssertEqual(testArtwork.imagePath, absFilePath.path)
    try! CacheFileManager.shared.removeItem(at: absFilePath, accountInfo: account.info)
  }

  func testImageWithWrongStatus() {
    testArtwork.status = ImageStatus.NotChecked
    let testData = Data(base64Encoded: "Test", options: .ignoreUnknownCharacters)!
    let relFilePath = URL(string: "testArtwork")!
    let absFilePath = CacheFileManager.shared.getAbsoluteAmperfyPath(relFilePath: relFilePath)!
    try! CacheFileManager.shared.writeDataExcludedFromBackup(
      data: testData,
      to: absFilePath,
      accountInfo: account.info
    )
    testArtwork.relFilePath = relFilePath
    XCTAssertEqual(testArtwork.status, ImageStatus.NotChecked)
    XCTAssertNil(testArtwork.imagePath)
    try! CacheFileManager.shared.removeItem(at: absFilePath, accountInfo: account.info)
  }

  func testOwners() {
    guard let artist1 = library.getArtist(for: account, id: cdHelper.seeder.artists[0].id)
    else { XCTFail(); return }
    guard let artist2 = library.getArtist(for: account, id: cdHelper.seeder.artists[1].id)
    else { XCTFail(); return }
    XCTAssertEqual(testArtwork.owners.count, 0)
    artist1.managedObject.artwork = testArtwork.managedObject
    XCTAssertEqual(testArtwork.owners.count, 1)
    artist2.managedObject.artwork = testArtwork.managedObject
    XCTAssertEqual(testArtwork.owners.count, 2)
  }

  /// Writes a file at the artwork's real cache path, like a finished download does
  @discardableResult
  private func writeArtworkFile(for artwork: Artwork) -> URL {
    let relFilePath = CacheFileManager.shared.createRelPath(
      for: artwork.remoteInfo,
      account: account.info
    )!
    let absFilePath = writeFile(relFilePath: relFilePath)
    artwork.relFilePath = relFilePath
    artwork.status = .CustomImage
    return absFilePath
  }

  private func writeFile(relFilePath: URL) -> URL {
    let absFilePath = CacheFileManager.shared.getAbsoluteAmperfyPath(relFilePath: relFilePath)!
    try! CacheFileManager.shared.writeDataExcludedFromBackup(
      data: Data(base64Encoded: "Test", options: .ignoreUnknownCharacters)!,
      to: absFilePath,
      accountInfo: account.info
    )
    addTeardownBlock { try? FileManager.default.removeItem(at: absFilePath) }
    return absFilePath
  }

  private func createArtwork(id: String, type: String = "") -> Artwork {
    library.getOrCreateArtwork(account: account, remoteInfo: ArtworkRemoteInfo(id: id, type: type))
  }

  private func seededArtist(_ index: Int) -> Artist {
    library.getArtist(for: account, id: cdHelper.seeder.artists[index].id)!
  }

  /// Checks by id, a deleted artwork's attributes are empty after the save
  private func exists(id: String, type: String = "") -> Bool {
    library.getArtwork(for: account, remoteInfo: ArtworkRemoteInfo(id: id, type: type)) != nil
  }

  private func unreferencedIds() -> Set<String> {
    Set(library.getUnreferencedArtworks(account: account).map { $0.id })
  }

  func testReplacedArtworkIsUnreferenced() {
    let artist = seededArtist(0)
    artist.artwork = createArtwork(id: "old")
    library.saveContext()
    XCTAssertFalse(unreferencedIds().contains("old"))

    artist.artwork = createArtwork(id: "new")
    library.saveContext()

    XCTAssertTrue(unreferencedIds().contains("old"))
    XCTAssertFalse(unreferencedIds().contains("new"))
    // not deleted on save, another context could still use it
    XCTAssertTrue(exists(id: "old"))
  }

  func testArtworkStillOwnedByOtherEntityIsReferenced() {
    let shared = createArtwork(id: "shared")
    seededArtist(0).artwork = shared
    seededArtist(1).artwork = shared
    library.saveContext()

    seededArtist(0).artwork = nil
    library.saveContext()

    XCTAssertFalse(unreferencedIds().contains("shared"))
  }

  func testArtworkOfDeletedPlaylistIsUnreferenced() {
    guard let playlist = library.getPlaylist(for: account, id: cdHelper.seeder.playlists[0].id)
    else { XCTFail(); return }
    playlist.artwork = createArtwork(id: "pl-cover")
    library.saveContext()
    XCTAssertFalse(unreferencedIds().contains("pl-cover"))

    library.deletePlaylist(playlist)
    library.saveContext()

    XCTAssertTrue(unreferencedIds().contains("pl-cover"))
  }

  func testDeleteArtworksWithCachedFiles() {
    let orphan = createArtwork(id: "orphan")
    let orphanFile = writeArtworkFile(for: orphan)
    orphan.managedObject.download = library.createDownload(account: account, id: "dl-orphan")
      .managedObject
    let owned = createArtwork(id: "owned")
    let ownedFile = writeArtworkFile(for: owned)
    seededArtist(0).artwork = owned
    library.saveContext()

    library.deleteArtworksWithCachedFiles(library.getUnreferencedArtworks(account: account))

    XCTAssertFalse(exists(id: "orphan"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphanFile.path))
    XCTAssertNil(library.getDownload(account: account, id: "dl-orphan"))
    XCTAssertTrue(exists(id: "owned"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: ownedFile.path))
  }

  func testDeleteArtworksKeepsFileSharedWithRemainingArtwork() {
    let used = createArtwork(id: "shared", type: "a")
    let sharedFile = writeArtworkFile(for: used)
    seededArtist(0).artwork = used
    let orphan = createArtwork(id: "shared", type: "b")
    orphan.relFilePath = used.relFilePath
    library.saveContext()

    library.deleteArtworksWithCachedFiles([orphan.managedObject])

    XCTAssertFalse(exists(id: "shared", type: "b"))
    XCTAssertTrue(exists(id: "shared", type: "a"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: sharedFile.path))
  }

  func testRemoveArtworkFilesWithoutArtwork() {
    let owned = createArtwork(id: "owned")
    let ownedFile = writeArtworkFile(for: owned)
    seededArtist(0).artwork = owned
    library.saveContext()
    // only the test account's artwork directory is swept, remove leftovers of earlier runs
    library.removeArtworkFilesWithoutArtwork(account: account)
    let strayRelFilePath = CacheFileManager.shared.createRelPath(
      for: ArtworkRemoteInfo(id: "stray", type: ""),
      account: account.info
    )!
    let strayFile = writeFile(relFilePath: strayRelFilePath)

    XCTAssertEqual(library.removeArtworkFilesWithoutArtwork(account: account), 1)

    XCTAssertFalse(FileManager.default.fileExists(atPath: strayFile.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: ownedFile.path))
  }

  func testDeletedEntityKeepsSharedArtwork() {
    let artist1 = seededArtist(0)
    let artist2 = seededArtist(1)
    let shared = createArtwork(id: "shared")
    artist1.artwork = shared
    artist2.artwork = shared
    library.saveContext()

    library.deleteArtist(artist: artist1)
    library.saveContext()

    XCTAssertTrue(exists(id: "shared"))
    XCTAssertEqual(artist2.artwork, shared)
    XCTAssertFalse(unreferencedIds().contains("shared"))

    library.deleteArtist(artist: artist2)
    library.saveContext()

    // the last owner is gone, the artwork is left for the cleanup at app start
    XCTAssertTrue(unreferencedIds().contains("shared"))
  }

  func testMigrationToV53() {
    let v52 = NSManagedObjectModel
      .managedObjectModel(forResource: CoreDataMigrationVersion.v52.rawValue)
    let v53 = NSManagedObjectModel
      .managedObjectModel(forResource: CoreDataMigrationVersion.v53.rawValue)
    let artworkRelationship = v53.entitiesByName["AbstractLibraryEntity"]?
      .relationshipsByName["artwork"]
    XCTAssertEqual(artworkRelationship?.deleteRule, .nullifyDeleteRule)
    // a delete rule alone doesn't change the hash, without the version hash modifier a v53 store
    // would also match v52 and be migrated again on every launch
    XCTAssertNotEqual(v52.entityVersionHashesByName, v53.entityVersionHashesByName)
    XCTAssertNotNil(try? NSMappingModel.inferredMappingModel(
      forSourceModel: v52,
      destinationModel: v53
    ))
  }
}

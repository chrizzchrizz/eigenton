//
//  AlbumTest.swift
//  AmperfyKitTests
//
//  Created by Maximilian Bauer on 31.12.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
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
class AlbumTest: XCTestCase {
  var cdHelper: CoreDataHelper!
  var library: LibraryStorage!
  var account: Account!
  var testAlbum: Album!
  let testId = "23489"

  override func setUp() async throws {
    cdHelper = CoreDataHelper()
    library = cdHelper.createSeededStorage()
    account = library.getAccount(info: TestAccountInfo.create1())
    testAlbum = library.createAlbum(account: account)
    testAlbum.id = testId
  }

  override func tearDown() {}

  func testCompilationFilter() {
    let compilation = library.createAlbum(account: account)
    compilation.id = "compilation"
    compilation.isCompilation = true
    let regular = library.createAlbum(account: account)
    regular.id = "regular"
    library.saveContext()

    let ids = library.getCompilationAlbums(for: account).map { $0.id }
    XCTAssertEqual(ids, ["compilation"])
  }

  func testCreation() {
    let album = library.createAlbum(account: account)
    XCTAssertEqual(album.account?.serverHash, TestAccountInfo.test1ServerHash)
    XCTAssertEqual(album.account?.userHash, TestAccountInfo.test1UserHash)
    XCTAssertEqual(album.id, "")
    XCTAssertEqual(album.identifier, "Unknown Album")
    XCTAssertEqual(album.name, "Unknown Album")
    XCTAssertEqual(album.year, 0)
    XCTAssertEqual(album.artist, nil)
    XCTAssertEqual(album.songs.count, 0)
    XCTAssertEqual(album.songCount, 0)
    XCTAssertNil(album.artwork)
    XCTAssertNil(
      album.imagePath(setting: .serverArtworkOnly)
    )
    XCTAssertEqual(
      album.getDefaultArtworkType(), .album
    )
    XCTAssertFalse(album.playables.hasCachedItems)
    XCTAssertFalse(album.isOrphaned)
  }

  func testArtist() {
    guard let artist = library.getArtist(for: account, id: cdHelper.seeder.artists[0].id)
    else { XCTFail(); return }
    testAlbum.artist = artist
    XCTAssertEqual(testAlbum.artist!.id, artist.id)
    library.saveContext()
    guard let albumFetched = library.getAlbum(
      for: account,
      id: testId,
      isDetailFaultResolution: true
    )
    else { XCTFail(); return }
    XCTAssertEqual(albumFetched.artist!.id, artist.id)
  }

  func testTitle() {
    let testTitle = "Alright"
    testAlbum.name = testTitle
    XCTAssertEqual(testAlbum.name, testTitle)
    XCTAssertEqual(testAlbum.identifier, testTitle)
    library.saveContext()
    guard let albumFetched = library.getAlbum(
      for: account,
      id: testId,
      isDetailFaultResolution: true
    )
    else { XCTFail(); return }
    XCTAssertEqual(albumFetched.name, testTitle)
    XCTAssertEqual(albumFetched.identifier, testTitle)
  }

  func testYear() {
    let testYear = 2001
    testAlbum.year = testYear
    XCTAssertEqual(testAlbum.year, testYear)
    library.saveContext()
    guard let albumFetched = library.getAlbum(
      for: account,
      id: testId,
      isDetailFaultResolution: true
    )
    else { XCTFail(); return }
    XCTAssertEqual(albumFetched.year, testYear)
  }

  func testArtworkAndImage() {
    let testData = UIImage.getGeneratedArtwork(theme: .blue, artworkType: .album).pngData()!
    let relFilePath = URL(string: "testArtwork")!
    let absFilePath = CacheFileManager.shared.getAbsoluteAmperfyPath(relFilePath: relFilePath)!
    try! CacheFileManager.shared.writeDataExcludedFromBackup(
      data: testData,
      to: absFilePath,
      accountInfo: account.info
    )
    testAlbum.artwork = library.createArtwork(account: account)
    testAlbum.artwork?.relFilePath = relFilePath
    testAlbum.artwork?.status = .CustomImage
    XCTAssertNotNil(testAlbum.artwork?.imagePath)
    library.saveContext()
    guard let albumFetched = library.getAlbum(
      for: account,
      id: testId,
      isDetailFaultResolution: true
    )
    else { XCTFail(); return }
    XCTAssertNotNil(albumFetched.artwork?.imagePath)
    try! CacheFileManager.shared.removeItem(at: absFilePath, accountInfo: account.info)
  }

  func testSongs() {
    guard let album3Items = library.getAlbum(
      for: account,
      id: cdHelper.seeder.albums[0].id,
      isDetailFaultResolution: true
    ) else { XCTFail(); return }
    XCTAssertEqual(album3Items.songs.count, 3)
    XCTAssertEqual(album3Items.songCount, 3)
    guard let album2Items = library.getAlbum(
      for: account,
      id: cdHelper.seeder.albums[2].id,
      isDetailFaultResolution: true
    ) else { XCTFail(); return }
    XCTAssertEqual(album2Items.songs.count, 2)
    XCTAssertEqual(album2Items.songCount, 2)
  }

  func testHasCachedSongs() {
    guard let albumNoCached = library.getAlbum(
      for: account,
      id: cdHelper.seeder.albums[0].id,
      isDetailFaultResolution: true
    ) else { XCTFail(); return }
    XCTAssertFalse(albumNoCached.playables.hasCachedItems)
    guard let albumTwoCached = library.getAlbum(
      for: account,
      id: cdHelper.seeder.albums[2].id,
      isDetailFaultResolution: true
    ) else { XCTFail(); return }
    XCTAssertTrue(albumTwoCached.playables.hasCachedItems)
  }

  func testIsOrphaned() {
    testAlbum.name = "blub"
    XCTAssertFalse(testAlbum.isOrphaned)
    testAlbum.name = "Unknown Album"
    XCTAssertFalse(testAlbum.isOrphaned)
    testAlbum.name = "Orphaned"
    XCTAssertFalse(testAlbum.isOrphaned)
    testAlbum.name = "Unknown (Orphaned)"
    XCTAssertTrue(testAlbum.isOrphaned)
    testAlbum.name = "blub"
    XCTAssertFalse(testAlbum.isOrphaned)
  }

  func testLatestReleasedAlbumsSortedByYearThenReleaseSortDate() {
    func createAlbum(id: String, year: Int, releaseSortDate: Date?) {
      let album = library.createAlbum(account: account)
      album.id = id
      album.name = id
      album.year = year
      album.releaseSortDate = releaseSortDate
    }
    createAlbum(
      id: "rel-a",
      year: 2025,
      releaseSortDate: Date(timeIntervalSince1970: 1_740_000_000)
    )
    createAlbum(
      id: "rel-b",
      year: 2025,
      releaseSortDate: Date(timeIntervalSince1970: 1_762_000_000)
    )
    createAlbum(
      id: "rel-c",
      year: 2026,
      releaseSortDate: Date(timeIntervalSince1970: 1_768_000_000)
    )
    createAlbum(id: "rel-d", year: 2025, releaseSortDate: nil)
    library.saveContext()

    let ids = library.getLatestReleasedAlbums(for: account, count: 1000)
      .map(\.id)
      .filter { $0.hasPrefix("rel-") }
    // newest year first, then newest date first; albums without a date come last in their year
    XCTAssertEqual(ids, ["rel-c", "rel-b", "rel-a", "rel-d"])
  }

  func testAddedDateSectionTitle() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    func title(_ added: Date?, now: Date) -> String {
      AddedDateSectionBoundaries(now: now, calendar: calendar).title(for: added)
    }

    let november = date(2026, 11, 12)
    XCTAssertEqual(title(date(2026, 11, 1), now: november), "This Month")
    XCTAssertEqual(title(date(2026, 10, 31), now: november), "Last 3 Months")
    XCTAssertEqual(title(date(2026, 8, 13), now: november), "Last 3 Months")
    XCTAssertEqual(title(date(2026, 8, 11), now: november), "Last 6 Months")
    XCTAssertEqual(title(date(2026, 5, 13), now: november), "Last 6 Months")
    XCTAssertEqual(title(date(2026, 5, 11), now: november), "This Year")
    XCTAssertEqual(title(date(2026, 1, 1), now: november), "This Year")
    XCTAssertEqual(title(date(2025, 12, 31), now: november), "2025")
    XCTAssertEqual(title(date(2019, 3, 3), now: november), "2019")
    XCTAssertEqual(title(nil, now: november), "")

    // early in the year the last months reach into the previous year, "This Year" stays empty
    let february = date(2027, 2, 10)
    XCTAssertEqual(title(date(2027, 1, 5), now: february), "Last 3 Months")
    XCTAssertEqual(title(date(2026, 12, 5), now: february), "Last 3 Months")
    XCTAssertEqual(title(date(2026, 9, 5), now: february), "Last 6 Months")
    XCTAssertEqual(title(date(2026, 8, 5), now: february), "2026")
  }

  func testNewestAlbumsGroupedByAddedDate() {
    let now = Date()
    let day: TimeInterval = 24 * 60 * 60
    func createAlbum(id: String, newestIndex: Int, addedDate: Date?) {
      let album = library.createAlbum(account: account)
      album.id = id
      album.name = id
      album.markAsNotNewAnymore()
      album.updateIsNewestInfo(index: newestIndex)
      album.addedDate = addedDate
    }
    createAlbum(id: "add-old", newestIndex: 3, addedDate: now.addingTimeInterval(-800 * day))
    createAlbum(id: "add-none", newestIndex: 4, addedDate: nil)
    createAlbum(id: "add-new", newestIndex: 1, addedDate: now)
    createAlbum(id: "add-mid", newestIndex: 2, addedDate: now.addingTimeInterval(-60 * day))
    library.saveContext()

    let controller = AlbumFetchedResultsController(
      coreDataCompanion: CoreDataCompanion(context: cdHelper.persistentContainer.viewContext),
      account: account,
      sortType: .newest,
      isGroupedInAlphabeticSections: true
    )
    controller.search(searchText: "", onlyCached: false, displayFilter: .newest)
    let sections = controller.sections ?? []
    let ids = sections.map { section in
      (section.objects as? [AlbumMO] ?? []).map(\.id).filter { $0.hasPrefix("add-") }
    }.filter { !$0.isEmpty }
    // newest added first, albums without a date last
    XCTAssertEqual(ids, [["add-new"], ["add-mid"], ["add-old"], ["add-none"]])
    XCTAssertEqual(sections.first?.name, "This Month")
    XCTAssertEqual(sections.last?.name, "")
  }

  func testHighestNewestIndexOfAlbumsWithoutAddedDate() {
    XCTAssertEqual(library.getHighestNewestIndexOfAlbumsWithoutAddedDate(for: account), 0)
    let dated = library.createAlbum(account: account)
    dated.updateIsNewestInfo(index: 7)
    dated.addedDate = Date()
    let undated = library.createAlbum(account: account)
    undated.updateIsNewestInfo(index: 3)
    let notNewest = library.createAlbum(account: account)
    notNewest.addedDate = nil
    library.saveContext()
    XCTAssertEqual(library.getHighestNewestIndexOfAlbumsWithoutAddedDate(for: account), 3)

    undated.addedDate = Date()
    library.saveContext()
    XCTAssertEqual(library.getHighestNewestIndexOfAlbumsWithoutAddedDate(for: account), 0)
  }

  func testAddedDateSetsSectionOnSave() {
    let album = library.createAlbum(account: account)
    XCTAssertEqual(album.managedObject.addedDateSection, "")
    album.addedDate = Date()
    library.saveContext()
    XCTAssertEqual(album.managedObject.addedDateSection, "This Month")
    // also when the managed object is written directly
    album.managedObject.addedDate = nil
    library.saveContext()
    XCTAssertEqual(album.managedObject.addedDateSection, "")
  }

  func testUpdateAddedDateSections() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    // stored groups as left by an earlier app run or the migration
    func createAlbum(added: Date?, section: String) -> AlbumMO {
      let album = library.createAlbum(account: account).managedObject
      album.addedDate = added
      library.saveContext()
      album.addedDateSection = section
      library.saveContext()
      return album
    }
    let migrated = createAlbum(added: date(2019, 3, 1), section: "")
    let movedOn = createAlbum(added: date(2026, 10, 20), section: "This Month")
    let unchanged = createAlbum(added: date(2026, 11, 2), section: "This Month")
    let wrongYear = createAlbum(added: date(2026, 11, 2), section: "2019")
    let withoutDate = createAlbum(added: nil, section: "")

    let boundaries = AddedDateSectionBoundaries(now: date(2026, 11, 12), calendar: calendar)
    XCTAssertEqual(library.updateAddedDateSections(boundaries: boundaries), 3)
    XCTAssertEqual(migrated.addedDateSection, "2019")
    XCTAssertEqual(movedOn.addedDateSection, "Last 3 Months")
    XCTAssertEqual(unchanged.addedDateSection, "This Month")
    // e.g. computed with another clock or calendar, every group is checked again
    XCTAssertEqual(wrongYear.addedDateSection, "This Month")
    XCTAssertEqual(withoutDate.addedDateSection, "")
    library.saveContext()
    XCTAssertEqual(library.updateAddedDateSections(boundaries: boundaries), 0)
  }

  func testAddedDateRangesMatchTitles() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let oldest = try XCTUnwrap(calendar.date(from: DateComponents(year: 2015, month: 6, day: 1)))
    // reference dates with "This Year" before and after the six months boundary
    for (month, day) in [(1, 1), (3, 15), (7, 31), (11, 12), (12, 31)] {
      let now = try XCTUnwrap(calendar.date(from: DateComponents(
        year: 2026, month: month, day: day, hour: 12
      )))
      let boundaries = AddedDateSectionBoundaries(now: now, calendar: calendar)
      let ranges = boundaries.ranges(oldestDate: oldest)
      var date = oldest
      while date <= now.addingTimeInterval(86400) {
        let matching = ranges.filter { date >= $0.start && date < ($0.end ?? .distantFuture) }
        XCTAssertEqual(matching.count, 1, "\(date) at \(now)")
        XCTAssertEqual(matching.first?.title, boundaries.title(for: date), "\(date) at \(now)")
        date = date.addingTimeInterval(5 * 3600 + 17)
      }
    }
  }
}

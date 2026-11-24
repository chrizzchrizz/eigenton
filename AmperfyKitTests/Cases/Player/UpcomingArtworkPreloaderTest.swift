//
//  UpcomingArtworkPreloaderTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 24.11.26.
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
final class UpcomingArtworkPreloaderTest: XCTestCase {
  var cdHelper: CoreDataHelper!
  var library: LibraryStorage!
  var account: Account!
  var upcoming = [AbstractPlayable]()
  var requestedCounts = [Int]()
  var displayPreference = ArtworkDisplayPreference.preferId3Tag
  var downloads = [(Artwork, AccountInfo)]()
  /// Fulfilled by each download request, fails the test if fulfilled more often than expected
  var downloadExpectation: XCTestExpectation?
  var preloader: UpcomingArtworkPreloader!

  override func setUp() async throws {
    cdHelper = CoreDataHelper()
    library = cdHelper.createSeededStorage()
    account = library.getAccount(info: TestAccountInfo.create1())
    upcoming = []
    requestedCounts = []
    displayPreference = .preferId3Tag
    downloads = []
    downloadExpectation = nil
    preloader = UpcomingArtworkPreloader(
      upcomingPlayables: { [unowned self] count in
        requestedCounts.append(count)
        return Array(upcoming.prefix(count))
      },
      artworkDisplayPreference: { [unowned self] _ in displayPreference },
      downloadArtwork: { [unowned self] artwork, accountInfo in
        downloads.append((artwork, accountInfo))
        downloadExpectation?.fulfill()
      }
    )
  }

  private func createSong(withArtwork: Bool = true, withEmbeddedArtwork: Bool = false) -> Song {
    let song = library.createSong(account: account)
    if withArtwork {
      song.artwork = library.createArtwork(account: account)
    }
    if withEmbeddedArtwork {
      song.embeddedArtwork = library.createEmbeddedArtwork(account: account)
    }
    return song
  }

  private var downloadedArtworks: [Artwork] { downloads.map { $0.0 } }

  /// Waits for exactly one scheduled update with a download request, and a moment longer to
  /// catch a second one
  private func waitForOneScheduledDownload() async throws {
    let expectation = expectation(description: "download requested")
    expectation.assertForOverFulfill = true
    downloadExpectation = expectation
    await fulfillment(of: [expectation], timeout: 2)
    try await Task.sleep(for: .milliseconds(100))
  }

  func testRequestsMissingArtworksOfUpcomingSongs() {
    let songA = createSong()
    let songB = createSong(withArtwork: false)
    let songC = createSong()
    upcoming = [songA, songB, songC]

    preloader.update()

    XCTAssertEqual(requestedCounts, [UpcomingArtworkPreloader.upcomingCount])
    XCTAssertEqual(downloadedArtworks, [songA.artwork!, songC.artwork!])
    XCTAssertTrue(downloads.allSatisfy { $0.1 == account.info })
  }

  func testDownloadedArtworksAreSkipped() {
    let downloaded = createSong()
    downloaded.artwork!.relFilePath = URL(string: "artworks/downloaded")
    let missing = createSong()
    upcoming = [downloaded, missing]

    preloader.update()

    XCTAssertEqual(downloadedArtworks, [missing.artwork!])
  }

  func testOnlyTheNextSongsAreRequested() {
    let songs = (0 ..< UpcomingArtworkPreloader.upcomingCount + 2).map { _ in createSong() }
    upcoming = songs

    preloader.update()

    let expected = songs.prefix(UpcomingArtworkPreloader.upcomingCount).map { $0.artwork! }
    XCTAssertEqual(downloadedArtworks, Array(expected))
  }

  func testRadiosAreSkipped() {
    let radio = library.createRadio(account: account)
    radio.artwork = library.createArtwork(account: account)
    upcoming = [radio]

    preloader.update()

    XCTAssertTrue(downloads.isEmpty)
  }

  func testArtworkDisplayPreference() {
    let plain = createSong()
    let embedded = createSong(withEmbeddedArtwork: true)
    upcoming = [plain, embedded]

    displayPreference = .preferId3Tag
    preloader.update()
    XCTAssertEqual(downloadedArtworks, [plain.artwork!])

    downloads = []
    displayPreference = .id3TagOnly
    preloader.update()
    XCTAssertTrue(downloads.isEmpty)

    for preference in [ArtworkDisplayPreference.preferServerArtwork, .serverArtworkOnly] {
      downloads = []
      displayPreference = preference
      preloader.update()
      XCTAssertEqual(downloadedArtworks, [plain.artwork!, embedded.artwork!])
    }
  }

  func testPlayerEventsAreCoalescedIntoOneUpdate() async throws {
    upcoming = [createSong()]

    preloader.didStartPlayingFromBeginning()
    preloader.didShuffleChange()
    preloader.didRepeatChange()
    preloader.didPlaylistChange()
    XCTAssertTrue(downloads.isEmpty)
    try await waitForOneScheduledDownload()

    XCTAssertEqual(downloads.count, 1)
  }
}

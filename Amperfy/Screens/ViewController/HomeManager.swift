//
//  HomeManager.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 29.12.25.
//  Copyright (c) 2025 Maximilian Bauer. All rights reserved.
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

import AmperfyKit
import CoreData
import OSLog
import UIKit

// MARK: - HomeItem

struct HomeItem: Hashable, @unchecked Sendable {
  /// Stable per section and entity: the diffable data source only sees real changes,
  /// so unchanged covers are not recreated (flicker) when a section is rebuilt.
  /// The section is part of the identity as an entity can show up in several sections.
  let id: String
  let section: HomeSection
  var playableContainable: PlayableContainable
  /// Not part of the identity: a changed value only makes the cell reconfigure (no flicker),
  /// e.g. when a playlist cover gets created or the server cover changes after the item was
  /// first shown.
  let artworkFingerprint: [NSManagedObjectID]
  /// Subtitle of a playlist tile (artists or song count). Like the artwork fingerprint not part
  /// of the identity, a change (e.g. after the songs got synced) only reconfigures the cell.
  let playlistSubtitle: String?

  init(
    section: HomeSection,
    playableContainable: PlayableContainable,
    playlistSubtitle: String? = nil
  ) {
    if let playlist = playableContainable as? Playlist {
      self.artworkFingerprint = playlist.managedObject.artworkItems.map(\.objectID) +
        [playlist.managedObject.artwork?.objectID].compactMap { $0 }
    } else {
      self.artworkFingerprint = []
    }
    self.section = section
    self.playlistSubtitle = playlistSubtitle
    let identifier = playableContainable.containerIdentifier
    self
      .id =
      "\(section)|\(identifier.type.map { "\($0)" } ?? "")|\(identifier.objectID ?? playableContainable.id)"
    self.playableContainable = playableContainable
  }

  static func == (lhs: HomeItem, rhs: HomeItem) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - HomeManager

@MainActor
class HomeManager: NSObject {
  public static let sectionMaxItemCount = 20

  public var orderedVisibleSections: [HomeSection]
  public var data: [HomeSection: [HomeItem]] = [:]
  public var applySnapshotCB: VoidFunctionCallback?
  private let account: Account
  private let storage: PersistentStorage
  private let getMeta: (_ accountInfo: AccountInfo) -> MetaManager
  private let eventLogger: EventLogger

  /// Number of artists shown in the subtitle of a playlist tile
  private static let playlistSubtitleArtistCount = 6
  /// Subtitles of the playlist tiles. The section is rebuilt on every change of a playlist,
  /// the artists are only looked up again when the songs of the playlist changed.
  private var playlistSubtitleCache = [
    NSManagedObjectID: (songsKey: PlaylistSongsKey, subtitle: String)
  ]()

  private struct PlaylistSongsKey: Equatable {
    let itemCount: Int
    let firstItemID: NSManagedObjectID?
    let songCount: Int
  }

  var isOfflineMode: Bool {
    storage.settings.user.isOfflineMode
  }

  private var albumsRecentlyPlayedFetchController: AlbumFetchedResultsController?
  private var albumsNewestFetchController: AlbumFetchedResultsController?
  private var albumsLatestReleasedFetchController: AlbumFetchedResultsController?
  private var playlistsLastTimePlayedFetchController: PlaylistFetchedResultsController?
  private var podcastEpisodesFetchedController: PodcastEpisodesReleaseDateFetchedResultsController?
  private var podcastsFetchedController: PodcastFetchedResultsController?
  private var radiosFetchedController: RadiosFetchedResultsController?

  init(
    account: Account,
    storage: PersistentStorage,
    getMeta: @escaping (_ accountInfo: AccountInfo) -> MetaManager,
    eventLogger: EventLogger
  ) {
    self.account = account
    self.storage = storage
    self.getMeta = getMeta
    self.eventLogger = eventLogger
    self.orderedVisibleSections = storage.settings.accounts
      .getSetting(account.info).read.homeSections
  }

  func createFetchController() {
    if orderedVisibleSections.contains(where: { $0 == .recentlyPlayedAlbums }) {
      albumsRecentlyPlayedFetchController = AlbumFetchedResultsController(
        coreDataCompanion: storage.main, account: account,
        sortType: .recent,
        isGroupedInAlphabeticSections: false,
        fetchLimit: Self.sectionMaxItemCount
      )
      albumsRecentlyPlayedFetchController?.delegate = self
      albumsRecentlyPlayedFetchController?.search(
        searchText: "",
        onlyCached: isOfflineMode,
        displayFilter: .recent
      )
      updateAlbumsRecentlyPlayed()
    } else {
      albumsRecentlyPlayedFetchController?.delegate = nil
      albumsRecentlyPlayedFetchController = nil
    }

    if orderedVisibleSections.contains(where: { $0 == .newestAlbums }) {
      albumsNewestFetchController = AlbumFetchedResultsController(
        coreDataCompanion: storage.main, account: account,
        sortType: .newest,
        isGroupedInAlphabeticSections: false,
        fetchLimit: Self.sectionMaxItemCount
      )
      albumsNewestFetchController?.delegate = self
      albumsNewestFetchController?.search(
        searchText: "",
        onlyCached: isOfflineMode,
        displayFilter: .newest
      )
      updateAlbumsNewest()
    } else {
      albumsNewestFetchController?.delegate = nil
      albumsNewestFetchController = nil
    }

    if orderedVisibleSections.contains(where: { $0 == .latestReleasedAlbums }) {
      albumsLatestReleasedFetchController = AlbumFetchedResultsController(
        coreDataCompanion: storage.main, account: account,
        sortType: .year,
        isGroupedInAlphabeticSections: false,
        fetchLimit: Self.sectionMaxItemCount,
        sortsYearByReleaseDate: true
      )
      albumsLatestReleasedFetchController?.delegate = self
      albumsLatestReleasedFetchController?.search(
        searchText: "",
        onlyCached: isOfflineMode,
        displayFilter: .all
      )
      updateAlbumsLatestReleased()
    } else {
      albumsLatestReleasedFetchController?.delegate = nil
      albumsLatestReleasedFetchController = nil
    }

    if orderedVisibleSections.contains(where: { $0 == .randomAlbums }) {
      Task { @MainActor in
        await updateRandomAlbums(isOfflineMode: isOfflineMode)
      }
    }
    if orderedVisibleSections.contains(where: { $0 == .compilations }) {
      Task { @MainActor in
        await updateCompilations(isOfflineMode: isOfflineMode)
      }
    }
    if orderedVisibleSections.contains(where: { $0 == .randomArtists }) {
      Task { @MainActor in
        await updateRandomArtists(isOfflineMode: isOfflineMode)
      }
    }
    if orderedVisibleSections.contains(where: { $0 == .favoriteAlbums }) {
      Task { @MainActor in
        await updateFavoriteAlbums(isOfflineMode: isOfflineMode)
      }
    }
    if orderedVisibleSections.contains(where: { $0 == .favoriteArtists }) {
      Task { @MainActor in
        await updateFavoriteArtists(isOfflineMode: isOfflineMode)
      }
    }
    if orderedVisibleSections.contains(where: { $0 == .randomGenres }) {
      Task { @MainActor in
        await updateRandomGenres()
      }
    }
    if orderedVisibleSections.contains(where: { $0 == .randomSongs }) {
      Task { @MainActor in
        await updateRandomSongs(isOfflineMode: isOfflineMode)
      }
    }
    let fixedSections = orderedVisibleSections.filter(\.isFixedDecadeOrGenre)
    if !fixedSections.isEmpty {
      Task { @MainActor in
        for section in fixedSections {
          await updateFixedDecadeOrGenreAlbums(section, isOfflineMode: isOfflineMode)
        }
      }
    }

    if orderedVisibleSections.contains(where: { $0 == .lastTimePlayedPlaylists }) {
      playlistsLastTimePlayedFetchController = PlaylistFetchedResultsController(
        coreDataCompanion: storage.main, account: account,
        sortType: .lastPlayed,
        isGroupedInAlphabeticSections: false,
        fetchLimit: Self.sectionMaxItemCount
      )
      playlistsLastTimePlayedFetchController?.delegate = self
      playlistsLastTimePlayedFetchController?.search(
        searchText: "",
        playlistSearchCategory: isOfflineMode ? .cached : .all
      )
      updatePlaylistsLastTimePlayed()
    } else {
      playlistsLastTimePlayedFetchController?.delegate = nil
      playlistsLastTimePlayedFetchController = nil
    }

    if orderedVisibleSections.contains(where: { $0 == .newestPodcastEpisodes }) {
      podcastEpisodesFetchedController = PodcastEpisodesReleaseDateFetchedResultsController(
        coreDataCompanion: storage.main, account: account,
        isGroupedInAlphabeticSections: false,
        fetchLimit: Self.sectionMaxItemCount
      )
      podcastEpisodesFetchedController?.delegate = self
      podcastEpisodesFetchedController?.search(searchText: "", onlyCachedSongs: isOfflineMode)
      updatePodcastEpisodesNewest()
    } else {
      podcastEpisodesFetchedController?.delegate = nil
      podcastEpisodesFetchedController = nil
    }

    if orderedVisibleSections.contains(where: { $0 == .podcasts }) {
      podcastsFetchedController = PodcastFetchedResultsController(
        coreDataCompanion: storage.main, account: account,
        isGroupedInAlphabeticSections: false
      )
      podcastsFetchedController?.delegate = self
      podcastsFetchedController?.search(searchText: "", onlyCached: isOfflineMode)
      updatePodcasts()
    } else {
      podcastsFetchedController?.delegate = nil
      podcastsFetchedController = nil
    }

    if orderedVisibleSections.contains(where: { $0 == .radios }) {
      radiosFetchedController = RadiosFetchedResultsController(
        coreDataCompanion: storage.main, account: account,
        isGroupedInAlphabeticSections: true
      )
      radiosFetchedController?.delegate = self
      radiosFetchedController?.fetch()
      updateRadios()
    } else {
      radiosFetchedController?.delegate = nil
      radiosFetchedController = nil
    }
  }

  func updateFromRemote() {
    guard storage.settings.user.isOnlineMode else { return }
    if orderedVisibleSections.contains(where: { $0 == .newestAlbums }) {
      Task { @MainActor in
        do {
          try await AutoDownloadLibrarySyncer(
            storage: self.storage,
            account: self.account,
            librarySyncer: self.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.getMeta(self.account.info)
              .playableDownloadManager
          )
          .syncNewestLibraryElements(offset: 0, count: Self.sectionMaxItemCount)
        } catch {
          self.eventLogger.report(topic: "Newest Albums Sync", error: error)
        }
      }
    }
    if orderedVisibleSections.contains(where: { $0 == .recentlyPlayedAlbums }) {
      Task { @MainActor in
        do {
          try await self.getMeta(self.account.info).librarySyncer
            .syncRecentAlbums(
              offset: 0,
              count: Self.sectionMaxItemCount
            )
        } catch {
          self.eventLogger.report(topic: "Recent Albums Sync", error: error)
        }
      }
    }
    if orderedVisibleSections.contains(where: { $0 == .lastTimePlayedPlaylists }) {
      Task { @MainActor in do {
        try await self.getMeta(self.account.info).librarySyncer
          .syncDownPlaylistsWithoutSongs()
      } catch {
        self.eventLogger.report(topic: "Playlists Sync", error: error)
      }}
    }
    if orderedVisibleSections.contains(where: { $0 == .newestPodcastEpisodes }) {
      Task { @MainActor in do {
        let _ = try await AutoDownloadLibrarySyncer(
          storage: self.storage,
          account: self.account,
          librarySyncer: self.getMeta(self.account.info).librarySyncer,
          playableDownloadManager: self.getMeta(self.account.info)
            .playableDownloadManager
        )
        .syncNewestPodcastEpisodes()
      } catch {
        self.eventLogger.report(topic: "Podcasts Sync", error: error)
      }}
    }
    if orderedVisibleSections.contains(where: { $0 == .radios }) {
      Task { @MainActor in
        do {
          try await self.getMeta(self.account.info).librarySyncer
            .syncRadios()
        } catch {
          self.eventLogger.report(topic: "Radios Sync", error: error)
        }
      }
    }
  }

  func updateAlbumsRecentlyPlayed() {
    if let albums = albumsRecentlyPlayedFetchController?.fetchedObjects as? [AlbumMO] {
      data[.recentlyPlayedAlbums] = albums.prefix(Self.sectionMaxItemCount)
        .compactMap { Album(managedObject: $0) }.compactMap {
          HomeItem(section: .recentlyPlayedAlbums, playableContainable: $0)
        }
      applySnapshotCB?()
    }
  }

  func updateAlbumsNewest() {
    if let albums = albumsNewestFetchController?.fetchedObjects as? [AlbumMO] {
      data[.newestAlbums] = albums.prefix(Self.sectionMaxItemCount)
        .compactMap { Album(managedObject: $0) }.compactMap {
          HomeItem(section: .newestAlbums, playableContainable: $0)
        }
      applySnapshotCB?()
    }
  }

  func updateAlbumsLatestReleased() {
    if let albums = albumsLatestReleasedFetchController?.fetchedObjects as? [AlbumMO] {
      data[.latestReleasedAlbums] = albums.prefix(Self.sectionMaxItemCount)
        .compactMap { Album(managedObject: $0) }.compactMap {
          HomeItem(section: .latestReleasedAlbums, playableContainable: $0)
        }
      applySnapshotCB?()
    }
  }

  func updateRandomAlbums(isOfflineMode: Bool) async {
    let randomAlbums = storage.main.library.getRandomAlbums(
      for: account,
      count: Self.sectionMaxItemCount,
      onlyCached: isOfflineMode
    )
    data[.randomAlbums] = randomAlbums.compactMap {
      HomeItem(section: .randomAlbums, playableContainable: $0)
    }
    applySnapshotCB?()
  }

  /// Random albums of the decade or genre group a fixed section stands for.
  func updateFixedDecadeOrGenreAlbums(_ section: HomeSection, isOfflineMode: Bool) async {
    var albums = [Album]()
    if let decade = section.fixedDecade {
      albums = storage.main.library.getRandomAlbums(
        for: account,
        inDecade: decade,
        count: Self.sectionMaxItemCount,
        onlyCached: isOfflineMode
      )
    } else if let group = section.fixedGenreGroup {
      albums = storage.main.library.getRandomAlbums(
        for: account,
        inGenreGroup: group,
        count: Self.sectionMaxItemCount,
        onlyCached: isOfflineMode
      )
    }
    data[section] = albums.compactMap { HomeItem(section: section, playableContainable: $0) }
    applySnapshotCB?()
  }

  func updateFavoriteAlbums(isOfflineMode: Bool) async {
    let favoriteAlbums = storage.main.library.getRandomAlbums(
      for: account,
      count: Self.sectionMaxItemCount,
      onlyCached: isOfflineMode,
      onlyFavorites: true
    )
    data[.favoriteAlbums] = favoriteAlbums.compactMap {
      HomeItem(section: .favoriteAlbums, playableContainable: $0)
    }
    applySnapshotCB?()
  }

  func updateCompilations(isOfflineMode: Bool) async {
    let compilations = storage.main.library.getRandomCompilationAlbums(
      for: account,
      count: Self.sectionMaxItemCount,
      onlyCached: isOfflineMode
    )
    data[.compilations] = compilations.compactMap {
      HomeItem(section: .compilations, playableContainable: $0)
    }
    applySnapshotCB?()
  }

  func updateRandomArtists(isOfflineMode: Bool) async {
    let randomArtists = storage.main.library.getRandomArtists(
      for: account,
      count: Self.sectionMaxItemCount,
      onlyCached: isOfflineMode
    )
    data[.randomArtists] = randomArtists.compactMap {
      HomeItem(section: .randomArtists, playableContainable: $0)
    }
    applySnapshotCB?()
  }

  func updateFavoriteArtists(isOfflineMode: Bool) async {
    let favoriteArtists = storage.main.library.getRandomArtists(
      for: account,
      count: Self.sectionMaxItemCount,
      onlyCached: isOfflineMode,
      onlyFavorites: true
    )
    data[.favoriteArtists] = favoriteArtists.compactMap {
      HomeItem(section: .favoriteArtists, playableContainable: $0)
    }
    applySnapshotCB?()
  }

  func updateRandomGenres() async {
    let randomGenres = storage.main.library.getRandomGenres(
      for: account,
      count: Self.sectionMaxItemCount
    )
    data[.randomGenres] = randomGenres.compactMap {
      HomeItem(section: .randomGenres, playableContainable: $0)
    }
    applySnapshotCB?()
  }

  func updateRandomSongs(isOfflineMode: Bool) async {
    let randomSongs = storage.main.library.getRandomSongs(
      for: account,
      count: Self.sectionMaxItemCount,
      onlyCached: isOfflineMode
    )
    data[.randomSongs] = randomSongs.compactMap {
      HomeItem(section: .randomSongs, playableContainable: $0)
    }
    applySnapshotCB?()
  }

  /// Up to `playlistSubtitleArtistCount` artists, the song count if the songs of the playlist
  /// are not synced yet.
  private func playlistSubtitle(for playlist: Playlist) -> String {
    let items = playlist.managedObject.items
    let songsKey = PlaylistSongsKey(
      itemCount: items.count,
      firstItemID: items.first?.objectID,
      songCount: playlist.songCount
    )
    let objectID = playlist.managedObject.objectID
    if let cached = playlistSubtitleCache[objectID], cached.songsKey == songsKey {
      return cached.subtitle
    }
    let artistNames = playlist.artistNames(limit: Self.playlistSubtitleArtistCount)
    let subtitle = !artistNames.isEmpty
      ? artistNames.joined(separator: ", ")
      : (playlist.songCount == 1 ? "1 Song" : "\(playlist.songCount) Songs")
    playlistSubtitleCache[objectID] = (songsKey, subtitle)
    return subtitle
  }

  func updatePlaylistsLastTimePlayed() {
    if let playlists = playlistsLastTimePlayedFetchController?.fetchedObjects as? [PlaylistMO] {
      data[.lastTimePlayedPlaylists] = playlists.prefix(Self.sectionMaxItemCount)
        .compactMap { Playlist(
          library: storage.main.library,
          managedObject: $0
        ) }.compactMap {
          HomeItem(
            section: .lastTimePlayedPlaylists,
            playableContainable: $0,
            playlistSubtitle: playlistSubtitle(for: $0)
          )
        }
      applySnapshotCB?()
    }
  }

  func updatePodcastEpisodesNewest() {
    if let podcastEpisodes = podcastEpisodesFetchedController?
      .fetchedObjects as? [PodcastEpisodeMO] {
      data[.newestPodcastEpisodes] = podcastEpisodes.prefix(Self.sectionMaxItemCount)
        .compactMap { PodcastEpisode(managedObject: $0) }.compactMap {
          HomeItem(section: .newestPodcastEpisodes, playableContainable: $0)
        }
      applySnapshotCB?()
    }
  }

  func updatePodcasts() {
    if let podcasts = podcastsFetchedController?.fetchedObjects as? [PodcastMO] {
      data[.podcasts] = podcasts.prefix(Self.sectionMaxItemCount)
        .compactMap { Podcast(managedObject: $0) }.compactMap {
          HomeItem(section: .podcasts, playableContainable: $0)
        }
      applySnapshotCB?()
    }
  }

  func updateRadios() {
    if let radios = radiosFetchedController?.fetchedObjects as? [RadioMO] {
      data[.radios] = radios.prefix(Self.sectionMaxItemCount)
        .compactMap { Radio(managedObject: $0) }.compactMap {
          HomeItem(section: .radios, playableContainable: $0)
        }
      applySnapshotCB?()
    }
  }
}

extension HomeManager: @preconcurrency NSFetchedResultsControllerDelegate {
  func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
    // fetch controller is created on Main thread -> Runtime Error if this function call is not on Main thread
    MainActor.assumeIsolated {
      if controller == albumsRecentlyPlayedFetchController?.fetchResultsController {
        updateAlbumsRecentlyPlayed()
      } else if controller == albumsNewestFetchController?.fetchResultsController {
        updateAlbumsNewest()
      } else if controller == albumsLatestReleasedFetchController?.fetchResultsController {
        updateAlbumsLatestReleased()
      } else if controller == playlistsLastTimePlayedFetchController?.fetchResultsController {
        updatePlaylistsLastTimePlayed()
      } else if controller == podcastEpisodesFetchedController?.fetchResultsController {
        updatePodcastEpisodesNewest()
      } else if controller == podcastsFetchedController?.fetchResultsController {
        updatePodcasts()
      } else if controller == radiosFetchedController?.fetchResultsController {
        updateRadios()
      }
    }
  }
}

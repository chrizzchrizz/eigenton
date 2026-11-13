//
//  SongsVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 09.03.19.
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

import AmperfyKit
import CoreData
import UIKit

class SongsVC: SingleFetchedResultsTableViewController<SongMO> {
  override var sceneTitle: String? {
    switch displayFilter {
    case .all, .compilations, .latestReleased, .newest, .recent: "Songs"
    case .favorites: "Favorite Songs"
    }
  }

  private var fetchedResultsController: SongsFetchedResultsController!
  private var detailHeaderView: LibraryElementDetailTableHeaderView?
  private var optionsButton: UIBarButtonItem!
  public var displayFilter: DisplayCategoryFilter = .all
  private var sortType: SongElementSortType = .name
  private var filterTitle = "Songs"

  init(account: Account) {
    super.init(style: .plain, account: account)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.separatorStyle = .none // rows draw their own separators

    if #available(macCatalyst 27.0, *) {
      refreshControl = UIRefreshControl()
    }

    appDelegate.userStatistics.visited(.songs)

    optionsButton = UIBarButtonItem.createOptionsBarButton()

    applyFilter()
    configureSearchController(
      placeholder: "Search in \"\(filterTitle)\"",
      scopeButtonTitles: ["All", "Cached"]
    )
    tableView.register(nibName: PlayableTableCell.typeName)
    tableView.rowHeight = PlayableTableCell.rowHeightLarge
    tableView.estimatedRowHeight = PlayableTableCell.rowHeightLarge
    tableView.clipsToBounds = false

    let playShuffleInfoConfig = PlayShuffleInfoConfiguration(
      infoCB: { [weak self] in
        guard let self else { return "" }
        return "\(fetchedResultsController.fetchedObjects?.count ?? 0) Song\((fetchedResultsController.fetchedObjects?.count ?? 0) == 1 ? "" : "s")"
      },
      playContextCb: { [weak self] in self?.handleHeaderPlay() },
      player: appDelegate.player,
      isInfoAlwaysHidden: false,
      shuffleContextCb: { [weak self] in self?.handleHeaderShuffle() }
    )
    detailHeaderView = LibraryElementDetailTableHeaderView.createTableHeader(
      rootView: self,
      configuration: playShuffleInfoConfig
    )
    #if !targetEnvironment(macCatalyst)
      refreshControl?.addTarget(
        self,
        action: #selector(Self.handleRefresh),
        for: UIControl.Event.valueChanged
      )
    #endif

    containableAtIndexPathCallback = { [weak self] indexPath in
      guard let self else { return nil }
      return fetchedResultsController.getWrappedEntity(at: indexPath)
    }
    playContextAtIndexPathCallback = { [weak self] indexPath in
      self?.convertIndexPathToPlayContext(songIndexPath: indexPath)
    }
    swipeCallback = { [weak self] indexPath, completionHandler in
      guard let self else { return }
      let song = fetchedResultsController.getWrappedEntity(at: indexPath)
      let playContext = convertIndexPathToPlayContext(songIndexPath: indexPath)
      completionHandler(SwipeActionContext(containable: song, playContext: playContext))
    }
    resultUpdateHandler?.changesDidEnd = { [weak self] in
      guard let self else { return }
      updateContentUnavailable()
    }
    showLargeTitleOnMac()
  }

  func updateContentUnavailable() {
    if fetchedResultsController.fetchedObjects?.count ?? 0 == 0 {
      if fetchedResultsController.isSearchActive {
        contentUnavailableConfiguration = UIContentUnavailableConfiguration.search()
      } else {
        contentUnavailableConfiguration = emptyContentConfig
      }
      detailHeaderView?.isHidden = true
    } else {
      contentUnavailableConfiguration = nil
      detailHeaderView?.isHidden = false
    }
  }

  lazy var emptyContentConfig: UIContentUnavailableConfiguration = {
    var config = UIContentUnavailableConfiguration.empty()
    config.image = .musicalNotes
    config.text = "No Songs"
    config.secondaryText = "Your songs will appear here."
    return config
  }()

  func applyFilter() {
    switch displayFilter {
    case .all:
      filterTitle = "Songs"
      isIndexTitelsHidden = false
      change(sortType: appDelegate.storage.settings.user.songsSortSetting)
    case .compilations, .latestReleased, .newest, .recent:
      break
    case .favorites:
      filterTitle = "Favorite Songs"
      isIndexTitelsHidden = false
      if account.apiType.asServerApiType != .ampache {
        change(sortType: appDelegate.storage.settings.user.favoriteSongSortSetting)
      } else {
        change(sortType: appDelegate.storage.settings.user.songsSortSetting)
      }
    }
    setNavBarTitle(title: filterTitle)
  }

  func change(sortType: SongElementSortType) {
    self.sortType = sortType
    singleFetchedResultsController?.clearResults()
    tableView.reloadData()
    fetchedResultsController = SongsFetchedResultsController(
      coreDataCompanion: appDelegate.storage.main, account: account,
      sortType: sortType,
      isGroupedInAlphabeticSections: sortType.hasSectionTitles
    )
    fetchedResultsController.fetchResultsController.sectionIndexType = sortType.asSectionIndexType
    singleFetchedResultsController = fetchedResultsController

    tableView.sectionFooterHeight = 0.0
    tableView.estimatedSectionFooterHeight = 0.0
    switch sortType {
    case .rating:
      tableView.sectionHeaderHeight = CommonScreenOperations.tableSectionHeightLarge
      tableView.estimatedSectionHeaderHeight = CommonScreenOperations.tableSectionHeightLarge
    default:
      tableView.sectionHeaderHeight = 0.0
      tableView.estimatedSectionHeaderHeight = 0.0
    }

    tableView.reloadData()
    updateRightBarButtonItems()
    detailHeaderView?.refresh()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = true
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    updateRightBarButtonItems()
    updateFromRemote()
    detailHeaderView?.refresh()
  }

  func updateRightBarButtonItems() {
    var actions = [UIMenu]()
    actions.append(createSortButtonMenu())
    if appDelegate.storage.settings.user.isOnlineMode {
      actions.append(createActionButtonMenu())
    }
    optionsButton = UIBarButtonItem.createOptionsBarButton()
    optionsButton.menu = UIMenu(children: actions)
    navigationItem.rightBarButtonItems = [optionsButton]
  }

  func updateFromRemote() {
    guard appDelegate.storage.settings.user.isOnlineMode else { return }
    switch displayFilter {
    case .all:
      break
    case .compilations, .latestReleased, .newest, .recent:
      break
    case .favorites:
      Task { @MainActor in
        do {
          try await self.appDelegate.getMeta(self.account.info).librarySyncer
            .syncFavoriteLibraryElements()
        } catch {
          self.appDelegate.eventLogger.report(topic: "Favorite Songs Sync", error: error)
        }
        self.detailHeaderView?.refresh()
        self.updateSearchResults(for: self.searchController)
      }
    }
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    let cell: PlayableTableCell = dequeueCell(for: tableView, at: indexPath)
    let song = fetchedResultsController.getWrappedEntity(at: indexPath)
    cell.display(
      playable: song,
      playContextCb: { [weak self] in self?.convertCellViewToPlayContext(cell: $0) },
      rootView: self
    )
    return cell
  }

  override func tableView(
    _ tableView: UITableView,
    heightForHeaderInSection section: Int
  )
    -> CGFloat {
    switch sortType {
    case .name:
      return super.tableView(tableView, heightForHeaderInSection: section)
    case .rating:
      return sectionHeaderHeight(forSection: section)
    case .addedDate:
      return 0.0
    case .duration:
      return 0.0
    case .starredDate:
      return 0.0
    }
  }

  override func tableView(
    _ tableView: UITableView,
    titleForHeaderInSection section: Int
  )
    -> String? {
    switch sortType {
    case .name:
      return super.tableView(tableView, titleForHeaderInSection: section)
    case .rating:
      if let sectionNameInitial = super.tableView(tableView, titleForHeaderInSection: section),
         sectionNameInitial != SectionIndexType.noRatingIndexSymbol {
        return "\(sectionNameInitial) Star\(sectionNameInitial != "1" ? "s" : "")"
      } else {
        return "Not rated"
      }
    case .addedDate:
      return nil
    case .duration:
      return nil
    case .starredDate:
      return nil
    }
  }

  func convertIndexPathToPlayContext(songIndexPath: IndexPath) -> PlayContext {
    let song = fetchedResultsController.getWrappedEntity(at: songIndexPath)

    guard let allFetchedObjects = fetchedResultsController.fetchedObjects,
          let arrayIndex = allFetchedObjects.firstIndex(of: song.managedObject)
    else { return PlayContext(containable: song) }

    let window = PlayContext.window(
      count: allFetchedObjects.count,
      index: arrayIndex,
      maxCount: appDelegate.player.maxSongsToAddOnce
    )
    let contextPlayables = window.range.map { Song(managedObject: allFetchedObjects[$0]) }
    return PlayContext(name: filterTitle, index: window.index, playables: contextPlayables)
  }

  func convertCellViewToPlayContext(cell: UITableViewCell) -> PlayContext? {
    guard let indexPath = tableView.indexPath(for: cell) else { return nil }
    return convertIndexPathToPlayContext(songIndexPath: indexPath)
  }

  override func updateSearchResults(for searchController: UISearchController) {
    guard let searchText = searchController.searchBar.text else { return }
    if !searchText.isEmpty, !searchController.searchBar.isCachedScopeSelected {
      Task { @MainActor in do {
        try await self.appDelegate.getMeta(self.account.info).librarySyncer
          .searchSongs(searchText: searchText)
      } catch {
        self.appDelegate.eventLogger.report(topic: "Songs Search", error: error)
      }}
      fetchedResultsController.search(
        searchText: searchText,
        onlyCachedSongs: false,
        displayFilter: displayFilter
      )
    } else if searchController.searchBar.isCachedScopeSelected {
      fetchedResultsController.search(
        searchText: searchText,
        onlyCachedSongs: true,
        displayFilter: displayFilter
      )
    } else if displayFilter != .all {
      fetchedResultsController.search(
        searchText: searchText,
        onlyCachedSongs: searchController.searchBar.isCachedScopeSelected,
        displayFilter: displayFilter
      )
    } else {
      fetchedResultsController.showAllResults()
    }
    tableView.reloadData()
    detailHeaderView?.refresh()
    updateContentUnavailable()
  }

  private func saveSortPreference(preference: SongElementSortType) {
    if account.apiType.asServerApiType != .ampache, displayFilter == .favorites {
      appDelegate.storage.settings.user.favoriteSongSortSetting = preference
    } else {
      appDelegate.storage.settings.user.songsSortSetting = preference
    }
  }

  private func handleHeaderPlay() -> PlayContext {
    guard let displayedSongsMO = fetchedResultsController.fetchedObjects else { return PlayContext(
      name: filterTitle,
      playables: []
    ) }
    if displayedSongsMO.count > appDelegate.player.maxSongsToAddOnce {
      let songsToPlay = displayedSongsMO.prefix(appDelegate.player.maxSongsToAddOnce)
        .compactMap { Song(managedObject: $0) }
      return PlayContext(name: filterTitle, playables: songsToPlay)
    } else {
      let songsToPlay = displayedSongsMO.compactMap { Song(managedObject: $0) }
      return PlayContext(name: filterTitle, playables: songsToPlay)
    }
  }

  private func handleHeaderShuffle() -> PlayContext {
    guard let displayedSongsMO = fetchedResultsController.fetchedObjects else { return PlayContext(
      name: filterTitle,
      playables: []
    ) }
    if displayedSongsMO.count > appDelegate.player.maxSongsToAddOnce {
      let songsToPlay = displayedSongsMO[randomPick: appDelegate.player.maxSongsToAddOnce]
        .compactMap { Song(managedObject: $0) }
      return PlayContext(name: filterTitle, playables: songsToPlay)
    } else {
      let songsToPlay = displayedSongsMO.compactMap { Song(managedObject: $0) }
      return PlayContext(name: filterTitle, playables: songsToPlay)
    }
  }

  private func createSortButtonMenu() -> UIMenu {
    let sortByName = UIAction(
      title: "Name",
      image: .letterPicker,
      state: sortType == .name ? .on : .off,
      handler: { [weak self] _ in
        guard let self else { return }
        change(sortType: .name)
        saveSortPreference(preference: .name)
        updateSearchResults(for: searchController)
        appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    let sortByRating = UIAction(
      title: "Rating",
      image: .starEmpty,
      state: sortType == .rating ? .on : .off,
      handler: { [weak self] _ in
        guard let self else { return }
        change(sortType: .rating)
        saveSortPreference(preference: .rating)
        updateSearchResults(for: searchController)
        appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    let sortByDuration = UIAction(
      title: "Duration",
      image: .timer,
      state: sortType == .duration ? .on : .off,
      handler: { [weak self] _ in
        guard let self else { return }
        change(sortType: .duration)
        saveSortPreference(preference: .duration)
        updateSearchResults(for: searchController)
        appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    let sortByStarredDate = UIAction(
      title: "Starred date",
      image: .heartEmpty,
      state: sortType == .starredDate ? .on : .off,
      handler: { [weak self] _ in
        guard let self else { return }
        change(sortType: .starredDate)
        saveSortPreference(preference: .starredDate)
        updateSearchResults(for: searchController)
        appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    let sortByAddedDate = UIAction(
      title: "Date Added",
      image: .calendarAdded,
      state: sortType == .addedDate ? .on : .off,
      handler: { [weak self] _ in
        guard let self else { return }
        change(sortType: .addedDate)
        saveSortPreference(preference: .addedDate)
        updateSearchResults(for: searchController)
        appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    if displayFilter == .favorites, account.apiType.asServerApiType != .ampache {
      return UIMenu(
        options: [.displayInline],
        children: [sortByName, sortByRating, sortByDuration, sortByStarredDate, sortByAddedDate]
      )
    } else if account.apiType.asServerApiType != .ampache {
      return UIMenu(
        options: [.displayInline],
        children: [sortByName, sortByRating, sortByDuration, sortByAddedDate]
      )
    } else {
      return UIMenu(
        options: [.displayInline],
        children: [sortByName, sortByRating, sortByDuration]
      )
    }
  }

  private func createActionButtonMenu() -> UIMenu {
    let action = UIAction(
      title: "Download \(filterTitle)",
      image: UIImage.startDownload,
      handler: { [weak self] _ in
        guard let self else { return }
        var songs = [Song]()
        switch displayFilter {
        case .all:
          songs = appDelegate.storage.main.library.getSongs(for: account)
        case .compilations, .latestReleased, .newest, .recent:
          break
        case .favorites:
          songs = appDelegate.storage.main.library
            .getFavoriteSongs(for: account)
        }
        if songs.count > AppDelegate.maxPlayablesDownloadsToAddAtOnceWithoutWarning {
          let alert = UIAlertController(
            title: "Many Songs",
            message: "Are you sure to add \(songs.count) songs from \"\(filterTitle)\" to download queue?",
            preferredStyle: .alert
          )
          alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            self.appDelegate.getMeta(self.account.info).playableDownloadManager
              .download(objects: songs)
          }))
          alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
          present(alert, animated: true, completion: nil)
        } else {
          appDelegate.getMeta(account.info).playableDownloadManager
            .download(objects: songs)
        }
      }
    )
    return UIMenu(options: [.displayInline], children: [action])
  }

  @objc
  func handleRefresh(refreshControl: UIRefreshControl) {
    guard appDelegate.storage.settings.user.isOnlineMode else {
      self.refreshControl?.endRefreshing()
      return
    }
    Task { @MainActor in
      do {
        try await AutoDownloadLibrarySyncer(
          storage: self.appDelegate.storage,
          account: self.account,
          librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
          playableDownloadManager: self.appDelegate.getMeta(self.account.info)
            .playableDownloadManager
        )
        .syncNewestLibraryElements()
      } catch {
        self.appDelegate.eventLogger.report(topic: "Songs Newest Elements Sync", error: error)
      }
      detailHeaderView?.refresh()
      self.refreshControl?.endRefreshing()
    }
  }
}

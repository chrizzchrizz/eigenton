//
//  AlbumsCommonVCInteractions.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 20.06.24.
//  Copyright (c) 2024 Maximilian Bauer. All rights reserved.
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

// MARK: - SliderMenuPopover

class SliderMenuPopover: UIViewController, UIPopoverPresentationControllerDelegate {
  var sliderMenuView: SliderMenuView {
    view as! SliderMenuView
  }

  override func loadView() {
    view = SliderMenuView()
  }

  func adaptivePresentationStyle(
    for controller: UIPresentationController,
    traitCollection: UITraitCollection
  )
    -> UIModalPresentationStyle {
    .none
  }
}

// MARK: - SliderMenuView

class SliderMenuView: UIView {
  let slider: UISlider = {
    let slider = UISlider()
    slider.translatesAutoresizingMaskIntoConstraints = false
    return slider
  }()

  var stepValue: Float = 1.0
  var sliderValueChangedCB: VoidFunctionCallback?

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    addSubview(slider)
    // keeps the thumb clear of the strongly rounded glass corners
    slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20).isActive = true
    slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20).isActive = true
    #if targetEnvironment(macCatalyst)
      slider.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    #else
      if #available(iOS 27.0, *) {
        // the popover has no arrow anymore, the content is centered
        slider.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
      } else {
        // compensates the arrow area of the popover on iOS 26
        slider.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6).isActive = true
      }
    #endif
    slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
  }

  @objc
  private func sliderValueChanged(_ sender: UISlider) {
    let newStep = roundf(slider.value / stepValue)
    slider.value = newStep * stepValue
    sliderValueChangedCB?()
  }
}

// MARK: - AlbumsCommonVCInteractions

@MainActor
class AlbumsCommonVCInteractions {
  var sceneTitle: String? {
    switch displayFilter {
    case .all: "Albums"
    case .newest: "Recently Added"
    case .recent: "Recently Played"
    case .latestReleased: "Latest Releases"
    case .favorites: "Favorite Albums"
    case .compilations: "Compilations"
    }
  }

  public var isIndexTitelsHiddenCB: VoidFunctionCallback?
  public var reloadListViewCB: VoidFunctionCallback?
  public var updateSearchResultsCB: VoidFunctionCallback?
  public var endRefreshCB: VoidFunctionCallback?
  public var updateFetchDataSourceCB: VoidFunctionCallback?

  private var appDelegate: AppDelegate = (UIApplication.shared.delegate as! AppDelegate)
  private var isSetNavbarButton = true

  public weak var rootVC: UIViewController?
  public var fetchedResultsController: AlbumFetchedResultsController!
  public var optionsButton: UIBarButtonItem = .createOptionsBarButton()
  public var displayFilter: DisplayCategoryFilter = .all
  public var sortType: AlbumElementSortType = .name
  public var filterTitle = "Albums"
  public var newestElementsOffsetsSynced = Set<Int>()
  public var isIndexTitelsHidden = false {
    didSet {
      isIndexTitelsHiddenCB?()
    }
  }

  private let account: Account

  init(account: Account, isSetNavbarButton: Bool = true) {
    self.account = account
    self.isSetNavbarButton = isSetNavbarButton
  }

  /// Header title of a section grouped by added date ("This Month", "2024", …), nil for the
  /// group without a date. Read from the fetched sections, as the section index stays empty.
  public func addedDateSectionTitle(forSection section: Int) -> String? {
    guard let sections = fetchedResultsController?.sections, sections.indices.contains(section)
    else { return nil }
    let title = sections[section].name
    return title.isEmpty ? nil : title
  }

  public var isContentUnavailable: Bool {
    fetchedResultsController.fetchedObjects?.count ?? 0 == 0
  }

  func updateContentUnavailable() {
    if isContentUnavailable {
      if fetchedResultsController.isSearchActive {
        rootVC?.contentUnavailableConfiguration = UIContentUnavailableConfiguration.search()
      } else {
        rootVC?.contentUnavailableConfiguration = emptyContentConfig
      }
    } else {
      rootVC?.contentUnavailableConfiguration = nil
    }
  }

  lazy var emptyContentConfig: UIContentUnavailableConfiguration = {
    var config = UIContentUnavailableConfiguration.empty()
    config.image = .album
    config.text = "No " + filterTitle
    config.secondaryText = "Your " + filterTitle.lowercased() + " will appear here."
    return config
  }()

  func applyFilter() {
    switch displayFilter {
    case .all:
      filterTitle = "Albums"
      isIndexTitelsHidden = false
      change(sortType: appDelegate.storage.settings.user.albumsSortSetting)
    case .newest:
      filterTitle = "Recently Added"
      isIndexTitelsHidden = true
      change(sortType: .newest)
    case .recent:
      filterTitle = "Recently Played"
      isIndexTitelsHidden = true
      change(sortType: .recent)
    case .latestReleased:
      filterTitle = "Latest Releases"
      isIndexTitelsHidden = true
      change(sortType: .year)
    case .favorites:
      filterTitle = "Favorite Albums"
      isIndexTitelsHidden = false
      change(sortType: appDelegate.storage.settings.user.albumsSortSetting)
    case .compilations:
      filterTitle = "Compilations"
      isIndexTitelsHidden = false
      change(sortType: appDelegate.storage.settings.user.albumsSortSetting)
    }
    rootVC?.setNavBarTitle(title: filterTitle)
  }

  func change(sortType: AlbumElementSortType) {
    self.sortType = sortType
    fetchedResultsController?.clearResults()
    var isGroupedInAlphabeticSections = false
    switch sortType {
    case .artist, .duration, .name, .newest, .rating, .year:
      // newest: sections by added date
      isGroupedInAlphabeticSections = true
    case .recent:
      isGroupedInAlphabeticSections = false
    }

    fetchedResultsController = AlbumFetchedResultsController(
      coreDataCompanion: appDelegate.storage.main, account: account,
      sortType: sortType,
      isGroupedInAlphabeticSections: isGroupedInAlphabeticSections,
      sortsYearByReleaseDate: displayFilter == .latestReleased
    )
    fetchedResultsController.fetchResultsController.sectionIndexType = sortType.asSectionIndexType
    updateFetchDataSourceCB?()
    fetchedResultsController.fetch()
    updateRightBarButtonItems()
    updateContentUnavailable()
  }

  func listViewWillDisplayCell(at indexPath: IndexPath, searchBarText: String?) {
    guard let elementCount = fetchedResultsController.fetchResultsController.fetchedObjects?.count
    else { return }
    guard sortType == .newest || sortType == .recent, (searchBarText ?? "").isEmpty else { return }
    // position in the whole list, the newest albums are grouped in sections
    let sections = fetchedResultsController.sections ?? []
    let row = sections.prefix(indexPath.section).reduce(0) { $0 + $1.numberOfObjects } + indexPath
      .row
    if row > 0,
       // fetch each 20th row or on last element
       row == elementCount - 1 || (row % 20 == 0),
       // this offset has not been synced yet
       !newestElementsOffsetsSynced.contains(row) {
      newestElementsOffsetsSynced.insert(row)
      updateFromRemote(offset: row, count: AmperKit.newestElementsFetchCount)
    }
  }

  func updateFromRemote(offset: Int = 0, count: Int = AmperKit.newestElementsFetchCount) {
    guard appDelegate.storage.settings.user.isOnlineMode else { return }
    switch displayFilter {
    case .all, .compilations:
      break
    case .newest:
      Task { @MainActor in
        do {
          try await AutoDownloadLibrarySyncer(
            storage: self.appDelegate.storage,
            account: account,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
          .syncNewestLibraryElements(offset: offset, count: count)
          if offset == 0 {
            try await self.syncMissingAddedDatesIfNeeded()
          }
        } catch {
          self.appDelegate.eventLogger.report(topic: "Newest Albums Sync", error: error)
        }
        self.updateSearchResultsCB?()
      }
    case .recent:
      Task { @MainActor in
        do {
          try await self.appDelegate.getMeta(self.account.info).librarySyncer
            .syncRecentAlbums(
              offset: offset,
              count: count
            )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Recent Albums Sync", error: error)
        }
        self.updateSearchResultsCB?()
      }
    case .latestReleased:
      break
    case .favorites:
      Task { @MainActor in
        do {
          try await self.appDelegate.getMeta(self.account.info).librarySyncer
            .syncFavoriteLibraryElements()
        } catch {
          self.appDelegate.eventLogger.report(topic: "Favorite Albums Sync", error: error)
        }
        self.updateSearchResultsCB?()
      }
    }
  }

  /// Accounts whose newest albums got their missing added dates in this app run
  private static var accountsWithSyncedAddedDates = Set<String>()
  /// Max albums per request (Subsonic getAlbumList2 limit)
  private static let addedDateSyncPageSize = 500

  /// Albums synced before the added date was stored (model v55) have none and would sit in a
  /// group without header at the end of the recently added list. Syncs the newest list again
  /// up to the last of them, once per account and app run; Ampache provides no added date.
  @MainActor
  private func syncMissingAddedDatesIfNeeded() async throws {
    guard account.apiType != .ampache,
          !Self.accountsWithSyncedAddedDates.contains(account.info.ident)
    else { return }
    // marked up front so a second list opened meanwhile doesn't sync again
    let accountIdent = account.info.ident
    Self.accountsWithSyncedAddedDates.insert(accountIdent)
    let lastIndex = appDelegate.storage.main.library
      .getHighestNewestIndexOfAlbumsWithoutAddedDate(for: account)
    guard lastIndex > 0 else { return }
    let librarySyncer = appDelegate.getMeta(account.info).librarySyncer
    do {
      // the newest index is 1-based
      for offset in stride(from: 0, to: lastIndex, by: Self.addedDateSyncPageSize) {
        try await librarySyncer.syncNewestAlbums(
          offset: offset,
          count: min(Self.addedDateSyncPageSize, lastIndex - offset)
        )
      }
    } catch {
      // try again the next time the list opens, e.g. after being offline
      Self.accountsWithSyncedAddedDates.remove(accountIdent)
      throw error
    }
  }

  func updateRightBarButtonItems() {
    guard isSetNavbarButton else { return }
    var actions = [UIMenu]()

    switch sortType {
    case .artist, .duration, .name, .rating, .year:
      if displayFilter != .latestReleased {
        actions.append(createSortButtonMenu())
      }
    case .newest, .recent:
      break
    }
    actions.append(createStyleButtonMenu())

    if appDelegate.storage.settings.user.isOnlineMode {
      actions.append(createActionButtonMenu())
    }

    if !actions.isEmpty {
      optionsButton = UIBarButtonItem.createOptionsBarButton()
      optionsButton.menu = UIMenu(children: actions)
      rootVC?.navigationItem.rightBarButtonItems = [optionsButton]
    } else {
      rootVC?.navigationItem.rightBarButtonItems = []
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
        appDelegate.storage.settings.user.albumsSortSetting = .name
        updateSearchResultsCB?()
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
        appDelegate.storage.settings.user.albumsSortSetting = .rating
        updateSearchResultsCB?()
        appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    let sortByArtist = UIAction(
      title: "Artist",
      image: .artist,
      state: sortType == .artist ? .on : .off,
      handler: { [weak self] _ in
        guard let self else { return }
        change(sortType: .artist)
        appDelegate.storage.settings.user.albumsSortSetting = .artist
        updateSearchResultsCB?()
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
        appDelegate.storage.settings.user.albumsSortSetting = .duration
        updateSearchResultsCB?()
        appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    let sortByYear = UIAction(
      title: "Year",
      image: .calendar,
      state: sortType == .year ? .on : .off,
      handler: { [weak self] _ in
        guard let self else { return }
        change(sortType: .year)
        appDelegate.storage.settings.user.albumsSortSetting = .year
        updateSearchResultsCB?()
        appDelegate.notificationHandler.post(
          name: .fetchControllerSortChanged,
          object: nil,
          userInfo: nil
        )
      }
    )
    return UIMenu(
      options: [.displayInline],
      children: [sortByName, sortByRating, sortByArtist, sortByDuration, sortByYear]
    )
  }

  func showSliderMenu() {
    guard let rootVC = rootVC else { return }

    let popoverContentController = SliderMenuPopover()
    let sliderMenuView = popoverContentController.sliderMenuView
    sliderMenuView.frame = CGRect(x: 0, y: 0, width: 250, height: 50)

    if UIDevice.current.userInterfaceIdiom == .mac {
      sliderMenuView.slider.minimumValue = 3
      sliderMenuView.slider.maximumValue = 11
    } else if UIDevice.current.userInterfaceIdiom == .pad {
      sliderMenuView.slider.minimumValue = 3
      sliderMenuView.slider.maximumValue = 7
    } else {
      sliderMenuView.slider.minimumValue = 2
      sliderMenuView.slider.maximumValue = 5
    }
    sliderMenuView.slider.value = min(
      max(
        sliderMenuView.slider.minimumValue,
        Float(appDelegate.storage.settings.user.albumsGridSizeSetting)
      ),
      sliderMenuView.slider.maximumValue
    )
    // the slider view stores this callback
    sliderMenuView.sliderValueChangedCB = { [weak self, weak sliderMenuView] in
      guard let self, let sliderMenuView else { return }
      let newIntValue = Int(sliderMenuView.slider.value)
      if newIntValue != appDelegate.storage.settings.user.albumsGridSizeSetting {
        appDelegate.storage.settings.user.albumsGridSizeSetting = newIntValue
        if let collectionVC = rootVC as? AlbumsCollectionVC {
          collectionVC.invalidateItemSizeCache()
          collectionVC.collectionView.reloadData()
        }
      }
    }

    popoverContentController.modalPresentationStyle = .popover
    popoverContentController.preferredContentSize = sliderMenuView.frame.size

    if let popoverPresentationController = popoverContentController.popoverPresentationController {
      popoverPresentationController.permittedArrowDirections = .up
      popoverPresentationController.delegate = popoverContentController
      popoverPresentationController.barButtonItem = optionsButton
      rootVC.present(popoverContentController, animated: true, completion: nil)
    }
  }

  private func createStyleButtonMenu() -> UIMenu {
    let tableStyle = UIAction(
      title: "Table",
      image: .listBullet,
      state: appDelegate.storage.settings.user.albumsStyleSetting == .table ? .on : .off,
      handler: { [weak self] _ in
        guard let self else { return }
        appDelegate.storage.settings.user.albumsStyleSetting = .table
        rootVC?.navigationController?.replaceCurrentlyActiveVC(
          with: AppStoryboard.Main
            .createAlbumsVC(
              account: account,
              style: appDelegate.storage.settings.user.albumsStyleSetting,
              category: displayFilter
            ),
          animated: false
        )
      }
    )
    let gridStyle = UIAction(
      title: "Grid",
      image: .grid,
      state: appDelegate.storage.settings.user.albumsStyleSetting == .grid ? .on : .off,
      handler: { [weak self] _ in
        guard let self else { return }
        appDelegate.storage.settings.user.albumsStyleSetting = .grid
        rootVC?.navigationController?.replaceCurrentlyActiveVC(
          with: AppStoryboard.Main
            .createAlbumsVC(
              account: account,
              style: appDelegate.storage.settings.user.albumsStyleSetting,
              category: displayFilter
            ),
          animated: false
        )
      }
    )
    let changeGridSize = UIAction(
      title: "Change Grid Size",
      image: .resize,
      handler: { [weak self] _ in
        guard let self else { return }
        showSliderMenu()
      }
    )
    changeGridSize
      .attributes = (appDelegate.storage.settings.user.albumsStyleSetting != .grid) ? .disabled : []

    return UIMenu(
      options: [.displayInline],
      children: [tableStyle, gridStyle, changeGridSize]
    )
  }

  private func createActionButtonMenu() -> UIMenu {
    let action = UIAction(
      title: "Download \(filterTitle)",
      image: UIImage.startDownload,
      handler: { [weak self] _ in
        guard let self else { return }
        var albums = [Album]()
        switch displayFilter {
        case .all:
          albums = appDelegate.storage.main.library.getAlbums(for: account)
        case .newest:
          albums = appDelegate.storage.main.library
            .getNewestAlbums(for: account)
        case .recent:
          albums = appDelegate.storage.main.library
            .getRecentAlbums(for: account)
        case .latestReleased:
          albums = appDelegate.storage.main.library
            .getLatestReleasedAlbums(for: account)
        case .favorites:
          albums = appDelegate.storage.main.library
            .getFavoriteAlbums(for: account)
        case .compilations:
          albums = appDelegate.storage.main.library
            .getCompilationAlbums(for: account)
        }
        let albumSongs = Array(albums.compactMap { $0.playables }.joined())
        if albumSongs.count > AppDelegate.maxPlayablesDownloadsToAddAtOnceWithoutWarning {
          let alert = UIAlertController(
            title: "Many Songs",
            message: "Are you sure to add \(albumSongs.count) songs from \"\(filterTitle)\" to download queue?",
            preferredStyle: .alert
          )
          alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            self.appDelegate.getMeta(self.account.info).playableDownloadManager
              .download(objects: albumSongs)
          }))
          alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
          rootVC?.present(alert, animated: true, completion: nil)
        } else {
          appDelegate.getMeta(account.info).playableDownloadManager
            .download(objects: albumSongs)
        }
      }
    )
    return UIMenu(options: [.displayInline], children: [action])
  }

  private var displayedSongs: [AbstractPlayable] {
    guard let displayedAlbumsMO = fetchedResultsController.fetchedObjects else { return [] }
    let displayedAlbums = displayedAlbumsMO.compactMap { Album(managedObject: $0) }
    var songs = [AbstractPlayable]()
    displayedAlbums.forEach { songs.append(contentsOf: $0.playables) }
    return songs
  }

  public func handleHeaderPlay() -> PlayContext {
    guard let displayedAlbumsMO = fetchedResultsController.fetchedObjects else { return PlayContext(
      name: filterTitle,
      playables: []
    ) }
    let firstAlbums = displayedAlbumsMO.prefix(5).compactMap { Album(managedObject: $0) }
    var songs = [AbstractPlayable]()
    firstAlbums.forEach { songs.append(contentsOf: $0.playables) }
    return PlayContext(
      name: filterTitle,
      playables: Array(songs.prefix(appDelegate.player.maxSongsToAddOnce))
    )
  }

  public func handleHeaderShuffle() -> PlayContext {
    guard let displayedAlbumsMO = fetchedResultsController.fetchedObjects else { return PlayContext(
      name: filterTitle,
      playables: []
    ) }
    let randomAlbums = displayedAlbumsMO[randomPick: 5].compactMap { Album(managedObject: $0) }
    var songs = [AbstractPlayable]()
    randomAlbums.forEach { songs.append(contentsOf: $0.playables) }
    return PlayContext(
      name: filterTitle,
      playables: Array(songs.prefix(appDelegate.player.maxSongsToAddOnce))
    )
  }

  func updateSearchResults(for searchController: UISearchController) {
    let searchText = searchController.searchBar.text ?? ""
    if !searchText.isEmpty, !searchController.searchBar.isCachedScopeSelected {
      Task { @MainActor in do {
        try await self.appDelegate.getMeta(self.account.info).librarySyncer
          .searchAlbums(searchText: searchText)
      } catch {
        self.appDelegate.eventLogger.report(topic: "Albums Search", error: error)
      }}
    }
    fetchedResultsController.search(
      searchText: searchText,
      onlyCached: searchController.searchBar.isCachedScopeSelected,
      displayFilter: displayFilter
    )
    updateContentUnavailable()
  }

  func createPlayShuffleInfoConfig() -> PlayShuffleInfoConfiguration {
    PlayShuffleInfoConfiguration(
      infoCB: { [weak self] in
        guard let self else { return "" }
        return "\(fetchedResultsController.fetchedObjects?.count ?? 0) Album\((fetchedResultsController.fetchedObjects?.count ?? 0) == 1 ? "" : "s")"
      },
      playContextCb: { [weak self] in self?.handleHeaderPlay() },
      player: appDelegate.player,
      isInfoAlwaysHidden: false,
      isShuffleOnContextNeccessary: false,
      shuffleContextCb: { [weak self] in self?.handleHeaderShuffle() }
    )
  }

  @objc
  func handleRefresh(refreshControl: UIRefreshControl) {
    guard appDelegate.storage.settings.user.isOnlineMode else {
      endRefreshCB?()
      return
    }
    Task { @MainActor in
      do {
        if self.displayFilter == .recent {
          try await self.appDelegate.getMeta(self.account.info).librarySyncer
            .syncRecentAlbums(
              offset: 0,
              count: AmperKit.newestElementsFetchCount
            )
        } else {
          try await AutoDownloadLibrarySyncer(
            storage: self.appDelegate.storage,
            account: account,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
          .syncNewestLibraryElements()
        }
      } catch {
        self.appDelegate.eventLogger.report(topic: "Albums Newest Elements Sync", error: error)
      }
      self.endRefreshCB?()
    }
  }
}

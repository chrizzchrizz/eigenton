//
//  ArtistDetailVC.swift
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

// MARK: - ArtistDetailVC

class ArtistDetailVC: MultiSourceTableViewController {
  /// The top section is needed due to display bugs
  private enum Section: Int, CaseIterable {
    case top
    case topSongs
    case albums
    case compilations
  }

  private static let topSongsLimit = 25
  private static let titleFontSizeIncrease: CGFloat = 10

  fileprivate let artist: Artist
  var albumToScrollTo: Album?
  /// Fetched results controllers that inserted, deleted or moved items since the last content change.
  private var controllersWithStructuralChange = Set<ObjectIdentifier>()
  private var albumsFetchedResultsController: ArtistAlbumsItemsFetchedResultsController!
  private var compilationsFetchedResultsController: ArtistAlbumsItemsFetchedResultsController!
  /// All songs of the artist, only used for the play and shuffle buttons of the header.
  private var songsFetchedResultsController: ArtistSongsItemsFetchedResultsController!
  private var topSongsFetchedResultsController: ArtistSongsItemsFetchedResultsController!
  private var optionsButton: UIBarButtonItem!
  private var detailOperationsView: GenericDetailTableHeader?
  private var artworkBackground: ArtworkBackgroundController!
  private let backdropView = ArtistBackdropView()
  private var albumsGridVC: ArtistAlbumsGridVC!
  private var compilationsGridVC: ArtistAlbumsGridVC!
  private var topSongsGridVC: ArtistTopSongsGridVC!
  private var similarContentFooter: SimilarContentFooterView?
  private var isLoadingSimilarContent = false
  /// Top songs ranked by the server; replace the locally computed ones as soon as they arrive.
  private var serverTopSongs = [Song]()
  private var isLoadingServerTopSongs = false
  private var didLoadServerTopSongs = false
  private var isLoadingArtistURL = false
  private var didLoadArtistURL = false
  private var artistURL: URL?
  /// The search filters the local songs only, so the server's list is not shown while searching.
  private var isSearchingTopSongs = false
  /// Offline, the server's songs are mostly not playable, so the local list is shown.
  private var isShowingServerTopSongs: Bool {
    !serverTopSongs.isEmpty && !isSearchingTopSongs
      && !appDelegate.storage.settings.user.isOfflineMode
  }

  init(account: Account, artist: Artist) {
    self.artist = artist
    super.init(style: .plain, account: account)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.separatorStyle = .none // rows draw their own separators
    appDelegate.userStatistics.visited(.artistDetail)

    optionsButton = UIBarButtonItem.createOptionsBarButton()

    albumsFetchedResultsController = ArtistAlbumsItemsFetchedResultsController(
      for: artist,
      isCompilation: false,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: false
    )
    albumsFetchedResultsController.delegate = self
    compilationsFetchedResultsController = ArtistAlbumsItemsFetchedResultsController(
      for: artist,
      isCompilation: true,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: false
    )
    compilationsFetchedResultsController.delegate = self
    songsFetchedResultsController = ArtistSongsItemsFetchedResultsController(
      for: artist,
      displayFilter: appDelegate.storage.settings.user.artistsFilterSetting,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: false
    )
    topSongsFetchedResultsController = ArtistSongsItemsFetchedResultsController(
      for: artist,
      displayFilter: appDelegate.storage.settings.user.artistsFilterSetting,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: false,
      isSortedByPlayCount: true
    )
    topSongsFetchedResultsController.delegate = self
    tableView.register(
      ArtistGridCell.self,
      forCellReuseIdentifier: ArtistGridCell.reuseID
    )

    albumsGridVC = ArtistAlbumsGridVC(
      account: account,
      albumCount: { [weak self] in
        self?.albumsFetchedResultsController.sections?[0].numberOfObjects ?? 0
      },
      album: { [weak self] row in
        self?.albumsFetchedResultsController.getWrappedEntity(at: IndexPath(row: row, section: 0))
      },
      owner: self
    )
    addChild(albumsGridVC)
    albumsGridVC.didMove(toParent: self)
    compilationsGridVC = ArtistAlbumsGridVC(
      account: account,
      albumCount: { [weak self] in
        self?.compilationsFetchedResultsController.sections?[0].numberOfObjects ?? 0
      },
      album: { [weak self] row in
        self?.compilationsFetchedResultsController.getWrappedEntity(at: IndexPath(
          row: row,
          section: 0
        ))
      },
      owner: self
    )
    addChild(compilationsGridVC)
    compilationsGridVC.didMove(toParent: self)
    topSongsGridVC = ArtistTopSongsGridVC(
      songCount: { [weak self] in self?.topSongCount ?? 0 },
      song: { [weak self] index in
        guard let songs = self?.topSongs, songs.indices.contains(index) else { return nil }
        return songs[index]
      },
      playContext: { [weak self] index in
        self?.topSongsPlayContext(index: index)
      },
      contentColor: { [weak self] in self?.artworkBackground.contentColor },
      owner: self
    )
    addChild(topSongsGridVC)
    topSongsGridVC.didMove(toParent: self)
    tableView.sectionHeaderHeight = 0.0
    tableView.estimatedSectionHeaderHeight = 0.0
    tableView.sectionFooterHeight = 0.0
    tableView.estimatedSectionFooterHeight = 0.0
    tableView.sectionHeaderTopPadding = 0.0
    tableView.backgroundColor = .clear

    configureSearchController(placeholder: "Albums and Songs", scopeButtonTitles: ["All", "Cached"])
    let artist = artist
    let playShuffleInfoConfig = PlayShuffleInfoConfiguration(
      infoCB: {
        "\(artist.albumCount) Album\(artist.albumCount == 1 ? "" : "s") \(CommonString.oneMiddleDot) \(artist.songCount) Song\(artist.songCount == 1 ? "" : "s")"
      },
      playContextCb: { [weak self] () in
        let songs = self?.songsFetchedResultsController
          .getContextSongs(
            onlyCachedSongs: self?.appDelegate.storage.settings.user
              .isOfflineMode ?? false
          ) ??
          []
        let sortedSongs = songs.filterSongs().sortByAlbum()
        return PlayContext(containable: artist, playables: sortedSongs)
      },
      player: appDelegate.player,
      isInfoAlwaysHidden: true
    )
    let detailHeaderConfig = DetailHeaderConfiguration(
      entityContainer: artist,
      rootView: self,
      tableView: tableView,
      playShuffleInfoConfig: playShuffleInfoConfig
    )
    detailOperationsView = GenericDetailTableHeader
      .createTableHeader(configuration: detailHeaderConfig)
    if let titleLabel = detailOperationsView?.titleLabel {
      let baseFont = UIFont.systemFont(
        ofSize: titleLabel.font.pointSize + Self.titleFontSizeIncrease,
        weight: .bold
      )
      titleLabel.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: baseFont)
      titleLabel.adjustsFontForContentSizeCategory = true
    }

    optionsButton = UIBarButtonItem.createOptionsBarButton()
    optionsButton.menu = UIMenu.lazyMenu { [weak self] in
      guard let self else { return [] }
      return EntityPreviewActionBuilder(container: artist, on: self).createMenuActions()
    }
    navigationItem.rightBarButtonItem = optionsButton

    // as early as possible, so the default color is barely visible during the push
    artworkBackground = ArtworkBackgroundController(
      owner: self,
      account: account,
      detailHeader: { [weak self] in self?.detailOperationsView },
      imagePath: { [weak self] setting in self?.artist.imagePath(setting: setting) }
    )
    artworkBackground.didApplyBackground = { [weak self] in
      self?.topSongsGridVC.reload()
      self?.updateBackdrop()
    }
    tableView.insertSubview(backdropView, at: 0)
    artworkBackground.update()
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
      self.artworkBackground.update(animated: true)
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = false
    artworkBackground.applyNavigationBarStyle()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    albumsFetchedResultsController?.delegate = self
    compilationsFetchedResultsController?.delegate = self
    topSongsFetchedResultsController?.delegate = self
    Task { @MainActor in
      do {
        try await artist.fetch(
          storage: self.appDelegate.storage,
          librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
          playableDownloadManager: self.appDelegate.getMeta(self.account.info)
            .playableDownloadManager
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Artist Sync", error: error)
      }
      self.detailOperationsView?.refresh()
      self.artworkBackground.update()
    }
    loadArtistURL()
    loadServerTopSongs()
    loadSimilarContent()
  }

  /// If the server knows a page of the artist (e.g. Apple Music), the name opens it.
  private func loadArtistURL() {
    guard !didLoadArtistURL, !isLoadingArtistURL else { return }
    isLoadingArtistURL = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      defer { isLoadingArtistURL = false }
      do {
        let url = try await appDelegate.getMeta(account.info).librarySyncer
          .requestArtistURL(artist: artist)
        guard let detailOperationsView else { return }
        let titleLabel = detailOperationsView.titleLabel!
        didLoadArtistURL = true
        guard let url else { return }
        artistURL = url
        detailOperationsView.hasTitleLink = true
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(UITapGestureRecognizer(
          target: self,
          action: #selector(openArtistURL)
        ))
      } catch {
        appDelegate.eventLogger.report(topic: "Artist URL", error: error, displayPopup: false)
      }
    }
  }

  @objc
  private func openArtistURL() {
    guard let artistURL else { return }
    UIApplication.shared.open(artistURL)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    similarContentFooter?.layout(in: tableView)
    layoutBackdrop()
  }

  /// The band photo lies behind the header, shown only if there is room for it (compact width).
  private func updateBackdrop() {
    let artworkDisplayPreference = appDelegate.storage.settings.accounts
      .getSetting(account.info).read.artworkDisplayPreference
    backdropView
      .load(imagePath: artist.imagePath(setting: artworkDisplayPreference)) { [weak self] in
        self?.layoutBackdrop()
      }
  }

  private func layoutBackdrop() {
    let isShown = backdropView.hasImage && traitCollection.horizontalSizeClass == .compact
    detailOperationsView?.isCoverHidden = isShown
    backdropView.isHidden = !isShown
    guard isShown, let headerHeight = tableView.tableHeaderView?.frame.height else { return }
    // reaches behind the navigation bar, up to the start of the first section
    let top = tableView.adjustedContentInset.top
    backdropView.frame = CGRect(
      x: 0,
      y: -top,
      width: tableView.bounds.width,
      height: top + headerHeight
    )
  }

  /// The server knows the popular songs of an artist (e.g. from Last.fm), the play counts of the
  /// local library only reflect what has been played. A failing or empty answer keeps the local list.
  private func loadServerTopSongs() {
    guard !didLoadServerTopSongs, !isLoadingServerTopSongs else { return }
    isLoadingServerTopSongs = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      defer { isLoadingServerTopSongs = false }
      do {
        // the server only knows the name, so songs of namesakes are dropped
        let songs = try await appDelegate.getMeta(account.info).librarySyncer
          .requestTopSongs(artist: artist, count: Self.topSongsLimit)
          .filter { $0.artist == artist }
        didLoadServerTopSongs = true
        guard !songs.isEmpty else { return }
        serverTopSongs = songs
        tableView.reloadSections([Section.topSongs.rawValue], with: .none)
      } catch {
        appDelegate.eventLogger.report(topic: "Top Songs", error: error, displayPopup: false)
      }
    }
  }

  private func loadSimilarContent() {
    // the footer is only kept once it has content, so a failed or empty load is tried again
    guard similarContentFooter == nil, !isLoadingSimilarContent else { return }
    isLoadingSimilarContent = true
    let footer = SimilarContentFooterView(account: account, owner: self)
    let artist = artist
    Task { @MainActor [weak self] in
      await footer.load(similarTo: artist)
      guard let self else { return }
      isLoadingSimilarContent = false
      guard footer.hasContent else { return }
      similarContentFooter = footer
      tableView.tableFooterView = footer
      footer.layout(in: tableView)
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // the navigation bar is shared with other screens
    artworkBackground.resetNavigationBarStyle()
    albumsFetchedResultsController?.delegate = nil
    compilationsFetchedResultsController?.delegate = nil
    topSongsFetchedResultsController?.delegate = nil
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    defer { albumToScrollTo = nil }
    guard let albumToScrollTo else { return }
    let grids: [(Section, ArtistAlbumsItemsFetchedResultsController, ArtistAlbumsGridVC)] = [
      (.albums, albumsFetchedResultsController, albumsGridVC),
      (.compilations, compilationsFetchedResultsController, compilationsGridVC),
    ]
    for (section, fetchedResultsController, gridVC) in grids {
      guard let indexPath = fetchedResultsController.fetchResultsController
        .indexPath(forObject: albumToScrollTo.managedObject) else { continue }
      // all albums of a section are inside one row
      tableView.scrollToRow(
        at: IndexPath(row: 0, section: section.rawValue),
        at: .top,
        animated: true
      )
      gridVC.scrollToAlbum(at: indexPath.row)
      return
    }
  }

  /// The top songs of the server, otherwise the most played songs of the local library.
  /// The fetched results controller ignores a fetch limit, so the songs are limited here.
  private var topSongs: [Song] {
    if isShowingServerTopSongs {
      return Array(serverTopSongs.prefix(Self.topSongsLimit))
    }
    return (topSongsFetchedResultsController.fetchedObjects ?? [])
      .prefix(Self.topSongsLimit)
      .map { Song(managedObject: $0) }
  }

  private var topSongCount: Int {
    if isShowingServerTopSongs {
      return min(serverTopSongs.count, Self.topSongsLimit)
    }
    return min(
      topSongsFetchedResultsController.sections?[0].numberOfObjects ?? 0,
      Self.topSongsLimit
    )
  }

  /// Plays the displayed top songs, starting with the selected one.
  private func topSongsPlayContext(index: Int) -> PlayContext? {
    let isOfflineMode = appDelegate.storage.settings.user.isOfflineMode
    let displayedSongs = topSongs
    guard displayedSongs.indices.contains(index) else { return nil }
    let selectedSong = displayedSongs[index]
    let songs: [AbstractPlayable] = displayedSongs.filter { !isOfflineMode || $0.isCached }
    guard let playContextIndex = songs.firstIndex(of: selectedSong) else { return nil }
    return PlayContext(containable: artist, index: playContextIndex, playables: songs)
  }

  // MARK: - Table view data source

  override func numberOfSections(in tableView: UITableView) -> Int {
    Section.allCases.count
  }

  override func tableView(
    _ tableView: UITableView,
    viewForHeaderInSection section: Int
  )
    -> UIView? {
    switch Section(rawValue: section) {
    case .albums:
      return ArtistSectionHeaderView(title: "Albums", bottomPadding: 0)
    case .compilations:
      return ArtistSectionHeaderView(title: "Compilations", bottomPadding: 0)
    case .topSongs:
      return ArtistSectionHeaderView(
        title: "Top Songs",
        bottomPadding: ArtistSectionHeaderView.contentSpacing
      )
    default:
      return nil
    }
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch Section(rawValue: section) {
    case .albums:
      // all albums are shown in one horizontally scrolling row
      return (albumsFetchedResultsController.sections?[0].numberOfObjects ?? 0) > 0 ? 1 : 0
    case .compilations:
      return (compilationsFetchedResultsController.sections?[0].numberOfObjects ?? 0) > 0 ? 1 : 0
    case .topSongs:
      // all top songs are shown in one horizontally scrolling row
      return topSongCount > 0 ? 1 : 0
    default:
      return 0
    }
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    switch Section(rawValue: indexPath.section) {
    case .albums:
      let cell = tableView.dequeueReusableCell(
        withIdentifier: ArtistGridCell.reuseID,
        for: indexPath
      ) as! ArtistGridCell
      cell.embed(gridVC: albumsGridVC)
      return cell
    case .compilations:
      let cell = tableView.dequeueReusableCell(
        withIdentifier: ArtistGridCell.reuseID,
        for: indexPath
      ) as! ArtistGridCell
      cell.embed(gridVC: compilationsGridVC)
      return cell
    case .topSongs:
      let cell = tableView.dequeueReusableCell(
        withIdentifier: ArtistGridCell.reuseID,
        for: indexPath
      ) as! ArtistGridCell
      cell.embed(gridVC: topSongsGridVC)
      return cell
    default:
      return UITableViewCell()
    }
  }

  override func tableView(
    _ tableView: UITableView,
    heightForHeaderInSection section: Int
  )
    -> CGFloat {
    switch Section(rawValue: section) {
    case .albums:
      return albumsFetchedResultsController.sections?[0]
        .numberOfObjects ?? 0 > 0 ? ArtistSectionHeaderView.height(bottomPadding: 0) : 0
    case .compilations:
      return compilationsFetchedResultsController.sections?[0]
        .numberOfObjects ?? 0 > 0 ? ArtistSectionHeaderView.height(bottomPadding: 0) : 0
    case .topSongs:
      return topSongCount > 0 ?
        ArtistSectionHeaderView.height(bottomPadding: ArtistSectionHeaderView.contentSpacing) : 0
    default:
      return 0.0
    }
  }

  override func tableView(
    _ tableView: UITableView,
    heightForRowAt indexPath: IndexPath
  )
    -> CGFloat {
    switch Section(rawValue: indexPath.section) {
    case .albums:
      return albumsGridVC.contentHeight
    case .compilations:
      return compilationsGridVC.contentHeight
    case .topSongs:
      return topSongsGridVC.contentHeight
    default:
      return 0.0
    }
  }

  override func tableView(
    _ tableView: UITableView,
    estimatedHeightForRowAt indexPath: IndexPath
  )
    -> CGFloat {
    switch Section(rawValue: indexPath.section) {
    case .albums:
      return albumsGridVC.contentHeight
    case .compilations:
      return compilationsGridVC.contentHeight
    case .topSongs:
      return topSongsGridVC.contentHeight
    default:
      return 0.0
    }
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    // albums and songs are selected inside the grids
  }

  override func updateSearchResults(for searchController: UISearchController) {
    guard let searchText = searchController.searchBar.text else { return }
    isSearchingTopSongs = !searchText.isEmpty || searchController.searchBar.isCachedScopeSelected
    if !searchText.isEmpty, !searchController.searchBar.isCachedScopeSelected {
      albumsFetchedResultsController.search(searchText: searchText, onlyCached: false)
      compilationsFetchedResultsController.search(searchText: searchText, onlyCached: false)
      topSongsFetchedResultsController.search(searchText: searchText, onlyCachedSongs: false)
    } else if searchController.searchBar.isCachedScopeSelected {
      albumsFetchedResultsController.search(searchText: searchText, onlyCached: true)
      compilationsFetchedResultsController.search(searchText: searchText, onlyCached: true)
      topSongsFetchedResultsController.search(searchText: searchText, onlyCachedSongs: true)
    } else {
      albumsFetchedResultsController.showAllResults()
      compilationsFetchedResultsController.showAllResults()
      topSongsFetchedResultsController.showAllResults()
    }
    tableView.reloadData()
  }

  override func controller(
    _ controller: NSFetchedResultsController<NSFetchRequestResult>,
    didChange anObject: Any,
    at indexPath: IndexPath?,
    for type: NSFetchedResultsChangeType,
    newIndexPath: IndexPath?
  ) {
    // the grids are updated as a whole in controllerDidChangeContent
    if type != .update {
      controllersWithStructuralChange.insert(ObjectIdentifier(controller))
    }
  }

  // The rows are not updated one by one, so the table must not be wrapped in begin/endUpdates:
  // a section gaining or losing its only row would fail the consistency check of endUpdates.
  override func controllerWillChangeContent(
    _ controller: NSFetchedResultsController<NSFetchRequestResult>
  ) {}

  override func controllerDidChangeContent(
    _ controller: NSFetchedResultsController<NSFetchRequestResult>
  ) {
    // changed values keep the cells, so the artworks are not loaded again
    let isStructuralChange = controllersWithStructuralChange
      .remove(ObjectIdentifier(controller)) != nil
    switch controller {
    case albumsFetchedResultsController.fetchResultsController:
      reloadGrid(in: .albums, isStructuralChange: isStructuralChange)
    case compilationsFetchedResultsController.fetchResultsController:
      reloadGrid(in: .compilations, isStructuralChange: isStructuralChange)
    case topSongsFetchedResultsController.fetchResultsController:
      reloadGrid(in: .topSongs, isStructuralChange: true)
    default:
      break
    }
  }

  private func reloadGrid(in section: Section, isStructuralChange: Bool) {
    // Any section can have changed its row count, not only the one of this controller
    // (e.g. the top songs switch between the server's and the local list in offline mode).
    // Re-embedding a grid does not reload it, so the grids of these sections are reloaded too.
    let changedSections = Section.allCases.filter {
      tableView(tableView, numberOfRowsInSection: $0.rawValue)
        != tableView.numberOfRows(inSection: $0.rawValue)
    }
    changedSections.forEach { gridVC(for: $0)?.reload() }
    tableView.reloadSections(IndexSet(changedSections.map(\.rawValue)), with: .none)
    guard !changedSections.contains(section) else { return }
    if isStructuralChange {
      gridVC(for: section)?.reload()
      tableView.performBatchUpdates(nil)
    } else {
      gridVC(for: section)?.reconfigure()
    }
  }

  private func gridVC(for section: Section) -> ArtistGridReloadable? {
    switch section {
    case .albums: return albumsGridVC
    case .compilations: return compilationsGridVC
    case .topSongs: return topSongsGridVC
    case .top: return nil
    }
  }

  override func controller(
    _ controller: NSFetchedResultsController<NSFetchRequestResult>,
    didChange sectionInfo: NSFetchedResultsSectionInfo,
    atSectionIndex sectionIndex: Int,
    for type: NSFetchedResultsChangeType
  ) {}
}

// MARK: - ArtistGridReloadable

@MainActor
protocol ArtistGridReloadable: AnyObject {
  func reload()
  /// Refreshes the shown items without recreating them.
  func reconfigure()
}

extension ArtistGridReloadable {
  func reconfigure() {
    reload()
  }
}

// MARK: - ArtistGridCell

/// Hosts the album or top songs row inside the table.
final class ArtistGridCell: UITableViewCell {
  static let reuseID = "ArtistGridCell"

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear
    selectionStyle = .none
    separatorInset = UIEdgeInsets(top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func embed(gridVC: UIViewController) {
    let gridView: UIView = gridVC.view
    guard gridView.superview !== contentView else { return }
    // a reused cell may still host the grid of the other section
    contentView.subviews.forEach { $0.removeFromSuperview() }
    gridView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(gridView)
    NSLayoutConstraint.activate([
      gridView.topAnchor.constraint(equalTo: contentView.topAnchor),
      gridView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      gridView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      gridView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
    ])
  }
}

// MARK: - ArtistAlbumsGridVC

/// Albums of an artist in one horizontally scrolling row with the tiles of the home screen.
final class ArtistAlbumsGridVC: UICollectionViewController, UICollectionViewDelegateFlowLayout,
  ArtistGridReloadable {
  private static let itemWidth: CGFloat = 160.0
  private static let spacing: CGFloat = 12.0
  private static let sideInset: CGFloat = 16.0
  private static let topInset = ArtistSectionHeaderView.contentSpacing
  private static let bottomInset: CGFloat = 0.0
  private static let labelsHeight: CGFloat = 50.0

  private let account: Account
  private let albumCount: () -> Int
  private let album: (Int) -> Album?
  private weak var owner: ArtistDetailVC?

  init(
    account: Account,
    albumCount: @escaping () -> Int,
    album: @escaping (Int) -> Album?,
    owner: ArtistDetailVC
  ) {
    self.account = account
    self.albumCount = albumCount
    self.album = album
    self.owner = owner
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.minimumInteritemSpacing = Self.spacing
    layout.minimumLineSpacing = Self.spacing
    layout.sectionInset = UIEdgeInsets(
      top: Self.topInset,
      left: Self.sideInset,
      bottom: Self.bottomInset,
      right: Self.sideInset
    )
    super.init(collectionViewLayout: layout)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    collectionView.backgroundColor = .clear
    collectionView.showsHorizontalScrollIndicator = false
    collectionView.register(
      UINib(nibName: AlbumCollectionCell.typeName, bundle: .main),
      forCellWithReuseIdentifier: AlbumCollectionCell.typeName
    )
  }

  func reload() {
    collectionView.reloadData()
  }

  func reconfigure() {
    collectionView.reconfigureItems(at: collectionView.indexPathsForVisibleItems)
  }

  func scrollToAlbum(at row: Int) {
    collectionView.scrollToItem(
      at: IndexPath(item: row, section: 0),
      at: .centeredHorizontally,
      animated: true
    )
  }

  // MARK: - Data source

  override func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  )
    -> Int {
    albumCount()
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  )
    -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: AlbumCollectionCell.typeName,
      for: indexPath
    ) as! AlbumCollectionCell
    if let album = album(indexPath.row) {
      cell.display(
        container: album,
        rootView: self,
        rootFlowLayout: self,
        initialIndexPath: indexPath
      )
    }
    return cell
  }

  // MARK: - Layout

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  )
    -> CGSize {
    Self.itemSize
  }

  private static let itemSize = CGSize(width: itemWidth, height: itemWidth + labelsHeight)

  /// Height of the row; the table row gets exactly this height.
  var contentHeight: CGFloat {
    albumCount() > 0 ? Self.topInset + Self.itemSize.height + Self.bottomInset : 0
  }

  // MARK: - Selection

  override func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard let album = album(indexPath.row) else { return }
    owner?.navigationController?.pushViewController(
      AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
      animated: true
    )
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    guard let album = album(indexPath.row), let owner else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: {
      let vc = EntityPreviewVC()
      vc.display(container: album, on: owner)
      Task { @MainActor in
        do {
          try await album.fetch(
            storage: owner.appDelegate.storage,
            librarySyncer: owner.appDelegate.getMeta(owner.account.info).librarySyncer,
            playableDownloadManager: owner.appDelegate.getMeta(owner.account.info)
              .playableDownloadManager
          )
        } catch {
          owner.appDelegate.eventLogger.report(topic: "Preview Sync", error: error)
        }
        vc.refresh()
      }
      return vc
    }) { _ in
      EntityPreviewActionBuilder(
        container: album,
        on: owner,
        playContextCb: { PlayContext(containable: album) }
      ).createMenu()
    }
  }
}

// MARK: - ArtistTopSongsGridVC

/// Top songs of an artist in columns of up to five rows, the columns scroll horizontally.
final class ArtistTopSongsGridVC: UICollectionViewController, UICollectionViewDelegateFlowLayout,
  ArtistGridReloadable {
  static let rowsPerColumn = 5
  /// Visible part of the next column, shows that the row can be scrolled.
  private static let peekWidth: CGFloat = 40.0
  private static let maxColumnWidth: CGFloat = 400.0

  let songCount: () -> Int
  let song: (Int) -> Song?
  let playContext: (Int) -> PlayContext?
  let contentColor: () -> UIColor?
  private(set) weak var owner: ArtistDetailVC?
  private var lastLayoutWidth: CGFloat = 0

  init(
    songCount: @escaping () -> Int,
    song: @escaping (Int) -> Song?,
    playContext: @escaping (Int) -> PlayContext?,
    contentColor: @escaping () -> UIColor?,
    owner: ArtistDetailVC
  ) {
    self.songCount = songCount
    self.song = song
    self.playContext = playContext
    self.contentColor = contentColor
    self.owner = owner
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    // the songs inside a column keep their distance to the next column with their own margins
    layout.minimumInteritemSpacing = 0
    layout.minimumLineSpacing = 0
    layout.sectionInset = .zero
    super.init(collectionViewLayout: layout)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    collectionView.backgroundColor = .clear
    collectionView.showsHorizontalScrollIndicator = false
    collectionView.decelerationRate = .fast
    collectionView.register(
      ArtistTopSongsColumnCell.self,
      forCellWithReuseIdentifier: ArtistTopSongsColumnCell.reuseID
    )
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // the column width depends on the available width, e.g. after rotating or resizing a window
    guard collectionView.bounds.width != lastLayoutWidth else { return }
    lastLayoutWidth = collectionView.bounds.width
    collectionView.collectionViewLayout.invalidateLayout()
  }

  func reload() {
    collectionView.reloadData()
  }

  private var columnCount: Int {
    (songCount() + Self.rowsPerColumn - 1) / Self.rowsPerColumn
  }

  private var rowCount: Int {
    min(songCount(), Self.rowsPerColumn)
  }

  private var columnWidth: CGFloat {
    let availableWidth = collectionView.bounds.width
    guard columnCount > 1 else { return availableWidth }
    return min(availableWidth - Self.peekWidth, Self.maxColumnWidth)
  }

  /// Height of the row; the table row gets exactly this height.
  var contentHeight: CGFloat {
    CGFloat(rowCount) * PlayableTableCell.rowHeight
  }

  // MARK: - Data source

  override func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  )
    -> Int {
    columnCount
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  )
    -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: ArtistTopSongsColumnCell.reuseID,
      for: indexPath
    ) as! ArtistTopSongsColumnCell
    let firstIndex = indexPath.item * Self.rowsPerColumn
    cell.display(
      firstIndex: firstIndex,
      rowCount: min(Self.rowsPerColumn, songCount() - firstIndex),
      gridVC: self
    )
    return cell
  }

  // MARK: - Layout

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  )
    -> CGSize {
    CGSize(width: max(columnWidth, 1), height: max(contentHeight, 1))
  }

  /// Stops at the start of a column, in the direction of the swipe.
  override func scrollViewWillEndDragging(
    _ scrollView: UIScrollView,
    withVelocity velocity: CGPoint,
    targetContentOffset: UnsafeMutablePointer<CGPoint>
  ) {
    let width = columnWidth
    guard width > 0 else { return }
    let position = scrollView.contentOffset.x / width
    let column: CGFloat
    if velocity.x > 0 {
      column = position.rounded(.up)
    } else if velocity.x < 0 {
      column = position.rounded(.down)
    } else {
      column = position.rounded()
    }
    let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
    targetContentOffset.pointee.x = min(max(0, column * width), maxOffset)
  }
}

// MARK: - ArtistTopSongsColumnCell

/// One column of the top songs, the songs use the cells of the song lists.
final class ArtistTopSongsColumnCell: UICollectionViewCell, UITableViewDataSource,
  UITableViewDelegate {
  static let reuseID = "ArtistTopSongsColumnCell"
  /// Like the header title and the album grid the songs start 16 pt from the edge.
  private static let sideInset: CGFloat = 16.0

  private let tableView = UITableView(frame: .zero, style: .plain)
  private var firstIndex = 0
  private var rowCount = 0
  private weak var gridVC: ArtistTopSongsGridVC?

  override init(frame: CGRect) {
    super.init(frame: frame)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.backgroundColor = .clear
    tableView.separatorStyle = .none // rows draw their own separators
    tableView.isScrollEnabled = false
    tableView.allowsSelection = false // the cells play on tap themselves
    tableView.rowHeight = PlayableTableCell.rowHeight
    // the columns are narrow, so the songs use the two line layout of compact width
    tableView.traitOverrides.horizontalSizeClass = .compact
    tableView.sectionHeaderTopPadding = 0
    tableView.insetsLayoutMarginsFromSafeArea = false
    tableView.preservesSuperviewLayoutMargins = false
    tableView.layoutMargins = UIEdgeInsets(
      top: 0,
      left: Self.sideInset,
      bottom: 0,
      right: Self.sideInset
    )
    tableView.register(nibName: PlayableTableCell.typeName)
    tableView.dataSource = self
    tableView.delegate = self
    contentView.addSubview(tableView)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: contentView.topAnchor),
      tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func display(firstIndex: Int, rowCount: Int, gridVC: ArtistTopSongsGridVC) {
    self.firstIndex = firstIndex
    self.rowCount = rowCount
    self.gridVC = gridVC
    // the same lines as the rows of the screen's table, which follow the artwork background
    tableView.separatorColor = gridVC.owner?.tableView.separatorColor
    tableView.reloadData()
  }

  private func songIndex(of cell: UITableViewCell) -> Int? {
    guard let indexPath = tableView.indexPath(for: cell) else { return nil }
    return firstIndex + indexPath.row
  }

  // MARK: - Table view

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    gridVC == nil ? 0 : rowCount
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    let cell: PlayableTableCell = tableView.dequeueCell(for: tableView, at: indexPath)
    guard let gridVC, let owner = gridVC.owner,
          let song = gridVC.song(firstIndex + indexPath.row) else { return cell }
    cell.contentColorOverride = gridVC.contentColor()
    cell.hidesEdgeSeparators = true
    cell.display(
      playable: song,
      playContextCb: { [weak self, weak gridVC] cell in
        guard let index = self?.songIndex(of: cell) else { return nil }
        return gridVC?.playContext(index)
      },
      rootView: owner,
      // songs of other artists on a shared album keep their artist as subtitle
      isAlbumSubtitle: song.artist == owner.artist
    )
    return cell
  }

  func tableView(
    _ tableView: UITableView,
    contextMenuConfigurationForRowAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    guard let gridVC else { return nil }
    let index = firstIndex + indexPath.row
    guard let song = gridVC.song(index), let owner = gridVC.owner else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: {
      let vc = EntityPreviewVC()
      vc.display(container: song, on: owner)
      Task { @MainActor in
        do {
          try await song.fetch(
            storage: owner.appDelegate.storage,
            librarySyncer: owner.appDelegate.getMeta(owner.account.info).librarySyncer,
            playableDownloadManager: owner.appDelegate.getMeta(owner.account.info)
              .playableDownloadManager
          )
        } catch {
          owner.appDelegate.eventLogger.report(topic: "Preview Sync", error: error)
        }
        vc.refresh()
      }
      return vc
    }) { [weak gridVC] _ in
      EntityPreviewActionBuilder(
        container: song,
        on: owner,
        playContextCb: { gridVC?.playContext(index) }
      ).createMenu()
    }
  }
}

// MARK: - ArtistSectionHeaderView

/// Section title in the style of the home screen sections.
final class ArtistSectionHeaderView: UIView {
  private static let topPadding: CGFloat = 16.0

  private static var font: UIFont {
    UIFont.systemFont(
      ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize,
      weight: .semibold
    )
  }

  /// Same size as the song titles in `PlayableTableCell` (16 pt, 14 pt on Mac).
  static var songTitleFont: UIFont {
    UIFont.systemFont(ofSize: Self.isMac ? 14.0 : 16.0, weight: .semibold)
  }

  private static var isMac: Bool {
    UIDevice.current.userInterfaceIdiom == .mac
  }

  /// Space between the title and the content below, like on the home screen.
  /// The album grid adds it as its own top inset, the song rows get it from the header.
  static let contentSpacing: CGFloat = 8.0

  /// Like on the home screen the header only is as high as its title.
  static func height(bottomPadding: CGFloat, font: UIFont = font) -> CGFloat {
    topPadding + ceil(font.lineHeight) + bottomPadding
  }

  private static let sideInset: CGFloat = 16.0

  private let titleLabel = UILabel()
  private var pinnedLeading: NSLayoutConstraint?
  private var isPinnedToTable = false

  init(title: String, bottomPadding: CGFloat, font: UIFont = font) {
    super.init(frame: .zero)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = title
    titleLabel.font = font
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .label
    addSubview(titleLabel)
    // fallback until the header is part of the table view, replaced by the table's safe area
    let fallbackLeading = titleLabel.leadingAnchor.constraint(
      equalTo: leadingAnchor,
      constant: Self.sideInset
    )
    let fallbackTrailing = titleLabel.trailingAnchor.constraint(
      equalTo: trailingAnchor,
      constant: -Self.sideInset
    )
    fallbackLeading.priority = .defaultLow
    fallbackTrailing.priority = .defaultLow
    NSLayoutConstraint.activate([
      fallbackLeading,
      fallbackTrailing,
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.topPadding),
      titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomPadding),
    ])
  }

  /// Section headers span the whole table width, also below the sidebar on Mac and iPad.
  /// Like the album grid (inside the cell's content view) the title keeps out of the safe area.
  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    guard !isPinnedToTable else { return }
    var view = superview
    while let current = view, !(current is UITableView) { view = current.superview }
    guard let tableView = view as? UITableView else { return }
    isPinnedToTable = true
    let leading = titleLabel.leadingAnchor.constraint(
      equalTo: tableView.safeAreaLayoutGuide.leadingAnchor,
      constant: Self.sideInset
    )
    pinnedLeading = leading
    NSLayoutConstraint.activate([
      leading,
      titleLabel.trailingAnchor.constraint(
        equalTo: tableView.safeAreaLayoutGuide.trailingAnchor,
        constant: -Self.sideInset
      ),
    ])
  }

  /// Starts the title where the content of the song rows starts, which is also where their
  /// separator lines start. The inset differs between iPhone, iPad and Mac.
  func alignLeading(withRowsOf tableView: UITableView) {
    guard let pinnedLeading,
          let cell = tableView.visibleCells.first(where: { $0 is BasicTableCell })
    else { return }
    let rowContent = cell.contentView.layoutMarginsGuide.layoutFrame
    let rowLeading = cell.contentView.convert(rowContent, to: tableView).minX
    let inset = rowLeading - tableView.safeAreaInsets.left
    if abs(pinnedLeading.constant - inset) > 0.01 {
      pinnedLeading.constant = inset
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - ArtistBackdropView

/// Photo of the artist that fades out towards its bottom edge.
private final class ArtistBackdropView: UIView {
  private let imageView = UIImageView()
  private let fadeMask = CAGradientLayer()
  private var loadedPath: String?

  var hasImage: Bool { imageView.image != nil }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    addSubview(imageView)
    fadeMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
    fadeMask.locations = [0, 0.45, 1]
    layer.mask = fadeMask
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    imageView.frame = bounds
    // a mask layer animates its frame implicitly, i.e. grows from the top left corner
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fadeMask.frame = bounds
    CATransaction.commit()
  }

  /// Path of the image that is currently shown, so a failed load is tried again.
  func load(imagePath: String?, completion: @escaping @MainActor () -> ()) {
    guard imagePath != loadedPath else { return }
    guard let imagePath else {
      loadedPath = nil
      imageView.image = nil
      completion()
      return
    }
    Task { @MainActor [weak self] in
      let image = await Self.loadImage(imagePath: imagePath)
      guard let self, let image else { return }
      loadedPath = imagePath
      imageView.image = image
      completion()
    }
  }

  /// The photo is only shown screen wide, so it is decoded in a reduced size.
  private nonisolated static let maxPixelSize = 1600

  @concurrent
  private static func loadImage(imagePath: String) async -> UIImage? {
    let url = URL(fileURLWithPath: imagePath) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return UIImage(cgImage: cgImage)
  }
}

//
//  AlbumDetailVC.swift
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

// MARK: - AlbumDetailDiffableDataSource

class AlbumDetailDiffableDataSource: BasicUITableViewDiffableDataSource {
  override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
    false
  }

  override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
    // Return true to be enable swipe
    true
  }
}

// MARK: - AlbumDetailVC

class AlbumDetailVC: SingleSnapshotFetchedResultsTableViewController<SongMO> {
  var songToScrollTo: Song?
  private var fetchedResultsController: AlbumSongsFetchedResultsController!
  private var optionsButton: UIBarButtonItem!
  private var detailOperationsView: GenericDetailTableHeader?
  private var artworkBackground: ArtworkBackgroundController!
  private var similarContentFooter: SimilarContentFooterView?
  private var isLoadingSimilarContent = false
  let album: Album

  init(account: Account, album: Album) {
    self.album = album
    // Mac: pinned (plain style) disc headers make the system top edge effect blur the whole
    // album header, grouped headers scroll with the rows
    super.init(
      style: UIDevice.current.userInterfaceIdiom == .mac ? .grouped : .plain,
      account: account
    )
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func createDiffableDataSource() -> BasicUITableViewDiffableDataSource {
    let source =
      AlbumDetailDiffableDataSource(tableView: tableView) { [
        weak self
      ] tableView, indexPath, objectID -> UITableViewCell? in
        guard let self else { return UITableViewCell() }
        guard let object = try? appDelegate.storage.main.context
          .existingObject(with: objectID),
          let songMO = object as? SongMO
        else {
          fatalError("Managed object should be available")
        }
        let song = Song(managedObject: songMO)
        return createCell(tableView, forRowAt: indexPath, song: song)
      }
    return source
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    appDelegate.userStatistics.visited(.albumDetail)

    optionsButton = UIBarButtonItem.createOptionsBarButton()

    fetchedResultsController = AlbumSongsFetchedResultsController(
      forAlbum: album,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: true // sections are the album's discs
    )
    singleFetchedResultsController = fetchedResultsController
    singleFetchedResultsController?.delegate = self
    singleFetchedResultsController?.fetch()
    updateDiscHeaderVisibility()
    snapshotDidChange = { [weak self] in self?.updateDiscHeaderVisibility() }

    configureSearchController(
      placeholder: "Search in \"Album\"",
      scopeButtonTitles: ["All", "Cached"]
    )
    tableView.register(nibName: PlayableTableCell.typeName)
    tableView.rowHeight = PlayableTableCell.rowHeight
    // Catalyst also need an estimate to calculate the correct height before scrolling
    tableView.estimatedRowHeight = PlayableTableCell.rowHeight
    tableView.sectionFooterHeight = 0.0
    tableView.estimatedSectionFooterHeight = 0.0
    tableView.sectionHeaderHeight = 0.0
    tableView.estimatedSectionHeaderHeight = 0.0
    tableView.separatorStyle = .none // rows draw their own separators

    let album = album
    let playShuffleInfoConfig = PlayShuffleInfoConfiguration(
      infoCB: { "\(album.songCount) Song\(album.songCount == 1 ? "" : "s")" },
      playContextCb: { [weak self] () in PlayContext(
        containable: album,
        playables: self?.fetchedResultsController
          .getContextSongs(
            onlyCachedSongs: self?.appDelegate.storage.settings.user
              .isOfflineMode ?? false
          ) ??
          []
      ) },
      player: appDelegate.player,
      isInfoAlwaysHidden: true
    )
    let detailHeaderConfig = DetailHeaderConfiguration(
      entityContainer: album,
      rootView: self,
      tableView: tableView,
      playShuffleInfoConfig: playShuffleInfoConfig
    )
    detailOperationsView = GenericDetailTableHeader
      .createTableHeader(configuration: detailHeaderConfig)

    optionsButton = UIBarButtonItem.createOptionsBarButton()
    optionsButton.menu = UIMenu.lazyMenu { [weak self] in
      guard let self else { return [] }
      return EntityPreviewActionBuilder(container: album, on: self).createMenuActions()
    }
    navigationItem.rightBarButtonItem = optionsButton

    containableAtIndexPathCallback = { [weak self] indexPath in
      self?.fetchedResultsController.getWrappedEntity(at: indexPath)
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

    // grouped style (Mac) defaults to the gray grouped background; without artwork background
    // the album should look like the other (plain) screens
    tableView.backgroundColor = .systemBackground
    // as early as possible, so the default color is barely visible during the push
    artworkBackground = ArtworkBackgroundController(
      owner: self,
      account: account,
      detailHeader: { [weak self] in self?.detailOperationsView },
      imagePath: { [weak self] setting in self?.album.imagePath(setting: setting) }
    )
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

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // the navigation bar is shared with other screens
    artworkBackground.resetNavigationBarStyle()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()

    Task { @MainActor in
      do {
        try await album.fetch(
          storage: self.appDelegate.storage,
          librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
          playableDownloadManager: self.appDelegate.getMeta(self.account.info)
            .playableDownloadManager
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Album Sync", error: error)
      }
      self.detailOperationsView?.refresh()
      self.artworkBackground.update()
    }
    loadSimilarContent()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    similarContentFooter?.layout(in: tableView)
    for header in discHeaders.allObjects {
      header.alignLeading(withRowsOf: tableView)
    }
  }

  private func loadSimilarContent() {
    // the footer is only kept once it has content, so a failed or empty load is tried again
    guard similarContentFooter == nil, !isLoadingSimilarContent else { return }
    isLoadingSimilarContent = true
    let footer = SimilarContentFooterView(account: account, owner: self)
    let album = album
    Task { @MainActor [weak self] in
      await footer.load(similarTo: album.artist, album: album)
      guard let self else { return }
      isLoadingSimilarContent = false
      guard footer.hasContent else { return }
      similarContentFooter = footer
      tableView.tableFooterView = footer
      footer.layout(in: tableView)
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    defer { songToScrollTo = nil }
    guard let songToScrollTo = songToScrollTo,
          let indexPath = fetchedResultsController.fetchResultsController
          .indexPath(forObject: songToScrollTo.managedObject)
    else { return }
    tableView.scrollToRow(at: indexPath, at: .top, animated: true)
  }

  func convertIndexPathToPlayContext(songIndexPath: IndexPath) -> PlayContext? {
    guard let songs = fetchedResultsController
      .getContextSongs(onlyCachedSongs: appDelegate.storage.settings.user.isOfflineMode)
    else { return nil }
    let selectedSong = fetchedResultsController.getWrappedEntity(at: songIndexPath)
    guard let playContextIndex = songs.firstIndex(of: selectedSong) else { return nil }
    return PlayContext(containable: album, index: playContextIndex, playables: songs)
  }

  func convertCellViewToPlayContext(cell: UITableViewCell) -> PlayContext? {
    guard let indexPath = tableView.indexPath(for: cell) else { return nil }
    return convertIndexPathToPlayContext(songIndexPath: indexPath)
  }

  func createCell(
    _ tableView: UITableView,
    forRowAt indexPath: IndexPath,
    song: Song
  )
    -> UITableViewCell {
    let cell: PlayableTableCell = dequeueCell(for: tableView, at: indexPath)
    cell.contentColorOverride = artworkBackground.contentColor
    cell.display(
      playable: song,
      playContextCb: { [weak self] cell in self?.convertCellViewToPlayContext(cell: cell) },
      rootView: self,
      isDislayAlbumTrackNumberStyle: true,
      hiddenCreatorName: album.artist?.name
    )
    return cell
  }

  /// Only albums with two or more discs show a "Disc n" header above each disc's songs.
  /// Not derived from the (possibly filtered) sections, so a search keeps the headers.
  private var isDiscHeaderVisible = false
  /// The headers follow the row content, which is only known once the rows are laid out.
  private let discHeaders = NSHashTable<ArtistSectionHeaderView>.weakObjects()

  private func updateDiscHeaderVisibility() {
    // keep the last value while searching, the results only contain a part of the album
    guard !fetchedResultsController.isSearchActive else { return }
    let discNumbers = Set(
      (fetchedResultsController.fetchedObjects ?? [])
        .compactMap { Song(managedObject: $0).discNumber }
    )
    let isVisible = discNumbers.count > 1
    guard isVisible != isDiscHeaderVisible else { return }
    isDiscHeaderVisible = isVisible
    tableView.reloadData()
  }

  /// The sections follow the raw disk strings ("1", "01" and "1/2" are different sections),
  /// so only the first section of a disc gets the header.
  private func discTitle(inSection section: Int) -> String? {
    guard let discNumber = discNumber(inSection: section) else { return nil }
    let isFirstSectionOfDisc = !(0 ..< section)
      .contains { discNumber == self.discNumber(inSection: $0) }
    return isFirstSectionOfDisc ? "Disc \(discNumber)" : nil
  }

  private func discNumber(inSection section: Int) -> Int? {
    guard let songMO = fetchedResultsController.sections?[section].objects?.first as? SongMO
    else { return nil }
    return Song(managedObject: songMO).discNumber
  }

  override func tableView(
    _ tableView: UITableView,
    viewForHeaderInSection section: Int
  )
    -> UIView? {
    guard isDiscHeaderVisible, let title = discTitle(inSection: section) else { return nil }
    let header = ArtistSectionHeaderView(
      title: title,
      bottomPadding: ArtistSectionHeaderView.contentSpacing,
      font: ArtistSectionHeaderView.songTitleFont
    )
    discHeaders.add(header)
    return header
  }

  /// The artist is hidden for songs of the album artist, those rows only have the title line.
  override func tableView(
    _ tableView: UITableView,
    heightForRowAt indexPath: IndexPath
  )
    -> CGFloat {
    let song = fetchedResultsController.getWrappedEntity(at: indexPath)
    return PlayableTableCell.isCreatorHidden(of: song, hiddenCreatorName: album.artist?.name)
      ? PlayableTableCell.singleLineRowHeight
      : PlayableTableCell.rowHeight
  }

  override func tableView(
    _ tableView: UITableView,
    heightForHeaderInSection section: Int
  )
    -> CGFloat {
    guard isDiscHeaderVisible, discTitle(inSection: section) != nil else { return 0.0 }
    return ArtistSectionHeaderView.height(
      bottomPadding: ArtistSectionHeaderView.contentSpacing,
      font: ArtistSectionHeaderView.songTitleFont
    )
  }

  override func updateSearchResults(for searchController: UISearchController) {
    fetchedResultsController.search(
      searchText: searchController.searchBar.text ?? "",
      onlyCachedSongs: searchController.searchBar.isCachedScopeSelected
    )
    tableView.reloadData()
  }
}

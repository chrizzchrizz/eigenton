//
//  AlbumsCollectionVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 19.06.24.
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

// MARK: - AlbumsCollectionDiffableDataSource

class AlbumsCollectionDiffableDataSource: BasicUICollectionViewDiffableDataSource {
  // weak: the screen owns its data source
  weak var vc: AlbumsCollectionVC?

  private var sortType: AlbumElementSortType {
    vc?.common.sortType ?? .name
  }

  init(
    vc: AlbumsCollectionVC,
    collectionView: UICollectionView,
    cellProvider: @escaping UICollectionViewDiffableDataSource<Int, NSManagedObjectID>.CellProvider
  ) {
    self.vc = vc
    super.init(collectionView: collectionView, cellProvider: cellProvider)
  }

  func getAlbum(at indexPath: IndexPath) -> Album? {
    guard let objectID = itemIdentifier(for: indexPath) else { return nil }
    guard let object = try? appDelegate.storage.main.context.existingObject(with: objectID),
          let albumMO = object as? AlbumMO
    else {
      return nil
    }
    return Album(managedObject: albumMO)
  }

  func getFirstAlbum(in section: Int) -> Album? {
    getAlbum(at: IndexPath(row: 0, section: section))
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    canMoveItemAt indexPath: IndexPath
  )
    -> Bool {
    // reordering/moving is not allowed
    false
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    viewForSupplementaryElementOfKind kind: String,
    at indexPath: IndexPath
  )
    -> UICollectionReusableView {
    guard kind == UICollectionView.elementKindSectionHeader else {
      return UICollectionReusableView()
    }
    let sectionHeader: CommonCollectionSectionHeader = collectionView
      .dequeueReusableSupplementaryView(
        ofKind: kind,
        withReuseIdentifier: CommonCollectionSectionHeader.typeName,
        for: indexPath
      ) as! CommonCollectionSectionHeader

    sectionHeader.applyHorizontalInset(leading: vc?.horizontalSectionInset.leading ?? 0)
    switch sortType {
    case .artist, .name:
      sectionHeader
        .display(title: sectionTitleToIndexTitle(sectionName: sectionTitle(for: indexPath.section)))
    case .rating, .year:
      sectionHeader.display(title: sectionTitle(for: indexPath.section))
    case .newest:
      let title = sectionTitle(for: indexPath.section)
      sectionHeader.display(title: title.isEmpty ? nil : title)
    case .duration, .recent:
      sectionHeader.display(title: nil)
    }

    if indexPath.section == 0, let vc {
      sectionHeader.displayPlayHeader(configuration: vc.common.createPlayShuffleInfoConfig())
    }
    return sectionHeader
  }

  override func indexTitles(for collectionView: UICollectionView) -> [String]? {
    // only name and artist have single-letter index titles; longer ones would cover the covers
    guard let vc, !vc.common.isIndexTitelsHidden, sortType == .name || sortType == .artist
    else { return nil }
    // UIKit checks every entry against an existing cell, so an empty grid gets no index
    let sectionCount = numberOfSections(in: collectionView)
    guard sectionCount > 0 else { return nil }
    var indexTitles = [String]()
    for i in 0 ..< sectionCount {
      // one entry per section, also without a title (album without artist), so they line up
      let indexTitle = sectionTitleToIndexTitle(sectionName: sectionTitle(for: i))
      indexTitles.append(indexTitle.isEmpty ? "#" : indexTitle)
    }
    return indexTitles
  }

  func sectionTitleToIndexTitle(sectionName: String) -> String {
    var indexTitle = ""
    switch sortType {
    case .name:
      indexTitle = sectionName.prefix(1).uppercased()
      if let _ = Int(indexTitle) {
        indexTitle = "#"
      }
    case .artist:
      indexTitle = sectionName.prefix(1).uppercased()
      if let _ = Int(indexTitle) {
        indexTitle = "#"
      }
    case .rating:
      indexTitle = IndexHeaderNameGenerator.sortByRating(forSectionName: sectionName)
    case .duration:
      indexTitle = IndexHeaderNameGenerator.sortByDurationAlbum(forSectionName: sectionName)
    case .year:
      indexTitle = IndexHeaderNameGenerator.sortByYear(forSectionName: sectionName)
    default:
      break
    }
    return indexTitle
  }

  func sectionTitle(for section: Int) -> String {
    switch sortType {
    case .name:
      guard let album = getFirstAlbum(in: section) else { return "" }
      return album.name
    case .rating:
      guard let album = getFirstAlbum(in: section) else { return "" }
      if album.rating > 0 {
        return "\(album.rating) Star\(album.rating != 1 ? "s" : "")"
      } else {
        return "Not rated"
      }
    case .newest:
      guard let album = getFirstAlbum(in: section) else { return "" }
      // the section name the list was grouped with
      return album.managedObject.addedDateSectionTitle
    case .recent:
      return ""
    case .artist:
      guard let album = getFirstAlbum(in: section) else { return "" }
      return album.subtitle ?? ""
    case .duration:
      guard let album = getFirstAlbum(in: section) else { return "" }
      return album.duration.description
    case .year:
      let year = getFirstAlbum(in: section)?.year.description
      guard let year = year else { return "" }
      return IndexHeaderNameGenerator.sortByYear(forSectionName: year)
    }
  }
}

// MARK: - AlbumsCollectionVC

class AlbumsCollectionVC: SingleSnapshotFetchedResultsCollectionViewController<AlbumMO> {
  override var sceneTitle: String? {
    common.sceneTitle
  }

  fileprivate var common: AlbumsCommonVCInteractions

  private var previousSize: CGSize = .zero
  private var cachedItemSize: CGSize?
  /// A check whether an index bar jump hid the section header is scheduled
  private var isHeaderCheckPending = false

  func invalidateItemSizeCache() {
    cachedItemSize = nil
  }

  public var displayFilter: DisplayCategoryFilter {
    set { common.displayFilter = newValue }
    get { common.displayFilter }
  }

  private var albumsDataSource: AlbumsCollectionDiffableDataSource? {
    diffableDataSource as? AlbumsCollectionDiffableDataSource
  }

  override init(collectionViewLayout: UICollectionViewLayout, account: Account) {
    self.common = AlbumsCommonVCInteractions(account: account)
    super.init(collectionViewLayout: collectionViewLayout, account: account)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func createDiffableDataSource() -> BasicUICollectionViewDiffableDataSource {
    let source = AlbumsCollectionDiffableDataSource(
      vc: self,
      collectionView: collectionView
    ) { [weak self] collectionView, indexPath, objectID -> UICollectionViewCell? in
      guard let self else { return collectionView.dequeueReusableCell(
        withReuseIdentifier: AlbumCollectionCell.typeName,
        for: indexPath
      ) }
      guard let object = try? appDelegate.storage.main.context.existingObject(with: objectID),
            let albumMO = object as? AlbumMO
      else {
        fatalError("Managed object should be available")
      }
      let album = Album(managedObject: albumMO)
      return createCell(collectionView, forItemAt: indexPath, album: album)
    }
    return source
  }

  override func loadView() {
    // own subclass to correct where the index bar jumps to (see `headerRevealingOffsetY`)
    let collectionView = TargetOffsetAdjustingCollectionView(
      frame: .zero,
      collectionViewLayout: collectionViewLayout
    )
    collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    collectionView.delegate = self
    collectionView.dataSource = self
    collectionView.adjustTargetOffsetY = { [weak self] offsetY in
      self?.headerRevealingOffsetY(forTargetOffsetY: offsetY) ?? offsetY
    }
    self.collectionView = collectionView
    view = collectionView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // ensures that the collection view stops placing items under the sidebar
    collectionView.contentInsetAdjustmentBehavior = .always

    appDelegate.userStatistics.visited(.albums)

    common.rootVC = self
    common.isIndexTitelsHiddenCB = { [weak self] in
      guard let self else { return }
      isIndexTitelsHidden = common.isIndexTitelsHidden
    }
    common.reloadListViewCB = { [weak self] in
      guard let self else { return }
      collectionView.reloadData()
    }
    common.updateSearchResultsCB = { [weak self] in
      guard let self else { return }
      updateSearchResults(for: searchController)
    }
    common.endRefreshCB = { [weak self] in
      guard let self else { return }
      refreshControl?.endRefreshing()
    }
    common.updateFetchDataSourceCB = { [weak self] in
      guard let self else { return }
      common.fetchedResultsController.delegate = self
    }

    common.applyFilter()
    configureSearchController(
      placeholder: "Search in \"\(common.filterTitle)\"",
      scopeButtonTitles: ["All", "Cached"]
    )
    collectionView.register(
      UINib(nibName: CommonCollectionSectionHeader.typeName, bundle: .main),
      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
      withReuseIdentifier: CommonCollectionSectionHeader.typeName
    )
    collectionView.register(
      UINib(nibName: AlbumCollectionCell.typeName, bundle: .main),
      forCellWithReuseIdentifier: AlbumCollectionCell.typeName
    )

    switch common.sortType {
    case .artist, .duration, .name, .rating, .year:
      collectionView.showsVerticalScrollIndicator = false
    case .newest, .recent:
      collectionView.showsVerticalScrollIndicator = true
    }

    if #available(macCatalyst 27.0, *) {
      refreshControl = UIRefreshControl()
    }

    refreshControl?.addTarget(
      common,
      action: #selector(AlbumsCommonVCInteractions.handleRefresh),
      for: UIControl.Event.valueChanged
    )
    collectionView.refreshControl = refreshControl

    containableAtIndexPathCallback = { [weak self] indexPath in
      guard let self else { return nil }
      return albumsDataSource?.getAlbum(at: indexPath)
    }
    playContextAtIndexPathCallback = { [weak self] indexPath in
      guard let self else { return nil }
      guard let album = albumsDataSource?.getAlbum(at: indexPath) else { return nil }
      return PlayContext(containable: album)
    }
    snapshotDidChange = { [weak self] in
      guard let self else { return }
      common.updateContentUnavailable()
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = true
  }

  override func viewLayoutMarginsDidChange() {
    super.viewLayoutMarginsDidChange()
    invalidateItemSizeCache()
    collectionView.collectionViewLayout.invalidateLayout()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    invalidateItemSizeCache()
    extendSafeAreaToAccountForMiniPlayer()
    common.updateRightBarButtonItems()
    common.updateFromRemote()
    common.updateContentUnavailable()
  }

  func createCell(
    _ collectionView: UICollectionView,
    forItemAt indexPath: IndexPath,
    album: Album
  )
    -> UICollectionViewCell {
    let cell: AlbumCollectionCell = collectionView.dequeueReusableCell(
      withReuseIdentifier: AlbumCollectionCell.typeName,
      for: indexPath
    ) as! AlbumCollectionCell
    if let album = (diffableDataSource as? AlbumsCollectionDiffableDataSource)?
      .getAlbum(at: indexPath) {
      cell.display(
        container: album,
        rootView: self,
        rootFlowLayout: self,
        initialIndexPath: indexPath
      )
    }
    return cell
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard let albumsDataSource = albumsDataSource,
          let album = albumsDataSource.getAlbum(at: indexPath)
    else { return }
    navigationController?.pushViewController(
      AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
      animated: true
    )
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    willDisplay cell: UICollectionViewCell,
    forItemAt indexPath: IndexPath
  ) {
    common.listViewWillDisplayCell(at: indexPath, searchBarText: searchController.searchBar.text)
  }

  override func indexTitles(for collectionView: UICollectionView) -> [String]? {
    isIndexTitelsHidden ? nil : albumsDataSource?.indexTitles(for: collectionView)
  }

  override func updateSearchResults(for searchController: UISearchController) {
    common.updateSearchResults(for: searchController)
    collectionView.reloadData()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    // Recalculate the layout when the viewController is resized
    let currentSize = view.bounds.size
    if currentSize != previousSize {
      previousSize = currentSize
      cachedItemSize = nil
      collectionView.collectionViewLayout.invalidateLayout()
    }
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    cachedItemSize = nil
    collectionView.collectionViewLayout.invalidateLayout()
  }
}

// MARK: - Index bar jump

extension AlbumsCollectionVC {
  override func scrollViewDidScroll(_ scrollView: UIScrollView) {
    // no super call: UICollectionViewController declares but doesn't implement this method
    // fallback for jumps that don't go through setContentOffset: a scroll without any touch
    // on the grid itself, checked once afterwards outside of any layout pass.
    // Not on Mac: no index bar there, but mouse wheel and keyboard scroll without a touch.
    #if !targetEnvironment(macCatalyst)
      guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating,
            !isHeaderCheckPending
      else { return }
      isHeaderCheckPending = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        isHeaderCheckPending = false
        guard !collectionView.isTracking, !collectionView.isDragging,
              !collectionView.isDecelerating
        else { return }
        let offsetY = collectionView.contentOffset.y
        let headerOffsetY = headerRevealingOffsetY(forTargetOffsetY: offsetY)
        guard headerOffsetY != offsetY else { return }
        collectionView.setContentOffset(
          CGPoint(x: collectionView.contentOffset.x, y: headerOffsetY),
          animated: false
        )
      }
    #endif
  }

  /// The index bar scrolls the first item of a section to the top, which leaves the section
  /// header behind the navigation bar. For such a target this returns the offset that shows the
  /// header (the letter) instead; any other target is returned unchanged.
  fileprivate func headerRevealingOffsetY(forTargetOffsetY offsetY: CGFloat) -> CGFloat {
    guard !common.isIndexTitelsHidden, common.sortType == .name || common.sortType == .artist,
          !collectionView.isTracking, !collectionView.isDragging, !collectionView.isDecelerating
    else { return offsetY }
    let inset = collectionView.adjustedContentInset
    let visibleTop = offsetY + inset.top
    // the item in the top leading corner must be the first of its section and sit at the top
    let probe = CGPoint(x: horizontalSectionInset.leading + 1, y: visibleTop + 1)
    guard let indexPath = collectionView.indexPathForItem(at: probe), indexPath.item == 0,
          let firstItem = collectionView.layoutAttributesForItem(at: indexPath),
          let header = collectionView.layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader,
            at: indexPath
          )
    else { return offsetY }
    let sectionInsetTop = collectionView(
      collectionView,
      layout: collectionView.collectionViewLayout,
      insetForSectionAt: indexPath.section
    ).top
    // only the exact positions the index bar jumps to (first item or its section inset at the
    // top), so wheel, keyboard or other programmatic scrolls near a section start stay as they are
    let isJumpTarget = abs(visibleTop - firstItem.frame.minY) < 0.5
      || abs(visibleTop - (firstItem.frame.minY - sectionInsetTop)) < 0.5
    guard isJumpTarget else { return offsetY }
    let headerOffsetY = max(header.frame.minY - inset.top, -inset.top)
    return min(headerOffsetY, offsetY)
  }
}

// MARK: - TargetOffsetAdjustingCollectionView

/// Lets the screen correct the target of programmatic scrolls, such as the index bar's jump,
/// before they start, so an animated jump ends at the corrected position right away.
private final class TargetOffsetAdjustingCollectionView: UICollectionView {
  var adjustTargetOffsetY: ((CGFloat) -> CGFloat)?

  override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
    var target = contentOffset
    if let adjustTargetOffsetY {
      target.y = adjustTargetOffsetY(contentOffset.y)
    }
    super.setContentOffset(target, animated: animated)
  }
}

// MARK: - AlbumsCollectionVC + UICollectionViewDelegateFlowLayout

extension AlbumsCollectionVC: UICollectionViewDelegateFlowLayout {
  static let minimumLineSpacing: CGFloat = 16
  static let minimumInteritemSpacing: CGFloat = 16

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  )
    -> CGSize {
    if let cachedItemSize {
      return cachedItemSize
    }
    let inset = self.collectionView(
      collectionView,
      layout: collectionViewLayout,
      insetForSectionAt: indexPath.section
    )

    let gridSize = appDelegate.storage.settings.user.albumsGridSizeSetting
    let marginsAndInsets = inset.left + inset.right + collectionView.safeAreaInsets
      .left + collectionView.safeAreaInsets.right + Self
      .minimumInteritemSpacing *
      CGFloat(gridSize - 1)
    let itemWidth =
      (
        (collectionView.bounds.size.width - marginsAndInsets) /
          CGFloat(gridSize)
      ).rounded(.down)
    let itemSize = CGSize(width: itemWidth, height: itemWidth + 45)
    cachedItemSize = itemSize
    return itemSize
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    minimumLineSpacingForSectionAt section: Int
  )
    -> CGFloat {
    Self.minimumLineSpacing
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    minimumInteritemSpacingForSectionAt section: Int
  )
    -> CGFloat {
    Self.minimumInteritemSpacing
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  )
    -> UIEdgeInsets {
    // more room between the albums of a section and the header of the next one;
    // sections without a header continue the grid seamlessly
    let bottom: CGFloat = hasSectionHeader(section + 1) || displayFilter == .latestReleased ? 32 : 8
    let inset = horizontalSectionInset
    return UIEdgeInsets(top: 8, left: inset.leading, bottom: bottom, right: inset.trailing)
  }

  /// Horizontal margin of the items, derived from the system layout margins.
  /// The safe area is already excluded from the content area, so it is not counted twice.
  var horizontalSectionInset: (leading: CGFloat, trailing: CGFloat) {
    let margins = collectionView.directionalLayoutMargins
    let safeArea = collectionView.safeAreaInsets
    return (
      leading: max(0, margins.leading - safeArea.left),
      trailing: max(0, margins.trailing - safeArea.right)
    )
  }

  /// Whether the section shows a title header (false for sections past the end)
  private func hasSectionHeader(_ section: Int) -> Bool {
    guard section < collectionView.numberOfSections else { return false }
    switch common.sortType {
    case .artist, .name, .rating, .year:
      return true
    case .newest:
      return !(albumsDataSource?.sectionTitle(for: section) ?? "").isEmpty
    case .duration, .recent:
      return false
    }
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    referenceSizeForHeaderInSection section: Int
  )
    -> CGSize {
    let headerTopHeight = section == 0 ? LibraryElementDetailTableHeaderView.frameHeight : 0.0
    let titleHeight = hasSectionHeader(section) ? CommonCollectionSectionHeader.frameHeight : 0.0
    return CGSize(width: collectionView.bounds.size.width, height: titleHeight + headerTopHeight)
  }
}

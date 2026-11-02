//
//  HomeVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 24.11.25.
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

// MARK: - HomeVC

final class HomeVC: UICollectionViewController {
  // MARK: - Properties

  private var dataSource: UICollectionViewDiffableDataSource<HomeSection, HomeItem>!
  private let log = OSLog(subsystem: "Amperfy", category: "HomeVC")

  private static let itemWidth: CGFloat = 160.0

  private let account: Account
  private var accountNotificationHandler: AccountNotificationHandler?
  private let sharedHome: HomeManager
  /// lazy: the account change callback arranges the buttons already while it is registered
  private lazy var editButton = {
    let button = UIBarButtonItem(
      image: UIImage.pencil,
      style: .plain,
      target: self,
      action: #selector(editSectionsTapped)
    )
    // own background, iOS otherwise joins it with its neighbours (Mac: see applyMacTrailingItemGroups)
    button.sharesBackground = false
    return button
  }()

  #if targetEnvironment(macCatalyst)
    /// on Mac the downloads are opened from Home, on iOS from the library
    private lazy var downloadsButton = DownloadsBarButton(account: account) { [weak self] in
      self?.showLibraryList(.downloads)
    }
  #endif

  // MARK: - Init

  init(account: Account) {
    self.account = account
    let appDelegate = (UIApplication.shared.delegate as! AppDelegate)
    self.sharedHome = HomeManager(
      account: account,
      storage: appDelegate.storage,
      getMeta: appDelegate.getMeta,
      eventLogger: appDelegate.eventLogger
    )
    let sectionLookup = SectionLookup()
    let layout = HomeVC.createLayout(sectionLookup: sectionLookup)
    super.init(collectionViewLayout: layout)
    sectionLookup.homeVC = self
    sharedHome.applySnapshotCB = { [weak self] in
      guard let self else { return }
      applySnapshot(animated: true)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    // ensures that the collection view stops placing items under the sidebar
    collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
    collectionView.topEdgeEffect.style = .soft
    // hide the small inline title that fades in when the large title scrolls away
    let inlineTitleAppearance = UINavigationBarAppearance()
    inlineTitleAppearance.configureWithDefaultBackground()
    inlineTitleAppearance.titleTextAttributes = [.foregroundColor: UIColor.clear]
    navigationItem.standardAppearance = inlineTitleAppearance
    title = "Home"

    accountNotificationHandler = AccountNotificationHandler(
      storage: appDelegate.storage,
      notificationHandler: appDelegate.notificationHandler
    )
    accountNotificationHandler?.registerCallbackForActiveAccountChange { [weak self] accountInfo in
      guard let self else { return }
      setupUserNavButton()
      arrangeNavButtonsForMac()
      refreshContinuePlaybackNavButton()
    }

    navigationController?.navigationBar.prefersLargeTitles = true
    navigationItem.rightBarButtonItem = editButton
    arrangeNavButtonsForMac()
    configureCollectionView()
    configureDataSource()
    sharedHome.createFetchController()
    applySnapshot(animated: false)

    appDelegate.notificationHandler.register(
      self,
      selector: #selector(refreshOfflineMode),
      name: .offlineModeChanged,
      object: nil
    )
  }

  /// On Mac the downloads button joins the edit button, each in its own toolbar group.
  private func arrangeNavButtonsForMac() {
    #if targetEnvironment(macCatalyst)
      applyMacTrailingItemGroups()
    #endif
  }

  #if targetEnvironment(macCatalyst)
    /// Mac turns the right bar button items into one toolbar group with a single glass background
    /// and ignores `sharesBackground`; one group per item gives every button its own background.
    /// Order is left to right: downloads, edit, continue playback.
    private func applyMacTrailingItemGroups() {
      var items: [UIBarButtonItem] = [downloadsButton.item, editButton]
      if appDelegate.isContinuePlaybackAvailable {
        items.append(continuePlaybackNavButton)
      }
      navigationItem.trailingItemGroups = items.map { .fixedGroup(items: [$0]) }
    }
  #endif

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = true
    // the play queue sync may have been switched in the settings
    refreshContinuePlaybackNavButton()
  }

  private lazy var continuePlaybackNavButton = {
    let button = UIBarButtonItem(
      image: .continuePlayback,
      primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        appDelegate.continuePlaybackFromOtherDevice(presentingVC: self)
      }
    )
    button.accessibilityLabel = "Sync Play Queue"
    // own glass background, it has nothing to do with the edit button next to it
    button.sharesBackground = false
    return button
  }()

  /// Rightmost item.
  private func refreshContinuePlaybackNavButton() {
    #if targetEnvironment(macCatalyst)
      applyMacTrailingItemGroups()
    #else
      var items = navigationItem.rightBarButtonItems ?? []
      items.removeAll { $0 === continuePlaybackNavButton }
      if appDelegate.isContinuePlaybackAvailable {
        items.insert(continuePlaybackNavButton, at: 0)
      }
      navigationItem.rightBarButtonItems = items
    #endif
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    sharedHome.updateFromRemote()
  }

  // MARK: - Layout

  /// Extra space between the large navigation title and the first section.
  private static let firstSectionTopSpacing: CGFloat = 16

  /// The layout is created before the view controller exists, it looks up the sections later.
  @MainActor
  private final class SectionLookup {
    weak var homeVC: HomeVC?

    func section(at index: Int) -> HomeSection? {
      homeVC?.dataSource?.sectionIdentifier(for: index)
    }
  }

  /// Layout and cell provider both decide with this whether a section shows playlist tiles
  private static func showsPlaylistTiles(_ section: HomeSection?) -> Bool {
    section == .lastTimePlayedPlaylists
  }

  private static func createLayout(sectionLookup: SectionLookup)
    -> UICollectionViewCompositionalLayout {
    let layout = UICollectionViewCompositionalLayout { sectionIndex, _ in
      guard let _ = HomeSection(rawValue: sectionIndex) else { return nil }
      // playlist tiles have a fixed aspect ratio, the other cells size themselves
      let groupHeight: NSCollectionLayoutDimension =
        showsPlaylistTiles(sectionLookup.section(at: sectionIndex))
          ? .absolute(PlaylistCollectionCell.height(forWidth: itemWidth))
          : .estimated(210)

      // Item: square image with title below -> estimate height accommodates label
      let itemSize = NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0),
        heightDimension: .fractionalHeight(1.0)
      )
      let item = NSCollectionLayoutItem(layoutSize: itemSize)

      // Group: fixed width to show large image; height estimated to fit image + label
      // We'll use a vertical group containing the cell's content; the cell itself handles layout.
      let groupSize = NSCollectionLayoutSize(
        widthDimension: .absolute(itemWidth),
        heightDimension: groupHeight
      )
      let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

      let sectionLayout = NSCollectionLayoutSection(group: group)
      sectionLayout.orthogonalScrollingBehavior = .continuous
      sectionLayout.interGroupSpacing = 12
      // horizontal margin comes from the collection view's layoutMargins (system-adaptive)
      sectionLayout.contentInsetsReference = .layoutMargins
      sectionLayout.contentInsets = NSDirectionalEdgeInsets(
        top: 6,
        leading: 0,
        bottom: 30,
        trailing: 0
      )

      // Header
      let headerSize = NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0),
        heightDimension: .estimated(44)
      )
      let header = NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: headerSize,
        elementKind: UICollectionView.elementKindSectionHeader,
        alignment: .top
      )
      // horizontal margin is already applied to the header via the section's layout margins
      header.pinToVisibleBounds = false
      header.zIndex = 1
      sectionLayout.boundarySupplementaryItems = [header]

      return sectionLayout
    }
    return layout
  }

  // MARK: - CollectionView Setup

  private func configureCollectionView() {
    collectionView.backgroundColor = .systemBackground
    collectionView.register(
      UINib(nibName: AlbumCollectionCell.typeName, bundle: .main),
      forCellWithReuseIdentifier: AlbumCollectionCell.typeName
    )
    collectionView.register(
      PlaylistCollectionCell.self,
      forCellWithReuseIdentifier: PlaylistCollectionCell.typeName
    )
    collectionView.register(
      SectionHeaderView.self,
      forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
      withReuseIdentifier: SectionHeaderView.reuseID
    )
  }

  // MARK: - Data Source

  private func configureDataSource() {
    dataSource = UICollectionViewDiffableDataSource<
      HomeSection,
      HomeItem
    >(collectionView: collectionView) { collectionView, indexPath, item in
      if Self.showsPlaylistTiles(item.section),
         let playlist = item.playableContainable as? Playlist {
        let cell = collectionView.dequeueReusableCell(
          withReuseIdentifier: PlaylistCollectionCell.typeName,
          for: indexPath
        ) as! PlaylistCollectionCell
        cell.display(playlist: playlist, subtitle: item.playlistSubtitle)
        return cell
      }
      let cell = collectionView.dequeueReusableCell(
        withReuseIdentifier: AlbumCollectionCell.typeName,
        for: indexPath
      ) as! AlbumCollectionCell
      cell.display(
        container: item.playableContainable,
        rootView: self,
        itemWidth: Self.itemWidth,
        initialIndexPath: indexPath,
        isImageCircular: [.favoriteArtists, .randomArtists]
          .contains(self.dataSource.sectionIdentifier(for: indexPath.section))
      )
      return cell
    }

    dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
      guard let self,
            kind == UICollectionView.elementKindSectionHeader,
            let header = collectionView.dequeueReusableSupplementaryView(
              ofKind: kind,
              withReuseIdentifier: SectionHeaderView.reuseID,
              for: indexPath
            ) as? SectionHeaderView,
            let section = dataSource.snapshot().sectionIdentifiers.element(at: indexPath.section)
      else {
        return nil
      }
      header.setRefreshMenu(nil)
      header.title = section.headerTitle
      if let displayType = section.libraryDisplayType {
        header.setTapHandler { [weak self] in self?.showLibraryList(displayType) }
      } else {
        header.setTapHandler(nil)
      }
      header.topInset = indexPath.section == 0 ? Self.firstSectionTopSpacing : 0
      if section == .randomAlbums {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomAlbumsSection() }
      } else if section == .compilations {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshCompilationsSection() }
      } else if section == .randomArtists {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomArtistsSection() }
      } else if section == .favoriteAlbums {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshFavoriteAlbumsSection() }
      } else if section == .favoriteArtists {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshFavoriteArtistsSection() }
      } else if section == .randomGenres {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomGenresSection() }
      } else if section == .randomSongs {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in self?.refreshRandomSongsSection() }
      } else if section.isFixedDecadeOrGenre {
        header.showsRefreshButton = true
        header.setRefreshHandler { [weak self] in
          guard let self else { return }
          Task { @MainActor in
            await self.sharedHome.updateFixedDecadeOrGenreAlbums(
              section,
              isOfflineMode: self.sharedHome.isOfflineMode
            )
            self.scrollSectionToStart(section)
          }
        }
      } else {
        header.showsRefreshButton = false
        header.setRefreshHandler(nil)
      }
      return header
    }
  }

  private func applySnapshot(animated: Bool = true) {
    var snapshot = NSDiffableDataSourceSnapshot<HomeSection, HomeItem>()
    // decade and genre sections are hidden as long as they have no albums
    let sections = sharedHome.orderedVisibleSections.filter {
      !$0.isFixedDecadeOrGenre || !(sharedHome.data[$0] ?? []).isEmpty
    }
    snapshot.appendSections(sections)
    for section in sections {
      // Ids are stable per entity, so a repeated entity would be a duplicate identifier (assert).
      var seenIds = Set<String>()
      let items = (sharedHome.data[section] ?? []).filter { seenIds.insert($0.id).inserted }
      snapshot.appendItems(items, toSection: section)
    }
    let oldItems = dataSource.snapshot().itemIdentifiers
    let oldItemsById = Dictionary(oldItems.map { ($0.id, $0) }) { first, _ in first }
    let changedItems = snapshot.itemIdentifiers.filter {
      guard let old = oldItemsById[$0.id] else { return false }
      return old.artworkFingerprint != $0.artworkFingerprint ||
        old.playlistSubtitle != $0.playlistSubtitle
    }
    snapshot.reconfigureItems(changedItems)
    dataSource.apply(snapshot, animatingDifferences: animated)
  }

  @objc
  private func refreshOfflineMode() {
    os_log("HomeVC: OfflineModeChanged", log: self.log, type: .info)
    sharedHome.createFetchController()
    refreshContinuePlaybackNavButton()
  }

  @objc
  private func editSectionsTapped() {
    presentSectionEditor()
  }

  private func presentSectionEditor() {
    // Build a simple editor using a temporary UIViewController with a table view
    let editor = HomeEditorVC(
      order: appDelegate.storage.settings.accounts.getSetting(account.info).read.homeSectionOrder,
      visible: sharedHome.orderedVisibleSections
    ) { [weak self] order, visible in
      guard let self else { return }
      sharedHome.orderedVisibleSections = visible
      // same account the order was read from
      appDelegate.storage.settings.accounts.updateSetting(account.info) { accountSettings in
        accountSettings.homeSections = visible
        accountSettings.homeSectionOrder = order
      }
      applySnapshot(animated: true)

      sharedHome.createFetchController()
      sharedHome.updateFromRemote()
    }
    #if targetEnvironment(macCatalyst)
      // reordering via drag & drop did not drop inside a form sheet on macOS
      // revert to the form sheet once fixed: https://developer.apple.com/forums/thread/850756
      navigationController?.pushViewController(editor, animated: true)
    #else
      let nav = UINavigationController(rootViewController: editor)
      nav.modalPresentationStyle = .formSheet
      present(nav, animated: true)
    #endif
  }

  @objc
  func refreshRandomAlbumsSection() {
    Task { @MainActor in
      await sharedHome.updateRandomAlbums(isOfflineMode: sharedHome.isOfflineMode)
      scrollSectionToStart(.randomAlbums)
    }
  }

  @objc
  func refreshCompilationsSection() {
    Task { @MainActor in
      await sharedHome.updateCompilations(isOfflineMode: sharedHome.isOfflineMode)
      scrollSectionToStart(.compilations)
    }
  }

  @objc
  func refreshRandomArtistsSection() {
    Task { @MainActor in
      await sharedHome.updateRandomArtists(isOfflineMode: sharedHome.isOfflineMode)
      scrollSectionToStart(.randomArtists)
    }
  }

  @objc
  func refreshFavoriteAlbumsSection() {
    Task { @MainActor in
      await sharedHome.updateFavoriteAlbums(isOfflineMode: sharedHome.isOfflineMode)
      scrollSectionToStart(.favoriteAlbums)
    }
  }

  @objc
  func refreshFavoriteArtistsSection() {
    Task { @MainActor in
      await sharedHome.updateFavoriteArtists(isOfflineMode: sharedHome.isOfflineMode)
      scrollSectionToStart(.favoriteArtists)
    }
  }

  @objc
  func refreshRandomGenresSection() {
    Task { @MainActor in
      await sharedHome.updateRandomGenres()
      scrollSectionToStart(.randomGenres)
    }
  }

  @objc
  func refreshRandomSongsSection() {
    Task { @MainActor in
      await sharedHome.updateRandomSongs(isOfflineMode: sharedHome.isOfflineMode)
      scrollSectionToStart(.randomSongs)
    }
  }

  // MARK: - Section Navigation

  private func showLibraryList(_ displayType: LibraryDisplayType) {
    navigationController?.pushViewController(
      displayType.controller(account: account, settings: appDelegate.storage.settings),
      animated: true
    )
    navigationController?.navigationBar.prefersLargeTitles = false
  }

  /// After a reload the section shows new content, so bring its horizontal list back to the first item.
  private func scrollSectionToStart(_ section: HomeSection) {
    let snapshot = dataSource.snapshot()
    guard let sectionIndex = snapshot.indexOfSection(section),
          snapshot.numberOfItems(inSection: section) > 0 else { return }
    collectionView.scrollToItem(
      at: IndexPath(item: 0, section: sectionIndex),
      at: .left,
      animated: true
    )
  }

  // MARK: - Selection Handling

  override func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard let playableContainer = dataSource.itemIdentifier(for: indexPath)?.playableContainable
    else { return }

    if let album = playableContainer as? Album {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let artist = playableContainer as? Artist {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let playlist = playableContainer as? Playlist {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToPlaylistDetail(account: account, playlist: playlist),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let song = playableContainer as? Song {
      appDelegate.player.play(context: PlayContext(containable: song))
    } else if let podcastEpisode = playableContainer as? PodcastEpisode,
              let podcast = podcastEpisode.podcast {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToPodcastDetail(
          account: account,
          podcast: podcast,
          episodeToScrollTo: podcastEpisode
        ),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let podcast = playableContainer as? Podcast {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToPodcastDetail(account: account, podcast: podcast),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let _ = playableContainer as? Radio {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToRadios(account: account),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    } else if let genre = playableContainer as? Genre {
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToGenreDetail(account: account, genre: genre),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
    }
  }
}

extension HomeVC {
  override func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    guard let containable = dataSource.itemIdentifier(for: indexPath)?.playableContainable
    else { return nil }

    let identifier = NSString(string: TableViewPreviewInfo(
      playableContainerIdentifier: containable.containerIdentifier,
      indexPath: indexPath
    ).asJSONString())
    return UIContextMenuConfiguration(identifier: identifier, previewProvider: {
      let vc = EntityPreviewVC()
      vc.display(container: containable, on: self)
      Task { @MainActor in
        do {
          try await containable.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Preview Sync", error: error)
        }
        vc.refresh()
      }
      return vc
    }) { suggestedActions in
      var playIndexCB: (() -> PlayContext?)?
      playIndexCB = { PlayContext(containable: containable) }
      return EntityPreviewActionBuilder(
        container: containable,
        on: self,
        playContextCb: playIndexCB
      ).createMenu()
    }
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionCommitAnimating
  ) {
    animator.addCompletion {
      if let identifier = configuration.identifier as? String,
         let tvPreviewInfo = TableViewPreviewInfo.create(fromIdentifier: identifier),
         let containerIdentifier = tvPreviewInfo.playableContainerIdentifier,
         let container = self.appDelegate.storage.main.library
         .getContainer(identifier: containerIdentifier) {
        EntityPreviewActionBuilder(container: container, on: self).performPreviewTransition()
      }
    }
  }
}

// MARK: - SectionHeaderView

final class SectionHeaderView: UICollectionReusableView {
  static let reuseID = "SectionHeaderView"

  private let refreshButton: UIButton = {
    let btn = UIButton(type: .system)
    btn.translatesAutoresizingMaskIntoConstraints = false
    btn.setImage(UIImage.refresh, for: .normal)
    btn.isHidden = true
    btn.accessibilityLabel = "Refresh Randoms"
    return btn
  }()

  private let titleLabel: UILabel = {
    let lbl = UILabel()
    lbl.translatesAutoresizingMaskIntoConstraints = false
    lbl.font = UIFont.preferredFont(forTextStyle: .title3).withWeight(.semibold)
    lbl.textColor = .label
    return lbl
  }()

  var showsRefreshButton: Bool {
    get { !refreshButton.isHidden }
    set { refreshButton.isHidden = !newValue }
  }

  func setRefreshHandler(_ handler: (() -> ())?) {
    refreshButton.removeTarget(nil, action: nil, for: .allEvents)
    guard let handler else { return }
    refreshButton.addAction(UIAction { _ in handler() }, for: .touchUpInside)
  }

  /// Shown on long press of the refresh button.
  func setRefreshMenu(_ menu: UIMenu?) {
    refreshButton.menu = menu
    refreshButton.showsMenuAsPrimaryAction = false
  }

  var title: String? {
    didSet { updateTitle() }
  }

  private func updateTitle() {
    guard let title else {
      titleLabel.attributedText = nil
      return
    }
    let result = NSMutableAttributedString(string: title)
    if tapHandler != nil {
      let pointSize = UIFont.preferredFont(forTextStyle: .subheadline).pointSize + 2
      let config = UIImage.SymbolConfiguration(
        pointSize: pointSize,
        weight: .semibold,
        scale: .small
      )
      let attachment = NSTextAttachment()
      attachment.image = UIImage(systemName: "chevron.right", withConfiguration: config)?
        .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
      result.append(NSAttributedString(string: " "))
      result.append(NSAttributedString(attachment: attachment))
    }
    titleLabel.attributedText = result
  }

  private var tapHandler: (() -> ())?

  func setTapHandler(_ handler: (() -> ())?) {
    tapHandler = handler
    updateTitle()
    isUserInteractionEnabled = true
    accessibilityTraits = handler == nil ? [] : .button
  }

  @objc
  private func headerTapped() {
    tapHandler?()
  }

  /// Extra space above the title, e.g. between the large navigation title and the first section.
  var topInset: CGFloat = 0 {
    didSet { titleTopConstraint.constant = topInset }
  }

  private lazy var titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: topAnchor)

  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(titleLabel)
    addSubview(refreshButton)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: refreshButton.leadingAnchor,
        constant: -8
      ),
      titleTopConstraint,
      titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
      refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
      refreshButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    addSubview(titleLabel)
    addSubview(refreshButton)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: refreshButton.leadingAnchor,
        constant: -8
      ),
      titleTopConstraint,
      titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
      refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
      refreshButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
    ])
  }
}

extension UIFont {
  fileprivate func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let descriptor = fontDescriptor.addingAttributes([
      UIFontDescriptor.AttributeName.traits: [UIFontDescriptor.TraitKey.weight: weight],
    ])
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}

extension HomeSection {
  /// The library overview matching this section; nil if there is none (e.g. random sections).
  fileprivate var libraryDisplayType: LibraryDisplayType? {
    switch self {
    case .recentlyPlayedAlbums: return .recentAlbums
    case .newestAlbums: return .newestAlbums
    case .latestReleasedAlbums: return .latestReleasedAlbums
    case .compilations: return .compilations
    case .favoriteAlbums: return .favoriteAlbums
    case .favoriteArtists: return .favoriteArtists
    case .lastTimePlayedPlaylists: return .playlists
    case .podcasts: return .podcasts
    case .radios: return .radios
    case .newestPodcastEpisodes, .randomAlbums, .randomArtists,
         .randomGenres, .randomSongs:
      return nil
    default:
      return nil
    }
  }
}

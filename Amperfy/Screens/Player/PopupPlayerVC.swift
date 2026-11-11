//
//  PopupPlayerVC.swift
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
import CoreMedia
import UIKit

// MARK: - PopupPlayerLayout

enum PopupPlayerLayout {
  /// big artwork above the title
  case large
  /// small artwork and title in the first row of the queue
  case compact
  /// small artwork and title in a header, the lyrics fill the space below
  case lyrics
}

// MARK: - PopupPlayerVC

class PopupPlayerVC: UIViewController, UIScrollViewDelegate {
  @IBOutlet
  weak var tableView: UITableView!
  @IBOutlet
  weak var largePlayerPlaceholderView: UIView!
  @IBOutlet
  weak var controlPlaceholderView: UIView!
  @IBOutlet
  weak var backgroundColorView: UIImageView!

  lazy var tableViewKeyCommandsController = TableViewKeyCommandsController(
    tableView: tableView,
    overrideFirstLastIndexPath: IndexPath(
      row: 0,
      section: PlayerSectionCategory.currentlyPlaying.rawValue
    )
  )

  /// Mac: shown as a child overlay of the split view instead of being presented
  var isOverlay = false

  var player: PlayerFacade!
  var playerHandler: PlayerUIHandler?
  var controlView: PlayerControlView?
  var largeCurrentlyPlayingView: LargeCurrentlyPlayingPlayerView?
  var accountNotificationHandler: AccountNotificationHandler?
  private var windowStyleObservation: (any UITraitChangeRegistration)?

  var currentlyPlayingTableCell: CurrentlyPlayingTableCell?
  var currentLayout: PopupPlayerLayout?
  let lyricsLayoutView = UIView()
  let lyricsContainerView = UIView()
  var lyricsHeaderCell: CurrentlyPlayingTableCell?
  private var lyricsBelowHeaderConstraint: NSLayoutConstraint?
  private var lyricsWithoutHeaderConstraint: NSLayoutConstraint?
  /// Regular width in landscape: the player stays on the left, queue and lyrics are shown on the right.
  private(set) var isSideBySide = false
  private var stackedConstraints = [NSLayoutConstraint]()
  private var sideBySideConstraints = [NSLayoutConstraint]()
  private var playerColumnLeadingConstraint: NSLayoutConstraint?
  private var playerColumnCenterConstraint: NSLayoutConstraint?
  var contextPrevQueueSectionHeader: ContextQueuePrevSectionHeader?
  var userQueueSectionHeader: UserQueueSectionHeader?
  var contextNextQueueSectionHeader: ContextQueueNextSectionHeader?
  var activeDisplayedSectionHeader = Set<PlayerSectionCategory>()
  lazy var clearEmptySectionFooter = {
    let view = UIView()
    view.backgroundColor = .clear
    view.isHidden = true
    return view
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    // darkened artwork color needs white labels
    overrideUserInterfaceStyle = .dark

    tableView.delegate = self
    tableView.dataSource = self
    tableView.dragDelegate = self
    tableView.dropDelegate = self
    tableView.dragInteractionEnabled = true

    player = appDelegate.player
    player.addNotifier(notifier: self)
    playerHandler = PlayerUIHandler(player: player, style: .popupPlayer)

    if let createdPlayerControlView = ViewCreator<PlayerControlView>.createFromNib() {
      controlView = createdPlayerControlView
      createdPlayerControlView.prepare(toWorkOnRootView: self)
      createdPlayerControlView.translatesAutoresizingMaskIntoConstraints = false
      controlPlaceholderView.addSubview(createdPlayerControlView)
      NSLayoutConstraint.activate([
        createdPlayerControlView.topAnchor.constraint(equalTo: controlPlaceholderView.topAnchor),
        createdPlayerControlView.bottomAnchor
          .constraint(equalTo: controlPlaceholderView.bottomAnchor),
        createdPlayerControlView.leadingAnchor
          .constraint(equalTo: controlPlaceholderView.leadingAnchor),
        createdPlayerControlView.trailingAnchor
          .constraint(equalTo: controlPlaceholderView.trailingAnchor),
      ])
    }
    // collects the xib constraints of the table view: before the lyrics layout is attached to it
    setupSideBySideLayout()
    setupLyricsLayout()
    if let createdLargeCurrentlyPlayingView = ViewCreator<LargeCurrentlyPlayingPlayerView>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: largePlayerPlaceholderView.bounds.size.width,
        height: largePlayerPlaceholderView.bounds.size.height
      )) {
      largeCurrentlyPlayingView = createdLargeCurrentlyPlayingView
      createdLargeCurrentlyPlayingView.prepare(toWorkOnRootView: self)
      largePlayerPlaceholderView.addSubview(createdLargeCurrentlyPlayingView)
    }

    setupTableView()
    fetchSongInfoAndUpdateViews()

    if let sectionView = ViewCreator<ContextQueuePrevSectionHeader>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: view.bounds.size.width,
        height: ContextQueuePrevSectionHeader.frameHeight
      )) {
      contextPrevQueueSectionHeader = sectionView
      contextPrevQueueSectionHeader?.display(name: "Previous")
    }
    if let sectionView = ViewCreator<UserQueueSectionHeader>.createFromNib(withinFixedFrame: CGRect(
      x: 0,
      y: 0,
      width: view.bounds.size.width,
      height: UserQueueSectionHeader.frameHeight
    )) {
      userQueueSectionHeader = sectionView
      userQueueSectionHeader?.display(name: "Next from Queue", buttonPressAction: clearUserQueue)
    }
    if let sectionView = ViewCreator<ContextQueueNextSectionHeader>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: view.bounds.size.width,
        height: ContextQueueNextSectionHeader.frameHeight
      )) {
      contextNextQueueSectionHeader = sectionView
      contextNextQueueSectionHeader?.prepare(toWorkOnRootView: self)
    }

    accountNotificationHandler = AccountNotificationHandler(
      storage: appDelegate.storage,
      notificationHandler: appDelegate.notificationHandler
    )
    accountNotificationHandler?.registerCallbackForAllAccounts { [weak self] accountInfo in
      guard let self else { return }
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).artworkDownloadManager
      )
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).playableDownloadManager
      )
    }

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.refresh()
      }
    )
    // the overlay on Mac is closed with the close button in the title bar (see SplitVC)
    if !isOverlay, modalPresentationStyle == .overFullScreen {
      setupFullScreenDismissal()
    }
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    overrideUserInterfaceStyle == .light ? .darkContent : .lightContent
  }

  /// Full screen there is no sheet: grabber and swipe down to close are provided by the player.
  private func setupFullScreenDismissal() {
    let grabber = UIView()
    grabber.translatesAutoresizingMaskIntoConstraints = false
    grabber.backgroundColor = .tertiaryLabel
    grabber.layer.cornerRadius = 2.5
    grabber.isUserInteractionEnabled = false
    view.addSubview(grabber)
    NSLayoutConstraint.activate([
      grabber.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
      grabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      grabber.widthAnchor.constraint(equalToConstant: 36),
      grabber.heightAnchor.constraint(equalToConstant: 5),
    ])

    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
    pan.delegate = self
    view.addGestureRecognizer(pan)
  }

  @objc
  private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
    let translationY = max(gesture.translation(in: view).y, 0)
    switch gesture.state {
    case .changed:
      view.transform = CGAffineTransform(translationX: 0, y: translationY)
    case .ended where isDismissPanFinished(gesture, translationY: translationY):
      // the system dismissal can't continue from a transformed view, so the player slides out itself
      UIView.animate(
        withDuration: 0.25,
        delay: 0,
        options: .curveEaseOut,
        animations: {
          self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
        },
        completion: { _ in
          self.dismiss(animated: false)
        }
      )
    case .cancelled, .ended, .failed:
      UIView.animate(
        withDuration: 0.3,
        delay: 0,
        usingSpringWithDamping: 0.8,
        initialSpringVelocity: 0,
        animations: { self.view.transform = .identity }
      )
    default:
      break
    }
  }

  /// A flick back up cancels the dismissal, also if the player was already dragged far down.
  private func isDismissPanFinished(_ gesture: UIPanGestureRecognizer, translationY: CGFloat)
    -> Bool {
    let velocityY = gesture.velocity(in: view).y
    return velocityY > 1000 || (translationY > view.bounds.height / 4 && velocityY >= 0)
  }

  /// Full screen the sheet's VoiceOver escape gesture is gone, the player closes itself.
  override func accessibilityPerformEscape() -> Bool {
    if isOverlay {
      closePopupPlayer()
      return true
    }
    guard modalPresentationStyle == .overFullScreen else { return false }
    dismiss(animated: true)
    return true
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    refreshCellMasks()
    refreshBottomFadeMask()
    controlView?.refreshView()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    appDelegate.userStatistics.visited(.popupPlayer)
    // the player overrides its own style, so system style changes are only visible on the window
    if windowStyleObservation == nil {
      windowStyleObservation = view.window?.registerForTraitChanges(
        [UITraitUserInterfaceStyle.self]
      ) { (_: UIWindow, _) in
        self.refreshBackgroundItemArtwork()
      }
    }
    becomeFirstResponder()
    applyDisplayLayout(animated: false)
    reloadData()
    scrollToCurrentlyPlayingRow()
    controlView?.refreshView()
    refresh()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    resignFirstResponder()
  }

  override func viewWillLayoutSubviews() {
    adjustLayoutMargins()
    refreshSideBySideMode()
  }

  /// The xib stacks player, queue and controls vertically. The side by side constraints put the
  /// player (large view and controls) into a column on the left and queue and lyrics on the right.
  private func setupSideBySideLayout() {
    let stackedViews: [UIView] = [largePlayerPlaceholderView, tableView, controlPlaceholderView]
    stackedConstraints = view.constraints.filter { constraint in
      stackedViews.contains { $0 === constraint.firstItem || $0 === constraint.secondItem }
    }

    let topInset: CGFloat = 20.0
    let columnSpacing: CGFloat = 30.0
    // the list ends above the bottom row of the controls (airplay, lyrics, queue)
    let listBottomAnchor = controlView?.optionsStackView.topAnchor ?? controlPlaceholderView
      .bottomAnchor
    sideBySideConstraints = [
      largePlayerPlaceholderView.topAnchor.constraint(
        equalTo: view.layoutMarginsGuide.topAnchor,
        constant: topInset
      ),
      largePlayerPlaceholderView.widthAnchor.constraint(
        equalTo: view.widthAnchor,
        multiplier: 0.42
      ),
      controlPlaceholderView.topAnchor.constraint(equalTo: largePlayerPlaceholderView.bottomAnchor),
      controlPlaceholderView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      controlPlaceholderView.leadingAnchor
        .constraint(equalTo: largePlayerPlaceholderView.leadingAnchor),
      controlPlaceholderView.trailingAnchor
        .constraint(equalTo: largePlayerPlaceholderView.trailingAnchor),
      tableView.topAnchor.constraint(
        equalTo: view.layoutMarginsGuide.topAnchor,
        constant: topInset
      ),
      tableView.bottomAnchor.constraint(equalTo: listBottomAnchor, constant: -10.0),
      tableView.leadingAnchor.constraint(
        equalTo: largePlayerPlaceholderView.trailingAnchor,
        constant: columnSpacing
      ),
      tableView.trailingAnchor.constraint(
        equalTo: view.layoutMarginsGuide.trailingAnchor,
        constant: -columnSpacing
      ),
    ]
    // without queue or lyrics the player column is centered
    playerColumnLeadingConstraint = largePlayerPlaceholderView.leadingAnchor.constraint(
      equalTo: view.layoutMarginsGuide.leadingAnchor,
      constant: columnSpacing
    )
    playerColumnCenterConstraint = largePlayerPlaceholderView.centerXAnchor
      .constraint(equalTo: view.centerXAnchor)
  }

  /// Below this height artwork, title and controls don't fit into the player column.
  private static let sideBySideMinHeight: CGFloat = 600.0

  private var shouldDisplaySideBySide: Bool {
    traitCollection.horizontalSizeClass == .regular &&
      view.bounds.width > view.bounds.height &&
      view.bounds.height >= Self.sideBySideMinHeight
  }

  private func refreshSideBySideMode() {
    let isSideBySideNeeded = shouldDisplaySideBySide
    guard isSideBySideNeeded != isSideBySide else { return }
    isSideBySide = isSideBySideNeeded
    if isSideBySide {
      NSLayoutConstraint.deactivate(stackedConstraints)
      NSLayoutConstraint.activate(sideBySideConstraints)
    } else {
      playerColumnLeadingConstraint?.isActive = false
      playerColumnCenterConstraint?.isActive = false
      NSLayoutConstraint.deactivate(sideBySideConstraints)
      NSLayoutConstraint.activate(stackedConstraints)
    }
    // the player column already shows title and artwork, queue and lyrics don't need their header
    lyricsHeaderCell?.isHidden = isSideBySide
    // the header row can't shrink below its artwork, the lyrics start above it instead
    if isSideBySide {
      lyricsBelowHeaderConstraint?.isActive = false
      lyricsWithoutHeaderConstraint?.isActive = true
    } else {
      lyricsWithoutHeaderConstraint?.isActive = false
      lyricsBelowHeaderConstraint?.isActive = true
    }
    tableView.reloadData()
    applyDisplayLayout(animated: false)
  }

  func setPlayerColumnCentered(_ isCentered: Bool) {
    // deactivate first, both constraints at once would conflict
    if isCentered {
      playerColumnLeadingConstraint?.isActive = false
      playerColumnCenterConstraint?.isActive = true
    } else {
      playerColumnCenterConstraint?.isActive = false
      playerColumnLeadingConstraint?.isActive = true
    }
  }

  /// Table view and lyrics layout share the same area, the lyrics layout has its own header row.
  private func setupLyricsLayout() {
    lyricsLayoutView.translatesAutoresizingMaskIntoConstraints = false
    lyricsLayoutView.isHidden = true
    lyricsLayoutView.alpha = 0.0
    view.insertSubview(lyricsLayoutView, aboveSubview: tableView)
    lyricsContainerView.translatesAutoresizingMaskIntoConstraints = false
    lyricsLayoutView.addSubview(lyricsContainerView)
    NSLayoutConstraint.activate([
      lyricsLayoutView.topAnchor.constraint(equalTo: tableView.topAnchor),
      lyricsLayoutView.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
      lyricsLayoutView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
      lyricsLayoutView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
      lyricsContainerView.bottomAnchor.constraint(equalTo: lyricsLayoutView.bottomAnchor),
      lyricsContainerView.leadingAnchor.constraint(equalTo: lyricsLayoutView.leadingAnchor),
      lyricsContainerView.trailingAnchor.constraint(equalTo: lyricsLayoutView.trailingAnchor),
    ])

    guard let header = ViewCreator<CurrentlyPlayingTableCell>.createFromNib() else {
      lyricsContainerView.topAnchor.constraint(equalTo: lyricsLayoutView.topAnchor).isActive = true
      return
    }
    lyricsHeaderCell = header
    header.prepare(toWorkOnRootView: self)
    header.backgroundColor = .clear
    header.translatesAutoresizingMaskIntoConstraints = false
    lyricsLayoutView.addSubview(header)
    let lyricsBelowHeaderConstraint = lyricsContainerView.topAnchor
      .constraint(equalTo: header.bottomAnchor)
    self.lyricsBelowHeaderConstraint = lyricsBelowHeaderConstraint
    lyricsWithoutHeaderConstraint = lyricsContainerView.topAnchor
      .constraint(equalTo: lyricsLayoutView.topAnchor)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: lyricsLayoutView.topAnchor),
      header.leadingAnchor.constraint(equalTo: lyricsLayoutView.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: lyricsLayoutView.trailingAnchor),
      header.heightAnchor.constraint(equalToConstant: CurrentlyPlayingTableCell.rowHeight),
      lyricsBelowHeaderConstraint,
    ])
  }

  func setLyricsDisplayed(_ isDisplayed: Bool) {
    appDelegate.storage.settings.user.isPlayerLyricsDisplayed = isDisplayed
    if !isDisplayed {
      // leaving the lyrics always shows the cover, also if the queue was shown before
      appDelegate.storage.settings.user.playerDisplayStyle = .large
    }
    applyDisplayLayout(animated: true)
    controlView?.refreshDisplayLyricsButton()
    controlView?.refreshDisplayPlaylistButton()
  }

  /// The lyrics come with the song info, until it is fetched "No Lyrics" would only flash up.
  private(set) var isFetchingSongInfo = false

  func fetchSongInfoAndUpdateViews() {
    guard appDelegate.storage.settings.user.isOnlineMode,
          let song = player.currentlyPlaying?.asSong,
          let account = song.account
    else { return }

    isFetchingSongInfo = true
    Task { @MainActor in
      do {
        try await self.appDelegate.getMeta(account.info).librarySyncer.sync(song: song)
      } catch {
        self.appDelegate.eventLogger.report(topic: "Song Info", error: error)
      }
      self.isFetchingSongInfo = false
      self.refreshCurrentlyPlayingInfoView()
    }
  }

  func reloadData() {
    tableView.reloadData()
    scrollToCurrentlyPlayingRow()
  }

  func scrollToCurrentlyPlayingRow() {
    tableView.scrollToRow(
      at: IndexPath(row: 0, section: PlayerSectionCategory.currentlyPlaying.rawValue),
      at: .top,
      animated: false
    )
  }

  func favoritePressed() {
    switch player.playerMode {
    case .music:
      guard let playableInfo = player.currentlyPlaying else { return }
      if playableInfo.isSong, let account = playableInfo.account {
        Task { @MainActor in
          do {
            try await playableInfo
              .remoteToggleFavorite(
                syncer: self.appDelegate.getMeta(account.info)
                  .librarySyncer
              )
          } catch {
            self.appDelegate.eventLogger.report(topic: "Toggle Favorite", error: error)
          }
          self.refresh()
        }
      } else if let radio = playableInfo.asRadio,
                let siteURL = radio.siteURL {
        UIApplication.shared.open(siteURL)
      }
    case .podcast:
      guard let podcastEpisode = player.currentlyPlaying?.asPodcastEpisode
      else { return }
      let plainDetailsVC = PlainDetailsVC()
      plainDetailsVC.display(podcastEpisode: podcastEpisode, on: self)
      present(plainDetailsVC, animated: true)
    }
  }

  func displayArtistDetail() {
    if let song = player.currentlyPlaying?.asSong, let artist = song.artist,
       let account = artist.account {
      let artistDetailVC = AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist)
      closePopupPlayerAndDisplayInLibraryTab(vc: artistDetailVC)
    }
  }

  func displayAlbumDetail() {
    if let song = player.currentlyPlaying?.asSong, let album = song.album,
       let account = album.account {
      let albumDetailVC = AppStoryboard.Main.segueToAlbumDetail(
        account: account,
        album: album,
        songToScrollTo: song
      )
      closePopupPlayerAndDisplayInLibraryTab(vc: albumDetailVC)
    }
  }

  func displayPodcastDetail() {
    if let podcastEpisode = player.currentlyPlaying?.asPodcastEpisode,
       let podcast = podcastEpisode.podcast,
       let account = podcastEpisode.account {
      let podcastDetailVC = AppStoryboard.Main.segueToPodcastDetail(
        account: account,
        podcast: podcast,
        episodeToScrollTo: podcastEpisode
      )
      closePopupPlayerAndDisplayInLibraryTab(vc: podcastDetailVC)
    }
  }

  func closePopupPlayer() {
    guard let hostingSplitVC = AppDelegate.mainWindowHostVC else { return }
    hostingSplitVC.visualizePopupPlayer(direction: .close, animated: true)
  }

  func closePopupPlayerAndDisplayInLibraryTab(vc: UIViewController) {
    guard let hostingSplitVC = AppDelegate.mainWindowHostVC else { return }
    hostingSplitVC.visualizePopupPlayer(direction: .close, animated: true, completion: { () in
      hostingSplitVC.pushNavLibrary(vc: vc)
    })
  }

  func refreshUserQueueSectionHeader() {
    guard let userQueueSectionView = userQueueSectionHeader else { return }
    if player.userQueueCount == 0 {
      userQueueSectionView.hide()
    } else {
      userQueueSectionView.display(
        name: PlayerQueueType.user.description,
        buttonPressAction: clearUserQueue
      )
    }
  }

  func refreshContextQueueSectionHeader() {
    guard let contextNextQueueSectionHeader = contextNextQueueSectionHeader else { return }
    contextNextQueueSectionHeader.refresh()
  }

  // MARK: - UIScrollViewDelegate

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    refreshCellMasks()
    refreshBottomFadeMask()
  }

  /// Fades out the rows at the bottom edge of the list. The mask lives in the bounds of the
  /// scroll view, so its frame follows the content offset.
  func refreshBottomFadeMask() {
    let fadeHeight: CGFloat = 30.0
    let bounds = tableView.bounds
    guard bounds.height > fadeHeight else {
      tableView.layer.mask = nil
      return
    }
    let mask = (tableView.layer.mask as? CAGradientLayer) ?? CAGradientLayer()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    mask.frame = bounds
    mask.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
    let fadeStart = NSNumber(value: Double((bounds.height - fadeHeight) / bounds.height))
    mask.locations = [0.0, fadeStart, 1.0]
    mask.startPoint = CGPoint(x: 0.5, y: 0.0)
    mask.endPoint = CGPoint(x: 0.5, y: 1.0)
    tableView.layer.mask = mask
    CATransaction.commit()
  }

  func refreshCellMasks() {
    guard let topSection = Array(activeDisplayedSectionHeader)
      .sorted(by: { $0.rawValue < $1.rawValue }).first
    else { return }

    let topSectionHeight = tableView(tableView, heightForHeaderInSection: topSection.rawValue)
    let scrollOffset = tableView.contentOffset.y

    for cell in tableView.visibleCells {
      let hiddenFrameHeight = scrollOffset + topSectionHeight - cell.frame.origin.y
      if hiddenFrameHeight >= 0 || hiddenFrameHeight <= cell.frame.size.height {
        if let customCell = cell as? PlayableTableCell {
          customCell.maskCell(fromTop: hiddenFrameHeight)
        }
      }
    }
  }

  func refreshCellsContent() {
    for cell in tableView.visibleCells {
      guard let playableCell = cell as? PlayableTableCell else { continue }
      playableCell.refresh()
    }
  }
}

// MARK: UIGestureRecognizerDelegate

extension PopupPlayerVC: UIGestureRecognizerDelegate {
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: view)
    // horizontal drags belong to the sliders
    guard velocity.y > abs(velocity.x) else { return false }
    // queue and lyrics scroll by themselves
    let location = pan.location(in: view)
    let isInList = [tableView, lyricsLayoutView].contains { listView in
      !listView.isHidden && listView.frame.contains(location)
    }
    return !isInList && !isControl(at: location)
  }

  /// Sliders, buttons and the rating keep their touches, also if the finger drifts downwards.
  private func isControl(at location: CGPoint) -> Bool {
    var hitView = view.hitTest(location, with: nil)
    while let current = hitView, current !== view {
      if current is UIControl || current is RatingView {
        return true
      }
      hitView = current.superview
    }
    return false
  }
}

// MARK: MusicPlayable

extension PopupPlayerVC: MusicPlayable {
  func didStartPlayingFromBeginning() {
    fetchSongInfoAndUpdateViews()
    largeCurrentlyPlayingView?.initializeLyrics()
    applyDisplayLayout(animated: false)
  }

  func didStartPlaying() {
    reloadData()
    refresh()
  }

  func didStopPlaying() {
    reloadData()
    refresh()
  }

  func didPlaylistChange() {
    reloadData()
    refresh()
  }

  func didPause() {}
  func didElapsedTimeChange() {}

  func didLyricsTimeChange(time: CMTime) {
    largeCurrentlyPlayingView?.refreshLyricsTime(time: time)
  }

  func didArtworkChange() {
    refreshCurrentlyPlayingArtworks()
  }

  func didNowPlayingInfoChange() {
    refreshCurrentlyPlayingInfoView()
  }

  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}
}

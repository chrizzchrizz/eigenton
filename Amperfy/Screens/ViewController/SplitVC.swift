//
//  SplitVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 25.02.24.
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
import UIKit

import SwiftUI

// MARK: - SplitVC

class SplitVC: UISplitViewController {
  /// Sidebar and inspector can be resized by dragging their divider, the width is remembered
  static let sidebarWidthRange: ClosedRange<CGFloat> = 200 ... 350
  static let sidebarDefaultWidth: CGFloat = 250
  static let inspectorWidthRange: ClosedRange<CGFloat> = 250 ... 450
  static let inspectorDefaultWidth: CGFloat = 300
  private var savedSidebarWidth: CGFloat = 0
  private var savedInspectorWidth: CGFloat = 0
  private var columnWidthsSaveTask: Task<(), Never>?

  var miniPlayer: MiniPlayerView?
  static let miniPlayerMaxWidth: CGFloat = 800
  /// Area between sidebar and inspector in which the mini player is centered.
  private let miniPlayerArea = UILayoutGuide()
  var miniPlayerLeadingConstraint: NSLayoutConstraint?
  var miniPlayerTrailingConstraint: NSLayoutConstraint?
  var miniPlayerBottomConstraint: NSLayoutConstraint?
  var miniPlayerHeightConstraint: NSLayoutConstraint?
  /// The popup player is shown as a child over the whole window, like the popup player on iOS.
  private(set) var popupPlayer: PopupPlayerVC?
  /// Pushed onto the detail navigation while the popup player is shown: its navigation bar, which
  /// the split view places in the window's title bar, only has the close button.
  private var popupPlayerTitlebarVC: UIViewController?
  private var isPopupPlayerAnimating = false
  /// Open/close requests that came in during an animation, run once it has finished
  private var afterPopupPlayerAnimation = [() -> ()]()
  private let account: Account!

  init(style: UISplitViewController.Style, account: Account) {
    self.account = account
    super.init(style: style)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // plain navigation: the offline button is shown in the secondary column only
    setViewController(
      UINavigationController(
        rootViewController: AppStoryboard.Main
          .segueToSideBar(account: account)
      ),
      for: .primary
    )
    setViewController(defaultSecondaryVC, for: .secondary)
    primaryEdge = .leading
    primaryBackgroundStyle = .sidebar
    // the sidebar always stays visible: no sidebar button, no swipe or overlay
    preferredDisplayMode = .oneBesideSecondary
    preferredSplitBehavior = .tile
    presentsWithGesture = false
    displayModeButtonVisibility = .never

    if appDelegate.storage.settings.user.isOfflineMode {
      appDelegate.eventLogger.info(topic: "Reminder", message: "Offline Mode is active.")
    }

    miniPlayer = MiniPlayerView(player: appDelegate.player)
    miniPlayer!.configureForMac()
    guard let miniPlayer else { return }

    let inspectorWidth = viewController(for: .inspector)?.view.bounds.width ?? 0.0
    displayOrHideInspector()

    view.addSubview(miniPlayer.glassContainer)
    // Set up constraints to pin it to the bottom, left, and right
    miniPlayer.glassContainer.translatesAutoresizingMaskIntoConstraints = false

    miniPlayer.glassContainer.layer.cornerRadius = 25
    miniPlayer.glassContainer.clipsToBounds = true

    view.addLayoutGuide(miniPlayerArea)
    miniPlayerLeadingConstraint = miniPlayerArea.leadingAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.leadingAnchor,
      constant: primaryColumnWidth + 20
    )
    miniPlayerTrailingConstraint = miniPlayerArea.trailingAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.trailingAnchor,
      constant: -inspectorWidth - 20
    )
    let miniPlayerPreferredWidth = miniPlayer.glassContainer.widthAnchor
      .constraint(equalTo: miniPlayerArea.widthAnchor)
    miniPlayerPreferredWidth.priority = .defaultHigh
    miniPlayerBottomConstraint = view.safeAreaLayoutGuide.bottomAnchor.constraint(
      equalTo: miniPlayer.glassContainer.bottomAnchor,
      constant: 15.0
    )
    miniPlayerHeightConstraint = miniPlayer.glassContainer.heightAnchor
      .constraint(equalToConstant: 50)

    NSLayoutConstraint.activate([
      miniPlayerLeadingConstraint!,
      miniPlayerTrailingConstraint!,
      miniPlayer.glassContainer.centerXAnchor.constraint(equalTo: miniPlayerArea.centerXAnchor),
      miniPlayer.glassContainer.widthAnchor
        .constraint(lessThanOrEqualToConstant: Self.miniPlayerMaxWidth),
      miniPlayerPreferredWidth,
      miniPlayerBottomConstraint!,
      miniPlayerHeightConstraint!,
    ])
  }

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()

    let inspectorWidth = viewController(for: .inspector)?.view.bounds.width ?? 0.0

    miniPlayerLeadingConstraint?.constant = (isSidebarVisible ? primaryColumnWidth : -0) + 40
    miniPlayerTrailingConstraint?.constant = -inspectorWidth - 40
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)

    applyColumnWidths()
    appDelegate.localNotificationManager.requestAuthorization()
    miniPlayer?.refreshPlayer()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    saveColumnWidthsIfChanged()
  }

  // MARK: - Column widths

  private func applyColumnWidths() {
    let settings = appDelegate.storage.settings.user
    savedSidebarWidth = Self.width(settings.macSidebarWidth, in: Self.sidebarWidthRange)
      ?? Self.sidebarDefaultWidth
    savedInspectorWidth = Self.width(settings.macInspectorWidth, in: Self.inspectorWidthRange)
      ?? Self.inspectorDefaultWidth

    minimumPrimaryColumnWidth = Self.sidebarWidthRange.lowerBound
    maximumPrimaryColumnWidth = Self.sidebarWidthRange.upperBound
    preferredPrimaryColumnWidth = savedSidebarWidth
    minimumInspectorColumnWidth = Self.inspectorWidthRange.lowerBound
    maximumInspectorColumnWidth = Self.inspectorWidthRange.upperBound
    preferredInspectorColumnWidth = savedInspectorWidth
  }

  /// A stored width inside the allowed range, nil for none (0) or an invalid one
  private static func width(_ storedWidth: Double, in range: ClosedRange<CGFloat>) -> CGFloat? {
    let width = CGFloat(storedWidth)
    return range.contains(width) ? width : nil
  }

  /// Remembers widths changed by dragging a divider. Saved with a delay: a drag changes the width
  /// with every layout pass.
  private func saveColumnWidthsIfChanged() {
    guard savedSidebarWidth > 0 else { return } // not applied yet
    let sidebarWidth = primaryColumnWidth
    let inspectorVC = viewController(for: .inspector)
    let inspectorWidth = (inspectorVC?.view.window != nil) ? inspectorVC?.view.bounds.width : nil

    var hasChanged = false
    if Self.sidebarWidthRange.contains(sidebarWidth), abs(sidebarWidth - savedSidebarWidth) >= 1 {
      savedSidebarWidth = sidebarWidth
      hasChanged = true
    }
    if let inspectorWidth, Self.inspectorWidthRange.contains(inspectorWidth),
       abs(inspectorWidth - savedInspectorWidth) >= 1 {
      savedInspectorWidth = inspectorWidth
      hasChanged = true
    }
    guard hasChanged else { return }

    // new windows and a shown inspector start with the dragged width
    preferredPrimaryColumnWidth = savedSidebarWidth
    preferredInspectorColumnWidth = savedInspectorWidth
    columnWidthsSaveTask?.cancel()
    columnWidthsSaveTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 500_000_000)
      guard let self, !Task.isCancelled else { return }
      appDelegate.storage.settings.user.macSidebarWidth = Double(savedSidebarWidth)
      appDelegate.storage.settings.user.macInspectorWidth = Double(savedInspectorWidth)
    }
  }

  func displayOrHideInspector() {
    // keep the shown lyrics or queue (scroll position, no reload) if they stay
    let inspectorVC = viewController(for: .inspector)
    let shownVC = (inspectorVC as? UINavigationController)?.topViewController ?? inspectorVC
    if appDelegate.storage.settings.user.isPlayerLyricsDisplayed {
      guard !(shownVC is LyricsVC) else { return }
      let lyricsVC = LyricsVC()
      setViewController(lyricsVC, for: .inspector)
      show(.inspector)
    } else if appDelegate.storage.settings.user.playerDisplayStyle == .compact {
      guard !(shownVC is QueueVC) else { return }
      let queueVC = QueueVC()
      setViewController(queueVC, for: .inspector)
      show(.inspector)
    } else {
      hide(.inspector)
      setViewController(nil, for: .inspector)
    }
  }

  // MARK: - Popup player overlay

  var isPopupPlayerOpen: Bool {
    popupPlayer != nil
  }

  func openPopupPlayer(animated: Bool, completion: (() -> ())? = nil) {
    guard !isPopupPlayerAnimating else {
      afterPopupPlayerAnimation.append { [weak self] in
        self?.openPopupPlayer(animated: animated, completion: completion)
      }
      return
    }
    guard popupPlayer == nil else {
      completion?()
      return
    }
    // the title bar changes first: the player's safe area must not change while it slides in,
    // it would lay out (and resize the artwork) again
    setTitlebarForPopupPlayer(isShown: true)
    view.layoutIfNeeded()

    let popupPlayer = PopupPlayerVC()
    popupPlayer.isOverlay = true
    self.popupPlayer = popupPlayer

    addChild(popupPlayer)
    popupPlayer.view.frame = view.bounds
    popupPlayer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // above the mini player bar
    view.addSubview(popupPlayer.view)
    popupPlayer.didMove(toParent: self)
    popupPlayer.view.layoutIfNeeded()
    appDelegate.rebuildMainMenu()

    guard animated else {
      completion?()
      return
    }
    isPopupPlayerAnimating = true
    popupPlayer.view.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
    UIView.animate(
      withDuration: 0.4,
      delay: 0,
      usingSpringWithDamping: 0.9,
      initialSpringVelocity: 0,
      options: [],
      animations: {
        popupPlayer.view.transform = .identity
      },
      completion: { _ in
        self.isPopupPlayerAnimating = false
        completion?()
        self.runAfterPopupPlayerAnimation()
      }
    )
  }

  func closePopupPlayer(animated: Bool, completion: (() -> ())? = nil) {
    guard !isPopupPlayerAnimating else {
      afterPopupPlayerAnimation.append { [weak self] in
        self?.closePopupPlayer(animated: animated, completion: completion)
      }
      return
    }
    guard let popupPlayer else {
      completion?()
      return
    }
    let removePopupPlayer = {
      // the title bar changes only once the player is gone, see openPopupPlayer
      self.setTitlebarForPopupPlayer(isShown: false)
      popupPlayer.willMove(toParent: nil)
      popupPlayer.view.removeFromSuperview()
      popupPlayer.removeFromParent()
      self.popupPlayer = nil
      self.isPopupPlayerAnimating = false
      // lyrics and queue share their setting with the popup player, which might have changed it
      self.displayOrHideInspector()
      self.miniPlayer?.refreshPlayer()
      self.appDelegate.rebuildMainMenu()
      completion?()
      self.runAfterPopupPlayerAnimation()
    }
    guard animated else {
      removePopupPlayer()
      return
    }
    isPopupPlayerAnimating = true
    // A still image slides out: moving the player itself out of the title bar shrinks its safe
    // area, it would lay out again and the artwork would jump.
    let slidingView: UIView
    if let snapshot = popupPlayer.view.snapshotView(afterScreenUpdates: false) {
      snapshot.frame = popupPlayer.view.frame
      view.addSubview(snapshot)
      popupPlayer.view.isHidden = true
      slidingView = snapshot
    } else {
      slidingView = popupPlayer.view
    }
    UIView.animate(
      withDuration: 0.3,
      delay: 0,
      options: .curveEaseIn,
      animations: {
        slidingView.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
      },
      completion: { _ in
        if slidingView !== popupPlayer.view {
          slidingView.removeFromSuperview()
        }
        removePopupPlayer()
      }
    )
  }

  private func runAfterPopupPlayerAnimation() {
    let pending = afterPopupPlayerAnimation
    afterPopupPlayerAnimation.removeAll()
    pending.forEach { $0() }
  }

  /// The navigation bars of the columns are shown in the window's title bar on Mac, above the popup
  /// player. Their buttons and titles don't belong to the player: sidebar and inspector bars are
  /// hidden, the detail column shows a screen with only the close button.
  private func setTitlebarForPopupPlayer(isShown: Bool) {
    for column in [UISplitViewController.Column.primary, .inspector] {
      let columnVC = viewController(for: column)
      let navController = (columnVC as? UINavigationController) ?? columnVC?.navigationController
      navController?.setNavigationBarHidden(isShown, animated: false)
    }

    if isShown {
      guard popupPlayerTitlebarVC == nil,
            let detailNav = viewController(for: .secondary) as? UINavigationController
      else { return }
      // a still image of the current screen: it stays visible while the player slides in
      let snapshot = detailNav.topViewController?.view.snapshotView(afterScreenUpdates: false)
      let titlebarVC = PopupPlayerTitlebarVC(
        snapshot: snapshot,
        closeAction: UIAction { [weak self] _ in
          self?.closePopupPlayer(animated: true)
        }
      )
      popupPlayerTitlebarVC = titlebarVC
      detailNav.pushViewController(titlebarVC, animated: false)
    } else {
      guard let titlebarVC = popupPlayerTitlebarVC else { return }
      popupPlayerTitlebarVC = nil
      // the detail navigation might have been replaced or pushed onto meanwhile
      guard let detailNav = titlebarVC.navigationController else { return }
      if detailNav.topViewController === titlebarVC {
        detailNav.popViewController(animated: false)
      } else {
        detailNav.viewControllers.removeAll { $0 === titlebarVC }
      }
    }
  }

  var isSidebarVisible: Bool {
    switch displayMode {
    case .allVisible, .automatic, .oneBesideSecondary, .primaryOverlay, .twoBesideSecondary,
         .twoDisplaceSecondary:
      // Sidebar is visible in some capacity
      return true
    case .oneOverSecondary, .secondaryOnly, .twoOverSecondary:
      // Sidebar is occupying main space
      return false
    @unknown default:
      return true
    }
  }

  func embeddInNavigation(vc: UIViewController) -> UINavigationController {
    OfflineIndicatingNavigationController(rootViewController: vc)
  }

  var defaultSecondaryVC: UINavigationController {
    embeddInNavigation(vc: TabNavigatorItem.home.getController(account: account))
  }

  public func push(vc: UIViewController) {
    let secondaryVC = viewController(for: .secondary) as? UINavigationController
    secondaryVC?.pushViewController(vc, animated: false)
  }
}

// MARK: MainSceneHostingViewController

extension SplitVC: MainSceneHostingViewController {
  public func pushNavLibrary(vc: UIViewController) {
    push(vc: vc)
  }

  public func pushLibraryCategory(vc: UIViewController) {
    setViewController(embeddInNavigation(vc: vc), for: .secondary)
  }

  func pushTabCategory(tabCategory: TabNavigatorItem) {
    let vc = tabCategory.getController(account: account)
    setViewController(embeddInNavigation(vc: vc), for: .secondary)
    // the sidebar doesn't know when a tab is opened from Home
    let sideBarVC = (viewController(for: .primary) as? UINavigationController)?
      .viewControllers.first as? SideBarVC
    sideBarVC?.select(tab: tabCategory)
  }

  func displaySearch() {
    visualizePopupPlayer(direction: .close, animated: true) {
      let searchVC = AppStoryboard.Main.segueToSearch(account: self.account)
      self.setViewController(self.embeddInNavigation(vc: searchVC), for: .secondary)
      Task {
        try? await Task.sleep(nanoseconds: 500_000_000)
        searchVC.activateSearchBar()
      }
    }
  }

  func getSafeAreaExtension() -> CGFloat {
    guard let miniPlayerBottomConstraint,
          let miniPlayerHeightConstraint else { return 0.0 }

    return miniPlayerBottomConstraint.constant + miniPlayerHeightConstraint.constant
  }
}

// MARK: - PopupPlayerTitlebarVC

/// Mac: the detail column's screen while the popup player is shown. The player covers it, only its
/// navigation bar with the system close button is visible in the window's title bar.
private class PopupPlayerTitlebarVC: UIViewController {
  private let snapshot: UIView?

  init(snapshot: UIView?, closeAction: UIAction) {
    self.snapshot = snapshot
    super.init(nibName: nil, bundle: nil)
    navigationItem.hidesBackButton = true
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: closeAction
    )
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    guard let snapshot else { return }
    snapshot.frame = view.bounds
    snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(snapshot)
  }
}

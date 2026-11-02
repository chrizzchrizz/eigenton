//
//  TabBarVC.swift
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
import UIKit

// MARK: - TabBarVC

class TabBarVC: UITabBarController {
  private var libraryGroup: UITabGroup?
  private var searchTab: UISearchTab?
  private var homeTab: UITab?
  private var playlistsTab: UITab?
  private let account: Account

  init(account: Account) {
    self.account = account
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var miniPlayer: MiniPlayerView?
  /// Kept while hidden, so the mini player can be shown again once a song is loaded.
  private var miniPlayerAccessory: UITabAccessory?

  override func viewDidLoad() {
    super.viewDidLoad()
    var fixTabs = [UITab]()

    searchTab = UISearchTab { _ in
      OfflineIndicatingNavigationController(
        rootViewController: TabNavigatorItem.search
          .getController(account: self.account)
      )
    }
    searchTab!.automaticallyActivatesSearch = true
    fixTabs.append(searchTab!)

    homeTab = UITab(
      title: TabNavigatorItem.home.title,
      image: TabNavigatorItem.home.icon,
      identifier: "Tabs.\(TabNavigatorItem.home.title)"
    ) { [account] _ in
      OfflineIndicatingNavigationController(
        rootViewController: TabNavigatorItem.home
          .getController(account: account)
      )
    }
    fixTabs.append(homeTab!)

    playlistsTab = UITab(
      title: TabNavigatorItem.playlists.title,
      image: TabNavigatorItem.playlists.icon,
      identifier: "Tabs.\(TabNavigatorItem.playlists.title)"
    ) { [account] _ in
      OfflineIndicatingNavigationController(
        rootViewController: TabNavigatorItem.playlists
          .getController(account: account)
      )
    }
    fixTabs.append(playlistsTab!)

    // all library tabs in the order arranged by the user, the ones not in use are hidden
    let librarySettings = appDelegate.storage.settings.accounts
      .getSetting(account.info).read
      .libraryDisplaySettings
    let libraryTabs = librarySettings.order
      .compactMap { item in
        let tab = UITab(
          title: item.displayName,
          image: item.image,
          identifier: "Tabs.\(item.displayName)"
        ) { [account, appDelegate] _ in
          item.controller(account: account, settings: appDelegate.storage.settings)
        }
        tab.allowsHiding = true
        tab.isHiddenByDefault = !librarySettings.isVisible(libraryType: item)
        return tab
      }

    libraryGroup = UITabGroup(
      title: "Library",
      image: .musicLibrary,
      identifier: "Tabs.Library",
      children: libraryTabs
    ) { tab in
      AppStoryboard.Main.segueToLibrary(account: self.account)
    }
    libraryGroup!.managingNavigationController = OfflineIndicatingNavigationController()
    libraryGroup!.allowsReordering = true
    fixTabs.append(libraryGroup!)

    delegate = self
    tabs = fixTabs

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleLibraryItemsChanged(notification:)),
      name: .LibraryItemsChanged,
      object: nil
    )

    tabBarMinimizeBehavior = .onScrollDown

    miniPlayer = MiniPlayerView(player: appDelegate.player)
    miniPlayer!.configureForiOS()
    miniPlayer!.glassContainer.translatesAutoresizingMaskIntoConstraints = false

    miniPlayerAccessory = UITabAccessory(contentView: miniPlayer!.glassContainer)

    heightConstraint = miniPlayer!.glassContainer.heightAnchor.constraint(equalToConstant: 48.0)
    heightConstraint?.isActive = true

    miniPlayer!.tabAccessoryTraitChangeCB = configureTraitChangesForMiniPlayer
    // Reports the current state right away and attaches the accessory if a song is loaded
    miniPlayer!.visibilityChangeCB = { [weak self] isVisible in
      self?.setMiniPlayerVisible(isVisible)
    }

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.miniPlayer?
          .refreshForTraitChange(horizontalSizeClass: self.traitCollection.horizontalSizeClass)
        self.configureTraitChangesForMiniPlayer()
      }
    )

    if appDelegate.storage.settings.user.isOfflineMode {
      appDelegate.eventLogger.info(topic: "Reminder", message: "Offline Mode is active.")
    }
  }

  private func setMiniPlayerVisible(_ isVisible: Bool) {
    let isOnScreen = viewIfLoaded?.window != nil
    setBottomAccessory(isVisible ? miniPlayerAccessory : nil, animated: isOnScreen)
    // The accessory is attached synchronously; lay it out before the show animation runs
    configureTraitChangesForMiniPlayer()
    if isOnScreen {
      view.setNeedsLayout()
      view.layoutIfNeeded()
    }
  }

  private func mainContent() -> UIView {
    // Attempt to find the main content view controller's view if the sidebar is visible.
    // Fallback to self.view.safeAreaLayoutGuide.leadingAnchor otherwise.
    if traitCollection.horizontalSizeClass == .regular, let selectedViewController {
      return selectedViewController.view
    }
    return view
  }

  var centerConstraint: NSLayoutConstraint?
  var regularWidthConstraint: NSLayoutConstraint?
  var heightConstraint: NSLayoutConstraint?
  var compactWidthConstraint: NSLayoutConstraint?
  /// `NSLayoutConstraint.secondItem` is unretained and dangles once the old container is gone.
  private weak var compactWidthSuperview: UIView?

  func configureTraitChangesForMiniPlayer() {
    guard let miniPlayer else { return }
    // While hidden the accessory is detached, so constraints to the main content can't be
    // activated; viewWillLayoutSubviews configures it again once it is shown
    guard miniPlayer.glassContainer.isDescendant(of: view),
          mainContent().isDescendant(of: view) else {
      centerConstraint?.isActive = false
      regularWidthConstraint?.isActive = false
      return
    }
    let isInline = miniPlayer.glassContainer.traitCollection.tabAccessoryEnvironment == .inline

    if traitCollection.horizontalSizeClass == .regular {
      centerConstraint?.isActive = false
      centerConstraint = miniPlayer.glassContainer.safeAreaLayoutGuide.centerXAnchor.constraint(
        equalTo: mainContent().safeAreaLayoutGuide.centerXAnchor,
        constant: 0
      )
      let mainContentView = mainContent()
      var playerWidth = mainContentView.frame.width - mainContentView.safeAreaInsets
        .left - mainContentView.safeAreaInsets.right
      playerWidth = min(playerWidth, 600)
      compactWidthConstraint?.isActive = false
      regularWidthConstraint?.isActive = false
      regularWidthConstraint = miniPlayer.glassContainer.widthAnchor
        .constraint(equalToConstant: playerWidth)
      regularWidthConstraint?.isActive = true
      centerConstraint?.isActive = true
      heightConstraint?.constant = 60.0
    } else if isInline {
      heightConstraint?.constant = 48.0
      centerConstraint?.isActive = false
      regularWidthConstraint?.isActive = false
      activateCompactWidthConstraint()
    } else {
      heightConstraint?.constant = 48.0
      centerConstraint?.isActive = false
      regularWidthConstraint?.isActive = false
      activateCompactWidthConstraint()
    }

    miniPlayer.glassContainer.setNeedsLayout()
    miniPlayer.glassContainer.layoutIfNeeded()
  }

  /// The accessory moves the mini player into a new container each time it is shown again,
  /// so the width constraint has to follow the current superview.
  private func activateCompactWidthConstraint() {
    guard let glassContainer = miniPlayer?.glassContainer,
          let superview = glassContainer.superview else { return }
    if compactWidthSuperview !== superview {
      compactWidthConstraint?.isActive = false
      compactWidthConstraint = glassContainer.widthAnchor
        .constraint(equalTo: superview.widthAnchor)
      compactWidthSuperview = superview
    }
    compactWidthConstraint?.isActive = true
  }

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    configureTraitChangesForMiniPlayer()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    refresh()
    selectedTab = homeTab
    appDelegate.localNotificationManager.requestAuthorization()
  }

  @objc
  func handleLibraryItemsChanged(notification: Notification) {
    refresh()
  }

  func refresh() {
    guard let libraryGroup else { return }
    let config = appDelegate.storage.settings.accounts.getSetting(account.info).read
      .libraryDisplaySettings
    libraryGroup.displayOrderIdentifiers = config.order.compactMap { "Tabs.\($0.displayName)" }
    for tab in libraryGroup.displayOrder {
      guard let item = LibraryDisplayType.createByDisplayName(name: tab.title) else { continue }
      if let _ = config.inUse.first(where: { $0 == item }) {
        tab.isHidden = false
      } else {
        tab.isHidden = true
      }
    }
  }

  public func push(vc: UIViewController) {
    guard let libraryGroup else { return }
    // Select the library first: changing the selection rebuilds the managed navigation stack,
    // which would otherwise drop a view controller pushed beforehand (no back button).
    if selectedTab?.managingTabGroup !== libraryGroup, selectedTab !== libraryGroup {
      selectedTab = libraryGroup
    }
    libraryGroup.managingNavigationController?.pushViewController(vc, animated: true)
  }
}

// MARK: UITabBarControllerDelegate

extension TabBarVC: UITabBarControllerDelegate {
  func tabBarControllerDidEndEditing(_ tabBarController: UITabBarController) {
    var order = [LibraryDisplayType]()
    var visibleItems = Set<LibraryDisplayType>()
    guard let libraryGroup else { return }
    // display order contains the hidden tabs too -> keep their position
    for tab in libraryGroup.displayOrder {
      guard let item = LibraryDisplayType.createByDisplayName(name: tab.title) else { continue }
      order.append(item)
      if !tab.isHidden {
        visibleItems.insert(item)
      }
    }
    appDelegate.storage.settings.accounts
      .updateSetting(account.info) { accountSettings in
        accountSettings.libraryDisplaySettings = LibraryDisplaySettings(
          order: order,
          inUse: visibleItems,
          excluded: LibraryDisplaySettings.libraryExcludedTypes
        )
      }
    NotificationCenter.default.post(name: .LibraryItemsChanged, object: nil, userInfo: nil)
  }
}

// MARK: MainSceneHostingViewController

extension TabBarVC: MainSceneHostingViewController {
  public func pushNavLibrary(vc: UIViewController) {
    push(vc: vc)
  }

  public func pushLibraryCategory(vc: UIViewController) {
    guard let libraryGroup else { return }
    libraryGroup.managingNavigationController?.popToRootViewController(animated: false)
    push(vc: vc)
  }

  func pushTabCategory(tabCategory: TabNavigatorItem) {
    switch tabCategory {
    case .home:
      selectedTab = homeTab
    case .playlists:
      selectedTab = playlistsTab
      // coming from a "show all" button the list is expected, not a previously opened playlist
      (playlistsTab?.viewController as? UINavigationController)?
        .popToRootViewController(animated: false)
    case .search:
      selectedTab = searchTab
    }
    configureTraitChangesForMiniPlayer()
  }

  func displaySearch() {
    guard let searchTab else { return }
    visualizePopupPlayer(direction: .close, animated: true) {
      self.selectedTab = searchTab
      searchTab.viewController?.navigationController?.popToRootViewController(animated: false)
      Task {
        try? await Task.sleep(nanoseconds: 500_000_000)
        if let searchTabVC = searchTab.viewController?.navigationController?
          .topViewController as? SearchVC {
          searchTabVC.activateSearchBar()
        }
      }
    }
  }

  func getSafeAreaExtension() -> CGFloat {
    0.0
  }
}

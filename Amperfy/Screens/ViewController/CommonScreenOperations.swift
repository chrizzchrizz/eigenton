//
//  CommonScreenOperations.swift
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
import Foundation
import UIKit

extension UIView {
  static let defaultMarginX: CGFloat = 25
  static let defaultMarginY: CGFloat = 11
  static let defaultMarginTopElement = UIEdgeInsets(
    top: 0.0,
    left: UIView.defaultMarginX,
    bottom: 0.0,
    right: UIView.defaultMarginX
  )
  static let defaultMarginMiddleElement = UIEdgeInsets(
    top: UIView.defaultMarginY,
    left: UIView.defaultMarginX,
    bottom: UIView.defaultMarginY,
    right: UIView.defaultMarginX
  )
  static let defaultMarginCellX: CGFloat = 16
  static let defaultMarginCellY: CGFloat = 9
  static let defaultMarginCell = UIEdgeInsets(
    top: UIView.defaultMarginCellY,
    left: UIView.defaultMarginCellX,
    bottom: UIView.defaultMarginCellY,
    right: UIView.defaultMarginCellX
  )
}

// MARK: - CommonScreenOperations

class CommonScreenOperations {
  static let tableSectionHeightLarge: CGFloat = 40
  static let tableSectionHeightFooter: CGFloat = 8
}

// MARK: - UIViewController

extension UIViewController {
  #if !targetEnvironment(macCatalyst)
    private func openSettings() {
      let nav = AppStoryboard.Main.segueToSettings()
      nav.modalPresentationStyle = .formSheet
      nav.sheetPresentationController?.prefersGrabberVisible = true
      present(nav, animated: true)
    }
  #endif

  public func setupUserNavButton() {
    // on Mac the settings are reachable via the main menu
    #if !targetEnvironment(macCatalyst)
      navigationItem.leftBarButtonItem = UIBarButtonItem(
        image: .settingsFilled,
        primaryAction: UIAction { [weak self] _ in
          self?.openSettings()
        }
      )
    #endif
    refreshOfflineBarButton()
  }

  private static let offlineBarButtonTag = 0x0FF1

  /// Shows the offline button next to the back or user button while offline mode is active.
  func refreshOfflineBarButton() {
    var items = (navigationItem.leftBarButtonItems ?? [])
      .filter { $0.tag != UIViewController.offlineBarButtonTag }
    if appDelegate.storage.settings.user.isOfflineMode {
      let goOnline = UIAction(title: "Go Online", image: .onlineMode) { [weak self] _ in
        self?.appDelegate.switchOnlineOfflineMode(isOfflineMode: false)
      }
      let offlineButton = UIBarButtonItem(
        title: "Offline Mode",
        image: .offlineMode,
        menu: UIMenu(title: "Offline Mode is active", children: [goOnline])
      )
      offlineButton.tag = UIViewController.offlineBarButtonTag
      items.append(offlineButton)
    }
    navigationItem.leftItemsSupplementBackButton = true
    navigationItem.leftBarButtonItems = items
  }
}

// MARK: - OfflineIndicatingNavigationController

/// Shows the offline button in the navigation bar of every screen while offline mode is active.
/// Used for the main navigation stacks (tabs, split view detail); sidebar and modal sheets keep a plain UINavigationController.
class OfflineIndicatingNavigationController: UINavigationController {
  override func viewDidLoad() {
    super.viewDidLoad()
    #if targetEnvironment(macCatalyst)
      delegate = self
    #endif
    viewControllers.forEach { $0.refreshOfflineBarButton() }
    appDelegate.notificationHandler.register(
      self,
      selector: #selector(offlineModeChanged),
      name: .offlineModeChanged,
      object: nil
    )
  }

  override func pushViewController(_ viewController: UIViewController, animated: Bool) {
    viewController.refreshOfflineBarButton()
    super.pushViewController(viewController, animated: animated)
  }

  override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
    viewControllers.forEach { $0.refreshOfflineBarButton() }
    super.setViewControllers(viewControllers, animated: animated)
  }

  @objc
  private func offlineModeChanged() {
    viewControllers.forEach { $0.refreshOfflineBarButton() }
  }
}

#if targetEnvironment(macCatalyst)
  extension OfflineIndicatingNavigationController: UINavigationControllerDelegate {
    /// On Mac a screen without a title shows the app name in the title bar instead,
    /// a blank title is shown in quotes. Hide the window title for such screens like on iOS.
    func navigationController(
      _ navigationController: UINavigationController,
      willShow viewController: UIViewController,
      animated: Bool
    ) {
      let hasTitle = !(viewController.navigationItem.title ?? viewController.title ?? "").isEmpty
      view.window?.windowScene?.titlebar?.titleVisibility = hasTitle ? .visible : .hidden
    }
  }
#endif

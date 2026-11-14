//
//  DownloadsVC.swift
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
import Foundation
import UIKit

// MARK: - DownloadsVC

class DownloadsVC: SingleFetchedResultsTableViewController<DownloadMO> {
  override var sceneTitle: String? { "Downloads" }

  private var fetchedResultsController: DownloadsFetchedResultsController!
  private var optionsButton: UIBarButtonItem!
  private var downloadManager: DownloadManageable!

  init(account: Account) {
    super.init(style: .plain, account: account)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.separatorStyle = .none // rows draw their own separators
    appDelegate.userStatistics.visited(.downloads)
    downloadManager = appDelegate.getMeta(account.info).playableDownloadManager

    fetchedResultsController = DownloadsFetchedResultsController(
      coreDataCompanion: appDelegate.storage.main, account: account,
      isGroupedInAlphabeticSections: false
    )
    singleFetchedResultsController = fetchedResultsController

    tableView.register(nibName: PlayableTableCell.typeName)
    tableView.reloadOnTextSizeChange { PlayableTableCell.rowHeight }
    tableView.sectionFooterHeight = 0.0
    tableView.estimatedSectionFooterHeight = 0.0
    tableView.sectionHeaderHeight = 0.0
    tableView.estimatedSectionHeaderHeight = 0.0

    optionsButton = UIBarButtonItem.createOptionsBarButton()
    optionsButton.menu = createActionButtonMenu()
    navigationItem.rightBarButtonItem = optionsButton
    showLargeTitleOnMac()
  }

  private func createActionButtonMenu() -> UIMenu {
    let clearFinishedDownloadsAction = UIAction(
      title: "Clear finished downloads",
      image: UIImage.clear,
      handler: { [weak self] _ in
        guard let self else { return }
        downloadManager.clearFinishedDownloads()
      }
    )
    let retryFailedDownloadsAction = UIAction(
      title: "Retry failed downloads",
      image: UIImage.redo,
      handler: { [weak self] _ in
        guard let self else { return }
        downloadManager.resetFailedDownloads()
      }
    )
    let cancelAllDownloadsAction = UIAction(
      title: "Cancel all downloads",
      image: UIImage.cancleDownloads,
      handler: { [weak self] _ in
        guard let self else { return }
        downloadManager.cancelDownloads()
      }
    )
    return UIMenu(children: [
      clearFinishedDownloadsAction,
      retryFailedDownloadsAction,
      cancelAllDownloadsAction,
    ])
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = true
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    fetchedResultsController.fetch()
    tableView.reloadData()
  }

  func convertCellViewToPlayContext(cell: UITableViewCell) -> PlayContext? {
    guard let indexPath = tableView.indexPath(for: cell) else { return nil }
    let downdload = fetchedResultsController.getWrappedEntity(at: indexPath)
    guard let playable = downdload.element as? AbstractPlayable else { return nil }
    return PlayContext(containable: playable)
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    let cell: PlayableTableCell = dequeueCell(for: tableView, at: indexPath)
    let download = fetchedResultsController.getWrappedEntity(at: indexPath)
    if let playable = download.element as? AbstractPlayable {
      cell.display(
        playable: playable,
        playContextCb: { [weak self] cell in self?.convertCellViewToPlayContext(cell: cell) },
        rootView: self,
        download: download
      )
    }
    return cell
  }
}

// MARK: - DownloadsBarButton

/// Bar button that opens the downloads, only visible while there are downloads.
@MainActor
final class DownloadsBarButton {
  let item: UIBarButtonItem

  init(account: Account, openCB: @escaping @MainActor () -> ()) {
    self.item = UIBarButtonItem(
      image: LibraryDisplayType.downloads.image,
      primaryAction: UIAction { _ in openCB() }
    )
    item.accessibilityLabel = LibraryDisplayType.downloads.displayName
    // own glass background, it has nothing to do with the edit button next to it
    item.sharesBackground = false
    DownloadsAvailability.shared(for: account).register(item)
  }
}

// MARK: - DownloadsAvailability

/// Tracks whether the downloads list of an account is empty, one instance per account shared by all
/// downloads buttons. Only counts, so the downloads themselves are never loaded for this.
@MainActor
final class DownloadsAvailability {
  private static var instances = [NSManagedObjectID: DownloadsAvailability]()

  static func shared(for account: Account) -> DownloadsAvailability {
    let key = account.managedObject.objectID
    if let instance = instances[key] { return instance }
    let instance = DownloadsAvailability(account: account)
    instances[key] = instance
    return instance
  }

  private let account: Account
  private let items = NSHashTable<UIBarButtonItem>.weakObjects()
  private var saveObserver: NSObjectProtocol?
  private(set) var hasDownloads = false

  private init(account: Account) {
    self.account = account
    self.hasDownloads = countDownloads() > 0
    let downloadEntityName = DownloadMO.entity().name
    // saves of all contexts: the main context doesn't report deleted downloads it never loaded
    self.saveObserver = NotificationCenter.default.addObserver(
      forName: .NSManagedObjectContextDidSaveObjectIDs,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      // only inserted or deleted downloads change whether the list is empty
      let isDownloadAffected = [NSInsertedObjectIDsKey, NSDeletedObjectIDsKey].contains { key in
        (notification.userInfo?[key] as? Set<NSManagedObjectID>)?
          .contains { $0.entity.name == downloadEntityName } ?? false
      }
      guard isDownloadAffected else { return }
      Task { @MainActor in self?.refresh() }
    }
  }

  func register(_ item: UIBarButtonItem) {
    items.add(item)
    item.isHidden = !hasDownloads
  }

  private func countDownloads() -> Int {
    (UIApplication.shared.delegate as! AppDelegate).storage.main.library
      .getPlayableDownloadCount(for: account)
  }

  private func refresh() {
    let hasDownloads = countDownloads() > 0
    guard hasDownloads != self.hasDownloads else { return }
    self.hasDownloads = hasDownloads
    for item in items.allObjects {
      item.isHidden = !hasDownloads
    }
  }
}

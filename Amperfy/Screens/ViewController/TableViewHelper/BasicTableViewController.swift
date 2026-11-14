//
//  BasicTableViewController.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 23.02.24.
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
import Foundation
import UIKit

extension UIViewController {
  func setNavBarTitle(title: String) {
    self.title = title
  }
}

// MARK: - TableViewPreviewInfo

public struct TableViewPreviewInfo: Codable {
  public var playableContainerIdentifier: PlayableContainerIdentifier?
  public var indexPath: IndexPath?

  static func create(fromIdentifier identifier: String) -> TableViewPreviewInfo? {
    guard let identifierData = identifier.data(using: .utf8),
          let tvIdentifier = try? JSONDecoder().decode(
            TableViewPreviewInfo.self,
            from: identifierData
          )
    else { return nil }
    return tvIdentifier
  }
}

public typealias ContainableAtIndexPathCallback = (IndexPath) -> PlayableContainable?
public typealias SwipeActionCallback = (
  IndexPath,
  _ completionHandler: @escaping (_ actionContext: SwipeActionContext?) -> ()
)
  -> ()
public typealias PlayContextAtIndexPathCallback = (IndexPath) -> PlayContext?

// MARK: - SwipeDisplaySettings

struct SwipeDisplaySettings {
  var playContextTypeOfElements: PlayerMode = .music

  func isAllowedToDisplay(
    actionType: SwipeActionType,
    containable: PlayableContainable,
    isOfflineMode: Bool,
    isSimplifiedQueue: Bool,
    hasLoadedPlayables: Bool
  )
    -> Bool {
    switch playContextTypeOfElements {
    case .music:
      if actionType == .appendContextQueue, isSimplifiedQueue, !hasLoadedPlayables {
        return false
      }
      if actionType == .addToPlaylist,
         containable.playables.count == 1,
         containable.playables[0].isRadio {
        return false
      }
      if actionType == .insertPodcastQueue ||
        actionType == .appendPodcastQueue {
        return false
      }
    case .podcast:
      if actionType == .playShuffled ||
        actionType == .addToPlaylist ||
        actionType == .insertContextQueue ||
        actionType == .appendContextQueue ||
        actionType == .insertUserQueue ||
        actionType == .appendUserQueue {
        return false
      }
    }
    if isOfflineMode,
       actionType == .addToPlaylist || actionType == .download || actionType == .favorite {
      return false
    }
    if !containable.isFavoritable, actionType == .favorite {
      return false
    }
    return true
  }
}

// MARK: - TableSectionHeaderView

/// Section title aligned with the row content: pinned to the layout margins of the table view
/// (safe area plus system margin, e.g. below the sidebar), like the margins of the cells.
final class TableSectionHeaderView: UIView {
  // A plain view: UIKit applies the title of `titleForHeaderInSection` to the default label of
  // UITableViewHeaderFooterView, which would be displayed in addition to this title.
  private let listContentView = UIListContentView(configuration: .header())
  /// Shown at the trailing end of the title, e.g. a button
  private let accessoryView: UIView?
  private var isPinnedToTable = false

  /// `topInset`: space above the title within the header, e.g. to separate it from the
  /// previous section when the table adds no padding above section headers
  init(title: String, accessoryView: UIView? = nil, topInset: CGFloat = 0) {
    self.accessoryView = accessoryView
    super.init(frame: .zero)
    var configuration = UIListContentConfiguration.header()
    configuration.text = title
    configuration.directionalLayoutMargins.leading = 0
    configuration.directionalLayoutMargins.trailing = 0
    listContentView.configuration = configuration
    listContentView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(listContentView)
    // fallback until the header is part of the table view, replaced by the table margins
    let fallbackLeading = listContentView.leadingAnchor.constraint(equalTo: leadingAnchor)
    let fallbackTrailing = (accessoryView ?? listContentView).trailingAnchor
      .constraint(equalTo: trailingAnchor)
    fallbackLeading.priority = .defaultLow
    fallbackTrailing.priority = .defaultLow
    NSLayoutConstraint.activate([
      listContentView.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
      listContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
      fallbackLeading,
      fallbackTrailing,
    ])
    if let accessoryView {
      accessoryView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(accessoryView)
      NSLayoutConstraint.activate([
        accessoryView.leadingAnchor.constraint(
          equalToSystemSpacingAfter: listContentView.trailingAnchor,
          multiplier: 1
        ),
        accessoryView.centerYAnchor.constraint(equalTo: listContentView.centerYAnchor),
      ])
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    guard !isPinnedToTable else { return }
    var view = superview
    while let current = view, !(current is UITableView) { view = current.superview }
    guard let tableView = view as? UITableView else { return }
    isPinnedToTable = true
    NSLayoutConstraint.activate([
      listContentView.leadingAnchor.constraint(equalTo: tableView.layoutMarginsGuide.leadingAnchor),
      (accessoryView ?? listContentView).trailingAnchor
        .constraint(equalTo: tableView.layoutMarginsGuide.trailingAnchor),
    ])
  }
}

// MARK: - BasicTableViewController

class BasicTableViewController: KeyCommandTableViewController {
  private static let swipeButtonColors: [UIColor] = [
    .defaultBlue,
    .systemOrange,
    .systemPurple,
    .systemGray,
  ]

  let searchController = UISearchController(searchResultsController: nil)
  private let searchResultsUpdaterProxy = DebouncedSearchResultsUpdater()

  var swipeDisplaySettings = SwipeDisplaySettings()
  var containableAtIndexPathCallback: ContainableAtIndexPathCallback?
  var playContextAtIndexPathCallback: PlayContextAtIndexPathCallback?
  var swipeCallback: SwipeActionCallback?
  var isEditLockedDueToActiveSwipe = false
  var isSingleCellEditingModeActive = false
  #if targetEnvironment(macCatalyst)
    private var macLargeTitle: MacLargeTitle?
  #endif

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.keyboardDismissMode = .onDrag
    #if targetEnvironment(macCatalyst)
      if #available(macCatalyst 27.0, *) {
        // the default hard edge on Mac draws an opaque band behind the title bar buttons;
        // soft lets the content run visibly under the glass buttons like on Home and Library.
        // Before macOS 27 the soft glass is too big (see SideBarVC), so keep the default there.
        tableView.topEdgeEffect.style = .soft
      }
      // no section index on Mac, the lists are scrolled with wheel, trackpad or keyboard
      tableView.sectionIndexMinimumDisplayRowCount = .max
    #endif
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    #if targetEnvironment(macCatalyst)
      // the navigation controller resets the title bar for every shown screen
      macLargeTitle?.update()
    #endif

    if searchController.searchBar.scopeButtonTitles?.count ?? 0 > 1,
       appDelegate.storage.settings.user.isOfflineMode {
      searchController.searchBar.selectedScopeButtonIndex = 1
    } else {
      searchController.searchBar.selectedScopeButtonIndex = 0
    }
    updateSearchResults(for: searchController)
  }

  /// Mac only: shows the title large above the table, like the large navigation title on iOS.
  /// Call at the end of `viewDidLoad`, after an own table header view was set.
  func showLargeTitleOnMac() {
    #if targetEnvironment(macCatalyst)
      macLargeTitle = MacLargeTitle(viewController: self, scrollView: tableView)
      macLargeTitle?.installAsTableHeader()
    #endif
  }

  /// Tables whose cells draw their own separators (`separatorStyle = .none`) also align the
  /// section titles with the cell margins.
  override func tableView(
    _ tableView: UITableView,
    viewForHeaderInSection section: Int
  )
    -> UIView? {
    guard tableView.separatorStyle == .none,
          let title = self.tableView(tableView, titleForHeaderInSection: section), !title.isEmpty
    else { return nil }
    return TableSectionHeaderView(
      title: title,
      topInset: sectionHeaderTopInset(forSection: section)
    )
  }

  /// Space above the title of the default section header (see `TableSectionHeaderView`)
  func sectionHeaderTopInset(forSection section: Int) -> CGFloat {
    0.0
  }

  /// Section headers created from `tableView(_:titleForHeaderInSection:)` have a fixed text
  /// size: use a text style that scales with the user's text size (see `TextScaling`)
  override func tableView(
    _ tableView: UITableView,
    willDisplayHeaderView view: UIView,
    forSection section: Int
  ) {
    guard let header = view as? UITableViewHeaderFooterView else { return }
    var content = (header.contentConfiguration as? UIListContentConfiguration) ??
      header.defaultContentConfiguration()
    if content.text == nil {
      content.text = tableView.dataSource?.tableView?(tableView, titleForHeaderInSection: section)
    }
    let traits = header.traitCollection
    let font = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits)
    content.textProperties.font = TextScaling.scaledFont(font, compatibleWith: traits)
    content.textProperties.adjustsFontForContentSizeCategory = true
    header.contentConfiguration = content
  }

  override func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
    isSingleCellEditingModeActive = true
  }

  override func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
    isSingleCellEditingModeActive = false
  }

  override func tableView(
    _ tableView: UITableView,
    leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  )
    -> UISwipeActionsConfiguration? {
    guard let swipeCB = swipeCallback,
          let containableCB = containableAtIndexPathCallback,
          let containable = containableCB(indexPath)
    else { return UISwipeActionsConfiguration() }

    var createdActionsIndex = 0
    var actions = [UIContextualAction]()
    for actionType in appDelegate.storage.settings.user.activeSwipeActionSettings.leading {
      if !swipeDisplaySettings.isAllowedToDisplay(
        actionType: actionType,
        containable: containable,
        isOfflineMode: appDelegate.storage.settings.user.isOfflineMode,
        isSimplifiedQueue: appDelegate.storage.settings.user.isSimplifiedQueueEnabled,
        hasLoadedPlayables: appDelegate.player.hasLoadedPlayables
      ) { continue }
      let buttonColor = Self.swipeButtonColors.element(at: createdActionsIndex) ?? Self
        .swipeButtonColors.last!
      actions.append(createSwipeAction(
        for: actionType,
        buttonColor: buttonColor,
        indexPath: indexPath,
        preCbContainable: containable,
        actionCallback: swipeCB
      ))
      createdActionsIndex += 1
    }
    return UISwipeActionsConfiguration(actions: actions)
  }

  override func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  )
    -> UISwipeActionsConfiguration? {
    // return nil here allows to display the "Delete" confirmation swipe action in edit mode (nil -> show default action -> delete is the default one)
    guard !(tableView.isEditing && !isSingleCellEditingModeActive) else { return nil }
    // this empty configuration ensures to only perform one "Delete" action at a time (no confirmation is displayed)
    guard !(tableView.isEditing && isSingleCellEditingModeActive)
    else { return UISwipeActionsConfiguration() }
    guard let swipeCB = swipeCallback,
          let containableCB = containableAtIndexPathCallback,
          let containable = containableCB(indexPath)
    else { return UISwipeActionsConfiguration() }
    var createdActionsIndex = 0
    var actions = [UIContextualAction]()
    for actionType in appDelegate.storage.settings.user.activeSwipeActionSettings.trailing {
      if !swipeDisplaySettings.isAllowedToDisplay(
        actionType: actionType,
        containable: containable,
        isOfflineMode: appDelegate.storage.settings.user.isOfflineMode,
        isSimplifiedQueue: appDelegate.storage.settings.user.isSimplifiedQueueEnabled,
        hasLoadedPlayables: appDelegate.player.hasLoadedPlayables
      ) { continue }
      let buttonColor = Self.swipeButtonColors.element(at: createdActionsIndex) ?? Self
        .swipeButtonColors.last!
      actions.append(createSwipeAction(
        for: actionType,
        buttonColor: buttonColor,
        indexPath: indexPath,
        preCbContainable: containable,
        actionCallback: swipeCB
      ))
      createdActionsIndex += 1
    }
    return UISwipeActionsConfiguration(actions: actions)
  }

  func configureSearchController(
    placeholder: String?,
    scopeButtonTitles: [String]? = nil
  ) {
    searchResultsUpdaterProxy.target = self
    searchController.searchResultsUpdater = searchResultsUpdaterProxy
    searchController.searchBar.autocapitalizationType = .none
    #if !targetEnvironment(macCatalyst)
      // On mac catalyist scopeButtonTitle together with fullscreen will trigger the following exception:
      // FAULT: NSInternalInconsistencyException: titlebarViewController not supported for this window style;
      searchController.searchBar.scopeButtonTitles = scopeButtonTitles
    #endif
    searchController.searchBar.placeholder = placeholder

    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = true
    #if targetEnvironment(macCatalyst)
      navigationItem.preferredSearchBarPlacement = .integrated
    #else
      navigationItem.preferredSearchBarPlacement = .automatic
    #endif

    searchController.delegate = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.delegate = self // Monitor when the search button is tapped.
    definesPresentationContext = true
  }

  override func tableView(
    _ tableView: UITableView,
    heightForHeaderInSection section: Int
  )
    -> CGFloat {
    0.0
  }

  override func tableView(
    _ tableView: UITableView,
    contextMenuConfigurationForRowAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    guard let containableCB = containableAtIndexPathCallback,
          let containable = containableCB(indexPath)
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
          if let account = containable.account {
            try await containable.fetch(
              storage: self.appDelegate.storage,
              librarySyncer: self.appDelegate.getMeta(account.info).librarySyncer,
              playableDownloadManager: self.appDelegate.getMeta(account.info)
                .playableDownloadManager
            )
          }
        } catch {
          self.appDelegate.eventLogger.report(topic: "Preview Sync", error: error)
        }
        vc.refresh()
      }
      return vc
    }) { suggestedActions in
      var playIndexCB: (() -> PlayContext?)?
      if let playContextAtIndexPathCP = self.playContextAtIndexPathCallback {
        playIndexCB = { playContextAtIndexPathCP(indexPath) }
      }
      return EntityPreviewActionBuilder(
        container: containable,
        on: self,
        playContextCb: playIndexCB
      ).createMenu()
    }
  }

  override func tableView(
    _ tableView: UITableView,
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

  func createSwipeAction(
    for actionType: SwipeActionType,
    buttonColor: UIColor,
    indexPath: IndexPath,
    preCbContainable: PlayableContainable,
    actionCallback: @escaping SwipeActionCallback
  )
    -> UIContextualAction {
    let action = UIContextualAction(
      style: .normal,
      title: actionType.displayName(
        isSimplifiedQueue: appDelegate.storage.settings.user.isSimplifiedQueueEnabled
      )
    ) { [weak self] action, view, completionHandler in
      // the table keeps its last swipe actions, which must not keep the screen alive
      guard let self else {
        completionHandler(false)
        return
      }
      Haptics.success
        .vibrate(isHapticsEnabled: appDelegate.storage.settings.user.isHapticsEnabled)
      actionCallback(indexPath) { actionContext in
        guard let actionContext = actionContext else { return }
        switch actionType {
        case .insertUserQueue:
          self.appDelegate.player
            .insertUserQueue(
              playables: actionContext.playables
                .filterCached(dependigOn: self.appDelegate.storage.settings.user.isOfflineMode)
            )
        case .appendUserQueue:
          self.appDelegate.player
            .appendUserQueue(
              playables: actionContext.playables
                .filterCached(dependigOn: self.appDelegate.storage.settings.user.isOfflineMode)
            )
        case .insertContextQueue:
          self.appDelegate.player
            .insertContextQueue(
              playables: actionContext.playables
                .filterCached(dependigOn: self.appDelegate.storage.settings.user.isOfflineMode)
            )
        case .appendContextQueue:
          self.appDelegate.player
            .appendContextQueue(
              playables: actionContext.playables
                .filterCached(dependigOn: self.appDelegate.storage.settings.user.isOfflineMode)
            )
        case .download:
          if let account = actionContext.containable.account {
            self.appDelegate.getMeta(account.info).playableDownloadManager
              .download(objects: actionContext.playables)
          }
        case .removeFromCache:
          let alert = UIAlertController(
            title: nil,
            message: "Are you sure you want to delete the download\(actionContext.playables.count > 1 ? "s" : "")?",
            preferredStyle: .alert
          )
          alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            if let account = actionContext.containable.account {
              self.appDelegate.getMeta(account.info).playableDownloadManager
                .removeFinishedDownload(for: actionContext.playables)
            }
            self.appDelegate.storage.main.library.deleteCache(of: actionContext.playables)
            self.appDelegate.storage.main.saveContext()
            if let cell = self.tableView.cellForRow(at: indexPath) as? PlayableTableCell {
              cell.refresh()
            }
          }))
          alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            // do nothing
          }))
          self.present(alert, animated: true, completion: nil)
        case .addToPlaylist:
          let filterSongs = actionContext.playables.filterSongs()
          if let account = filterSongs.first?.account {
            let selectPlaylistVC = AppStoryboard.Main
              .segueToPlaylistSelector(
                account: account,
                itemsToAdd: filterSongs
              )
            let selectPlaylistNav = UINavigationController(rootViewController: selectPlaylistVC)
            self.present(selectPlaylistNav, animated: true)
          }
        case .play:
          self.appDelegate.player.play(context: actionContext.playContext)
        case .playShuffled:
          var playContext = actionContext.playContext
          if actionContext.playables.count <= 1 {
            playContext.isKeepIndexDuringShuffle = true
          }
          self.appDelegate.player.playShuffled(context: playContext)
        case .insertPodcastQueue:
          self.appDelegate.player
            .insertPodcastQueue(
              playables: actionContext.playables
                .filterCached(dependigOn: self.appDelegate.storage.settings.user.isOfflineMode)
            )
        case .appendPodcastQueue:
          self.appDelegate.player
            .appendPodcastQueue(
              playables: actionContext.playables
                .filterCached(dependigOn: self.appDelegate.storage.settings.user.isOfflineMode)
            )
        case .favorite:
          Task { @MainActor in
            do {
              if let account = actionContext.containable.account {
                try await actionContext.containable
                  .remoteToggleFavorite(
                    syncer: self.appDelegate
                      .getMeta(account.info).librarySyncer
                  )
              }
            } catch {
              self.appDelegate.eventLogger.report(topic: "Toggle Favorite", error: error)
            }
            if let cell = self.tableView.cellForRow(at: indexPath) as? PlayableTableCell {
              cell.refresh()
            }
          }
        }
      }
      completionHandler(true)
    }
    action.backgroundColor = buttonColor
    if actionType == .favorite {
      action.image = preCbContainable.isFavorite
        ? UIImage.heartFill.withRenderingMode(.alwaysOriginal)
        : UIImage.heartEmpty.withRenderingMode(.alwaysOriginal)
    } else {
      action.image = actionType.image.withRenderingMode(.alwaysOriginal)
    }
    return action
  }
}

// MARK: UISearchResultsUpdating

extension BasicTableViewController: UISearchResultsUpdating {
  func updateSearchResults(for searchController: UISearchController) {}
}

// MARK: UISearchBarDelegate

extension BasicTableViewController: UISearchBarDelegate {
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    searchBar.resignFirstResponder()
  }

  func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
    updateSearchResults(for: searchController)
  }
}

// MARK: UISearchControllerDelegate

extension BasicTableViewController: UISearchControllerDelegate {}

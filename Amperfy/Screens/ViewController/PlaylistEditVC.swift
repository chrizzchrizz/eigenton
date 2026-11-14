//
//  PlaylistEditVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 06.12.24.
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

// MARK: - PlaylistEditMode

enum PlaylistEditMode {
  case reorder
  case delete
}

// MARK: - PlaylistEditVC

class PlaylistEditVC: SingleSnapshotFetchedResultsTableViewController<PlaylistItemMO> {
  private var fetchedResultsController: PlaylistItemsFetchedResultsController!

  let playlist: Playlist
  var onDoneCB: VoidFunctionCallback?

  private var doneButton: UIBarButtonItem!
  private var selectBarButton: UIBarButtonItem!
  private var deleteBarButton: UIBarButtonItem!
  private var addBarButton: UIBarButtonItem!

  var detailOperationsView: GenericDetailTableHeader?

  private var selectedItems = [PlaylistItem]()
  private var editMode = PlaylistEditMode.reorder
  private lazy var coverPicker = CoverImagePicker(presenter: self)

  init(account: Account, playlist: Playlist) {
    self.playlist = playlist
    super.init(style: .plain, account: account)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func createDiffableDataSource() -> BasicUITableViewDiffableDataSource {
    let source =
      PlaylistDetailDiffableDataSource(tableView: tableView) { [
        weak self
      ] tableView, indexPath, objectID -> UITableViewCell? in
        guard let self else { return UITableViewCell() }
        guard let object = try? appDelegate.storage.main.context
          .existingObject(with: objectID),
          let playlistItemMO = object as? PlaylistItemMO
        else {
          return UITableViewCell()
        }
        let playlistItem = PlaylistItem(
          library: appDelegate.storage.main.library,
          managedObject: playlistItemMO
        )
        return createCell(tableView, forRowAt: indexPath, playlistItem: playlistItem)
      }
    source.playlist = playlist
    return source
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.separatorStyle = .none // rows draw their own separators

    fetchedResultsController = PlaylistItemsFetchedResultsController(
      forPlaylist: playlist,
      coreDataCompanion: appDelegate.storage.main,
      isGroupedInAlphabeticSections: false
    )
    singleFetchedResultsController = fetchedResultsController
    singleFetchedResultsController?.delegate = self
    singleFetchedResultsController?.fetch()

    tableView.register(nibName: PlayableTableCell.typeName)
    tableView.reloadOnTextSizeChange { PlayableTableCell.rowHeight }
    tableView.sectionFooterHeight = 0.0
    tableView.estimatedSectionFooterHeight = 0.0
    tableView.sectionHeaderHeight = 0.0
    tableView.estimatedSectionHeaderHeight = 0.0

    let detailHeaderConfig = DetailHeaderConfiguration(
      entityContainer: playlist,
      rootView: self,
      tableView: tableView,
      playShuffleInfoConfig: nil
    )
    detailOperationsView = GenericDetailTableHeader
      .createTableHeader(configuration: detailHeaderConfig)

    tableView.allowsSelection = true
    tableView.allowsMultipleSelection = true
    tableView.allowsSelectionDuringEditing = true
    tableView.dragDelegate = self
    tableView.dropDelegate = self
    tableView.dragInteractionEnabled = true
    detailOperationsView?.startEditing()
    enableCoverEditingIfSupported()

    navigationController?.setToolbarHidden(false, animated: false)
    let flexible = UIBarButtonItem(
      barButtonSystemItem: UIBarButtonItem.SystemItem.flexibleSpace,
      target: self,
      action: nil
    )
    selectBarButton = UIBarButtonItem(
      title: "Select",
      style: .plain,
      target: self,
      action: #selector(selectBarButtonPressed)
    )
    deleteBarButton = UIBarButtonItem(
      image: .trash,
      style: .plain,
      target: self,
      action: #selector(deleteBarButtonPressed)
    )
    addBarButton = UIBarButtonItem(
      image: .plus,
      style: .plain,
      target: self,
      action: #selector(addBarButtonPressed)
    )
    toolbarItems = [selectBarButton, flexible, addBarButton, flexible, deleteBarButton]

    changeEditMode(.reorder)
    refreshBarButtons()
  }

  private func enableCoverEditingIfSupported() {
    guard appDelegate.storage.settings.user.isOnlineMode, !playlist.isSmartPlaylist else { return }
    Task { @MainActor [weak self] in
      guard let self else { return }
      let librarySyncer = appDelegate.getMeta(account.info).librarySyncer
      guard await librarySyncer.isPlaylistCoverUploadSupported() else { return }
      detailOperationsView?.onCoverEditTap = { [weak self] sourceView in
        self?.presentCoverSourceSelection(sourceView: sourceView)
      }
    }
  }

  private func presentCoverSourceSelection(sourceView: UIView) {
    let alert = UIAlertController(title: "Cover", message: nil, preferredStyle: .actionSheet)
    alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
      self?.coverPicker.pickFromPhotoLibrary { self?.uploadCover($0) }
    })
    alert.addAction(UIAlertAction(title: "Files", style: .default) { [weak self] _ in
      self?.coverPicker.pickFromFiles { self?.uploadCover($0) }
    })
    alert.addAction(UIAlertAction(title: "Remove Cover", style: .destructive) { [weak self] _ in
      self?.removeCover()
    })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.popoverPresentationController?.sourceView = sourceView
    alert.popoverPresentationController?.sourceRect = sourceView.bounds
    present(alert, animated: true)
  }

  private func uploadCover(_ image: UIImage) {
    guard let jpegData = image.jpegData(compressionQuality: 0.9) else { return }
    performCoverChange(topic: "Playlist Upload Cover") { librarySyncer, playlist in
      try await librarySyncer.syncUpload(playlist: playlist, coverJpegData: jpegData)
    }
  }

  private func removeCover() {
    performCoverChange(topic: "Playlist Remove Cover") { librarySyncer, playlist in
      try await librarySyncer.syncUpload(playlistToRemoveCover: playlist)
    }
  }

  private func performCoverChange(
    topic: String,
    change: @escaping @MainActor (LibrarySyncer, Playlist) async throws -> ()
  ) {
    detailOperationsView?.isUserInteractionEnabled = false
    Task { @MainActor in
      defer {
        self.detailOperationsView?.isUserInteractionEnabled = true
        self.detailOperationsView?.refresh()
      }
      do {
        try await change(
          self.appDelegate.getMeta(self.account.info).librarySyncer,
          self.playlist
        )
        // the sync ran in the background, the cover of the playlist might have been replaced
        self.appDelegate.storage.main.context.refresh(
          self.playlist.managedObject,
          mergeChanges: true
        )
        // the server can keep the id of the cover, so the cached image would stay
        if let artwork = self.playlist.artwork {
          self.appDelegate.storage.main.context.refresh(artwork.managedObject, mergeChanges: true)
          artwork.resetCache()
          self.appDelegate.storage.main.saveContext()
          self.appDelegate.getMeta(self.account.info).artworkDownloadManager
            .redownload(object: artwork)
        }
      } catch {
        self.appDelegate.eventLogger.report(topic: topic, error: error)
      }
    }
  }

  func changeEditMode(_ newMode: PlaylistEditMode) {
    editMode = newMode
    (diffableDataSource as? PlaylistDetailDiffableDataSource)?
      .isMoveAllowed = (editMode == .reorder)
    (diffableDataSource as? PlaylistDetailDiffableDataSource)?.isEditAllowed = true
    selectedItems.removeAll()
    tableView.reloadData()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    detailOperationsView?.endEditing()
    onDoneCB?()
  }

  @IBAction
  func doneBarButtonPressed(_ sender: UIBarButtonItem) {
    dismiss()
  }

  @IBAction
  func selectBarButtonPressed(_ sender: Any) {
    changeEditMode((editMode == .reorder) ? .delete : .reorder)
    selectBarButton.title = (editMode == .reorder) ? "Select" : "Reorder"
    refreshDeleteButton()
  }

  func refreshDeleteButton() {
    deleteBarButton.isEnabled = !selectedItems.isEmpty
  }

  @IBAction
  func deleteBarButtonPressed(_ sender: Any) {
    let selectedItemsSorted = selectedItems.sorted(by: { $0.order > $1.order })

    Task { @MainActor in
      do {
        for item in selectedItemsSorted {
          guard let index = self.playlist.getFirstIndex(item: item) else { continue }
          try await self.appDelegate.getMeta(self.account.info).librarySyncer
            .syncUpload(
              playlistToDeleteSong: self.playlist,
              index: index
            )
          self.playlist.remove(at: index)
        }
      } catch {
        self.appDelegate.eventLogger.report(topic: "Playlist Upload Entry Remove", error: error)
      }
      self.detailOperationsView?.refresh()
    }

    selectedItems.removeAll()
    refreshDeleteButton()
  }

  @IBAction
  func addBarButtonPressed(_ sender: Any) {
    let playlistAddVC = PlaylistAddLibraryVC(account: account)
    playlistAddVC.addToPlaylistManager.playlist = playlist
    playlistAddVC.addToPlaylistManager.onDoneCB = {
      self.detailOperationsView?.refresh()
      self.tableView.reloadData()
    }
    let playlistAddNav = UINavigationController(rootViewController: playlistAddVC)
    present(playlistAddNav, animated: true, completion: nil)
  }

  private func dismiss() {
    dismiss(animated: true, completion: nil)
  }

  func refreshBarButtons() {
    doneButton = UIBarButtonItem(
      image: .check,
      style: .plain,
      target: self,
      action: #selector(doneBarButtonPressed)
    )
    refreshDeleteButton()

    navigationItem.leftItemsSupplementBackButton = true
    navigationItem.rightBarButtonItem = doneButton
  }

  func createCell(
    _ tableView: UITableView,
    forRowAt indexPath: IndexPath,
    playlistItem: PlaylistItem
  )
    -> UITableViewCell {
    let cell: PlayableTableCell = tableView.dequeueCell(for: tableView, at: indexPath)
    if let song = playlistItem.playable.asSong {
      cell.display(
        playable: song,
        displayMode: (editMode == .reorder) ? .reorder : .selection,
        playContextCb: nil,
        rootView: self,
        isMarked: (selectedItems.firstIndex { $0 == playlistItem } != nil)
      )
    }
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: false)
    guard editMode == .delete else { return }

    let item = fetchedResultsController.getWrappedEntity(at: indexPath)
    if let cell = tableView.cellForRow(at: indexPath) as? PlayableTableCell {
      let markedIndex = selectedItems.firstIndex { $0 == item }
      if let markedIndex = markedIndex {
        selectedItems.remove(at: markedIndex)
        cell.isMarked = false
      } else {
        selectedItems.append(item)
        cell.isMarked = true
      }
      cell.refresh()
    }
    refreshDeleteButton()
  }
}

// MARK: UITableViewDragDelegate

extension PlaylistEditVC: UITableViewDragDelegate {
  func tableView(
    _ tableView: UITableView,
    itemsForBeginning session: UIDragSession,
    at indexPath: IndexPath
  )
    -> [UIDragItem] {
    // Reordering is done via tableView(_:moveRowAt:to:); the item only has to be non-empty.
    reorderDragItems()
  }

  func tableView(
    _ tableView: UITableView,
    dragPreviewParametersForRowAt indexPath: IndexPath
  )
    -> UIDragPreviewParameters? {
    let parameter = UIDragPreviewParameters()
    return parameter
  }
}

// MARK: UITableViewDropDelegate

extension PlaylistEditVC: UITableViewDropDelegate {
  // Only accept drags that originate from this table view (reordering).
  func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
    tableView.hasActiveDrag && session.localDragSession != nil
  }

  func tableView(
    _ tableView: UITableView,
    dropSessionDidUpdate session: UIDropSession,
    withDestinationIndexPath destinationIndexPath: IndexPath?
  )
    -> UITableViewDropProposal {
    guard tableView.hasActiveDrag, session.localDragSession != nil else {
      return UITableViewDropProposal(operation: .cancel)
    }
    return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
  }

  func tableView(
    _ tableView: UITableView,
    performDropWith coordinator: UITableViewDropCoordinator
  ) {
    // Local drags with one item go through the existing tableView(_:moveRowAt:to:) method on the data source
  }

  func tableView(_ tableView: UITableView, dropSessionDidEnd session: UIDropSession) {}

  func tableView(
    _ tableView: UITableView,
    dropPreviewParametersForRowAt indexPath: IndexPath
  )
    -> UIDragPreviewParameters? {
    let parameter = UIDragPreviewParameters()
    return parameter
  }
}

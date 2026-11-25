//
//  LibraryChangeSyncer.swift
//  AmperfyKit
//
//  Created by Chrizz Gelbach on 25.11.26.
//  Copyright (c) 2026 Chrizz Gelbach. All rights reserved.
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

import CoreData
import Foundation
import os.log

// MARK: - LibraryChangeSyncer

/// Favorite and rating changes of songs, albums and artists: set locally right away, also in
/// offline mode, and uploaded to the server as soon as the app is online and has network.
/// Until then they wait as `PendingLibraryChange`, the last change of an entity wins.
@MainActor
public class LibraryChangeSyncer {
  /// How an upload failed
  enum UploadFailure: Equatable {
    /// The server can't be reached or doesn't accept the login: the other changes would fail
    /// too, the upload is tried again later
    case serverUnavailable
    /// Only this change failed, e.g. a generic server error: the others are still uploaded and
    /// this one is tried again later
    case changeFailed
    /// The server rejects the change, e.g. the entity is gone or the operation is not allowed:
    /// sending it again would fail again, it is dropped
    case changeRejected
  }

  private let log = OSLog(subsystem: "Amperfy", category: "LibraryChangeSyncer")
  private let account: Account
  private let storage: PersistentStorage
  private let librarySyncer: LibrarySyncer
  private let networkMonitor: NetworkMonitorFacade
  private let eventLogger: EventLogger
  private let retryDelay: Duration
  /// Set while the account's managers run: changes are recorded anyway, uploaded only then
  private var isEnabled = false
  private var isUploadRequested = false
  private var isActive = false
  private var retryTask: Task<(), Never>?

  init(
    account: Account,
    storage: PersistentStorage,
    librarySyncer: LibrarySyncer,
    networkMonitor: NetworkMonitorFacade,
    eventLogger: EventLogger,
    retryDelay: Duration = .seconds(60)
  ) {
    self.account = account
    self.storage = storage
    self.librarySyncer = librarySyncer
    self.networkMonitor = networkMonitor
    self.eventLogger = eventLogger
    self.retryDelay = retryDelay
  }

  private var isUploadAllowed: Bool {
    isEnabled && storage.settings.user.isOnlineMode && networkMonitor.isConnectedToNetwork
  }

  // MARK: Changes

  /// Toggles the favorite of a song, album or artist, other containables are ignored
  public func toggleFavorite(_ containable: PlayableContainable) {
    guard let entity = containable as? AbstractLibraryEntity else { return }
    setFavorite(entity, isFavorite: !entity.isFavorite)
  }

  public func setFavorite(_ entity: AbstractLibraryEntity, isFavorite: Bool) {
    guard let entityType = PendingLibraryChangeEntityType.of(entity) else { return }
    PendingLibraryChange.setFavorite(isFavorite, on: entity)
    record(entity: entity, entityType: entityType, kind: .favorite, isFavorite: isFavorite)
  }

  /// 0 removes the rating
  public func setRating(_ entity: AbstractLibraryEntity, rating: Int) {
    guard let entityType = PendingLibraryChangeEntityType.of(entity),
          rating >= 0, rating <= 5 else { return }
    entity.rating = rating
    record(entity: entity, entityType: entityType, kind: .rating, rating: rating)
  }

  private func record(
    entity: AbstractLibraryEntity,
    entityType: PendingLibraryChangeEntityType,
    kind: PendingLibraryChangeKind,
    isFavorite: Bool = false,
    rating: Int = 0
  ) {
    // the entity's context: the change is saved together with the entity
    let context = entity.managedObjectContext ?? storage.main.context
    let library = LibraryStorage(context: context)
    let accountInContext = Account(
      managedObject: context.object(with: account.managedObject.objectID) as! AccountMO
    )
    library.recordPendingLibraryChange(
      account: accountInContext,
      entityType: entityType,
      entityId: entity.id,
      kind: kind,
      isFavorite: isFavorite,
      rating: rating
    )
    library.saveContext()
    requestUpload()
  }

  // MARK: Upload

  /// The account's managers are started: the pending changes are uploaded from now on
  public func start() {
    isEnabled = true
    requestUpload()
  }

  public func stop() {
    isEnabled = false
    retryTask?.cancel()
    retryTask = nil
  }

  /// Uploads the pending changes if allowed (started, online mode, network), e.g. after going
  /// online or the network coming back
  public func requestUpload() {
    guard isUploadAllowed else { return }
    isUploadRequested = true
    guard !isActive else { return }
    isActive = true
    retryTask?.cancel()
    retryTask = nil
    uploadInBackground()
  }

  private func uploadInBackground() {
    Task { @MainActor in
      os_log("start", log: self.log, type: .info)
      let library = self.storage.main.library
      var isRetryNeeded = false
      rounds: while self.isUploadRequested, self.isUploadAllowed {
        self.isUploadRequested = false
        // failed in this round, tried again in the next one
        var failedChangeIds = [NSManagedObjectID]()
        while self.isUploadAllowed,
              let change = library.getFirstPendingLibraryChange(
                for: self.account,
                excluding: failedChangeIds
              ) {
          guard let entity = library.getEntity(of: change) else {
            // not in the library anymore
            library.deletePendingLibraryChange(change)
            library.saveContext()
            continue
          }
          let changeDate = change.changeDate
          do {
            try await self.upload(change: change, entity: entity)
            // a change made meanwhile replaced this one and is uploaded in this round too
            if change.managedObject.managedObjectContext != nil, change.changeDate == changeDate {
              // a server sync during the upload may have set the server's old value
              change.apply(to: entity)
              library.deletePendingLibraryChange(change)
            }
            library.saveContext()
          } catch {
            switch Self.failure(of: error) {
            case .changeRejected:
              self.eventLogger.report(
                topic: "Favorite/Rating Sync",
                error: error,
                displayPopup: true
              )
              // unless a change made meanwhile replaced it
              if change.changeDate == changeDate {
                library.deletePendingLibraryChange(change)
                library.saveContext()
              }
            case .changeFailed:
              isRetryNeeded = true
              failedChangeIds.append(change.managedObject.objectID)
              self.eventLogger.report(
                topic: "Favorite/Rating Sync",
                error: error,
                displayPopup: false
              )
            case .serverUnavailable:
              isRetryNeeded = true
              self.eventLogger.report(
                topic: "Favorite/Rating Sync",
                error: error,
                displayPopup: false
              )
              break rounds
            }
          }
        }
      }
      os_log("stopped", log: self.log, type: .info)
      self.isActive = false
      if isRetryNeeded {
        self.scheduleRetry()
      }
    }
  }

  /// A failed upload is tried again after the retry delay, e.g. the server was briefly down
  /// while the network stayed connected
  private func scheduleRetry() {
    guard isEnabled, retryTask == nil else { return }
    let delay = retryDelay
    retryTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: delay)
      guard let self, !Task.isCancelled else { return }
      retryTask = nil
      requestUpload()
    }
  }

  static func failure(of error: Error) -> UploadFailure {
    guard let responseError = error as? ResponseError else {
      // e.g. no connection, timeout, TLS
      return .serverUnavailable
    }
    if let subsonicError = responseError.asSubsonicError {
      switch subsonicError {
      case .requestedDataNotFound, .requiredParameterMissing, .trialPeriodForServerIsOver,
           .userIsNotAuthorized:
        return .changeRejected
      case .clientVersionToLow, .serverVerionToLow, .tokenAuthenticationNotSupported,
           .wrongUsernameOrPassword:
        return .serverUnavailable
      case .generic:
        return .changeFailed
      }
    }
    if let ampacheError = responseError.asAmpacheError {
      switch ampacheError {
      case .accessDenied, .badRequest, .depreciated, .failedAccessCheck, .missing, .notFound:
        return .changeRejected
      case .accessControlNotEnabled, .receivedInvalidHandshake:
        return .serverUnavailable
      case .empty:
        return .changeFailed
      }
    }
    // e.g. an HTML error page of a proxy instead of the server's XML
    return .changeFailed
  }

  private func upload(change: PendingLibraryChange, entity: AbstractLibraryEntity) async throws {
    switch (change.kind, change.entityType) {
    case (.favorite, .song):
      guard let song = (entity as? AbstractPlayable)?.asSong else { return }
      try await librarySyncer.setFavorite(song: song, isFavorite: change.isFavorite)
    case (.favorite, .album):
      guard let album = entity as? Album else { return }
      try await librarySyncer.setFavorite(album: album, isFavorite: change.isFavorite)
    case (.favorite, .artist):
      guard let artist = entity as? Artist else { return }
      try await librarySyncer.setFavorite(artist: artist, isFavorite: change.isFavorite)
    case (.rating, .song):
      guard let song = (entity as? AbstractPlayable)?.asSong else { return }
      try await librarySyncer.setRating(song: song, rating: change.rating)
    case (.rating, .album):
      guard let album = entity as? Album else { return }
      try await librarySyncer.setRating(album: album, rating: change.rating)
    case (.rating, .artist):
      guard let artist = entity as? Artist else { return }
      try await librarySyncer.setRating(artist: artist, rating: change.rating)
    case (_, .none), (.none, _):
      return
    }
  }
}

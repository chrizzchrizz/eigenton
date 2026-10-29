//
//  PlayQueueSyncer.swift
//  AmperfyKit
//
//  Created by Chrizz Gelbach on 28.10.26.
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

import CoreMedia
import Foundation
import os.log
import UIKit

// MARK: - PlayQueueSaveThrottle

/// Decides when the play queue is saved and when the server is asked whether another device took over.
struct PlayQueueSaveThrottle {
  /// While playing, the position is saved at most this often.
  static let periodicSaveInterval: TimeInterval = 30
  /// A smaller change of the position alone is not saved.
  static let positionToleranceInMs = 5000
  /// How often the server is asked whether another device saved its queue.
  static let takeoverCheckInterval: TimeInterval = 120
  /// After playback was started on this device, a queue saved by another device is ignored for this
  /// long, so the other device detects the takeover first and stops saving, instead of both stopping.
  static let takeoverGracePeriod: TimeInterval = 180

  private(set) var lastSaved: PlayQueueSnapshot?
  private(set) var lastSaveDate: Date?
  private var lastTakeoverCheckDate: Date?
  private var ignoreOtherDevicesUntil: Date?

  func isPeriodicSaveDue(now: Date) -> Bool {
    guard let lastSaveDate else { return true }
    return now.timeIntervalSince(lastSaveDate) >= Self.periodicSaveInterval
  }

  func isSaveNeeded(for snapshot: PlayQueueSnapshot) -> Bool {
    guard let lastSaved else { return true }
    return snapshot.songIds != lastSaved.songIds ||
      snapshot.currentIndex != lastSaved.currentIndex ||
      abs(snapshot.positionInMs - lastSaved.positionInMs) >= Self.positionToleranceInMs
  }

  mutating func didSave(_ snapshot: PlayQueueSnapshot, now: Date) {
    lastSaved = snapshot
    lastSaveDate = now
  }

  /// A failed or skipped save is retried with the next periodic save, not on every elapsed time
  /// change.
  mutating func didAttemptSave(now: Date) {
    lastSaveDate = now
  }

  /// True if the server should be asked now; marks the check as done.
  mutating func shouldCheckForTakeover(now: Date) -> Bool {
    if let ignoreOtherDevicesUntil, now < ignoreOtherDevicesUntil { return false }
    if let lastTakeoverCheckDate,
       now.timeIntervalSince(lastTakeoverCheckDate) < Self.takeoverCheckInterval {
      return false
    }
    lastTakeoverCheckDate = now
    return true
  }

  /// Playback was started on this device by the user.
  mutating func didStartLocally(now: Date) {
    ignoreOtherDevicesUntil = now.addingTimeInterval(Self.takeoverGracePeriod)
    lastSaved = nil
  }

  /// The queue on the server was saved by another device if its client name isn't one this device
  /// used, the device name may have been changed since its last save.
  /// Devices with the same name, e.g. two iPhones without a device name set, can't be told apart.
  static func isSavedByOtherDevice(
    _ info: ServerPlayQueueInfo,
    ownClientNames: Set<String>
  )
    -> Bool {
    guard let changedBy = info.changedBy, !changedBy.isEmpty else { return false }
    return !ownClientNames.contains(changedBy)
  }
}

// MARK: - PlayQueueSyncer

/// Saves the music play queue of the account to the server, so another device can continue
/// playback, and continues playback of the queue another device saved.
///
/// Conflicts: the last save wins. Once another device saved its queue, this device stops saving
/// until playback is started here again, so a device that keeps playing after the takeover doesn't
/// overwrite the queue of the device that took over.
@MainActor
public class PlayQueueSyncer {
  private static let songChangeSaveDelay: Duration = .seconds(2)
  private static let queueChangeSaveDelay: Duration = .seconds(5)

  /// iOS only reveals the device type, the user assigned name needs an entitlement.
  public static var defaultDeviceName: String {
    #if targetEnvironment(macCatalyst)
      return "Mac"
    #else
      return UIDevice.current.model
    #endif
  }

  /// Different names let the server tell the devices apart, also two of the same type.
  static func clientName(deviceName: String) -> String {
    let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    return "Amperfy (\(name.isEmpty ? defaultDeviceName : name))"
  }

  private var clientName: String {
    Self.clientName(deviceName: storage.settings.user.playQueueDeviceName)
  }

  private let log = OSLog(subsystem: "Amperfy", category: "PlayQueueSyncer")
  private let player: PlayerFacade
  private let networkMonitor: NetworkMonitorFacade
  private let account: Account
  private let storage: PersistentStorage
  private let librarySyncer: LibrarySyncer
  private let eventLogger: EventLogger

  private var throttle = PlayQueueSaveThrottle()
  private var isSupported: Bool?
  /// Another device saved its queue after this one, saving is stopped until playback starts here.
  private var isTakenOverByOtherDevice = false
  private var isPlaybackInterrupted = true
  /// Client names of this device's saves in this session.
  private var savedClientNames = Set<String>()
  private var scheduledSave: Task<(), Never>?
  private var runningSave: Task<(), Never>?
  private var isAnotherSaveRequested = false

  init(
    player: PlayerFacade,
    networkMonitor: NetworkMonitorFacade,
    account: Account,
    storage: PersistentStorage,
    librarySyncer: LibrarySyncer,
    eventLogger: EventLogger
  ) {
    self.player = player
    self.networkMonitor = networkMonitor
    self.account = account
    self.storage = storage
    self.librarySyncer = librarySyncer
    self.eventLogger = eventLogger
  }

  private var isSyncActive: Bool {
    storage.settings.user.isPlayQueueSyncEnabled && storage.settings.user.isOnlineMode &&
      networkMonitor.isConnectedToNetwork
  }

  /// Throws if the server couldn't be asked whether it stores a play queue.
  public func isContinuePlaybackAvailable() async throws -> Bool {
    guard storage.settings.user.isPlayQueueSyncEnabled else { return false }
    return try await isServerSupportingSync()
  }

  /// Only an answer of the server is kept, after an error it is asked again.
  private func isServerSupportingSync() async throws -> Bool {
    if let isSupported { return isSupported }
    let supported = try await librarySyncer.isPlayQueueSyncSupported()
    isSupported = supported
    return supported
  }

  // MARK: Save

  /// Saves the queue right away, e.g. before the app moves to the background; returns once the
  /// latest state is saved, also if a save was running already.
  public func saveNow() async {
    scheduledSave?.cancel()
    scheduledSave = nil
    await save()
  }

  private func scheduleSave(after delay: Duration) {
    guard isSyncActive, !isTakenOverByOtherDevice, isSupported != false else { return }
    scheduledSave?.cancel()
    scheduledSave = Task { @MainActor [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self else { return }
      scheduledSave = nil
      await save()
    }
  }

  private func save() async {
    guard isSyncActive, !isTakenOverByOtherDevice else { return }
    if let runningSave {
      // the running save repeats with the latest state
      isAnotherSaveRequested = true
      await runningSave.value
      return
    }
    let saveTask = Task { @MainActor in
      repeat {
        isAnotherSaveRequested = false
        await saveIfNeeded()
      } while isAnotherSaveRequested && !isTakenOverByOtherDevice
    }
    runningSave = saveTask
    await saveTask.value
    runningSave = nil
  }

  private func saveIfNeeded() async {
    // the cheap checks first, every account's syncer is asked to save
    guard let snapshot = createSnapshot(), throttle.isSaveNeeded(for: snapshot) else {
      throttle.didAttemptSave(now: Date())
      return
    }
    do {
      guard try await isServerSupportingSync() else { return }
      if throttle.shouldCheckForTakeover(now: Date()),
         let info = try await librarySyncer.requestPlayQueueInfo(),
         PlayQueueSaveThrottle.isSavedByOtherDevice(
           info,
           ownClientNames: savedClientNames.union([clientName])
         ) {
        os_log(
          "Play queue saved by %s, stop saving until playback starts here",
          log: log,
          type: .info,
          info.changedBy ?? "-"
        )
        isTakenOverByOtherDevice = true
        return
      }
      let clientName = clientName
      try await librarySyncer.savePlayQueue(snapshot: snapshot, clientName: clientName)
      savedClientNames.insert(clientName)
      throttle.didSave(snapshot, now: Date())
    } catch {
      throttle.didAttemptSave(now: Date())
      eventLogger.report(topic: "Play Queue Sync", error: error, displayPopup: false)
    }
  }

  private func createSnapshot() -> PlayQueueSnapshot? {
    guard player.playerMode == .music else { return nil }
    return Self.createSnapshot(
      account: account,
      current: player.currentMusicItem,
      prev: player.getAllPrevQueueItems(),
      user: player.getAllUserQueueItems(),
      next: player.getAllNextQueueItems(),
      elapsedTime: player.elapsedTime
    )
  }

  /// Songs of the account in playback order, radios and songs of other accounts are left out;
  /// nil if the current item isn't a song of the account.
  static func createSnapshot(
    account: Account,
    current: AbstractPlayable?,
    prev: [AbstractPlayable],
    user: [AbstractPlayable],
    next: [AbstractPlayable],
    elapsedTime: Double
  )
    -> PlayQueueSnapshot? {
    guard let currentSong = current?.asSong, currentSong.account == account else { return nil }
    let accountSongIds: ([AbstractPlayable]) -> [String] = { playables in
      playables.compactMap { $0.asSong }.filter { $0.account == account }.map { $0.id }
    }
    let prevIds = accountSongIds(prev)
    return PlayQueueSnapshot(
      songIds: prevIds + [currentSong.id] + accountSongIds(user) + accountSongIds(next),
      currentIndex: prevIds.count,
      positionInMs: PlayQueueSnapshot.milliseconds(fromSeconds: elapsedTime)
    )
  }

  /// The user started playback on this device, it is the active one again.
  private func didStartLocally() {
    isTakenOverByOtherDevice = false
    throttle.didStartLocally(now: Date())
  }

  // MARK: Continue Playback

  /// The queue another device saved; nil if the server has none.
  public func requestServerPlayQueue() async throws -> ServerPlayQueue? {
    try await librarySyncer.requestPlayQueue()
  }

  /// The saved queue is the one of this device, there is nothing to continue.
  public func isSavedByThisDevice(_ playQueue: ServerPlayQueue) -> Bool {
    guard let changedBy = playQueue.info.changedBy, !changedBy.isEmpty else { return false }
    return savedClientNames.union([clientName]).contains(changedBy)
  }

  /// Replaces the player's queue, including the user queue, with the saved one without starting
  /// playback; play continues it from the saved position.
  public func continuePlayback(of playQueue: ServerPlayQueue) {
    guard !playQueue.songs.isEmpty else { return }
    os_log(
      "Sync the play queue of %s: %i songs",
      log: log,
      type: .info,
      playQueue.info.changedBy ?? "-",
      playQueue.songs.count
    )
    didStartLocally()
    // the saved queue already contains the user queue of the device that saved it
    player.clearUserQueue()
    player.load(
      context: PlayContext(
        name: "Synced Play Queue",
        index: playQueue.startIndex,
        playables: playQueue.songs
      ),
      startSecond: playQueue.startPositionInSeconds
    )
    // the stop schedules a save, the position isn't applied before playback; the save after
    // the user started playback has it
    scheduledSave?.cancel()
    scheduledSave = nil
  }
}

// MARK: MusicPlayable

extension PlayQueueSyncer: MusicPlayable {
  public func didStartPlayingFromBeginning() {
    scheduleSave(after: Self.songChangeSaveDelay)
  }

  public func didStartPlaying() {
    // also called for every song that follows, only a start after a pause or stop is the user's
    if isPlaybackInterrupted {
      isPlaybackInterrupted = false
      didStartLocally()
      scheduleSave(after: Self.songChangeSaveDelay)
    }
  }

  public func didPause() {
    isPlaybackInterrupted = true
    scheduleSave(after: .zero)
  }

  public func didStopPlaying() {
    isPlaybackInterrupted = true
    scheduleSave(after: .zero)
  }

  public func didElapsedTimeChange() {
    // called several times per second, cheap checks first
    guard player.isPlaying, scheduledSave == nil, runningSave == nil,
          throttle.isPeriodicSaveDue(now: Date()), player.playerMode == .music,
          player.currentMusicItem?.asSong?.account == account
    else { return }
    scheduleSave(after: .zero)
  }

  public func didPlaylistChange() {
    scheduleSave(after: Self.queueChangeSaveDelay)
  }

  public func didArtworkChange() {}
  public func didShuffleChange() {}
  public func didRepeatChange() {}
  public func didPlaybackRateChange() {}
}

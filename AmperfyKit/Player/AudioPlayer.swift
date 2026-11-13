//
//  AudioPlayer.swift
//  AmperfyKit
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

import AVFoundation
import Foundation
import MediaPlayer
import os.log

// MARK: - WeakMusicPlayable

final class WeakMusicPlayable {
  weak var value: MusicPlayable?
  init(_ value: MusicPlayable) {
    self.value = value
  }
}

// MARK: - AudioPlayer

@MainActor
public class AudioPlayer: NSObject, BackendAudioPlayerNotifiable {
  public static let replayInsteadPlayPreviousTimeInSec = 5.0
  static let progressTimeStartThreshold: Double = 15.0
  static let progressTimeEndThreshold: Double = 15.0
  /// Position and duration are saved at this interval while playing, otherwise only on pause, stop,
  /// item change and when the app goes to the background. Each save updates every list showing
  /// the playable, so not on every elapsed time update.
  static let playInformationSaveInterval: TimeInterval = 15.0

  var currentlyPlaying: AbstractPlayable? {
    queueHandler.currentlyPlaying
  }

  var currentMusicItem: AbstractPlayable? {
    queueHandler.currentMusicItem
  }

  var currentPodcastItem: AbstractPlayable? {
    queueHandler.currentPodcastItem
  }

  var isShouldPauseAfterFinishedPlaying = false
  /// The playable whose position the backend player reports. Nil while the next item is prepared:
  /// the backend may still play the previous item meanwhile (e.g. while a stream URL is requested).
  private var playableInPlayer: AbstractPlayable? {
    didSet { lastObservedPosition = nil }
  }

  private var lastPlayInformationSaveDate: Date?
  /// Position and duration of playableInPlayer at the last elapsed time update
  private var lastObservedPosition: (elapsed: Double, duration: Double)?

  /// Where to resume after a playback error tore down the player. Only applies to the
  /// playable it was captured for and is used at most once, so it can't leak into a
  /// different item if the recovery fails or the user plays something else.
  private var errorResumePoint: (playable: AbstractPlayable, time: Double)?
  /// Automatic recoveries of the playable that failed last and the furthest position it failed
  /// at. Reset once playback got clearly past that position or the user acted.
  private var errorRecovery: (
    playable: AbstractPlayable,
    count: Int,
    position: Double,
    hadDataError: Bool
  )?
  private var errorRecoveryTask: Task<(), Never>?
  /// Playables skipped in a row because of data errors, so a queue that only fails can't loop
  private var consecutiveErrorSkipCount = 0
  /// The item in the player is an automatic retry: not a new play (count, scrobble)
  private var isRetryInPlayer = false
  /// An error tore down the player and the playable wasn't inserted again since
  private var isPlayerTornDownByError = false
  /// Waiting time before each retry after a connection error, to outlast a short network drop
  var errorRecoveryDelays: [TimeInterval] = [1.0, 3.0, 6.0]
  static let maxErrorRecoveryCount = 3
  static let maxConsecutiveErrorSkipCount = 3
  static let errorFreePlaybackToResetRecovery: Double = 10.0
  var autoplayCB: (@MainActor (Song) async throws -> [Song])?

  private var playerStatus: PlayerStatusPersistent
  private var queueHandler: PlayQueueHandler
  private let backendAudioPlayer: BackendAudioPlayer
  private let settings: AmperfySettings
  private let userStatistics: UserStatistics
  private var notifierList: [WeakMusicPlayable] = []
  /// Position to seek to once the playable is prepared, instead of its last stopped play time.
  private var startPosition: (playable: AbstractPlayable, second: Double)?
  public private(set) var currentRadioNowPlaying: RadioNowPlayingInfo?
  private var lastRadioStreamTitle: String?

  init(
    coreData: PlayerStatusPersistent,
    queueHandler: PlayQueueHandler,
    backendAudioPlayer: BackendAudioPlayer,
    settings: AmperfySettings,
    userStatistics: UserStatistics
  ) {
    self.playerStatus = coreData
    self.queueHandler = queueHandler
    self.backendAudioPlayer = backendAudioPlayer
    self.settings = settings
    self.userStatistics = userStatistics
    super.init()
    self.backendAudioPlayer.responder = self
    self.backendAudioPlayer.nextPlayablePreloadCB = { () in
      guard !self.isShouldPauseAfterFinishedPlaying else { return nil }
      guard self.playerStatus.repeatMode != .single else { return nil }
      guard let nextPlayerIndex = self.nextPlayerIndex else { return nil }
      return self.queueHandler.getPlayable(at: nextPlayerIndex)
    }
  }

  private func shouldCurrentItemReplayedInsteadOfPrevious() -> Bool {
    if let currentlyPlaying = currentlyPlaying,
       currentlyPlaying.isRadio {
      return false
    }
    if !backendAudioPlayer.canBeContinued {
      return false
    }
    return backendAudioPlayer.elapsedTime >= Self.replayInsteadPlayPreviousTimeInSec
  }

  private func replayCurrentItem() {
    os_log(.debug, "Replay")
    if let currentPlayable = currentlyPlaying {
      insertIntoPlayer(playable: currentPlayable)
    }
    notifyItemStartedPlayingFromBeginning()
  }

  private func insertIntoPlayer(playable: AbstractPlayable, isRetry: Bool = false) {
    isRetryInPlayer = isRetry
    isPlayerTornDownByError = false
    // a retry keeps the saved position and isn't a new play
    if !isRetry {
      userStatistics.playedItem(
        repeatMode: playerStatus.repeatMode,
        isShuffle: playerStatus.isShuffle
      )
      playable.countPlayed()
      if let playableInPlayer, playableInPlayer == playable {
        // replay: start from the beginning, a saved position would be resumed
        playable.playProgress = 0
      } else {
        // the position of the previous playable is lost once the backend player switches
        savePlayInformation()
      }
    }
    playableInPlayer = nil
    backendAudioPlayer.requestToPlay(
      playable: playable,
      playbackRate: playerStatus.playbackRate,
      autoStartPlayback: !settings.user.isPlaybackStartOnlyOnPlay
    )
  }

  // BackendAudioPlayerNotifiable
  func notifyItemPreparationFinished() {
    playableInPlayer = currentlyPlaying
    lastPlayInformationSaveDate = Date()
    handleRadioStartIfNeeded()
    let isRetry = isRetryInPlayer
    isRetryInPlayer = false
    notifyItemStartedPlayingFromBeginning(isNotifyingListeners: !isRetry)
    notifyItemStartedPlaying()
  }

  // BackendAudioPlayerNotifiable
  func didItemFinishedPlaying() {
    // ended without an error, also before a replay with repeat single
    resetErrorRecovery()
    if let playableInPlayer, !playableInPlayer.isRadio {
      // The backend may already report the next (preloaded) item, use the last observed position.
      // Played to the end: start from the beginning next time. Ended early (e.g. connection loss):
      // keep the position.
      if let lastObservedPosition, lastObservedPosition.duration > 0,
         lastObservedPosition.elapsed > Self.progressTimeStartThreshold,
         lastObservedPosition.elapsed < lastObservedPosition.duration - Self
         .progressTimeEndThreshold {
        playableInPlayer.playProgress = Int(lastObservedPosition.elapsed)
      } else {
        playableInPlayer.playProgress = 0
      }
    }
    playableInPlayer = nil
    if isShouldPauseAfterFinishedPlaying {
      isShouldPauseAfterFinishedPlaying = false
      pause()
    } else if playerStatus
      .repeatMode == .single ||
      (
        // repeat mode all and only one song is in player -> repeat
        playerStatus.repeatMode == .all && queueHandler.prevQueueCount == 0 && queueHandler
          .userQueueCount == 0 && queueHandler
          .nextQueueCount == 0
      ) {
      replayCurrentItem()
    } else if !settings.user.isPlaybackStartOnlyOnPlay {
      playNext()
    }
  }

  /// Called by the backend player for every playback error, after it tore down the player.
  /// Retries a few times. Then a playable whose data can't be decoded is skipped; on other
  /// errors the player stays paused and play resumes at the error position.
  func recoverFromPlaybackError() {
    guard let playable = currentlyPlaying else { return }
    let previous = errorRecovery?.playable == playable ? errorRecovery : nil
    let count = (previous?.count ?? 0) + 1
    // a report from the restarted player has no position yet, keep the one of the first report
    let position = max(previous?.position ?? 0, backendAudioPlayer.elapsedTimeBeforeErrorOccurred)
    let isDataError = backendAudioPlayer.isDataErrorOccurred
    let hadDataError = (previous?.hadDataError ?? false) || isDataError
    errorRecovery = (
      playable: playable,
      count: count,
      position: position,
      hadDataError: hadDataError
    )
    let delay: TimeInterval
    if count > Self.maxErrorRecoveryCount || isDataError || errorRecoveryDelays.isEmpty {
      delay = 0
    } else {
      delay = errorRecoveryDelays[min(count, errorRecoveryDelays.count) - 1]
    }
    errorRecoveryTask?.cancel()
    // not within the backend's error handling, a new insert may report an error itself
    errorRecoveryTask = Task { @MainActor [weak self] in
      if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
      // paused, stopped or replaced by the user or a newer error meanwhile
      guard let self, !Task.isCancelled, currentlyPlaying == playable,
            backendAudioPlayer.isErrorOccurred
      else { return }
      errorRecoveryTask = nil
      if count <= Self.maxErrorRecoveryCount {
        continueOrInsertCurrent(isRetry: true)
      } else if hadDataError, !playable.isRadio, let nextPlayerIndex,
                consecutiveErrorSkipCount < Self.maxConsecutiveErrorSkipCount {
        os_log(.default, "Skip the playable after %d failed recoveries", Self.maxErrorRecoveryCount)
        consecutiveErrorSkipCount += 1
        // start it from the beginning next time, the torn down player has no position to save
        errorResumePoint = nil
        playable.playProgress = 0
        playableInPlayer = nil
        // not through playNext, which counts as the user's action
        guard let next = queueHandler.markAndGetPlayableAsPlaying(at: nextPlayerIndex)
        else { return }
        insertIntoPlayer(playable: next)
      } else {
        os_log(.default, "Stop recovering after %d failed recoveries", Self.maxErrorRecoveryCount)
        notifyItemPaused()
      }
    }
  }

  private func resetErrorRecovery(isCancellingRetry: Bool = true) {
    errorRecovery = nil
    consecutiveErrorSkipCount = 0
    if isCancellingRetry {
      cancelErrorRecoveryTask()
    }
  }

  private func cancelErrorRecoveryTask() {
    errorRecoveryTask?.cancel()
    errorRecoveryTask = nil
  }

  /// The user chose a new position: a pending retry and the next start resume there
  func userDidSeek(toSecond second: Double) {
    resetErrorRecovery(isCancellingRetry: false)
    guard let playable = currentlyPlaying else { return }
    // a torn down player can't seek, the seek is applied when it is inserted again
    if isPlayerTornDownByError {
      errorResumePoint = (playable: playable, time: second)
    }
  }

  func play() {
    resetErrorRecovery()
    // playing on after an error continues the same listen
    continueOrInsertCurrent(isRetry: isPlayerTornDownByError)
  }

  private func continueOrInsertCurrent(isRetry: Bool = false) {
    if !backendAudioPlayer.canBeContinued {
      if let currentPlayable = currentlyPlaying {
        insertIntoPlayer(playable: currentPlayable, isRetry: isRetry)
      }
    } else {
      backendAudioPlayer.continuePlay()
      notifyItemStartedPlaying()
    }
  }

  public func play(context: PlayContext) {
    guard context.getActivePlayable() != nil else { return }
    resetErrorRecovery()
    guard let playable = replaceActiveQueue(with: context) else {
      stop()
      return
    }
    insertIntoPlayer(playable: playable)
  }

  /// Replaces the queue like `play(context:)` but leaves the player stopped at the context's
  /// active playable; `play()` starts it.
  public func load(context: PlayContext) {
    guard context.getActivePlayable() != nil else { return }
    resetErrorRecovery()
    guard replaceActiveQueue(with: context) != nil else {
      stop()
      return
    }
    // a paused previous item would otherwise be continued by play()
    stopButRemainIndex()
  }

  /// Replaces the active queue with the context and marks its active playable as playing.
  private func replaceActiveQueue(with context: PlayContext) -> AbstractPlayable? {
    guard let activePlayable = context.getActivePlayable() else { return nil }
    let topUserQueueItem = queueHandler.getUserQueueItem(at: 0)
    let wasUserQueuePlaying = queueHandler.isUserQueuePlaying
    queueHandler.clearActiveQueue()
    queueHandler.appendActiveQueue(playables: context.playables)
    if context.type == .music {
      queueHandler.setContextName(context.name)
    }

    if queueHandler.isUserQueuePlaying {
      let playable = queueHandler.markAndGetPlayableAsPlaying(
        at: PlayerIndex(queueType: .next, index: context.index)
      )
      if !wasUserQueuePlaying, let topUserQueueItem = topUserQueueItem {
        queueHandler.insertUserQueue(playables: [topUserQueueItem])
      }
      return playable
    } else if context.index == 0 {
      return activePlayable
    } else {
      return queueHandler.markAndGetPlayableAsPlaying(
        at: PlayerIndex(queueType: .next, index: context.index - 1)
      )
    }
  }

  func play(playerIndex: PlayerIndex) {
    resetErrorRecovery()
    guard let playable = queueHandler.markAndGetPlayableAsPlaying(at: playerIndex) else {
      stop()
      return
    }
    insertIntoPlayer(playable: playable)
  }

  func playPreviousOrReplay() {
    resetErrorRecovery()
    if shouldCurrentItemReplayedInsteadOfPrevious() {
      replayCurrentItem()
    } else {
      playPrevious()
    }
  }

  // BackendAudioPlayerNotifiable
  func playPrevious() {
    resetErrorRecovery()
    if queueHandler.prevQueueCount > 0 {
      play(playerIndex: PlayerIndex(queueType: .prev, index: queueHandler.prevQueueCount - 1))
    } else if playerStatus.repeatMode == .all, queueHandler.nextQueueCount > 0 {
      play(playerIndex: PlayerIndex(queueType: .next, index: queueHandler.nextQueueCount - 1))
    } else {
      replayCurrentItem()
    }
  }

  // BackendAudioPlayerNotifiable
  func playNext() {
    resetErrorRecovery()
    if let nextPlayerIndex = nextPlayerIndex {
      play(playerIndex: nextPlayerIndex)
    } else if settings.user.isAutoplayEnabled,
              let song = currentlyPlaying?.asSong,
              let cb = autoplayCB,
              !backendAudioPlayer.isOfflineMode {
      Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          let similarSongs = try await cb(song)
          guard !similarSongs.isEmpty else { stop(); return }
          queueHandler.appendContextQueue(playables: similarSongs)
          play(playerIndex: PlayerIndex(queueType: .next, index: 0))
        } catch {
          stop()
        }
      }
    } else {
      stop()
    }
  }

  private var nextPlayerIndex: PlayerIndex? {
    if queueHandler.userQueueCount > 0 {
      return PlayerIndex(queueType: .user, index: 0)
    } else if queueHandler.nextQueueCount > 0 {
      return PlayerIndex(queueType: .next, index: 0)
    } else if playerStatus.repeatMode == .all, queueHandler.prevQueueCount > 0 {
      return PlayerIndex(queueType: .prev, index: 0)
    } else {
      return nil
    }
  }

  func pause() {
    // a pending retry would start playback again
    cancelErrorRecoveryTask()
    if let currentlyPlaying = currentlyPlaying,
       currentlyPlaying.isRadio {
      stopButRemainIndex()
    } else {
      savePlayInformation()
      backendAudioPlayer.pause()
      notifyItemPaused()
    }
  }

  // BackendAudioPlayerNotifiable
  func stop() {
    resetErrorRecovery()
    isPlayerTornDownByError = false
    savePlayInformation()
    playableInPlayer = nil
    backendAudioPlayer.stop()
    playerStatus.stop()
    notifyPlayerStopped()
  }

  func stopButRemainIndex() {
    cancelErrorRecoveryTask()
    isPlayerTornDownByError = false
    savePlayInformation()
    playableInPlayer = nil
    backendAudioPlayer.stop()
    notifyPlayerStopped()
  }

  func togglePlayPause() {
    if backendAudioPlayer.isPlaying {
      pause()
    } else {
      play()
    }
  }

  func setStartPosition(second: Double, of playable: AbstractPlayable) {
    startPosition = (playable, second)
  }

  private func seekToLastStoppedPlayTime() {
    // nothing is in the player, keep the positions for the next attempt
    guard !backendAudioPlayer.isPreparationFailed else { return }
    if let startPosition {
      self.startPosition = nil
      // the user may have skipped before the playable was prepared
      if let playable = currentlyPlaying, playable == startPosition.playable {
        if startPosition.second > 0 {
          backendAudioPlayer.seek(toSecond: startPosition.second)
        }
        return
      }
    }

    // An error tears the player down and re-inserts the current playable, which
    // makes it start from the beginning. Resume from the position captured when
    // the error occurred instead. The persisted `playProgress` cannot be used
    // for this: `savePlayInformation` deliberately resets it to zero within
    // `progressTimeEndThreshold` of the end of the track, which is exactly where
    // a stream error is most likely to happen.
    if let resumePoint = errorResumePoint {
      errorResumePoint = nil
      if resumePoint.playable == currentlyPlaying {
        backendAudioPlayer.seek(toSecond: resumePoint.time)
        return
      }
    }

    if let playable = currentlyPlaying,
       playable.playProgress > 0,
       playable
       .isPodcastEpisode ||
       (playable.isSong && settings.user.isPlayerSongPlaybackResumeEnabled) {
      backendAudioPlayer.seek(toSecond: Double(playable.playProgress))
    }
  }

  // BackendAudioPlayerNotifiable
  func didElapsedTimeChange() {
    notifyElapsedTimeChanged()
    if playableInPlayer != nil {
      lastObservedPosition = (backendAudioPlayer.elapsedTime, backendAudioPlayer.duration)
    }
    // played clearly past the error, or another playable plays: errors are no longer in a row
    if let errorRecovery, playableInPlayer != nil, backendAudioPlayer.isPlaying,
       !backendAudioPlayer.isErrorOccurred {
      let errorPosition = errorRecovery.playable == playableInPlayer ? errorRecovery.position : 0
      if backendAudioPlayer.elapsedTime >= errorPosition + Self.errorFreePlaybackToResetRecovery {
        resetErrorRecovery()
      }
    }
    if let lastPlayInformationSaveDate,
       Date().timeIntervalSince(lastPlayInformationSaveDate) < Self.playInformationSaveInterval {
      return
    }
    savePlayInformation()
  }

  // BackendAudioPlayerNotifiable
  func didLyricsTimeChange(time: CMTime) {
    notifyLyricsTimeChanged(time: time)
  }

  // BackendAudioPlayerNotifiable
  func didReadStreamMetadata(_ metadata: [String: String]) {
    guard let radio = currentlyPlaying?.asRadio else { return }
    updateRadioNowPlaying(from: metadata, radio: radio)
  }

  /// Saves position and duration of the playable in the player, see playInformationSaveInterval
  func savePlayInformation() {
    lastPlayInformationSaveDate = Date()
    guard let playable = playableInPlayer else { return }
    let playDuration = backendAudioPlayer.duration
    let playProgress = backendAudioPlayer.elapsedTime
    if playDuration != 0.0, playProgress != 0.0 {
      playable.playDuration = Int(playDuration)
      if playProgress > Self.progressTimeStartThreshold,
         playProgress < (playDuration - Self.progressTimeEndThreshold) {
        playable.playProgress = Int(playProgress)
      } else {
        playable.playProgress = 0
      }
    }
  }

  func addNotifier(notifier: MusicPlayable) {
    notifierList.append(WeakMusicPlayable(notifier))
  }

  func removeAllNotifier() {
    notifierList.removeAll()
  }

  func notifyItemStartedPlayingFromBeginning(isNotifyingListeners: Bool = true) {
    if isNotifyingListeners {
      notifierList = notifierList.filter { $0.value != nil }
      for notifier in notifierList {
        notifier.value?.didStartPlayingFromBeginning()
      }
    }
    seekToLastStoppedPlayTime()
  }

  func notifyItemStartedPlaying() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didStartPlaying()
    }
  }

  // BackendAudioPlayerNotifiable
  func notifyErrorOccurred(error: Error) {
    // the backend tore down the player, or the preparation left nothing in it
    isPlayerTornDownByError = true
    // Radios are live streams and can't be seeked, they just reconnect.
    // A failed preparation reports no position, a pending resume point stays for the next attempt.
    let resumeTime = backendAudioPlayer.elapsedTimeBeforeErrorOccurred
    if let playable = currentlyPlaying, !playable.isRadio, resumeTime > 0,
       !backendAudioPlayer.isPreparationFailed {
      errorResumePoint = (playable: playable, time: resumeTime)
    }
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.errorOccurred(error: error)
    }
  }

  func notifyItemPaused() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didPause()
    }
  }

  func notifyPlayerStopped() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didStopPlaying()
    }
  }

  func notifyArtworkChanged() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didArtworkChange()
    }
  }

  func notifyElapsedTimeChanged() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didElapsedTimeChange()
    }
  }

  func notifyLyricsTimeChanged(time: CMTime) {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didLyricsTimeChange(time: time)
    }
  }

  func notifyPlaylistUpdated() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didPlaylistChange()
    }
  }

  func notifyNowPlayingInfoChanged() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didNowPlayingInfoChange()
    }
  }

  func notifyShuffleUpdated() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didShuffleChange()
    }
  }

  func notifyRepeatUpdated() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didRepeatChange()
    }
  }

  func notifyPlaybackRateUpdated() {
    notifierList = notifierList.filter { $0.value != nil }
    for notifier in notifierList {
      notifier.value?.didPlaybackRateChange()
    }
  }

  private func handleRadioStartIfNeeded() {
    guard currentlyPlaying?.asRadio != nil else {
      if currentRadioNowPlaying != nil {
        currentRadioNowPlaying = nil
        lastRadioStreamTitle = nil
        notifyNowPlayingInfoChanged()
      }
      return
    }

    currentRadioNowPlaying = nil
    lastRadioStreamTitle = nil
    notifyNowPlayingInfoChanged()
  }

  private func updateRadioNowPlaying(from metadata: [String: String], radio: Radio) {
    guard let currentRadio = currentlyPlaying?.asRadio,
          currentRadio.managedObject == radio.managedObject else { return }
    let streamTitleKey = metadata.keys.first { $0.lowercased() == "streamtitle" }
    guard let streamTitleKey,
          let rawStreamTitle = metadata[streamTitleKey]
    else { return }
    let streamTitle = rawStreamTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !streamTitle.isEmpty else { return }
    guard streamTitle != lastRadioStreamTitle else { return }

    let parsedInfo = parseStreamTitle(streamTitle)
    guard let parsedInfo, !parsedInfo.isEmpty else { return }

    lastRadioStreamTitle = streamTitle
    currentRadioNowPlaying = parsedInfo
    notifyNowPlayingInfoChanged()
  }

  private func parseStreamTitle(_ streamTitle: String) -> RadioNowPlayingInfo? {
    let cleaned = streamTitle.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    let parts = cleaned.components(separatedBy: " - ")
    if parts.count >= 2 {
      let artist = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let title = parts.dropFirst().joined(separator: " - ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return RadioNowPlayingInfo(title: title, artist: artist)
    }
    return RadioNowPlayingInfo(title: cleaned, artist: "")
  }
}

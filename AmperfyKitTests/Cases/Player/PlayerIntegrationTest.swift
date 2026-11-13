//
//  PlayerIntegrationTest.swift
//  AmperfyKitTests
//
//  Created by Chrizz Gelbach on 13.11.26.
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

@testable import AmperfyKit
import XCTest

// MARK: - RecordingMusicPlayable

@MainActor
final class RecordingMusicPlayable: MusicPlayable {
  /// Calls of the error recovery, one per reported playback error
  private(set) var recoverCount = 0
  private(set) var log = [String]()
  private let start = Date()

  func record(_ event: String) {
    log.append(String(format: "%6.2f %@", Date().timeIntervalSince(start), event))
  }

  func didStartPlayingFromBeginning() { record("startedFromBeginning") }
  func didStartPlaying() { record("started") }
  func didPause() { record("paused") }
  func didStopPlaying() { record("stopped") }
  func didElapsedTimeChange() {}
  func didPlaylistChange() {}
  func didArtworkChange() {}
  func didShuffleChange() {}
  func didRepeatChange() {}
  func recover(isDataError: Bool) {
    recoverCount += 1
    record("recover (data error: \(isDataError))")
  }
}

// MARK: - PlayerIntegrationTest

/// Plays real streams from a local HTTP server through AudioStreaming and the whole player stack.
///
/// The tests take several seconds each and need audio output, so they only run on request:
/// `TEST_RUNNER_AMPERFY_INTEGRATION_TESTS=1 xcodebuild … test -only-testing:AmperfyKitTests/PlayerIntegrationTest`
@MainActor
final class PlayerIntegrationTest: XCTestCase {
  static let songSeconds = 20.0
  static let sampleRate = 22050
  /// Bytes per second of audio, the server is throttled relative to it
  static let audioByteRate = sampleRate * 2
  static let songData = LocalAudioServer.makeWav(seconds: songSeconds, sampleRate: sampleRate)
  /// The first error and the error of every retry
  static let errorCountUntilGivingUp = 1 + AudioPlayer.maxErrorRecoveryCount

  var cdHelper: CoreDataHelper!
  var library: LibraryStorage!
  var account: Account!
  var storage: PersistentStorage!
  var backendApi: MOCK_BackendApi!
  var backendPlayer: BackendAudioPlayer!
  var musicPlayer: AmperfyKit.AudioPlayer!
  var player: AmperfyKit.PlayerFacade!
  var recorder: RecordingMusicPlayable!
  var server: LocalAudioServer!
  var requestLogStart = Date()

  override func setUp() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["AMPERFY_INTEGRATION_TESTS"] == "1",
      "Set TEST_RUNNER_AMPERFY_INTEGRATION_TESTS=1 to run the player integration tests"
    )
    server = LocalAudioServer()
    try await server.start()

    cdHelper = CoreDataHelper()
    library = cdHelper.createSeededStorage()
    account = library.getAccount(info: TestAccountInfo.create1())
    storage = PersistentStorage(coreDataManager: MOCK_CoreDataManager(
      persistentContainer: cdHelper.persistentContainer
    ))
    let eventLogger = EventLogger(storage: storage)
    let userStatistics = library.getUserStatistics(appVersion: "")
    backendApi = MOCK_BackendApi()
    let server = server!
    backendApi.streamUrlProvider = { info in server.url(path: "/\(info.id).wav") }
    backendPlayer = BackendAudioPlayer(
      createAudioStreamingPlayerCB: {
        AudioStreamingPlayer(configuration: AudioStreamingPlayer.configuration)
      },
      audioSessionHandler: AudioSessionHandler(),
      eventLogger: eventLogger,
      getBackendApiCB: { [unowned self] _ in backendApi },
      networkMonitor: MOCK_NetworkMonitor(),
      cacheProxy: library,
      userStatistics: userStatistics
    )
    let playerData = library.getPlayerData()
    let queueHandler = PlayQueueHandler(playerData: playerData)
    musicPlayer = AudioPlayer(
      coreData: playerData,
      queueHandler: queueHandler,
      backendAudioPlayer: backendPlayer,
      settings: storage.settings,
      userStatistics: userStatistics
    )
    backendPlayer.triggerReinsertPlayableCB = { [unowned self] in
      recorder.recover(isDataError: backendPlayer.isDataErrorOccurred)
      musicPlayer.recoverFromPlaybackError()
    }
    player = PlayerFacadeImpl(
      playerStatus: playerData,
      queueHandler: queueHandler,
      musicPlayer: musicPlayer,
      library: library,
      backendAudioPlayer: backendPlayer,
      userStatistics: userStatistics
    )
    recorder = RecordingMusicPlayable()
    requestLogStart = Date()
    player.addNotifier(notifier: recorder)
  }

  override func tearDown() async throws {
    if let player {
      player.stop()
      // print the event log of failed tests for diagnosis
      if testRun?.hasSucceeded == false {
        print("Player events:\n" + recorder.log.joined(separator: "\n"))
        let requests = server.requests.prefix(80).map {
          String(format: "%6.2f %@", $0.date.timeIntervalSince(requestLogStart), $0.description)
        }
        print("Requests (\(server.requests.count)):\n" + requests.joined(separator: "\n"))
      }
    }
    server?.stop()
    // XCTest keeps every test case instance until the suite ends, release the audio engines
    player = nil
    musicPlayer = nil
    backendPlayer = nil
    backendApi = nil
    recorder = nil
    server = nil
    storage = nil
    account = nil
    library = nil
    cdHelper = nil
  }

  // MARK: Helper

  func createSong(id: String, data: Data? = nil) -> Song {
    let song = library.createSong(account: account)
    song.id = id
    song.title = id
    song.contentType = "audio/wav"
    song.remoteDuration = Int(Self.songSeconds)
    _ = song.updateDuration()
    server.serve(
      path: "/\(id).wav",
      data: data ?? Self.songData,
      contentType: "audio/wav"
    )
    return song
  }

  /// Polls the condition until it holds or the timeout ends
  @discardableResult
  func wait(
    _ description: String,
    timeout: TimeInterval,
    file: StaticString = #filePath,
    line: UInt = #line,
    until condition: () -> Bool
  ) async
    -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !condition() {
      guard Date() < end else {
        XCTFail("timed out: \(description)", file: file, line: line)
        return false
      }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return true
  }

  /// Checks that the condition holds the whole time
  func hold(
    _ description: String,
    for duration: TimeInterval,
    file: StaticString = #filePath,
    line: UInt = #line,
    while condition: () -> Bool
  ) async {
    let end = Date().addingTimeInterval(duration)
    while Date() < end {
      guard condition() else {
        XCTFail("broken: \(description)", file: file, line: line)
        return
      }
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  func play(_ songs: [Song]) {
    player.play(context: PlayContext(name: "", playables: songs))
  }

  /// Every attempt to open a stream starts with a probe request for the first two bytes
  func streamAttempts(for song: Song) -> Int {
    server.requests.filter { $0.path == "/\(song.id).wav" && $0.range == "bytes=0-1" }.count
  }

  // MARK: Tests

  func testStream_Plays() async {
    let song = createSong(id: "song1")
    play([song])
    await wait("playback progresses", timeout: 10) { player.elapsedTime >= 2 }
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(player.currentlyPlaying?.id, song.id)
    XCTAssertEqual(recorder.recoverCount, 0)
  }

  func testStream_ShortOutage_KeepsPlaying() async {
    server.bytesPerSecond = Self.audioByteRate * 3 / 2
    let song = createSong(id: "song1")
    play([song])
    await wait("playback progresses", timeout: 10) { player.elapsedTime >= 2 }

    server.isOffline = true
    try? await Task.sleep(for: .seconds(2))
    server.isOffline = false

    await wait("playback continues after the outage", timeout: 20) { player.elapsedTime >= 8 }
    XCTAssertEqual(player.currentlyPlaying?.id, song.id)
    XCTAssertTrue(player.isPlaying)
  }

  func testStream_OutageShorterThanStallTimeout_KeepsPlaying() async {
    // reconnecting and refilling the buffer after the 4 s outage takes several seconds more
    backendPlayer.stallTimeout = 20
    server.bytesPerSecond = Self.audioByteRate * 3 / 2
    let song = createSong(id: "song1")
    play([song])
    await wait("playback progresses", timeout: 10) { player.elapsedTime >= 3 }

    // AudioStreaming reconnects on its own without reporting an error
    server.isOffline = true
    try? await Task.sleep(for: .seconds(4))
    XCTAssertFalse(backendPlayer.isErrorOccurred)
    let position = player.elapsedTime

    server.isOffline = false
    await wait("playback resumes", timeout: 15) { player.elapsedTime > position + 1 }
    XCTAssertEqual(player.currentlyPlaying?.id, song.id)
    XCTAssertTrue(player.isPlaying)
    XCTAssertEqual(recorder.recoverCount, 0)
  }

  func testStream_LongOutage_PausesAfterStallTimeoutThenResumesAtPosition() async {
    backendPlayer.stallTimeout = 3
    server.bytesPerSecond = Self.audioByteRate * 3 / 2
    let song = createSong(id: "song1")
    play([song])
    await wait("playback progresses", timeout: 10) { player.elapsedTime >= 3 }

    server.isOffline = true
    await wait("player pauses after the stall timeout", timeout: 20) { !player.isPlaying }
    XCTAssertTrue(backendPlayer.isStallErrorOccurred)
    XCTAssertEqual(recorder.recoverCount, 1, "no retries after a stall")
    let position = backendPlayer.elapsedTimeBeforeErrorOccurred
    XCTAssertGreaterThan(position, 2)
    XCTAssertGreaterThan(server.refusedConnectionCount, 0, "AudioStreaming reconnected meanwhile")
    // the torn down player stops reconnecting
    try? await Task.sleep(for: .seconds(1))
    let refused = server.refusedConnectionCount
    await hold("stays paused without reconnecting", for: 7) {
      !player.isPlaying && server.refusedConnectionCount == refused
    }

    server.isOffline = false
    player.play()
    await wait("playback resumes", timeout: 15) { player.isPlaying && player.elapsedTime >= 1 }
    XCTAssertEqual(player.currentlyPlaying?.id, song.id)
    XCTAssertGreaterThanOrEqual(player.elapsedTime, position - 1, "resumes instead of restarting")
  }

  func testStream_ServerDownAtStart_PausesAfterStallTimeout() async {
    backendPlayer.stallTimeout = 3
    server.isOffline = true
    let song = createSong(id: "song1")
    play([song])
    await wait("player pauses after the stall timeout", timeout: 20) {
      recorder.recoverCount == 1 && !player.isPlaying
    }
    XCTAssertTrue(backendPlayer.isStallErrorOccurred)
    XCTAssertEqual(player.currentlyPlaying?.id, song.id)

    server.isOffline = false
    player.play()
    await wait("playback starts", timeout: 15) { player.isPlaying && player.elapsedTime >= 1 }
    XCTAssertEqual(player.currentlyPlaying?.id, song.id)
  }

  func testStream_ServerErrorDuringPlayback_PausesThenResumesAtPosition() async {
    musicPlayer.errorRecoveryDelays = [0.2, 0.2, 0.2]
    server.bytesPerSecond = Self.audioByteRate * 3 / 2
    let song = createSong(id: "song1")
    play([song])
    await wait("playback progresses", timeout: 10) { player.elapsedTime >= 3 }

    // e.g. a reverse proxy answering 502 while the music server restarts
    let position = player.elapsedTime
    server.httpStatus = 502
    server.isOffline = true
    server.isOffline = false
    let errorCount = Self.errorCountUntilGivingUp
    await wait("all retries failed", timeout: 30) {
      recorder.recoverCount >= errorCount && !player.isPlaying
    }
    XCTAssertEqual(recorder.recoverCount, errorCount)
    // the torn down AudioStreaming instance opens the stream once more right after an error
    try? await Task.sleep(for: .milliseconds(500))
    let attempts = streamAttempts(for: song)
    await hold("stays paused without further attempts", for: 3) {
      !player.isPlaying && streamAttempts(for: song) == attempts
        && recorder.recoverCount == errorCount
    }
    XCTAssertEqual(player.currentlyPlaying?.id, song.id)

    server.httpStatus = nil
    player.play()
    await wait("playback resumes", timeout: 15) { player.isPlaying && player.elapsedTime >= 1 }
    XCTAssertEqual(player.currentlyPlaying?.id, song.id)
    XCTAssertGreaterThanOrEqual(player.elapsedTime, position - 1, "resumes instead of restarting")
  }

  func testStream_ServerError_StaysPausedThenPlays() async {
    musicPlayer.errorRecoveryDelays = [0.2, 0.2, 0.2]
    server.httpStatus = 500
    let song = createSong(id: "song1")
    let next = createSong(id: "song2")
    play([song, next])
    let errorCount = Self.errorCountUntilGivingUp
    await wait("all attempts failed", timeout: 20) {
      recorder.recoverCount >= errorCount && !player.isPlaying
    }
    XCTAssertEqual(recorder.recoverCount, errorCount)
    // the torn down AudioStreaming instance may open the stream once more right after an error
    try? await Task.sleep(for: .milliseconds(500))
    let attempts = streamAttempts(for: song)
    await hold("stays paused on the song without further attempts", for: 3) {
      !player.isPlaying && player.currentlyPlaying?.id == song.id
        && streamAttempts(for: song) == attempts && recorder.recoverCount == errorCount
    }
    XCTAssertEqual(streamAttempts(for: next), 0, "a network error doesn't skip")

    server.httpStatus = nil
    player.play()
    await wait("playback starts", timeout: 15) { player.isPlaying && player.elapsedTime >= 1 }
    XCTAssertEqual(player.currentlyPlaying?.id, song.id)
  }

  func testStream_BrokenFile_SkipsToNextSong() async {
    musicPlayer.errorRecoveryDelays = [0.2, 0.2, 0.2]
    var garbage = Data(count: 400_000)
    garbage.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
    let broken = createSong(id: "broken", data: garbage)
    let next = createSong(id: "song2")
    play([broken, next])
    await wait("skips to the next song and plays it", timeout: 30) {
      player.currentlyPlaying?.id == next.id && player.isPlaying && player.elapsedTime >= 1
    }
    XCTAssertEqual(recorder.recoverCount, Self.errorCountUntilGivingUp)
  }

  func testStream_PauseDuringRetryDelay_CancelsRetry() async {
    musicPlayer.errorRecoveryDelays = [0.2, 0.2, 4]
    server.httpStatus = 503
    let song = createSong(id: "song1")
    play([song])
    // the first error and two failed retries, the third retry waits 4 s
    await wait("two retries failed", timeout: 20) { recorder.recoverCount >= 3 }
    XCTAssertEqual(recorder.recoverCount, 3)
    try? await Task.sleep(for: .milliseconds(500))
    player.pause()
    let attempts = streamAttempts(for: song)
    try? await Task.sleep(for: .seconds(6))
    XCTAssertEqual(streamAttempts(for: song), attempts, "no retry after pause")
    XCTAssertEqual(recorder.recoverCount, 3)
    XCTAssertFalse(player.isPlaying)
  }
}

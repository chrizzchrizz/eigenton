//
//  AppDelegateMainMenuExtension.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 08.08.25.
//  Copyright (c) 2025 Maximilian Bauer. All rights reserved.
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
@preconcurrency import UIKit

extension AppDelegate {
  func configureMainMenu() {
    let config = UIMainMenuSystem.Configuration()
    config.newScenePreference = .removed
    config.documentPreference = .removed
    config.printingPreference = .removed
    config.findingPreference = .included
    config.findingConfiguration.style = .search
    config.toolbarPreference = .included
    config.sidebarPreference = .included
    config.inspectorPreference = .included
    config.textFormattingPreference = .removed

    UIMainMenuSystem.shared.setBuildConfiguration(config) { builder in
      self.buildMainMenu(with: builder)
    }
  }

  public func rebuildMainMenu() {
    UIMenuSystem.main.setNeedsRebuild()
  }

  private func buildMainMenu(with builder: any UIMenuBuilder) {
    guard builder.system == .main else { return }

    #if targetEnvironment(macCatalyst) // ok
      // Add File menu
      let fileMenus = [
        UIMenu(options: .displayInline, children: [
          UIAction(
            title: "Open Player Window",
            image: AmperfyImage.openPlayerWindow.asUIImage,
            attributes: isMainWindowOpen ? .disabled : []
          ) { _ in
            self.openMainWindow()
          },
          UIKeyCommand(
            title: "Close Player Window",
            image: AmperfyImage.xmark.asUIImage,
            action: #selector(closePlayerWindow),
            input: "W",
            modifierFlags: .command,
            attributes: !isMainWindowOpen ? .disabled : []
          ),
        ]),
      ]
      builder.insertChild(fileMenus[0], atStartOfMenu: .file)
      let openSettingsMenu = UIMenu(options: .displayInline, children: [
        UIKeyCommand(
          title: "Settings…",
          image: AmperfyImage.settings.asUIImage,
          action: #selector(showSettings),
          input: ",",
          modifierFlags: .command
        ),
      ])
      builder.insertSibling(openSettingsMenu, afterMenu: .about)
      let switchPlayerMenu = UIMenu(options: .displayInline, children: [
        UIKeyCommand(
          title: isPopupPlayerOpen ? "Hide Player" : "Show Player",
          image: AmperfyImage.switchPlayerWindow.asUIImage,
          action: #selector(keyCommandShowHidePlayer),
          input: "F",
          modifierFlags: [.shift, .command],
          // the player is shown in the main window
          attributes: isMainWindowOpen ? [] : .disabled
        ),
      ])
      builder.insertSibling(switchPlayerMenu, afterMenu: .minimizeAndZoom)
    #endif

    // Add media controls
    builder.insertSibling(
      UIMenu(title: "Controls", children: buildControlsMenu()),
      afterMenu: .view
    )

    builder.insertChild(UIMenu(options: .displayInline, children: [
      UIAction(title: "Report an issue on GitHub") { _ in
        if let url = URL(string: "https://github.com/chrizzchrizz/eigenton/issues") {
          UIApplication.shared.open(url)
        }
      },
    ]), atStartOfMenu: .help)
  }

  @objc
  private func keyCommandPause() {
    player.pause()
  }

  @objc
  private func keyCommandPlay() {
    player.play()
  }

  @objc
  private func keyCommandStop() {
    player.stop()
  }

  @objc
  private func keyCommandNext() {
    player.playNext()
  }

  @objc
  private func keyCommandPrevious() {
    player.playPreviousOrReplay()
  }

  @objc
  private func keyCommandSkipForward() {
    player.skipForward(interval: player.skipForwardInterval)
  }

  @objc
  private func keyCommandSkipBackward() {
    player.skipBackward(interval: player.skipBackwardInterval)
  }

  @objc
  private func keyCommandGoToCurrent() {
    let playable = player.currentlyPlaying
    guard let album = playable?.asSong?.album, let account = playable?.account else { return }
    appDelegate.userStatistics.usedAction(.alertGoToAlbum)
    let albumDetailVC = AppStoryboard.Main.segueToAlbumDetail(
      account: account,
      album: album,
      songToScrollTo: playable?.asSong
    )
    displayInLibraryTab(vc: albumDetailVC)
  }

  @objc
  private func keyCommandShowHidePlayer() {
    visualizePopupPlayer(direction: .toggle, animated: true)
  }

  @objc
  private func keyCommandShuffleOn() {
    guard !player.isShuffle else { return }
    player.toggleShuffle()
  }

  @objc
  private func keyCommandShuffleOff() {
    guard player.isShuffle else { return }
    player.toggleShuffle()
  }

  private func buildControlsMenu() -> [UIMenuElement] {
    let isPlaying = player.isPlaying
    let isShuffle = player.isShuffle
    let isSkipAvailable = isPlaying && player.isSkipAvailable
    let hasAlbum = player.currentlyPlaying?.asSong?.album != nil

    let section1 = [
      UIKeyCommand(
        title: isPlaying ? (player.isStopInsteadOfPause ? "Stop Radio" : "Pause") : "Play",
        image: isPlaying ? (player.isStopInsteadOfPause ? .stop : .pause) : .play,
        action: isPlaying ? #selector(keyCommandPause) : #selector(keyCommandPlay),
        input: " "
      ),
      UIKeyCommand(
        title: (isPlaying && player.isStopInsteadOfPause) ? "Stop Player" : "Stop",
        image: .stop,
        action: #selector(keyCommandStop),
        input: ".",
        modifierFlags: .command,
        attributes: []
      ),
      UIKeyCommand(
        title: "Next Track",
        image: .forwardMenu,
        action: #selector(keyCommandNext),
        input: UIKeyCommand.inputRightArrow,
        modifierFlags: .command,
        attributes: []
      ),
      UIKeyCommand(
        title: "Previous Track",
        image: .backwardMenu,
        action: #selector(keyCommandPrevious),
        input: UIKeyCommand.inputLeftArrow,
        modifierFlags: .command,
        attributes: []
      ),
      UIKeyCommand(
        title: "Skip Forward: " + Int(player.skipForwardInterval).description + " sec.",
        image: player.skipForwardIcon,
        action: #selector(keyCommandSkipForward),
        input: UIKeyCommand.inputRightArrow,
        modifierFlags: [.shift, .command],
        attributes: isSkipAvailable ? [] : [.disabled]
      ),
      UIKeyCommand(
        title: "Skip Backward: " + Int(player.skipBackwardInterval).description + " sec.",
        image: player.skipBackwardIcon,
        action: #selector(keyCommandSkipBackward),
        input: UIKeyCommand.inputLeftArrow,
        modifierFlags: [.shift, .command],
        attributes: isSkipAvailable ? [] : [.disabled]
      ),
      UIKeyCommand(
        title: "Go to Current Song",
        image: .currentSongMenu,
        action: #selector(keyCommandGoToCurrent),
        input: "L",
        modifierFlags: [.command],
        attributes: hasAlbum ? [] : [.disabled]
      ),
    ]

    var section2 = [
      UIMenu(
        title: "Playback Rate",
        image: .playbackRate,
        children: PlaybackRate.allCases.map { rate in
          UIAction(
            title: rate.description,
            state: rate == self.player.playbackRate ? .on : .off
          ) { _ in
            self.player.setPlaybackRate(rate)
          }
        }
      ),
    ]

    if appDelegate.player.playerMode == .music {
      let repeatMenu = UIMenu(
        title: "Repeat",
        image: .repeatMenu,
        children: RepeatMode.allCases.map { mode in
          UIAction(
            title: mode.description,
            state: mode == self.player.repeatMode ? .on : .off
          ) { _ in
            self.player.setRepeatMode(mode)
          }
        }
      )
      section2.insert(repeatMenu, at: 0)
    }
    if appDelegate.player.playerMode == .music,
       appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled {
      let shuffleMenu = UIMenu(title: "Shuffle", image: .shuffleMenu, children: [
        UIAction(title: "On", state: isShuffle ? .on : .off) { [weak self] _ in
          self?.keyCommandShuffleOn()
        },
        UIAction(title: "Off", state: !isShuffle ? .on : .off) { [weak self] _ in
          self?.keyCommandShuffleOff()
        },
      ])
      section2.insert(shuffleMenu, at: 0)
    }

    let section3 = [
      createSleepTimerMenu(refreshCB: {
        self.rebuildMainMenu()
      }),
    ]

    var section4: [UIMenuElement] = [
      UIAction(
        title: "Switch Music/Podcast mode",
        image: player.playerMode == .music ? .musicalNotes : .podcast
      ) { _ in
        self.player.setPlayerMode(self.player.playerMode.nextMode)
      },
    ]
    if isContinuePlaybackAvailable {
      section4.append(createContinuePlaybackAction())
    }

    let sections: [[UIMenuElement]] = [section1, section2, section3, section4]

    return sections.reduce([]) { result, section in
      result + [UIMenu(options: .displayInline)] + section
    }
  }

  @objc
  func closePlayerWindow(sender: Any) {
    if isMainWindowOpen {
      closeMainWindow()
    }
    rebuildMainMenu()
  }

  @objc
  func showSettings(sender: Any) {
    let settingsActivity = NSUserActivity(activityType: settingsWindowActivityType)
    UIApplication.shared.requestSceneSessionActivation(
      settingsSceneSession,
      userActivity: settingsActivity,
      options: nil,
      errorHandler: nil
    )
  }

  func createSleepTimerMenu(refreshCB: VoidFunctionCallback?) -> UIMenuElement {
    if let timer = sleepTimer {
      let actionTitle = "Turn Off (Pause at: \(timer.fireDate.asShortHrMinString))"
      let deactivate = UIAction(title: actionTitle, image: nil, handler: { _ in
        self.sleepTimer?.invalidate()
        self.sleepTimer = nil
        refreshCB?()
      })
      return UIMenu(
        title: "Sleep Timer",
        subtitle: "Pause at: \(timer.fireDate.asShortHrMinString)",
        image: .sleep,
        children: [deactivate]
      )
    } else if player.isShouldPauseAfterFinishedPlaying {
      let actionTitle = "Turn Off (Pause at end of \(player.playerMode.playableName))"
      let deactivate = UIAction(title: actionTitle, image: nil, handler: { _ in
        self.player.isShouldPauseAfterFinishedPlaying = false
        refreshCB?()
      })
      return UIMenu(
        title: "Sleep Timer",
        subtitle: "Pause at end of \(player.playerMode.playableName)",
        children: [deactivate]
      )
    } else {
      let endOfTrack = UIAction(title: "End of Song or Podcast Episode", image: nil, handler: { _ in
        self.player.isShouldPauseAfterFinishedPlaying = true
        refreshCB?()
      })
      let sleep5 = UIAction(title: "5 Minutes", image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(5 * 60))
        refreshCB?()
      })
      let sleep10 = UIAction(title: "10 Minutes", image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(10 * 60))
        refreshCB?()
      })
      let sleep15 = UIAction(title: "15 Minutes", image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(15 * 60))
        refreshCB?()
      })
      let sleep30 = UIAction(title: "30 Minutes", image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(30 * 60))
        refreshCB?()
      })
      let sleep45 = UIAction(title: "45 Minutes", image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(45 * 60))
        refreshCB?()
      })
      let sleep60 = UIAction(title: "1 Hour", image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(60 * 60))
        refreshCB?()
      })
      let sleep120 = UIAction(title: "2 Hours", image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(2 * 60 * 60))
        refreshCB?()
      })
      let sleep240 = UIAction(title: "4 Hours", image: nil, handler: { _ in
        self.activateSleepTimer(timeInterval: TimeInterval(4 * 60 * 60))
        refreshCB?()
      })
      return UIMenu(
        title: "Sleep Timer",
        image: .sleep,
        children: [
          endOfTrack,
          sleep5,
          sleep10,
          sleep15,
          sleep30,
          sleep45,
          sleep60,
          sleep120,
          sleep240,
        ]
      )
    }
  }

  private func activateSleepTimer(timeInterval: TimeInterval) {
    appDelegate.sleepTimer?.invalidate()
    appDelegate.sleepTimer = Timer
      .scheduledTimer(withTimeInterval: timeInterval, repeats: false) { _ in
        Task { @MainActor in
          self.appDelegate.player.pause()
          self.appDelegate.eventLogger.info(
            topic: "Sleep Timer",
            message: "Sleep Timer paused playback.",
            toast: AlertToastText(title: "Sleep Timer", subtitle: "Paused by sleep timer")
          )
          self.appDelegate.sleepTimer?.invalidate()
          self.appDelegate.sleepTimer = nil
        }
      }
  }

  /// Mac: the popup player overlay of the main window is shown
  var isPopupPlayerOpen: Bool {
    (Self.mainWindowHostVC as? SplitVC)?.isPopupPlayerOpen ?? false
  }

  /// A main window is shown. A closed window's scene can stay connected in the background for a
  /// while, it doesn't count.
  var isMainWindowOpen: Bool {
    mainWindowScenes.contains {
      $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
    }
  }

  /// Connected scenes of main windows, also in the background
  private var mainWindowScenes: [UIWindowScene] {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { scene in
        scene.windows.contains { $0.rootViewController is MainSceneHostingViewController }
      }
  }

  func closeMainWindow() {
    // Close all main sessions (this might be more than one with multiple tabs open)
    UIApplication.shared.connectedScenes
      .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
      .filter { ($0.rootViewController as? MainSceneHostingViewController) != nil }
      .compactMap { $0.windowScene?.session }
      .forEach {
        let options = UIWindowSceneDestructionRequestOptions()
        options.windowDismissalAnimation = .standard
        UIApplication.shared.requestSceneSessionDestruction(
          $0,
          options: options,
          errorHandler: nil
        )
      }
  }

  func openMainWindow() {
    let defaultActivity = NSUserActivity(activityType: defaultWindowActivityType)
    // a main window scene that is still connected in the background comes back instead of a new one
    UIApplication.shared.requestSceneSessionActivation(
      mainWindowScenes.first?.session,
      userActivity: defaultActivity,
      options: nil,
      errorHandler: nil
    )
  }
}

// MARK: - AppDelegate + MusicPlayable

extension AppDelegate: MusicPlayable {
  func didStartPlaying() {
    rebuildMainMenu()
  }

  func didPause() {
    rebuildMainMenu()
  }

  func didStopPlaying() {
    rebuildMainMenu()
  }

  func didShuffleChange() {
    rebuildMainMenu()
  }

  func didRepeatChange() {
    rebuildMainMenu()
  }

  func didPlaybackRateChange() {
    rebuildMainMenu()
  }

  func didStartPlayingFromBeginning() {}
  func didElapsedTimeChange() {}
  func didPlaylistChange() {}
  func didArtworkChange() {}
}

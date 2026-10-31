//
//  PlayerControlView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 07.02.24.
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
import AVFoundation
import MarqueeLabel
import MediaPlayer
import UIKit

// MARK: - PlayerControlView

#if !targetEnvironment(macCatalyst) // ok
  /// Own slider for the system volume.
  /// MPVolumeView's slider doesn't reliably follow volume changes and fights with any value we
  /// write into it. So the visible slider is a plain UISlider that is fully under our control:
  /// - reading: `AVAudioSession.outputVolume` (KVO, plus a refresh when shown or reactivated)
  /// - writing: the slider of a hidden MPVolumeView, the only way to change the system volume
  private class SystemVolumeSlider: UIView {
    private let slider = UISlider()
    // must be part of the view hierarchy (and not hidden) to work and to suppress the system HUD
    private let hiddenVolumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private var volumeObservation: NSKeyValueObservation?
    private var appActiveObserver: NSObjectProtocol?
    /// KVO reports lag behind while dragging; ignore them shortly after the user changed the value
    private var lastUserChange = Date.distantPast

    private var systemSlider: UISlider? {
      hiddenVolumeView.subviews.first { $0 is UISlider } as? UISlider
    }

    override init(frame: CGRect) {
      super.init(frame: frame)
      hiddenVolumeView.alpha = 0.01
      hiddenVolumeView.isUserInteractionEnabled = false
      addSubview(hiddenVolumeView)

      slider.translatesAutoresizingMaskIntoConstraints = false
      slider.minimumTrackTintColor = .label
      slider.maximumTrackTintColor = UIColor.label.withAlphaComponent(0.3)
      // invisible thumb; it must keep a real size, otherwise the slider can't be grabbed
      let invisibleThumb = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28))
        .image { _ in }
      slider.setThumbImage(invisibleThumb, for: .normal)
      slider.setThumbImage(invisibleThumb, for: .highlighted)
      slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
      addSubview(slider)
      NSLayoutConstraint.activate([
        slider.leadingAnchor.constraint(equalTo: leadingAnchor),
        slider.trailingAnchor.constraint(equalTo: trailingAnchor),
        slider.centerYAnchor.constraint(equalTo: centerYAnchor),
      ])
      setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      volumeObservation = nil
      if let appActiveObserver {
        NotificationCenter.default.removeObserver(appActiveObserver)
      }
      appActiveObserver = nil
      guard window != nil else { return }
      refreshFromSystem()
      volumeObservation = AVAudioSession.sharedInstance()
        .observe(\.outputVolume, options: [.new]) { [weak self] _, change in
          guard let volume = change.newValue else { return }
          Task { @MainActor in self?.refreshFromSystem(volume) }
        }
      // changes made in Control Center while the app was inactive
      appActiveObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.refreshFromSystem() }
      }
    }

    private func refreshFromSystem(_ volume: Float = AVAudioSession.sharedInstance().outputVolume) {
      guard !slider.isTracking, Date().timeIntervalSince(lastUserChange) > 0.5 else { return }
      slider.setValue(volume, animated: false)
    }

    @objc
    private func sliderValueChanged() {
      lastUserChange = Date()
      guard let systemSlider else { return }
      systemSlider.setValue(slider.value, animated: false)
      systemSlider.sendActions(for: .valueChanged)
    }
  }
#endif

// MARK: - PlayerControlView

class PlayerControlView: UIView {
  static private let margin = UIEdgeInsets(
    top: 0,
    left: UIView.defaultMarginX,
    bottom: 20,
    right: UIView.defaultMarginX
  )

  private var player: PlayerFacade!
  private var rootView: PopupPlayerVC?
  private var playerHandler: PlayerUIHandler?

  @IBOutlet
  weak var playButton: UIButton!
  @IBOutlet
  weak var previousButton: UIButton!
  @IBOutlet
  weak var nextButton: UIButton!
  @IBOutlet
  weak var skipBackwardButton: UIButton!
  @IBOutlet
  weak var skipForwardButton: UIButton!

  @IBOutlet
  weak var timeSlider: UISlider!
  @IBOutlet
  weak var elapsedTimeLabel: UILabel!
  @IBOutlet
  weak var remainingTimeLabel: UILabel!
  @IBOutlet
  weak var liveLabel: UILabel!
  @IBOutlet
  weak var audioInfoLabel: UILabel!
  @IBOutlet
  weak var playTypeIcon: UIImageView!

  @IBOutlet
  weak var volumeStackView: UIStackView!
  @IBOutlet
  weak var volumeStackHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  weak var volumeStackTopConstraint: NSLayoutConstraint!
  @IBOutlet
  weak var optionsStackView: UIStackView!
  @IBOutlet
  weak var playerModeButton: UIButton!
  @IBOutlet
  weak var airplayButton: UIButton!
  @IBOutlet
  weak var displayLyricsButton: UIButton!
  @IBOutlet
  weak var displayPlaylistButton: UIButton!
  @IBOutlet
  weak var volumeButton: UIButton!
  @IBOutlet
  weak var optionsButton: UIButton!

  #if !targetEnvironment(macCatalyst) // ok
    private let systemVolumeSlider = SystemVolumeSlider(frame: .zero)
  #endif

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    self.layoutMargins = Self.margin
    self.player = appDelegate.player
    player.addNotifier(notifier: self)
  }

  func prepare(toWorkOnRootView: PopupPlayerVC?) {
    rootView = toWorkOnRootView

    playerHandler = PlayerUIHandler(player: player, style: .popupPlayer)

    #if targetEnvironment(macCatalyst) // ok
      volumeStackView.isHidden = true
      volumeStackHeightConstraint.constant = 0
      volumeStackTopConstraint.constant = 0
    #else
      if systemVolumeSlider.superview == nil {
        volumeStackView.insertArrangedSubview(systemVolumeSlider, at: 1)
        // same height as the icons, so slider and icons share the same center line
        systemVolumeSlider.heightAnchor.constraint(equalTo: volumeStackView.heightAnchor)
          .isActive = true
      }
      for case let icon as UIImageView in volumeStackView.arrangedSubviews {
        icon.tintColor = .label
      }
      // the system volume slider replaces the app volume button
      volumeButton.isHidden = true
    #endif

    playButton.imageView?.tintColor = .label
    previousButton.tintColor = .label
    nextButton.tintColor = .label
    skipBackwardButton.tintColor = .label
    skipForwardButton.tintColor = .label
    airplayButton.tintColor = .label
    displayLyricsButton.tintColor = .label
    playerModeButton.tintColor = .label
    volumeButton.tintColor = .label
    optionsButton.imageView?.tintColor = .label
    refreshPlayer()
    playerHandler?.refreshPlayerOptions(
      optionsButton: optionsButton,
      menuCreateCB: createPlayerOptionsMenu
    )

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.playerHandler?.refreshTimeInfo(
          timeSlider: self.timeSlider,
          elapsedTimeLabel: self.elapsedTimeLabel,
          remainingTimeLabel: self.remainingTimeLabel,
          audioInfoLabel: self.audioInfoLabel,
          playTypeIcon: self.playTypeIcon,
          liveLabel: self.liveLabel
        )
      }
    )
  }

  @IBAction
  func swipeHandler(_ gestureRecognizer: UISwipeGestureRecognizer) {
    if gestureRecognizer.state == .ended {
      rootView?.closePopupPlayer()
    }
  }

  @IBAction
  func playButtonPushed(_ sender: Any) {
    playerHandler?.playButtonPushed()
    playerHandler?.refreshPlayButton(playButton)
  }

  @IBAction
  func previousButtonPushed(_ sender: Any) {
    playerHandler?.previousButtonPushed()
  }

  @IBAction
  func nextButtonPushed(_ sender: Any) {
    playerHandler?.nextButtonPushed()
  }

  @IBAction
  func skipBackwardButtonPushed(_ sender: Any) {
    playerHandler?.skipBackwardButtonPushed()
  }

  @IBAction
  func skipForwardButtonPushed(_ sender: Any) {
    playerHandler?.skipForwardButtonPushed()
  }

  @IBAction
  func timeSliderChanged(_ sender: Any) {
    playerHandler?.timeSliderChanged(timeSlider: timeSlider)
  }

  @IBAction
  func timeSliderIsChanging(_ sender: Any) {
    playerHandler?.timeSliderIsChanging(
      timeSlider: timeSlider,
      elapsedTimeLabel: elapsedTimeLabel,
      remainingTimeLabel: remainingTimeLabel
    )
  }

  @IBAction
  func airplayButtonPushed(_ sender: UIButton) {
    playerHandler?.airplayButtonPushed(rootView: self)
  }

  @IBAction
  func volumeButtonPressed(_ sender: Any) {
    showVolumeSliderMenu()
  }

  func showVolumeSliderMenu() {
    let popoverContentController = SliderMenuPopover()
    let sliderMenuView = popoverContentController.sliderMenuView
    sliderMenuView.frame = CGRect(x: 0, y: 0, width: 250, height: 50)

    sliderMenuView.slider.minimumValue = 0
    sliderMenuView.slider.maximumValue = 100
    sliderMenuView.slider.value = appDelegate.player.volume * 100

    // the slider view stores this callback
    sliderMenuView.sliderValueChangedCB = { [weak self, weak sliderMenuView] in
      guard let self, let sliderMenuView else { return }
      appDelegate.player.volume = Float(sliderMenuView.slider.value) / 100.0
    }

    popoverContentController.modalPresentationStyle = .popover
    popoverContentController.preferredContentSize = sliderMenuView.frame.size

    if let popoverPresentationController = popoverContentController.popoverPresentationController {
      popoverPresentationController.permittedArrowDirections = .down
      popoverPresentationController.delegate = popoverContentController
      popoverPresentationController.sourceView = volumeButton
      rootView?.present(
        popoverContentController,
        animated: true,
        completion: nil
      )
    }
  }

  @IBAction
  func displayLyricsPressed() {
    rootView?.setLyricsDisplayed(rootView?.currentLayout != .lyrics)
  }

  func refreshDisplayLyricsButton() {
    playerHandler?.refreshDisplayLyricsButton(
      displayLyricsButton: displayLyricsButton,
      selectedForegroundColor: rootView?.backgroundColorView.backgroundColor
    )
  }

  func refreshDisplayPlaylistButton() {
    playerHandler?.refreshDisplayPlaylistButton(
      displayPlaylistButton: displayPlaylistButton,
      selectedForegroundColor: rootView?.backgroundColorView.backgroundColor
    )
  }

  @IBAction
  func displayPlaylistPressed() {
    rootView?.switchDisplayStyleOptionPersistent()
    refreshDisplayLyricsButton()
    refreshDisplayPlaylistButton()
    playerHandler?.refreshPlayerOptions(
      optionsButton: optionsButton,
      menuCreateCB: createPlayerOptionsMenu
    )
  }

  @IBAction
  func playerModeChangePressed(_ sender: Any) {
    switch player.playerMode {
    case .music:
      appDelegate.player.setPlayerMode(.podcast)
    case .podcast:
      appDelegate.player.setPlayerMode(.music)
    }
    refreshPlayerModeChangeButton()
  }

  func refreshView() {
    refreshPlayer()
  }

  func refreshPlayer() {
    playerHandler?.refreshSkipButtons(
      skipBackwardButton: skipBackwardButton,
      skipForwardButton: skipForwardButton
    )
    playerHandler?.refreshPlayButton(playButton)
    playerHandler?.refreshTimeInfo(
      timeSlider: timeSlider,
      elapsedTimeLabel: elapsedTimeLabel,
      remainingTimeLabel: remainingTimeLabel,
      audioInfoLabel: audioInfoLabel,
      playTypeIcon: playTypeIcon,
      liveLabel: liveLabel
    )
    playerHandler?.refreshPrevNextButtons(previousButton: previousButton, nextButton: nextButton)
    refreshDisplayPlaylistButton()
    refreshDisplayLyricsButton()
    refreshPlayerModeChangeButton()
    refreshTimeSliderColors()
  }

  /// Progress bar follows the black or white content color of the popup player background.
  private func refreshTimeSliderColors() {
    guard let contentColor = rootView?.contentColor else { return }
    timeSlider.minimumTrackTintColor = contentColor
    timeSlider.maximumTrackTintColor = contentColor.withAlphaComponent(0.3)
  }

  func createPlaybackRateMenu() -> UIMenuElement {
    let playerPlaybackRate = player.playbackRate
    let availablePlaybackRates: [UIAction] = PlaybackRate.allCases.compactMap { playbackRate in
      UIAction(
        title: playbackRate.description,
        image: playbackRate == playerPlaybackRate ? .check : nil,
        handler: { _ in
          self.player.setPlaybackRate(playbackRate)
        }
      )
    }
    return UIMenu(
      title: "Playback Rate",
      subtitle: playerPlaybackRate.description,
      image: .playbackRate,
      children: availablePlaybackRates
    )
  }

  func createPlayerOptionsMenu() -> [UIMenuElement] {
    var menuActions = [UIMenuElement]()
    if player.currentlyPlaying != nil || player.prevQueueCount > 0 || player
      .userQueueCount > 0 || player.nextQueueCount > 0 {
      let clearPlayer = UIAction(title: "Clear Player", image: .clear, handler: { _ in
        self.player.clearQueues()
      })
      menuActions.append(clearPlayer)
    }
    if player.userQueueCount > 0 {
      let clearUserQueue = UIAction(title: "Clear User Queue", image: .playlistX, handler: { _ in
        self.rootView?.clearUserQueue()
      })
      menuActions.append(clearUserQueue)
    }

    menuActions.append(appDelegate.createSleepTimerMenu(refreshCB: nil))
    if player.playerMode == .podcast {
      menuActions.append(createPlaybackRateMenu())
    }

    switch player.playerMode {
    case .music:
      if player.currentlyPlaying != nil || player.prevQueueCount > 0 || player.nextQueueCount > 0,
         appDelegate.storage.settings.user.isOnlineMode {
        let addContextToPlaylist = UIAction(
          title: appDelegate.storage.settings.user.isSimplifiedQueueEnabled
            ? "Add Queue to Playlist"
            : "Add Context Queue to Playlist",
          image: .playlistPlus,
          handler: { _ in
            var itemsToAdd = self.player.getAllPrevQueueItems().filterSongs()
            if let currentlyPlaying = self.player.currentlyPlaying,
               let currentSong = currentlyPlaying.asSong {
              itemsToAdd.append(currentSong)
            }
            itemsToAdd.append(contentsOf: self.player.getAllNextQueueItems().filterSongs())
            // allow add to playlist only if all songs belong to the same account
            guard let firstItemAccount = itemsToAdd.first?.account,
                  itemsToAdd.count == itemsToAdd.filter({ $0.account == firstItemAccount }).count
            else { return }
            let selectPlaylistVC = AppStoryboard.Main
              .segueToPlaylistSelector(account: firstItemAccount, itemsToAdd: itemsToAdd)
            let selectPlaylistNav = UINavigationController(rootViewController: selectPlaylistVC)
            self.rootView?.present(selectPlaylistNav, animated: true, completion: nil)
          }
        )
        menuActions.append(addContextToPlaylist)
      }
      if appDelegate.isContinuePlaybackAvailable {
        menuActions.append(appDelegate.createContinuePlaybackAction(presentingVC: rootView))
      }
    case .podcast: break
    }

    // the queue is only visible in the compact layout, not in large or lyrics
    if rootView?.currentLayout == .compact {
      let scrollToCurrentlyPlaying = UIAction(
        title: "Scroll to currently playing",
        image: .squareArrow,
        handler: { _ in
          self.rootView?.scrollToCurrentlyPlayingRow()
        }
      )
      menuActions.append(scrollToCurrentlyPlaying)
    }

    let playerInfo = UIAction(title: "Player Info", image: .info, handler: { _ in
      guard let rootView = self.rootView else { return }
      let detailVC = PlainDetailsVC()
      detailVC.display(player: self.player, on: rootView)
      rootView.present(detailVC, animated: true)
    })
    menuActions.append(playerInfo)
    return menuActions
  }

  func refreshPlayerModeChangeButton() {
    playerModeButton.isHidden = appDelegate.player.podcastItemCount == 0 && appDelegate.player
      .playerMode != .podcast
    switch player.playerMode {
    case .music:
      playerModeButton.setImage(UIImage.musicalNotes, for: .normal)
    case .podcast:
      playerModeButton.setImage(UIImage.podcast, for: .normal)
    }
    optionsStackView.layoutIfNeeded()
  }
}

// MARK: MusicPlayable

extension PlayerControlView: MusicPlayable {
  func didStartPlayingFromBeginning() {}

  func didStartPlaying() {
    refreshPlayer()
  }

  func didPause() {
    refreshPlayer()
  }

  func didStopPlaying() {
    refreshPlayer()
    playerHandler?.refreshSkipButtons(
      skipBackwardButton: skipBackwardButton,
      skipForwardButton: skipForwardButton
    )
  }

  func didElapsedTimeChange() {
    playerHandler?.refreshTimeInfo(
      timeSlider: timeSlider,
      elapsedTimeLabel: elapsedTimeLabel,
      remainingTimeLabel: remainingTimeLabel,
      audioInfoLabel: audioInfoLabel,
      playTypeIcon: playTypeIcon,
      liveLabel: liveLabel
    )
  }

  func didPlaylistChange() {
    refreshPlayer()
  }

  func didArtworkChange() {}

  func didShuffleChange() {}

  func didRepeatChange() {}

  func didPlaybackRateChange() {}
}

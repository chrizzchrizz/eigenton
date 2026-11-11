//
//  ContextQueueSectionHeader.swift
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
import MarqueeLabel
import UIKit

// MARK: - ContextQueueNextSectionHeader

class ContextQueueNextSectionHeader: UIView {
  static let frameHeight: CGFloat = 40.0 + margin.top + margin.bottom
  static let margin = UIEdgeInsets(
    top: 8,
    left: UIView.defaultMarginX,
    bottom: 8,
    right: UIView.defaultMarginX
  )

  private var player: PlayerFacade!
  private var rootView: PopupPlayerVC?
  private var playerHandler: PlayerUIHandler?

  @IBOutlet
  weak var queueNameLabel: UILabel!
  @IBOutlet
  weak var contextNameLabel: MarqueeLabel!

  @IBOutlet
  weak var shuffleButton: UIButton!
  @IBOutlet
  weak var repeatButton: UIButton!
  @IBOutlet
  weak var autoplayButton: UIButton!

  @IBOutlet
  weak var autoplayTrailingConstraint: NSLayoutConstraint!

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    self.layoutMargins = Self.margin
    self.player = appDelegate.player
    player.addNotifier(notifier: self)
    self.playerHandler = PlayerUIHandler(player: player, style: .popupPlayer)
  }

  func prepare(toWorkOnRootView: PopupPlayerVC?) {
    rootView = toWorkOnRootView
    contextNameLabel.applyAmperfyStyle()
    refresh()
  }

  func refresh() {
    contextNameLabel.text = "\(player.contextName)"
    refreshCurrentlyPlayingInfo()
    configureAutoplayButtonPosition()
    playerHandler?.refreshRepeatButton(repeatButton: repeatButton)
    playerHandler?.refreshShuffleButton(shuffleButton: shuffleButton)
    playerHandler?.refreshAutoplayButton(autoplayButton: autoplayButton)
  }

  /// Mac: the queue in the split view's inspector, not in the popup player
  private var isInInspector: Bool {
    #if targetEnvironment(macCatalyst)
      rootView == nil
    #else
      false
    #endif
  }

  func configureAutoplayButtonPosition() {
    autoplayTrailingConstraint.isActive = false
    if isInInspector {
      autoplayTrailingConstraint = autoplayButton.trailingAnchor.constraint(
        equalTo: safeAreaLayoutGuide.trailingAnchor,
        constant: -8.0
      )
    } else {
      autoplayTrailingConstraint = autoplayButton.trailingAnchor.constraint(
        equalTo: shuffleButton.leadingAnchor,
        constant: -8.0
      )
    }
    NSLayoutConstraint.activate([
      autoplayTrailingConstraint,
    ])
  }

  /// Visibility of the buttons is only set here
  func refreshCurrentlyPlayingInfo() {
    let isMusic = player.playerMode == .music
    // the queue in the inspector: the mini player bar already has repeat and shuffle
    repeatButton.isHidden = !isMusic || isInInspector
    shuffleButton.isHidden = !isMusic || isInInspector
    autoplayButton.isHidden = !isMusic
  }

  @IBAction
  func pressedShuffle(_ sender: Any) {
    playerHandler?.shuffleButtonPushed()
    playerHandler?.refreshShuffleButton(shuffleButton: shuffleButton)
    rootView?.scrollToCurrentlyPlayingRow()
  }

  @IBAction
  func pressedRepeat(_ sender: Any) {
    playerHandler?.repeatButtonPushed()
    playerHandler?.refreshRepeatButton(repeatButton: repeatButton)
  }

  @IBAction
  func pressedAutoplay(_ sender: Any) {
    playerHandler?.autoplayButtonPushed()
    playerHandler?.refreshAutoplayButton(autoplayButton: autoplayButton)
  }
}

// MARK: MusicPlayable

extension ContextQueueNextSectionHeader: MusicPlayable {
  func didStartPlayingFromBeginning() {}

  func didStartPlaying() {}

  func didPause() {}

  func didStopPlaying() {
    refreshCurrentlyPlayingInfo()
  }

  func didElapsedTimeChange() {}

  func didPlaylistChange() {
    refresh()
  }

  func didArtworkChange() {}

  func didShuffleChange() {
    playerHandler?.refreshShuffleButton(shuffleButton: shuffleButton)
  }

  func didRepeatChange() {
    playerHandler?.refreshRepeatButton(repeatButton: repeatButton)
  }

  func didPlaybackRateChange() {}
}

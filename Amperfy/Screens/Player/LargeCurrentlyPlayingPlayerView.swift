//
//  LargeCurrentlyPlayingPlayerView.swift
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
import MediaPlayer
import UIKit

// MARK: - LargeDisplayElement

enum LargeDisplayElement {
  case artwork
  case lyrics
}

// MARK: - LargeCurrentlyPlayingPlayerView

class LargeCurrentlyPlayingPlayerView: UIView, UIGestureRecognizerDelegate {
  static let rowHeight: CGFloat = 94.0
  static private let margin = UIEdgeInsets(
    top: 0,
    left: UIView.defaultMarginX,
    bottom: 20,
    right: UIView.defaultMarginX
  )

  private var rootView: PopupPlayerVC?
  private var lyricsView: LyricsView?
  private(set) var displayElement: LargeDisplayElement = .artwork

  @IBOutlet
  weak var upperContainerView: UIView!
  @IBOutlet
  weak var artworkImage: LibraryEntityImage!
  private static let artworkCornerRadius = CornerRadius.medium.asCGFloat
  private let artworkShadowView = UIView()
  @IBOutlet
  weak var detailsContainer: UIView!
  @IBOutlet
  weak var titleLabel: MarqueeLabel!
  @IBOutlet
  weak var artistLabel: MarqueeLabel!
  @IBOutlet
  weak var favoriteButton: UIButton!
  @IBOutlet
  weak var optionsButton: UIButton!

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    self.layoutMargins = Self.margin
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Force a layout to prevent wrong size on first appearance on macOS
    upperContainerView.layoutIfNeeded()

    updateArtworkShadowPath()
  }

  /// The artwork clips its content, so the shadow is cast by a separate view right behind it.
  private func setupArtworkShadow() {
    guard artworkShadowView.superview == nil, let container = artworkImage.superview else { return }
    artworkShadowView.translatesAutoresizingMaskIntoConstraints = false
    artworkShadowView.isUserInteractionEnabled = false
    artworkShadowView.layer.shadowColor = UIColor.black.cgColor
    artworkShadowView.layer.shadowOpacity = 0.35
    artworkShadowView.layer.shadowRadius = 16
    artworkShadowView.layer.shadowOffset = CGSize(width: 0, height: 6)
    container.insertSubview(artworkShadowView, belowSubview: artworkImage)
    NSLayoutConstraint.activate([
      artworkShadowView.leadingAnchor.constraint(equalTo: artworkImage.leadingAnchor),
      artworkShadowView.trailingAnchor.constraint(equalTo: artworkImage.trailingAnchor),
      artworkShadowView.topAnchor.constraint(equalTo: artworkImage.topAnchor),
      artworkShadowView.bottomAnchor.constraint(equalTo: artworkImage.bottomAnchor),
    ])
  }

  private func updateArtworkShadowPath() {
    artworkShadowView.layer.shadowPath = UIBezierPath(
      roundedRect: artworkShadowView.bounds,
      cornerRadius: artworkImage.layer.cornerRadius
    ).cgPath
  }

  func prepare(toWorkOnRootView: PopupPlayerVC?) {
    rootView = toWorkOnRootView
    artworkImage.layer.cornerRadius = Self.artworkCornerRadius
    artworkImage.layer.cornerCurve = .continuous
    setupArtworkShadow()
    titleLabel.applyAmperfyStyle()
    artistLabel.applyAmperfyStyle()

    lyricsView = LyricsView()
    lyricsView!.translatesAutoresizingMaskIntoConstraints = false
    lyricsView!.onLyricSelected = { [weak self] lyric in
      self?.appDelegate.player.seek(toSecond: lyric.startTime.seconds)
    }
    let lyricsTap = UITapGestureRecognizer(target: self, action: #selector(handleLyricsTap(_:)))
    lyricsTap.cancelsTouchesInView = false
    lyricsTap.delegate = self
    lyricsView!.addGestureRecognizer(lyricsTap)
    // the lyrics are shown below the header of the lyrics layout, not inside of this view
    if let lyricsContainer = toWorkOnRootView?.lyricsContainerView {
      lyricsContainer.addSubview(lyricsView!)
      NSLayoutConstraint.activate([
        lyricsView!.topAnchor.constraint(equalTo: lyricsContainer.topAnchor),
        lyricsView!.bottomAnchor.constraint(equalTo: lyricsContainer.bottomAnchor),
        lyricsView!.leadingAnchor.constraint(equalTo: lyricsContainer.leadingAnchor),
        lyricsView!.trailingAnchor.constraint(equalTo: lyricsContainer.trailingAnchor),
      ])
    }

    addSwipeGesturesToArtwork()

    displayElement = getDisplayElementBasedOnConfig()
    refresh()
  }

  @objc
  private func handleLyricsTap(_ gesture: UITapGestureRecognizer) {
    // Toggle back to artwork when lyrics are tapped
    rootView?.setLyricsDisplayed(false)
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
    -> Bool {
    guard let lyricsView = lyricsView,
          gestureRecognizer is UITapGestureRecognizer
    else { return true }
    let location = touch.location(in: lyricsView)
    return lyricsView.indexPathForRow(at: location) == nil
  }

  private func addSwipeGesturesToArtwork() {
    func createLeftSwipe() -> UISwipeGestureRecognizer {
      let swipeLeft = UISwipeGestureRecognizer(
        target: self,
        action: #selector(handleSwipe(_:))
      )
      swipeLeft.direction = .left
      return swipeLeft
    }

    func createRightSwipe() -> UISwipeGestureRecognizer {
      let swipeRight = UISwipeGestureRecognizer(
        target: self,
        action: #selector(handleSwipe(_:))
      )
      swipeRight.direction = .right
      return swipeRight
    }

    artworkImage.isUserInteractionEnabled = true
    artworkImage.addGestureRecognizer(createLeftSwipe())
    artworkImage.addGestureRecognizer(createRightSwipe())
  }

  @objc
  private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
    switch gesture.direction {
    case .left:
      rootView?.controlView?.nextButtonPushed(self)
    case .right:
      rootView?.controlView?.previousButtonPushed(self)
    default:
      break
    }
  }

  func refreshLyricsTime(time: CMTime) {
    lyricsView?.scroll(toTime: time)
  }

  func initializeLyrics() {
    guard isLyricsViewAllowedToDisplay else {
      hideLyrics()
      return
    }

    guard let playable = rootView?.player.currentlyPlaying,
          let song = playable.asSong,
          let account = song.account,
          let lyricsRelFilePath = song.lyricsRelFilePath
    else {
      if rootView?.isFetchingSongInfo == true {
        // the lyrics might arrive with the song info
        lyricsView?.clear()
      } else {
        showLyricsAreNotAvailable()
      }
      return
    }

    Task { @MainActor in do {
      let lyricsList = try await appDelegate.getMeta(account.info).librarySyncer
        .parseLyrics(relFilePath: lyricsRelFilePath)
      guard self.isLyricsViewAllowedToDisplay else {
        self.hideLyrics()
        return
      }

      if song == self.appDelegate.player.currentlyPlaying?.asSong,
         let structuredLyrics = lyricsList.getFirstSyncedLyricsOrUnsyncedAsDefault() {
        self.showLyrics(structuredLyrics: structuredLyrics)
      } else {
        self.showLyricsAreNotAvailable()
      }
    } catch {
      guard self.isLyricsViewAllowedToDisplay else {
        self.hideLyrics()
        return
      }
      self.showLyricsAreNotAvailable()
    }}
  }

  var isLyricsViewAllowedToDisplay: Bool {
    displayElement == .lyrics &&
      appDelegate.player.playerMode == .music &&
      appDelegate.storage.settings.accounts.availableApiTypes.contains(.subsonic)
  }

  var isLyricsButtonAllowedToDisplay: Bool {
    appDelegate.player.playerMode == .music &&
      appDelegate.storage.settings.accounts.availableApiTypes.contains(.subsonic)
  }

  public func getDisplayElementBasedOnConfig() -> LargeDisplayElement {
    if appDelegate.storage.settings.user.isPlayerLyricsDisplayed, isLyricsButtonAllowedToDisplay {
      return .lyrics
    } else {
      return .artwork
    }
  }

  public func display(element: LargeDisplayElement) {
    displayElement = element

    switch element {
    case .artwork:
      hideLyrics()
      showArtwork()
    case .lyrics:
      showArtwork()
      initializeLyrics()
    }
  }

  public func showArtwork() {
    artworkImage.alpha = 1
    artworkShadowView.alpha = 1
  }

  private func hideLyrics() {
    lyricsView?.clear()
    lyricsView?.isHidden = true
  }

  private func showLyricsAreNotAvailable() {
    var notAvailableLyrics = StructuredLyrics()
    notAvailableLyrics.synced = false
    var line = LyricsLine()
    line.value = "No Lyrics"
    notAvailableLyrics.line.append(line)
    showLyrics(structuredLyrics: notAvailableLyrics)
    lyricsView?.highlightAllLyrics()
  }

  private func showLyrics(structuredLyrics: StructuredLyrics) {
    lyricsView?.display(lyrics: structuredLyrics)
    lyricsView?.isHidden = false
  }

  func refresh() {
    rootView?.playerHandler?.refreshCurrentlyPlayingInfo(
      artworkImage: artworkImage,
      titleLabel: titleLabel,
      artistLabel: artistLabel
    )
    rootView?.refreshFavoriteButton(button: favoriteButton)
    rootView?.refreshOptionButton(button: optionsButton, rootView: rootView)
    display(element: displayElement)
  }

  func refreshArtwork() {
    rootView?.playerHandler?.refreshArtwork(artworkImage: artworkImage)
  }

  @IBAction
  func artworkPressed(_ sender: Any) {
    rootView?.controlView?.displayPlaylistPressed()
  }

  @IBAction
  func titlePressed(_ sender: Any) {
    rootView?.displayAlbumDetail()
    rootView?.displayPodcastDetail()
  }

  @IBAction
  func artistNamePressed(_ sender: Any) {
    rootView?.displayArtistDetail()
    rootView?.displayPodcastDetail()
  }

  @IBAction
  func favoritePressed(_ sender: Any) {
    rootView?.favoritePressed()
    rootView?.refreshFavoriteButton(button: favoriteButton)
  }
}

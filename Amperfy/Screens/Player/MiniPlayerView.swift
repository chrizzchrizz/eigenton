//
//  MiniPlayerView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 31.07.25.
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
import MarqueeLabel
import MediaPlayer
import UIKit

// MARK: - MiniPlayerView

class MiniPlayerView: UIView {
  private var player: PlayerFacade
  private var playerHandler: PlayerUIHandler?

  private var hoverOverlayView: UIView?

  static let mediumButtonSize: CGFloat = 20.0

  fileprivate lazy var artworkOverlay: UIView = {
    let view = UIView()
    view.backgroundColor = .black.withAlphaComponent(0.4)
    view.isHidden = true

    let imageView = UIImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = .white
    imageView.image = .miniPlayer.withRenderingMode(.alwaysTemplate)

    view.addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      imageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
      imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.8),
    ])

    return view
  }()

  fileprivate lazy var artworkImage: LibraryEntityImage = {
    let imageView = LibraryEntityImage(frame: .zero)
    imageView.backgroundColor = .clear
    #if targetEnvironment(macCatalyst) // ok
      artworkOverlay.translatesAutoresizingMaskIntoConstraints = false
      imageView.addSubview(artworkOverlay)
      NSLayoutConstraint.activate([
        artworkOverlay.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
        artworkOverlay.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
        artworkOverlay.widthAnchor.constraint(equalTo: imageView.widthAnchor),
        artworkOverlay.heightAnchor.constraint(equalTo: imageView.heightAnchor),
      ])

      imageView.isUserInteractionEnabled = true
      let miniPlayerHoverGesture = UIHoverGestureRecognizer(
        target: self,
        action: #selector(artworkHovered(_:))
      )
      let miniPlayerTapGesture = UITapGestureRecognizer(
        target: self,
        action: #selector(artworkClicked(_:))
      )
      imageView.addGestureRecognizer(miniPlayerTapGesture)
      imageView.addGestureRecognizer(miniPlayerHoverGesture)
    #endif
    return imageView
  }()

  fileprivate lazy var titleLabel: UILabel = {
    let label = MarqueeLabel(frame: .zero)
    label.applyAmperfyStyle()
    label.textAlignment = .center
    label.backgroundColor = .clear
    label.numberOfLines = 1
    label.textColor = .label
    return label
  }()

  fileprivate lazy var subtitleLabel: UILabel = {
    let label = MarqueeLabel(frame: .zero)
    label.applyAmperfyStyle()
    label.backgroundColor = .clear
    label.textAlignment = .center
    label.numberOfLines = 1
    label.textColor = .secondaryLabel
    return label
  }()

  fileprivate lazy var timeSlider: ExpandableTrackTimeSlider = {
    let slider = ExpandableTrackTimeSlider(frame: .zero)
    slider.preferredBehavioralStyle = .pad
    // explicit colors: the default tint is hard to tell apart from the track on the glass background
    slider.minimumTrackTintColor = .label
    slider.maximumTrackTintColor = .label.withAlphaComponent(0.2)
    return slider
  }()

  @objc
  func artworkHovered(_ sender: UIHoverGestureRecognizer) {
    switch sender.state {
    case .began:
      artworkOverlay.isHidden = false
    case .cancelled, .ended, .failed:
      artworkOverlay.isHidden = true
    default:
      break
    }
  }

  @objc
  func artworkClicked(_ sender: UITapGestureRecognizer) {
    switch sender.state {
    case .ended:
      openPlayerView()
    default:
      break
    }
  }

  @objc
  func timeSliderChanged(_ slider: UISlider) {
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

  fileprivate lazy var elapsedTimeLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.textColor = .secondaryLabel
    label.font = .systemFont(ofSize: 12.0)
    return label
  }()

  fileprivate lazy var remainingTimeLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.textAlignment = .right
    label.textColor = .secondaryLabel
    label.font = .systemFont(ofSize: 12.0)
    return label
  }()

  fileprivate lazy var liveLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.text = "LIVE"
    label.font = .systemFont(ofSize: 12.0)
    label.textAlignment = .center
    return label
  }()

  fileprivate lazy var audioInfoLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.font = .systemFont(ofSize: 12.0)
    return label
  }()

  fileprivate lazy var playTypeIcon: UIImageView = {
    let imageView = UIImageView(frame: .zero)
    imageView.tintColor = .secondaryLabel
    return imageView
  }()

  fileprivate lazy var moreButton: UIButton = {
    let button = UIButton()
    button.setImage(
      .ellipsis.withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
        .withRenderingMode(.alwaysTemplate),
      for: .normal
    )
    button.imageView?.tintColor = .label
    button.showsMenuAsPrimaryAction = true
    return button
  }()

  fileprivate lazy var playButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = .play
      .withConfiguration(
        UIImage
          .SymbolConfiguration(pointSize: PlayerUIHandler.playButtonImagePointSize)
      )
    let button = UIButton(configuration: config)
    button.tintColor = .label
    button.addTarget(self, action: #selector(Self.playButtonPushed), for: .touchUpInside)
    return button
  }()

  @IBAction
  func playButtonPushed(_ sender: Any) {
    playerHandler?.playButtonPushed()
    refreshPlayButton()
  }

  fileprivate lazy var previousButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = .backwardFill.withConfiguration(UIImage.SymbolConfiguration(scale: .large))
    let button = UIButton(configuration: config)
    button.tintColor = .label
    button.addTarget(self, action: #selector(Self.previousButtonPushed), for: .touchUpInside)
    return button
  }()

  @IBAction
  func previousButtonPushed(_ sender: Any) {
    playerHandler?.previousButtonPushed()
  }

  fileprivate lazy var nextButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = .forwardFill.withConfiguration(UIImage.SymbolConfiguration(scale: .large))
    let button = UIButton(configuration: config)
    button.tintColor = .label
    button.addTarget(self, action: #selector(Self.nextButtonPushed), for: .touchUpInside)
    return button
  }()

  @IBAction
  func nextButtonPushed(_ sender: Any) {
    playerHandler?.nextButtonPushed()
  }

  fileprivate lazy var repeatButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = .repeatMenu.withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
    let button = UIButton(configuration: config)
    button.addTarget(self, action: #selector(Self.repeatButtonPushed), for: .touchUpInside)
    button
      .cornerConfiguration =
      .corners(radius: UICornerRadius(floatLiteral: Self.mediumButtonSize / 2))
    return button
  }()

  @IBAction
  func repeatButtonPushed(_ sender: Any) {
    playerHandler?.repeatButtonPushed()
    playerHandler?.refreshRepeatButton(repeatButton: repeatButton)
  }

  fileprivate lazy var shuffleButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = .shuffle.withConfiguration(UIImage.SymbolConfiguration(scale: .medium))
    let button = UIButton(configuration: config)
    button.addTarget(self, action: #selector(Self.shuffleButtonPushed), for: .touchUpInside)
    button
      .cornerConfiguration =
      .corners(radius: UICornerRadius(floatLiteral: Self.mediumButtonSize / 2))
    return button
  }()

  @IBAction
  func shuffleButtonPushed(_ sender: Any) {
    playerHandler?.shuffleButtonPushed()
    playerHandler?.refreshShuffleButton(shuffleButton: shuffleButton)
  }

  fileprivate lazy var lyricsButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = .lyrics
      .withConfiguration(
        UIImage
          .SymbolConfiguration(pointSize: PlayerUIHandler.bigButtonImagePointSize)
      )
    let button = UIButton(configuration: config)
    button.tintColor = .label
    button.addTarget(self, action: #selector(Self.lyricsPressed), for: .touchUpInside)
    return button
  }()

  @IBAction
  func lyricsPressed() {
    #if !targetEnvironment(macCatalyst)
      // iPad: open the popup player with the lyrics shown; the stored cover or queue view stays
      // for when the lyrics are left, like with the popup player's lyrics button
      appDelegate.storage.settings.user.isPlayerLyricsDisplayed = true
      openPlayerView()
    #else
      appDelegate.storage.settings.user.isPlayerLyricsDisplayed.toggle()
      if appDelegate.storage.settings.user.isPlayerLyricsDisplayed {
        appDelegate.storage.settings.user.playerDisplayStyle = .large
      }
      playerHandler?.refreshDisplayLyricsButton(displayLyricsButton: lyricsButton)
      playerHandler?.refreshDisplayPlaylistButton(displayPlaylistButton: playlistButton)

      guard let host = AppDelegate.mainWindowHostVC as? SplitVC else { return }
      host.displayOrHideInspector()
    #endif
  }

  fileprivate lazy var playlistButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = .playlist
      .withConfiguration(
        UIImage
          .SymbolConfiguration(pointSize: PlayerUIHandler.bigButtonImagePointSize)
      )
    let button = UIButton(configuration: config)
    button.tintColor = .label
    button.addTarget(self, action: #selector(Self.playlistPressed), for: .touchUpInside)
    return button
  }()

  @IBAction
  func playlistPressed() {
    #if !targetEnvironment(macCatalyst)
      // iPad: open the popup player with the queue shown
      PopupPlayerVC.showQueuePersistent(appDelegate: appDelegate)
      openPlayerView()
    #else
      appDelegate.storage.settings.user.playerDisplayStyle.switchToNextStyle()
      if appDelegate.storage.settings.user.playerDisplayStyle == .compact {
        appDelegate.storage.settings.user.isPlayerLyricsDisplayed = false
      }
      playerHandler?.refreshDisplayPlaylistButton(displayPlaylistButton: playlistButton)
      playerHandler?.refreshDisplayLyricsButton(displayLyricsButton: lyricsButton)

      guard let host = AppDelegate.mainWindowHostVC as? SplitVC else { return }
      host.displayOrHideInspector()
    #endif
  }

  fileprivate lazy var airplayButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.image = .airplayaudio
      .withConfiguration(
        UIImage
          .SymbolConfiguration(pointSize: PlayerUIHandler.bigButtonImagePointSize)
      )
    let button = UIButton(configuration: config)
    button.tintColor = .label
    button.addTarget(self, action: #selector(Self.airplayButtonPushed), for: .touchUpInside)
    return button
  }()

  @objc
  func airplayButtonPushed(_ sender: UIButton) {
    playerHandler?.airplayButtonPushed(rootView: self, sourceButton: sender)
  }

  /// Theme color while playing to an AirPlay device
  private func refreshAirplayButton() {
    #if targetEnvironment(macCatalyst) // ok
      let isAirPlayActive = MacOutputVolume.shared.isAirPlayActive
    #else
      let isAirPlayActive = AVAudioSession.sharedInstance().currentRoute.outputs
        .contains { $0.portType == .airPlay }
    #endif
    airplayButton.tintColor = isAirPlayActive ? .tintColor : .label
  }

  private var audioRouteObserver: NSObjectProtocol?

  /// Keeps the AirPlay button color in sync with the audio route (iOS; Mac uses
  /// MacOutputVolume's notification, Catalyst doesn't report AirPlay route changes)
  private func observeAudioRoute() {
    #if !targetEnvironment(macCatalyst) // ok
      guard audioRouteObserver == nil else { return }
      audioRouteObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.refreshAirplayButton()
        }
      }
    #endif
  }

  #if targetEnvironment(macCatalyst) // ok
    /// System volume, or the AirPlay volume while playing to AirPlay
    fileprivate lazy var volumeButton: UIButton = {
      let button = MacOutputVolume.makeButton(pointSize: PlayerUIHandler.bigButtonImagePointSize)
      button.addTarget(self, action: #selector(Self.volumeButtonPushed), for: .touchUpInside)
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(Self.outputVolumeDidChange),
        name: MacOutputVolume.didChangeNotification,
        object: nil
      )
      return button
    }()

    @objc
    func volumeButtonPushed(_ sender: UIButton) {
      MacOutputVolume.shared.presentSlider(
        from: sender,
        on: AppDelegate.mainWindowHostVC as? UIViewController,
        arrowDirection: .up
      )
    }

    @objc
    private func outputVolumeDidChange() {
      refreshTrailingButtons()
    }
  #endif

  public lazy var infoView: UIView = {
    let view = UIView(frame: .zero)

    self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
    (subtitleLabel).translatesAutoresizingMaskIntoConstraints = false
    (artworkImage).translatesAutoresizingMaskIntoConstraints = false
    (moreButton).translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
    view.addSubview(artworkImage)
    view.addSubview(moreButton)

    // title and artist with their intrinsic heights (fixed heights cut off descenders),
    // centered as a group; an empty artist label has no height and leaves the title centered
    let labelsGuide = UILayoutGuide()
    view.addLayoutGuide(labelsGuide)

    NSLayoutConstraint.activate([
      labelsGuide.topAnchor.constraint(equalTo: self.titleLabel.topAnchor),
      labelsGuide.bottomAnchor.constraint(equalTo: self.subtitleLabel.bottomAnchor),
      labelsGuide.centerYAnchor.constraint(equalTo: view.centerYAnchor),

      artworkImage.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
      artworkImage.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
      artworkImage.widthAnchor.constraint(equalTo: artworkImage.heightAnchor),
      artworkImage.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      self.titleLabel.leadingAnchor.constraint(equalTo: artworkImage.trailingAnchor, constant: 10),
      self.titleLabel.trailingAnchor.constraint(
        equalTo: self.moreButton.leadingAnchor,
        constant: 0
      ),
      self.subtitleLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor),
      self.subtitleLabel.leadingAnchor.constraint(
        equalTo: self.artworkImage.trailingAnchor,
        constant: 10
      ),
      self.subtitleLabel.trailingAnchor.constraint(
        equalTo: self.moreButton.leadingAnchor,
        constant: 0
      ),

      self.moreButton.widthAnchor.constraint(equalToConstant: 30),
      self.moreButton.heightAnchor.constraint(equalToConstant: 30),
      self.moreButton.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: 0
      ),
      self.moreButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 2),
    ])

    return view
  }()

  public lazy var sliderAndinfoView: UIView = {
    let view = UIView(frame: .zero)

    let hoverContainer = UIView()

    self.infoView.translatesAutoresizingMaskIntoConstraints = false
    (timeSlider).translatesAutoresizingMaskIntoConstraints = false
    (liveLabel).translatesAutoresizingMaskIntoConstraints = false
    (hoverContainer).translatesAutoresizingMaskIntoConstraints = false

    let hoverGesture = UIHoverGestureRecognizer(
      target: self,
      action: #selector(handleHoverContainerHover(_:))
    )
    hoverContainer.addGestureRecognizer(hoverGesture)

    hoverContainer.addSubview(timeSlider)
    view.addSubview(infoView)
    view.addSubview(liveLabel)
    view.addSubview(hoverContainer)

    NSLayoutConstraint.activate([
      // tall enough for the expanded track (same center as before), so the radio mask doesn't clip it
      timeSlider.bottomAnchor.constraint(equalTo: hoverContainer.bottomAnchor, constant: -3),
      timeSlider.leadingAnchor.constraint(equalTo: hoverContainer.leadingAnchor),
      timeSlider.trailingAnchor.constraint(
        equalTo: hoverContainer.trailingAnchor,
        constant: 0
      ),
      timeSlider.heightAnchor
        .constraint(equalToConstant: ExpandableTrackTimeSlider.expandedTrackHeight),

      liveLabel.centerXAnchor.constraint(equalTo: timeSlider.centerXAnchor, constant: 0),
      liveLabel.centerYAnchor.constraint(equalTo: timeSlider.centerYAnchor, constant: 0),

      infoView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
      infoView.bottomAnchor.constraint(equalTo: timeSlider.topAnchor, constant: -3),
      infoView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
      infoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

      hoverContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0),
      hoverContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hoverContainer.trailingAnchor.constraint(
        equalTo: view.trailingAnchor,
        constant: 0
      ),
      hoverContainer.heightAnchor.constraint(equalToConstant: 17),
    ])

    return view
  }()

  public lazy var leadingButtonsView: UIView = {
    NSLayoutConstraint.activate([
      shuffleButton.heightAnchor.constraint(equalToConstant: Self.mediumButtonSize),
      shuffleButton.widthAnchor.constraint(equalTo: shuffleButton.heightAnchor, constant: 3),
      repeatButton.heightAnchor.constraint(equalToConstant: Self.mediumButtonSize),
      repeatButton.widthAnchor.constraint(equalTo: repeatButton.heightAnchor, constant: 3),
    ])

    self.shuffleButton.translatesAutoresizingMaskIntoConstraints = false
    self.previousButton.translatesAutoresizingMaskIntoConstraints = false
    self.playButton.translatesAutoresizingMaskIntoConstraints = false
    self.nextButton.translatesAutoresizingMaskIntoConstraints = false
    self.repeatButton.translatesAutoresizingMaskIntoConstraints = false

    let stack = UIStackView(arrangedSubviews: [
      shuffleButton,
      previousButton,
      playButton,
      nextButton,
      repeatButton,
    ])
    stack.axis = .horizontal
    stack.distribution = .equalSpacing
    stack.alignment = .center
    return stack
  }()

  public lazy var trailingButtonsView: UIStackView = {
    self.lyricsButton.translatesAutoresizingMaskIntoConstraints = false
    self.playlistButton.translatesAutoresizingMaskIntoConstraints = false
    self.airplayButton.translatesAutoresizingMaskIntoConstraints = false

    #if targetEnvironment(macCatalyst) // ok
      volumeButton.translatesAutoresizingMaskIntoConstraints = false
      let buttons = [lyricsButton, playlistButton, airplayButton, volumeButton]
    #else
      let buttons = [lyricsButton, playlistButton, airplayButton]
    #endif
    let stack = UIStackView(arrangedSubviews: buttons)
    stack.axis = .horizontal
    stack.distribution = .equalSpacing
    stack.alignment = .center
    return stack
  }()

  /// iPad only: lyrics and queue buttons left of the play button that open the popup player
  /// with that view.
  private lazy var displayButtonsView: UIStackView = {
    lyricsButton.translatesAutoresizingMaskIntoConstraints = false
    playlistButton.translatesAutoresizingMaskIntoConstraints = false
    let stack = UIStackView(arrangedSubviews: [lyricsButton, playlistButton])
    stack.axis = .horizontal
    stack.spacing = 0
    stack.alignment = .center
    NSLayoutConstraint.activate([
      lyricsButton.widthAnchor.constraint(equalToConstant: 40),
      lyricsButton.heightAnchor.constraint(equalToConstant: 30),
      playlistButton.widthAnchor.constraint(equalToConstant: 40),
      playlistButton.heightAnchor.constraint(equalToConstant: 30),
    ])
    return stack
  }()

  /// `configureForiOS` (iPhone and iPad) instead of `configureForMac`.
  private var isConfiguredForiOS: Bool { playerHandler?.style == .miniPlayeriOS }

  /// iPad with regular width, where the popup player covers the whole screen: previous, play
  /// and next sit left of the artwork and the lyrics and queue buttons on the trailing side.
  /// Also kept if the tab bar accessory is inline, as the mini player keeps its regular size.
  private var isPadLayout: Bool {
    traitCollection.userInterfaceIdiom == .pad &&
      traitCollection.horizontalSizeClass == .regular
  }

  public func refreshTrailingButtons() {
    guard let playerHandler else { return }
    observeAudioRoute()
    refreshAirplayButton()
    if isConfiguredForiOS {
      // lyrics and queue buttons only on iPad, see displayButtonsView
      lyricsButton.isHidden = !isPadLayout || !playerHandler.isLyricsButtonAllowedToDisplay
      playlistButton.isHidden = !isPadLayout
    } else {
      lyricsButton.isHidden = !playerHandler.isLyricsButtonAllowedToDisplay
      #if targetEnvironment(macCatalyst) // ok
        MacOutputVolume.shared.update(
          button: volumeButton,
          pointSize: PlayerUIHandler.bigButtonImagePointSize
        )
      #endif
      let visibleButtonCount = trailingButtonsView.arrangedSubviews.filter { !$0.isHidden }.count
      trailingButtonsViewWidthConstraint?.constant = CGFloat(visibleButtonCount) * 40
    }
  }

  private func refreshPlayButton() {
    playerHandler?.refreshPlayButton(
      playButton,
      miniPlayeriOSPointSize: controlsLayout == .pad
        ? Self.padPlayButtonImagePointSize
        : PlayerUIHandler.playAndNextiOSButtonImagePointSize
    )
  }

  func refreshMoreButton() {
    let currentlyPlaying = player.currentlyPlaying
    let hasPlayable = currentlyPlaying != nil

    moreButton.isEnabled = hasPlayable

    if let currentlyPlaying,
       let hostVC = AppDelegate.mainWindowHostVC as? UIViewController {
      moreButton.menu = UIMenu.lazyMenu {
        EntityPreviewActionBuilder(container: currentlyPlaying, on: hostVC).createMenuActions()
      }
    }
  }

  private var trailingButtonsViewWidthConstraint: NSLayoutConstraint?

  init(player: PlayerFacade) {
    self.player = player

    super.init(frame: .zero)

    player.addNotifier(notifier: self)

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.refreshControlsLayout()
        self.refreshPlayer()
      }
    )

    registerForTraitChanges([UITraitTabAccessoryEnvironment.self]) { (
      self: Self,
      previousTraitCollection: UITraitCollection
    ) in
      self.refreshControlsLayout()
      self.refreshTrailingButtons()
      self.tabAccessoryTraitChangeCB?()
    }
  }

  public var tabAccessoryTraitChangeCB: VoidFunctionCallback?
  /// Called with `true` once a playable is loaded and with `false` when all queues are empty.
  /// Setting it reports the current state right away.
  public var visibilityChangeCB: ((Bool) -> ())? {
    didSet {
      reportedPlayableLoaded = nil
      refreshVisibility()
    }
  }

  public var isPlayableLoaded: Bool { player.hasLoadedPlayables }
  private var reportedPlayableLoaded: Bool?

  /// Only called from player notifications, not from UI refreshes, because showing or hiding
  /// moves this view in the hierarchy.
  private func refreshVisibility() {
    let isLoaded = isPlayableLoaded
    guard isLoaded != reportedPlayableLoaded else { return }
    reportedPlayableLoaded = isLoaded
    visibilityChangeCB?(isLoaded)
  }

  private enum ControlsLayout {
    /// play and next on the trailing side
    case phone
    /// only play on the trailing side
    case phoneInline
    /// previous, play and next left of the artwork, see `isPadLayout`
    case pad
  }

  private static let padPlayButtonImagePointSize: CGFloat = 24
  private var controlsLayout: ControlsLayout?
  private var controlsLayoutConstraints = [NSLayoutConstraint]()

  /// Depends on the tab bar bottom accessory environment and on the horizontal size class.
  private func refreshControlsLayout() {
    guard isConfiguredForiOS else { return }
    let layout: ControlsLayout
    if isPadLayout {
      layout = .pad
    } else if traitCollection.tabAccessoryEnvironment == .inline {
      layout = .phoneInline
    } else {
      layout = .phone
    }
    guard layout != controlsLayout else { return }
    controlsLayout = layout

    NSLayoutConstraint.deactivate(controlsLayoutConstraints)
    nextButton.isHidden = layout == .phoneInline
    previousButton.isHidden = layout != .pad
    // the play button is bigger on iPad
    refreshPlayButton()
    switch layout {
    case .phone, .phoneInline:
      controlsLayoutConstraints = [
        playButton.widthAnchor.constraint(equalToConstant: 30),
        // hidden, only positioned to keep the layout unambiguous
        previousButton.trailingAnchor.constraint(equalTo: playButton.leadingAnchor),
        artworkImage.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        displayButtonsView.trailingAnchor.constraint(equalTo: playButton.leadingAnchor),
        nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        layout == .phoneInline
          ? playButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
          : playButton.trailingAnchor.constraint(
            equalTo: nextButton.leadingAnchor,
            constant: -5
          ),
      ]
    case .pad:
      controlsLayoutConstraints = [
        playButton.widthAnchor.constraint(equalToConstant: 44),
        previousButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        playButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 5),
        nextButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 5),
        artworkImage.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 12),
        displayButtonsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      ]
    }
    NSLayoutConstraint.activate(controlsLayoutConstraints)
  }

  public func configureForMac() {
    playerHandler = PlayerUIHandler(player: player, style: .miniPlayerMac)
    sliderAndinfoView.translatesAutoresizingMaskIntoConstraints = false
    leadingButtonsView.translatesAutoresizingMaskIntoConstraints = false
    trailingButtonsView.translatesAutoresizingMaskIntoConstraints = false

    addSubview(sliderAndinfoView)
    addSubview(leadingButtonsView)
    addSubview(trailingButtonsView)

    trailingButtonsViewWidthConstraint = trailingButtonsView.widthAnchor
      .constraint(equalToConstant: 160)

    titleLabel.font = .systemFont(ofSize: titleLabel.font.pointSize - 1, weight: .medium)
    subtitleLabel.font = .systemFont(ofSize: subtitleLabel.font.pointSize - 1)

    timeSlider.addTarget(self, action: #selector(timeSliderChanged(_:)), for: .valueChanged)
    timeSlider.addTarget(self, action: #selector(timeSliderIsChanging(_:)), for: .touchDragInside)
    timeSlider.addTarget(self, action: #selector(timeSliderIsChanging(_:)), for: .touchDragOutside)

    NSLayoutConstraint.activate([
      leadingButtonsView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      leadingButtonsView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
      leadingButtonsView.bottomAnchor.constraint(equalTo: bottomAnchor),
      leadingButtonsView.widthAnchor.constraint(equalToConstant: 150),

      sliderAndinfoView.leadingAnchor.constraint(
        equalTo: leadingButtonsView.trailingAnchor,
        constant: 10
      ),
      sliderAndinfoView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
      sliderAndinfoView.bottomAnchor.constraint(equalTo: bottomAnchor),
      sliderAndinfoView.trailingAnchor.constraint(
        equalTo: trailingButtonsView.leadingAnchor,
        constant: -10
      ),

      trailingButtonsView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
      trailingButtonsView.bottomAnchor.constraint(equalTo: bottomAnchor),
      trailingButtonsViewWidthConstraint!,
      trailingButtonsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
    ])
    refreshPlayer()
  }

  public func configureForiOS() {
    playerHandler = PlayerUIHandler(player: player, style: .miniPlayeriOS)
    let miniPlayerGotTouchedView = UIView()
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(miniPlayerGotTouched))
    addGestureRecognizer(tapGesture)

    miniPlayerGotTouchedView.translatesAutoresizingMaskIntoConstraints = false
    artworkImage.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    playButton.translatesAutoresizingMaskIntoConstraints = false
    nextButton.translatesAutoresizingMaskIntoConstraints = false
    previousButton.translatesAutoresizingMaskIntoConstraints = false
    displayButtonsView.translatesAutoresizingMaskIntoConstraints = false

    addSubview(displayButtonsView)
    addSubview(miniPlayerGotTouchedView)
    addSubview(artworkImage)
    addSubview(titleLabel)
    addSubview(subtitleLabel)
    addSubview(previousButton)
    addSubview(playButton)
    addSubview(nextButton)

    NSLayoutConstraint.activate([
      miniPlayerGotTouchedView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
      miniPlayerGotTouchedView.heightAnchor.constraint(equalTo: heightAnchor),
      miniPlayerGotTouchedView.bottomAnchor.constraint(equalTo: bottomAnchor),
      miniPlayerGotTouchedView.trailingAnchor.constraint(
        equalTo: displayButtonsView.leadingAnchor,
        constant: -8
      ),

      artworkImage.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      artworkImage.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      artworkImage.widthAnchor.constraint(equalTo: artworkImage.heightAnchor),
      // horizontal positions of artwork, play, next and display buttons: refreshControlsLayout

      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      titleLabel.bottomAnchor.constraint(equalTo: playButton.centerYAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: artworkImage.trailingAnchor, constant: 8),
      titleLabel.trailingAnchor.constraint(
        equalTo: displayButtonsView.leadingAnchor,
        constant: -8
      ),

      subtitleLabel.topAnchor.constraint(equalTo: playButton.centerYAnchor, constant: 0),
      subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      subtitleLabel.leadingAnchor.constraint(equalTo: artworkImage.trailingAnchor, constant: 8),
      subtitleLabel.trailingAnchor.constraint(
        equalTo: displayButtonsView.leadingAnchor,
        constant: -8
      ),

      // without visible buttons the stack has no width
      displayButtonsView.centerYAnchor.constraint(equalTo: artworkImage.centerYAnchor),

      playButton.centerYAnchor.constraint(equalTo: artworkImage.centerYAnchor, constant: 0),
      // playButton width: refreshControlsLayout
      playButton.heightAnchor.constraint(equalTo: playButton.widthAnchor),

      nextButton.centerYAnchor.constraint(equalTo: artworkImage.centerYAnchor, constant: 0),
      nextButton.widthAnchor.constraint(equalToConstant: 30),
      nextButton.heightAnchor.constraint(equalTo: nextButton.widthAnchor),

      previousButton.centerYAnchor.constraint(equalTo: artworkImage.centerYAnchor, constant: 0),
      previousButton.widthAnchor.constraint(equalToConstant: 30),
      previousButton.heightAnchor.constraint(equalTo: previousButton.widthAnchor),
    ])
    refreshControlsLayout()
    refreshPlayer()
    refreshForTraitChange(horizontalSizeClass: traitCollection.horizontalSizeClass)
  }

  public func refreshForTraitChange(horizontalSizeClass: UIUserInterfaceSizeClass) {
    if horizontalSizeClass == .regular {
      titleLabel.font = .systemFont(ofSize: 15.0, weight: .semibold)
      subtitleLabel.font = .systemFont(ofSize: 15.0)
    } else {
      titleLabel.font = .systemFont(ofSize: 13.0, weight: .semibold)
      subtitleLabel.font = .systemFont(ofSize: 12.0)
    }
  }

  @objc
  private func miniPlayerGotTouched(_ recognizer: UITapGestureRecognizer) {
    openPlayerView()
  }

  public func openPlayerView(completion: (() -> ())? = nil) {
    guard let hostVC = AppDelegate.mainWindowHostVC as? UIViewController else { return }
    if let splitVC = hostVC as? SplitVC {
      // Mac: shown as an overlay over the whole window
      splitVC.openPopupPlayer(animated: true, completion: completion)
      return
    }
    let popupPlayer = PopupPlayerVC()
    #if !targetEnvironment(macCatalyst)
      if hostVC.traitCollection.horizontalSizeClass == .regular {
        // a sheet would only be a card in the middle of the screen
        popupPlayer.modalPresentationStyle = .overFullScreen
        popupPlayer.modalPresentationCapturesStatusBarAppearance = true
        hostVC.present(popupPlayer, animated: true, completion: completion)
        return
      }
    #endif
    popupPlayer.modalPresentationStyle = .pageSheet
    if let sheet = popupPlayer.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
      sheet.preferredCornerRadius = 24
    }
    hostVC.present(popupPlayer, animated: true, completion: completion)
  }

  @objc
  private func handleHoverContainerHover(_ recognizer: UIHoverGestureRecognizer) {
    switch recognizer.state {
    case .began, .changed:
      if hoverOverlayView == nil {
        showHoverOverlay()
      }
      timeSlider.isHoverActive = true
    case .cancelled, .ended, .failed:
      hideHoverOverlay()
      timeSlider.isHoverActive = false
    default:
      break
    }
  }

  private func showHoverOverlay() {
    guard hoverOverlayView == nil, liveLabel.isHidden else { return }
    let overlay = createHoverOverlayView()
    addSubview(overlay)
    // Position overlay above artwork/title/subtitle area
    overlay.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      overlay.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 0),
      overlay.trailingAnchor.constraint(equalTo: infoView.trailingAnchor, constant: 0),
      overlay.topAnchor.constraint(equalTo: infoView.topAnchor, constant: 0),
      overlay.heightAnchor.constraint(equalTo: infoView.heightAnchor),
    ])
    hoverOverlayView = overlay
  }

  private func hideHoverOverlay() {
    guard let overlay = hoverOverlayView else { return }
    overlay.removeFromSuperview()
    hoverOverlayView = nil
    infoView.layer.mask = nil
  }

  private func createHoverOverlayView() -> UIView {
    // make the info view transparent
    let mask = CAGradientLayer()
    mask.frame = infoView.bounds
    mask.colors = [
      UIColor.white.withAlphaComponent(0).cgColor,
      UIColor.white.withAlphaComponent(0).cgColor,
    ]
    mask.startPoint = CGPoint(x: 0.0, y: 0.0)
    mask.endPoint = CGPoint(x: 1.0, y: 0.0)
    mask.locations = [
      0.0, 1.0,
    ]
    infoView.layer.mask = mask

    let overlay = UIView()
    overlay.isUserInteractionEnabled = false

    let innerView = UIView(frame: .zero)
    innerView.addSubview(playTypeIcon)
    innerView.addSubview(audioInfoLabel)

    let outerView = UIView(frame: .zero)
    outerView.addSubview(innerView)

    overlay.addSubview(elapsedTimeLabel)
    overlay.addSubview(outerView)
    overlay.addSubview(remainingTimeLabel)

    innerView.translatesAutoresizingMaskIntoConstraints = false
    outerView.translatesAutoresizingMaskIntoConstraints = false
    elapsedTimeLabel.translatesAutoresizingMaskIntoConstraints = false
    playTypeIcon.translatesAutoresizingMaskIntoConstraints = false
    audioInfoLabel.translatesAutoresizingMaskIntoConstraints = false
    remainingTimeLabel.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      playTypeIcon.leadingAnchor.constraint(equalTo: innerView.leadingAnchor, constant: 0),
      playTypeIcon.centerYAnchor.constraint(equalTo: innerView.centerYAnchor, constant: 0),
      playTypeIcon.trailingAnchor.constraint(equalTo: audioInfoLabel.leadingAnchor, constant: -8),
      playTypeIcon.widthAnchor.constraint(equalToConstant: 14),
      playTypeIcon.heightAnchor.constraint(equalToConstant: 14),
      audioInfoLabel.centerYAnchor.constraint(equalTo: innerView.centerYAnchor, constant: 0),
      audioInfoLabel.trailingAnchor.constraint(equalTo: innerView.trailingAnchor, constant: 0),

      innerView.centerXAnchor.constraint(equalTo: outerView.centerXAnchor, constant: 0),
      innerView.centerYAnchor.constraint(equalTo: outerView.centerYAnchor, constant: 0),
      innerView.heightAnchor.constraint(equalTo: outerView.heightAnchor, constant: 0),

      outerView.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: 0),
      outerView.heightAnchor.constraint(equalTo: overlay.heightAnchor, constant: 0),
      elapsedTimeLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 0),
      elapsedTimeLabel.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: 0),
      elapsedTimeLabel.widthAnchor.constraint(equalToConstant: 60),
      outerView.leadingAnchor.constraint(equalTo: elapsedTimeLabel.trailingAnchor, constant: 0),
      outerView.trailingAnchor.constraint(equalTo: remainingTimeLabel.leadingAnchor, constant: 0),
      remainingTimeLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: 0),
      remainingTimeLabel.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: 0),
      remainingTimeLabel.widthAnchor.constraint(equalToConstant: 60),
    ])
    return overlay
  }

  func refreshPlayer() {
    if traitCollection.userInterfaceStyle == .dark {
      titleLabel.textColor = .white
      subtitleLabel.textColor = .white
    } else {
      titleLabel.textColor = .black
      subtitleLabel.textColor = .black
    }
    playerHandler?.refreshCurrentlyPlayingInfo(
      artworkImage: artworkImage,
      titleLabel: titleLabel,
      artistLabel: subtitleLabel
    )
    playerHandler?.refreshArtwork(artworkImage: artworkImage)
    refreshPlayButton()
    playerHandler?.refreshPrevNextButtons(previousButton: previousButton, nextButton: nextButton)
    #if targetEnvironment(macCatalyst) // ok
      // on iPad the buttons only open the popup player and show no state
      playerHandler?.refreshDisplayPlaylistButton(displayPlaylistButton: playlistButton)
    #endif
    playerHandler?.refreshRepeatButton(repeatButton: repeatButton)
    playerHandler?.refreshShuffleButton(shuffleButton: shuffleButton)
    playerHandler?.refreshTimeInfo(
      timeSlider: timeSlider,
      elapsedTimeLabel: elapsedTimeLabel,
      remainingTimeLabel: remainingTimeLabel,
      audioInfoLabel: audioInfoLabel,
      playTypeIcon: playTypeIcon,
      liveLabel: liveLabel
    )
    refreshMoreButton()
    refreshTrailingButtons()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public lazy var glassContainer: UIVisualEffectView = {
    let container = UIVisualEffectView()
    let glassEffect = UIGlassEffect(style: .regular)
    glassEffect.isInteractive = false
    container.effect = glassEffect
    container.contentView.addSubview(self)

    container.translatesAutoresizingMaskIntoConstraints = false
    self.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
      container.trailingAnchor.constraint(equalTo: trailingAnchor),
      container.topAnchor.constraint(equalTo: topAnchor, constant: 0),
      container.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    return container
  }()
}

// MARK: MusicPlayable

extension MiniPlayerView: MusicPlayable {
  func didStartPlayingFromBeginning() {}

  func didStartPlaying() {
    refreshPlayer()
    refreshVisibility()
  }

  func didPause() {
    refreshPlayer()
  }

  func didStopPlaying() {
    refreshPlayer()
    refreshVisibility()
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
    refreshVisibility()
  }

  func didArtworkChange() {
    playerHandler?.refreshCurrentlyPlayingInfo(
      artworkImage: artworkImage,
      titleLabel: titleLabel,
      artistLabel: subtitleLabel
    )
  }

  func didNowPlayingInfoChange() {
    playerHandler?.refreshCurrentlyPlayingInfo(
      artworkImage: artworkImage,
      titleLabel: titleLabel,
      artistLabel: subtitleLabel
    )
  }

  func didShuffleChange() {
    playerHandler?.refreshShuffleButton(shuffleButton: shuffleButton)
  }

  func didRepeatChange() {
    playerHandler?.refreshRepeatButton(repeatButton: repeatButton)
  }

  func didPlaybackRateChange() {}
}

//
//  SongTableCell.swift
//  Amperfy
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

import AmperfyKit
import UIKit

typealias GetPlayContextFromTableCellCallback = (UITableViewCell) -> PlayContext?
typealias GetPlayerIndexFromTableCellCallback = (PlayableTableCell) -> PlayerIndex?

// MARK: - DisplayMode

enum DisplayMode {
  case normal
  case selection
  case reorder
  case add
}

// MARK: - PlayableTableCellStyle

enum PlayableTableCellStyle {
  case none
  case trackNumber
  case artwork
}

// MARK: - PlayableTableCell

@MainActor
class PlayableTableCell: BasicTableCell {
  @IBOutlet
  weak var titleLabel: UILabel!
  @IBOutlet
  weak var artistLabel: UILabel!
  @IBOutlet
  weak var durationLabel: UILabel!
  @IBOutlet
  weak var entityImage: EntityImageView!
  @IBOutlet
  weak var trackNumberLabel: UILabel!
  @IBOutlet
  weak var trackNumberContainer: UIView!
  @IBOutlet
  weak private var cacheIconImage: UIImageView!
  @IBOutlet
  weak private var favoriteIconImage: UIImageView!

  /// vertical position of the title/artist block in the row
  @IBOutlet
  weak var labelsCenterYConstraint: NSLayoutConstraint!

  /// aligns the favorite icon with the track number (centered on the title line), otherwise it is
  /// centered in the row
  @IBOutlet
  weak var favoriteTitleAlignConstraint: NSLayoutConstraint!
  /// trailing gap of the favorite icon to the leading margin, 2pt smaller with track number
  @IBOutlet
  weak var favoriteTrailingConstraint: NSLayoutConstraint!
  @IBOutlet
  weak var optionsButton: UIButton!
  @IBOutlet
  weak var deleteButton: UIButton!
  @IBOutlet
  weak var playOverButton: UIButton!
  @IBOutlet
  weak var playOverButtonLeadingConstraint: NSLayoutConstraint!

  // fixed sizes in the xib that scale with the text size (see `applyTextSize`)
  @IBOutlet
  private var titleHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var artistHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var labelsHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var trackNumberHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var trackNumberContainerWidthConstraint: NSLayoutConstraint!
  @IBOutlet
  private var cacheIconHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var favoriteIconHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var favoriteIconWidthConstraint: NSLayoutConstraint!

  private var ratingStackView: UIStackView?
  /// visible gap between the trailing accessories (stars, cache icon, duration, options)
  private static let accessoryGapRegular: CGFloat = 16
  private static let accessoryGapCompact: CGFloat = 10
  private var ratingStarViews: [UIImageView] = []

  /// The cover is square and as high as the row content. All row heights scale with the
  /// user's text size (see `TextScaling`).
  static var rowHeight: CGFloat { scaledRowHeight(contentHeight: 42) }
  /// For the song list, with a larger cover
  static var rowHeightLarge: CGFloat { scaledRowHeight(contentHeight: 56) }
  /// rows with the artist label hidden, only the title line remains
  static var singleLineRowHeight: CGFloat { scaledRowHeight(contentHeight: 40) }
  private static let touchAnimation = 0.4

  /// Single rule for the cell and the row height of its table view.
  static func isCreatorHidden(of playable: AbstractPlayable, hiddenCreatorName: String?) -> Bool {
    hiddenCreatorName != nil && playable.creatorName == hiddenCreatorName
  }

  private var style = PlayableTableCellStyle.none
  private var playerIndexCb: GetPlayerIndexFromTableCellCallback?
  private var playContextCb: GetPlayContextFromTableCellCallback?
  private var playable: AbstractPlayable?
  private var download: Download?
  /// the file of the playable is downloading right now, the cache icon is animated meanwhile
  private var isDownloadRunning = false
  private var isCacheIconAnimating = false
  private weak var rootView: UIViewController?
  private var playIndicator: PlayIndicator?
  private var isDislayAlbumTrackNumberStyle: Bool = false
  private var isAlbumSubtitle: Bool = false
  private var hiddenCreatorName: String?
  private var displayMode: DisplayMode = .normal
  private var hoverGestureRecognizer: UIHoverGestureRecognizer!
  private var tapGestureRecognizer: UITapGestureRecognizer!
  private var isHovered = false
  private let hoverBackgroundView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.6)
    view.layer.cornerRadius = CornerRadius.medium.asCGFloat
    view.isUserInteractionEnabled = false
    view.isHidden = true
    return view
  }()

  private var isNotificationRegistered = false

  public var isMarked = false
  private var isDeleteButtonAllowedToBeVisible: Bool {
    (traitCollection.userInterfaceIdiom == .mac) && (playerIndexCb != nil)
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    // This must be called in Main thread
    MainActor.assumeIsolated {
      applyTextSize()
      registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _) in
        // duration, cache icon and label spacing depend on the size class, e.g. after resizing a window
        self.applyTextSize()
        self.refreshCacheAndDuration(userSettings: self.appDelegate.storage.settings.user)
      }
      registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
        self.applyTextSize()
      }
      registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
        self.playIndicator?.applyStyle()
      }
      playContextCb = nil
      for name in [
        Notification.Name.downloadStarted,
        .downloadFinishedSuccess,
        .downloadFinishedFailure,
      ] {
        appDelegate.notificationHandler.register(
          self,
          selector: #selector(downloadStateChanged(notification:)),
          name: name,
          object: nil
        )
      }
      hoverGestureRecognizer = UIHoverGestureRecognizer(
        target: self,
        action: #selector(hovering(_:))
      )
      self.addGestureRecognizer(hoverGestureRecognizer)
      isHovered = false
      tapGestureRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(tap)
      )
      // macOS: play on double click, iOS: play on single tap
      #if targetEnvironment(macCatalyst) // ok
        tapGestureRecognizer.numberOfTapsRequired = 2
      #else
        tapGestureRecognizer.numberOfTapsRequired = 1
      #endif
      self.addGestureRecognizer(tapGestureRecognizer)

      style = PlayableTableCellStyle.none
      deleteButton.tintColor = .red
      playOverButton.layer.cornerRadius = CornerRadius.small.asCGFloat
      selectionStyle = .none
      setupTrailingAccessories()
      setupRatingStars()
      resetForReuse()
    }
  }

  private func setupTrailingAccessories() {
    // the duration is as wide as its text, so the gaps around it don't depend on the text width
    durationLabel.setContentHuggingPriority(.required, for: .horizontal)
    // with a large text size the duration shrinks its font instead of pushing the title away
    durationLabel.setContentCompressionResistancePriority(.defaultHigh + 10, for: .horizontal)
    durationLabel.adjustsFontSizeToFitWidth = true
    if let accessoriesStack = durationLabel.superview {
      accessoriesStack.widthAnchor.constraint(
        lessThanOrEqualTo: contentView.widthAnchor,
        multiplier: 0.5
      ).isActive = true
    }
  }

  private func setupRatingStars() {
    let stackView = UIStackView()
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.distribution = .fill
    stackView.translatesAutoresizingMaskIntoConstraints = false

    // Create 5 star image views
    for _ in 0 ..< 5 {
      let starView = UIImageView()
      starView.contentMode = .scaleAspectFit
      starView.translatesAutoresizingMaskIntoConstraints = false
      starView.image = .starFill
      let starSize: CGFloat = 10
      NSLayoutConstraint.activate([
        starView.widthAnchor.constraint(equalToConstant: starSize),
        starView.heightAnchor.constraint(equalToConstant: starSize),
      ])
      ratingStarViews.append(starView)
      stackView.addArrangedSubview(starView)
    }

    // left of the cache icon in the trailing accessories stack, collapses when hidden
    if let accessoriesStack = cacheIconImage.superview as? UIStackView,
       let cacheIconIndex = accessoriesStack.arrangedSubviews.firstIndex(of: cacheIconImage) {
      accessoriesStack.insertArrangedSubview(stackView, at: cacheIconIndex)
    }

    ratingStackView = stackView
  }

  private func updateRatingDisplay(rating: Int) {
    // hidden stars collapse in the stack view
    for (index, starView) in ratingStarViews.enumerated() {
      starView.isHidden = index >= rating
    }

    // Only show rating if song has a rating > 0
    ratingStackView?.isHidden = (rating == 0)
  }

  func resetForReuse() {
    isAlbumArtworkFallback = false
    playIndicator?.reset()
    deleteButton.isHidden = true
    playOverButton.isHidden = true
    trackNumberLabel.isHidden = false
    ratingStackView?.isHidden = true
    // Reset all stars for next use
    for starView in ratingStarViews {
      starView.isHidden = false
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    resetForReuse()
  }

  private func register() {
    guard !isNotificationRegistered else { return }
    appDelegate.notificationHandler.register(
      self,
      selector: #selector(playerPlay(notification:)),
      name: .playerPlay,
      object: nil
    )
    appDelegate.notificationHandler.register(
      self,
      selector: #selector(playerPause(notification:)),
      name: .playerPause,
      object: nil
    )
    appDelegate.notificationHandler.register(
      self,
      selector: #selector(playerStop(notification:)),
      name: .playerStop,
      object: nil
    )
    isNotificationRegistered = true
  }

  /// Shows the album artwork until the song's own artwork is downloaded, e.g. where many songs of
  /// albums with already downloaded covers appear at once.
  var isAlbumArtworkFallback = false

  /// Black or white color for secondary texts (track number, artist, duration) on custom backgrounds.
  var contentColorOverride: UIColor? {
    didSet {
      playIndicator?.colorOverride = contentColorOverride
      playIndicator?.applyStyle()
    }
  }

  func display(
    playable: AbstractPlayable,
    displayMode: DisplayMode = .normal,
    playContextCb: GetPlayContextFromTableCellCallback?,
    rootView: UIViewController,
    playerIndexCb: GetPlayerIndexFromTableCellCallback? = nil,
    isDislayAlbumTrackNumberStyle: Bool = false,
    isAlbumSubtitle: Bool = false,
    hiddenCreatorName: String? = nil,
    download: Download? = nil,
    isMarked: Bool = false
  ) {
    if playIndicator?.rootViewTypeName != rootView.typeName {
      playIndicator = PlayIndicator(rootViewTypeName: rootView.typeName)
      playIndicator?.colorOverride = contentColorOverride
    }

    self.playable = playable
    self.displayMode = displayMode
    self.playContextCb = playContextCb
    self.playerIndexCb = playerIndexCb
    self.rootView = rootView
    self.isDislayAlbumTrackNumberStyle = isDislayAlbumTrackNumberStyle
    self.isAlbumSubtitle = isAlbumSubtitle
    self.hiddenCreatorName = hiddenCreatorName
    self.download = download
    self.isMarked = isMarked
    isDownloadRunning = playable.isDownloading

    hoverGestureRecognizer.isEnabled = (displayMode == .normal)
    isHovered = false
    register()
    tapGestureRecognizer.isEnabled = (displayMode == .normal)
    backgroundColor = .clear
    refresh()
  }

  /// Scales the fixed label, icon and duration sizes of the xib with the user's text size.
  /// The fonts scale themselves (`ScaledLabel`), the cover follows the row height.
  private func applyTextSize() {
    let traits = traitCollection
    let scaled = { (value: CGFloat) in self.scaledConstant(value) }
    // iPad shows title and artist side by side with the same height, the Mac keeps the iPhone sizes
    let isRegularWidth = traits.horizontalSizeClass == .regular
    let isLargeRegularWidth = isRegularWidth && traits.userInterfaceIdiom != .mac
    titleHeightConstraint.constant = scaled(22)
    artistHeightConstraint.constant = scaled(isLargeRegularWidth ? 22 : 16)
    labelsHeightConstraint.constant = scaled(38)
    trackNumberHeightConstraint.constant = scaled(22)
    trackNumberContainerWidthConstraint.constant = scaled(32)
    cacheIconHeightConstraint.constant = scaled(isRegularWidth ? 17 : 15)
    favoriteIconHeightConstraint.constant = scaled(12)
    favoriteIconWidthConstraint.constant = scaled(12)
  }

  private func configureStyle(playable: AbstractPlayable, newStyle: PlayableTableCellStyle) {
    // adjust style only if it has changed
    guard newStyle != style else { return }

    switch newStyle {
    case .trackNumber:
      configureTrackNumberLabel()
      playIndicator?.willDisplayIndicatorCB = { [weak self] () in
        guard let self = self else { return }
        trackNumberLabel.text = ""
      }
      playIndicator?.willHideIndicatorCB = { [weak self] () in
        guard let self = self else { return }
        configureTrackNumberLabel()
      }
      trackNumberContainer.isHidden = false
      entityImage.isHidden = true
      favoriteTitleAlignConstraint.priority = UILayoutPriority(999)
      favoriteTrailingConstraint.constant = -2
    case .artwork:
      playIndicator?.willDisplayIndicatorCB = nil
      playIndicator?.willHideIndicatorCB = nil
      trackNumberContainer.isHidden = true
      entityImage.isHidden = false
      favoriteTitleAlignConstraint.priority = UILayoutPriority(1)
      favoriteTrailingConstraint.constant = 4
    case .none:
      break // do nothing
    }
  }

  override var usesSystemHorizontalMargins: Bool { true }

  /// separator starts at the title/artist text instead of the track number
  override var separatorLeadingView: UIView? { isDislayAlbumTrackNumberStyle ? titleLabel : nil }

  private func configurePlayIndicator(playable: AbstractPlayable?) {
    guard let playable = playable else {
      playIndicator?.reset()
      return
    }

    if isDislayAlbumTrackNumberStyle {
      playIndicator?.display(playable: playable, rootView: trackNumberLabel)
    } else {
      if playerIndexCb == nil {
        playIndicator?.display(playable: playable, rootView: entityImage, isOnImage: true)
      } else {
        // don't show play indicator on PopupPlayer
        playIndicator?.reset()
      }
    }
  }

  func refresh() {
    guard let playable = playable else { return }
    let themePreference = appDelegate.storage.settings.accounts
      .getSetting(playable.account?.info).read.themePreference
    let userSettings = appDelegate.storage.settings.user
    titleLabel.text = playable.title
    // the second line shows the album instead of the artist, e.g. on the screen of that artist
    if isAlbumSubtitle, let albumName = playable.asSong?.album?.name {
      artistLabel.text = albumName
    } else {
      artistLabel.text = playable.creatorName
    }
    // e.g. on the album screen, where the album artist is already shown in the header
    artistLabel.isHidden = Self.isCreatorHidden(of: playable, hiddenCreatorName: hiddenCreatorName)
    // the title has more free space above its glyphs than the artist below, lift both lines a bit
    labelsCenterYConstraint.constant = artistLabel.isHidden ? 0 : -1

    configureStyle(
      playable: playable,
      newStyle: isDislayAlbumTrackNumberStyle ? .trackNumber : .artwork
    )
    entityImage.display(
      theme: themePreference,
      container: playable,
      fallbackEntity: isAlbumArtworkFallback ? playable.asSong?.album : nil
    )
    configurePlayIndicator(playable: playable)

    if displayMode == .selection {
      let img = UIImageView(image: isMarked ? .checkmark : .circle)
      img.tintColor = isMarked ? themePreference.asColor : .secondaryLabel
      accessoryView = img
    } else if displayMode == .add {
      let img = UIImageView(image: isMarked ? .checkmark : .plusCircle)
      img.tintColor = themePreference.asColor
      accessoryView = img
    } else if displayMode == .reorder || playerIndexCb != nil {
      let img = UIImageView(image: .bars)
      img.tintColor = .label
      accessoryView = img
    } else if let download = download {
      if download.error != nil {
        let img = UIImageView(image: .exclamation)
        img.tintColor = .label
        accessoryView = img
      } else if download.isFinishedSuccessfully {
        let img = UIImageView(image: .check)
        img.tintColor = .label
        accessoryView = img
      } else if download.isDownloading {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.tintColor = .label
        accessoryView = spinner
      } else {
        accessoryView = nil
      }
    } else {
      accessoryView = nil
    }

    refreshSubtitleColor()
    refreshCacheAndDuration(userSettings: userSettings)

    // Update rating display for songs (only if setting is enabled)
    if userSettings.isShowRating, let song = playable.asSong {
      updateRatingDisplay(rating: song.rating)
    } else {
      ratingStackView?.isHidden = true
    }
  }

  private func configureTrackNumberLabel() {
    guard let playable = playable else { return }
    trackNumberLabel.text = playable.trackInDisc > 0 ? "\(playable.trackInDisc)" : ""
  }

  func refreshCacheAndDuration(userSettings: UserSettings) {
    guard let playable = playable else { return }
    favoriteIconImage.isHidden = !playable.isFavorite

    // the duration is always shown in regular width, in compact width only if enabled in settings
    let isDurationVisible = !playable.isRadio &&
      (
        traitCollection.horizontalSizeClass == .regular ||
          userSettings.isShowSongDuration
      )
    let isDisplayOptionButton = (playContextCb != nil) && (playerIndexCb == nil)
    optionsButton.isHidden = !isDisplayOptionButton
    if isDisplayOptionButton {
      optionsButton.showsMenuAsPrimaryAction = true
      optionsButton.imageView?.tintColor = .label
      if rootView != nil {
        let playContext = playContextCb != nil ? { [weak self] in
          self.flatMap { $0.playContextCb?($0) }
        } : nil
        let playIndex = playerIndexCb != nil ? { [weak self] in
          self.flatMap { $0.playerIndexCb?($0) }
        } : nil
        // the menu belongs to the cell, which must not keep the screen alive
        optionsButton.menu = UIMenu.lazyMenu { [weak self] in
          guard let rootView = self?.rootView else { return [] }
          return EntityPreviewActionBuilder(
            container: playable,
            on: rootView,
            playContextCb: playContext,
            playerIndexCb: playIndex
          ).createMenuActions()
        }
      }
    }

    // The rating stars, cache icon, duration and options button are arranged in a stack view,
    // hidden ones collapse. The labels end before that stack.
    refreshCacheIcon(playable: playable)
    durationLabel.isHidden = !isDurationVisible
    if isDurationVisible {
      durationLabel.text = playable.duration.asColonDurationString
    }
    refreshAccessorySpacing()
  }

  /// Equal visible gaps between the trailing accessories. The ellipsis sits inside the wider
  /// options button, its empty space is subtracted from the gap before it.
  private func refreshAccessorySpacing() {
    guard let accessoriesStack = cacheIconImage.superview as? UIStackView else { return }
    let gap = traitCollection.horizontalSizeClass == .regular ?
      Self.accessoryGapRegular : Self.accessoryGapCompact
    let gapBeforeOptions = optionsButton.isHidden ? gap : max(0, gap - optionsButtonImageInset)
    accessoriesStack.spacing = gap
    accessoriesStack.setCustomSpacing(
      durationLabel.isHidden ? gapBeforeOptions : gap,
      after: cacheIconImage
    )
    accessoriesStack.setCustomSpacing(gapBeforeOptions, after: durationLabel)
  }

  /// Empty space left of the ellipsis inside the fixed width options button. The xib shifts the
  /// image 2 pt to the left (right image inset of 4 pt).
  private var optionsButtonImageInset: CGFloat {
    let buttonWidth = optionsButton.constraints
      .first { $0.firstAttribute == .width && $0.secondItem == nil }?.constant ?? 0
    let imageWidth = optionsButton.currentImage?.size.width ?? 0
    guard buttonWidth > 0, imageWidth > 0 else { return 0 }
    return max(0, (buttonWidth - imageWidth) / 2 - 2)
  }

  /// Shows the arrow if the playable is cached and an animated dotted arrow while it is downloading.
  private func refreshCacheIcon(playable: AbstractPlayable) {
    let isDownloading = !playable.isCached && isDownloadRunning
    let isVisible = playable.isCached || isDownloading
    // In regular width (iPad, Mac) the icon keeps its space when invisible, so the stars stay
    // aligned. Compact width has no room to spare. Playables that can't be cached never need it.
    let isSpaceKept = traitCollection.horizontalSizeClass == .regular && !playable.isRadio
    cacheIconImage.isHidden = !isVisible && !isSpaceKept
    cacheIconImage.alpha = isVisible ? 1 : 0
    guard isDownloading != isCacheIconAnimating else { return }
    isCacheIconAnimating = isDownloading
    if isDownloading {
      cacheIconImage.image = .downloading
      cacheIconImage.addSymbolEffect(.pulse, options: .repeating)
    } else {
      cacheIconImage.removeAllSymbolEffects()
      cacheIconImage.image = .download
    }
  }

  @objc
  private func downloadStateChanged(notification: Notification) {
    guard let downloadNotification = DownloadNotification.fromNotification(notification),
          let playable, playable.uniqueID == downloadNotification.id
    else { return }
    isDownloadRunning = (notification.name == .downloadStarted)
    refreshCacheAndDuration(userSettings: appDelegate.storage.settings.user)
  }

  private func refreshSubtitleColor() {
    // follows the title's font color
    favoriteIconImage.tintColor = contentColorOverride ?? UIColor.label
    for starView in ratingStarViews {
      starView.tintColor = contentColorOverride ?? UIColor.label
    }
    if let contentColor = contentColorOverride {
      // screens with a custom background color need explicit, readable text colors
      let secondaryColor = contentColor.withAlphaComponent(0.7)
      cacheIconImage.tintColor = secondaryColor
      artistLabel.textColor = secondaryColor
      durationLabel.textColor = secondaryColor
      trackNumberLabel.textColor = secondaryColor
    } else if playerIndexCb != nil {
      cacheIconImage.tintColor = UIColor.label
      artistLabel.textColor = UIColor.label
      durationLabel.textColor = UIColor.label
    } else {
      cacheIconImage.tintColor = UIColor.secondaryLabel
      artistLabel.textColor = UIColor.secondaryLabel
      durationLabel.textColor = UIColor.secondaryLabel
    }
  }

  func playThisSong() {
    guard let playable = playable else { return }
    if let playerIndex = playerIndexCb?(self) {
      appDelegate.player.play(playerIndex: playerIndex)
    } else if let context = playContextCb?(self),
              playable.isCached || appDelegate.storage.settings.user.isOnlineMode {
      animateActivation()
      hideSearchBarKeyboardInRootView()
      Haptics.success.vibrate(isHapticsEnabled: appDelegate.storage.settings.user.isHapticsEnabled)
      appDelegate.player.play(context: context)
    }
  }

  private func hideSearchBarKeyboardInRootView() {
    if let basicRootView = rootView as? BasicTableViewController {
      basicRootView.searchController.searchBar.endEditing(true)
    }
  }

  @IBAction
  func deleteButtonPressed(_ sender: Any) {
    if let playerIndexCb = playerIndexCb,
       let playerIndex = playerIndexCb(self),
       let queueVC = rootView as? QueueVC,
       let tableView = queueVC.tableView {
      queueVC.tableView(tableView, commit: .delete, forRowAt: playerIndex.asIndexPath)
    }
    if let playerIndexCb = playerIndexCb,
       let playerIndex = playerIndexCb(self),
       let popupPlayerVC = rootView as? PopupPlayerVC,
       let tableView = popupPlayerVC.tableView {
      popupPlayerVC.tableView(tableView, commit: .delete, forRowAt: playerIndex.asIndexPath)
    }
  }

  @IBAction
  func playButtonPressed(_ sender: Any) {
    if appDelegate.player.currentlyPlaying == playable,
       appDelegate.player.isPlaying {
      appDelegate.player.pause()
    } else if appDelegate.player.currentlyPlaying == playable {
      appDelegate.player.play()
    } else {
      playThisSong()
    }
    refreshHoverStyle()
  }

  /// 1.0 keeps the table's background color, smaller values make the hover darker.
  private static let hoverBrightnessFactor: CGFloat = 0.8

  /// The hover uses the background color of the table view the cell is displayed in, darkened.
  private var tableBackgroundColor: UIColor {
    (enclosingTableView?.backgroundColor ?? .secondarySystemGroupedBackground)
      .darkened(brightnessFactor: Self.hoverBrightnessFactor)
  }

  private func installHoverBackgroundIfNeeded() {
    guard hoverBackgroundView.superview == nil else { return }
    contentView.insertSubview(hoverBackgroundView, at: 0)
    let guide = contentView.layoutMarginsGuide
    NSLayoutConstraint.activate([
      hoverBackgroundView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
      hoverBackgroundView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: 10),
      hoverBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
      hoverBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  func refreshHoverStyle() {
    if isHovered {
      playIndicator?.reset()
      if isDeleteButtonAllowedToBeVisible {
        deleteButton.isHidden = false
      } else {
        var buttonImg = UIImage()
        if appDelegate.player.currentlyPlaying == playable,
           appDelegate.player.isPlaying {
          if appDelegate.player.isStopInsteadOfPause {
            buttonImg = UIImage.stop
          } else {
            buttonImg = UIImage.pause
          }
        } else {
          buttonImg = UIImage.play
        }
        // the button is inset in the track number slot, but covers the whole cover
        playOverButtonLeadingConstraint.constant = isDislayAlbumTrackNumberStyle ? 12 : 0
        if isDislayAlbumTrackNumberStyle {
          trackNumberLabel.isHidden = true
          playOverButton.layer.backgroundColor = nil
          playOverButton.imageView?.tintColor = appDelegate.storage.settings.accounts
            .getSetting(playable?.account?.info).read.themePreference
            .asColor
        } else {
          playOverButton.layer.backgroundColor = UIColor.imageOverlayBackground.cgColor
          playOverButton.imageView?.tintColor = .white
        }
        playOverButton.setImage(buttonImg, for: UIControl.State.normal)
        playOverButton.isHidden = false
      }
      cacheIconImage.tintColor = appDelegate.storage.settings.accounts
        .getSetting(playable?.account?.info).read.themePreference.asColor
      optionsButton.imageView?.tintColor = appDelegate.storage.settings.accounts
        .getSetting(playable?.account?.info).read.themePreference.asColor
      if isDislayAlbumTrackNumberStyle {
        // translucent hover limited to the content margins instead of the full cell width
        installHoverBackgroundIfNeeded()
        hoverBackgroundView.backgroundColor = tableBackgroundColor.withAlphaComponent(0.6)
        hoverBackgroundView.isHidden = false
      } else {
        backgroundColor = (rootView is PopupPlayerVC) ?
          tableBackgroundColor.withAlphaComponent(0.2) :
          tableBackgroundColor
      }
    } else {
      playOverButton.isHidden = true
      if isDislayAlbumTrackNumberStyle {
        trackNumberLabel.isHidden = false
      }
      configurePlayIndicator(playable: playable)
      deleteButton.isHidden = true
      refreshSubtitleColor()
      optionsButton.imageView?.tintColor = .label
      backgroundColor = .clear
      hoverBackgroundView.isHidden = true
    }
  }

  @objc
  func hovering(_ recognizer: UIHoverGestureRecognizer) {
    switch recognizer.state {
    case .began:
      isHovered = true
      refreshHoverStyle()
    case .ended:
      isHovered = false
      refreshHoverStyle()
    default:
      if !isHovered {
        isHovered = true
        refreshHoverStyle()
      }
    }
  }

  @objc
  func tap(sender: UITapGestureRecognizer) {
    switch sender.state {
    case .ended:
      if displayMode == .normal {
        playThisSong()
      }
    default:
      break
    }
  }

  @objc
  private func playerPlay(notification: Notification) {
    guard isHovered else { return }
    refreshHoverStyle()
  }

  @objc
  private func playerPause(notification: Notification) {
    guard isHovered else { return }
    refreshHoverStyle()
  }

  @objc
  private func playerStop(notification: Notification) {
    guard isHovered else { return }
    refreshHoverStyle()
  }
}

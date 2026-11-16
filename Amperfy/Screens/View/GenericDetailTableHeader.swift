//
//  GenericDetailTableHeader.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 19.02.22.
//  Copyright (c) 2022 Maximilian Bauer. All rights reserved.
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

// MARK: - DetailHeaderConfiguration

struct DetailHeaderConfiguration {
  var entityContainer: PlayableContainable
  // weak: the header is part of the table of this screen
  weak var rootView: UIViewController?
  weak var tableView: UITableView?
  var playShuffleInfoConfig: PlayShuffleInfoConfiguration?
  var descriptionText: String?
}

// MARK: - GenericDetailTableHeader

class GenericDetailTableHeader: UIView {
  @IBOutlet
  weak var entityImage: EntityImageView!
  @IBOutlet
  weak var titleLabel: UILabel!
  @IBOutlet
  weak var nameTextField: UITextField!
  @IBOutlet
  weak var subtitleView: UIView!
  @IBOutlet
  weak var subtitleLabel: UILabel!
  @IBOutlet
  weak var infoLabel: UILabel!
  @IBOutlet
  weak var playShuffleInfoPlaceholderStack: UIStackView!
  @IBOutlet
  weak var descriptionLabel: UILabel!
  @IBOutlet
  weak var playShuffleInfoContainerView: UIView!

  @IBOutlet
  weak var titlePlayButtonContainerHeightConstraint: NSLayoutConstraint!

  var playShuffleInfoView: LibraryElementDetailTableHeaderView?
  var isEditing = false

  /// Album rating below the info text, display only
  private let ratingRow = UIView()
  private let ratingStack = UIStackView()
  private var ratingStarViews: [UIImageView] = []
  private var ratingLeadingConstraint: NSLayoutConstraint?
  private var ratingCenterXConstraint: NSLayoutConstraint?
  private static let ratingStarSize: CGFloat = 12
  private static let ratingTopPadding: CGFloat = 8
  private static var ratingRowHeight: CGFloat { ratingStarSize + ratingTopPadding }

  static let frameHeightCompact: CGFloat = 440.0
  static let frameHeightRegular: CGFloat = 340.0
  static func frameHeight(traitCollection: UITraitCollection) -> CGFloat {
    if traitCollection.horizontalSizeClass == .compact {
      return GenericDetailTableHeader.frameHeightCompact
    } else {
      return GenericDetailTableHeader.frameHeightRegular
    }
  }

  static let frameHeightForDescription: CGFloat = 85.0
  private static let titlePlayButtonContainerHeightCompact: CGFloat = 155.0
  private static let titlePlayButtonContainerHeightWithoutButtons: CGFloat =
    titlePlayButtonContainerHeightCompact - LibraryElementDetailTableHeaderView.frameHeight

  private var config: DetailHeaderConfiguration?

  public static func createTableHeader(configuration: DetailHeaderConfiguration)
    -> GenericDetailTableHeader? {
    guard let rootView = configuration.rootView else { return nil }
    configuration.tableView?.tableHeaderView = UIView(frame: CGRect(
      x: 0,
      y: 0,
      width: rootView.view.bounds.size.width,
      height: GenericDetailTableHeader
        .frameHeight(traitCollection: rootView.traitCollection)
    ))
    let genericDetailTableHeaderView = ViewCreator<GenericDetailTableHeader>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: rootView.view.bounds.size.width,
        height: GenericDetailTableHeader
          .frameHeight(traitCollection: rootView.traitCollection)
      ))!
    genericDetailTableHeaderView.prepare(configuration: configuration)
    configuration.tableView?.tableHeaderView?.addSubview(genericDetailTableHeaderView)
    return genericDetailTableHeaderView
  }

  func prepare(configuration: DetailHeaderConfiguration) {
    config = configuration
    config?.playShuffleInfoConfig?.isEmbeddedInOtherView = true
    titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    nameTextField.setContentCompressionResistancePriority(.required, for: .vertical)
    subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    // Fix attributed text ignores tint
    subtitleLabel.textColor = .tintColor
    infoLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    setupRatingRow()
    layoutMargins = UIView.defaultMarginTopElement
    if let playShuffleInfoConfig = config?.playShuffleInfoConfig {
      playShuffleInfoView = ViewCreator<LibraryElementDetailTableHeaderView>.createFromNib()
      playShuffleInfoPlaceholderStack.addArrangedSubview(playShuffleInfoView!)
      playShuffleInfoView?.prepare(configuration: playShuffleInfoConfig)
      playShuffleInfoContainerView.isHidden = false
    } else {
      playShuffleInfoContainerView.isHidden = true
    }
    if let descriptionText = configuration.descriptionText {
      descriptionLabel.text = descriptionText
      descriptionLabel.isHidden = false
    } else {
      descriptionLabel.isHidden = true
    }
    applyTraitCollectionChange()
    refresh()
    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.applyTraitCollectionChange()
      }
    )
  }

  private func setupRatingRow() {
    ratingRow.isHidden = true
    guard let infoStack = infoLabel.superview as? UIStackView,
          let infoIndex = infoStack.arrangedSubviews.firstIndex(of: infoLabel)
    else { return }
    ratingStack.axis = .horizontal
    ratingStack.alignment = .center
    ratingStack.translatesAutoresizingMaskIntoConstraints = false
    for _ in 0 ..< 5 {
      let starView = UIImageView(image: .starFill)
      starView.contentMode = .scaleAspectFit
      starView.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        starView.widthAnchor.constraint(equalToConstant: Self.ratingStarSize),
        starView.heightAnchor.constraint(equalToConstant: Self.ratingStarSize),
      ])
      ratingStarViews.append(starView)
      ratingStack.addArrangedSubview(starView)
    }
    ratingRow.translatesAutoresizingMaskIntoConstraints = false
    ratingRow.addSubview(ratingStack)
    infoStack.insertArrangedSubview(ratingRow, at: infoIndex + 1)
    // left aligned in regular width, centered in compact width like the info text
    ratingLeadingConstraint = ratingStack.leadingAnchor.constraint(equalTo: ratingRow.leadingAnchor)
    ratingCenterXConstraint = ratingStack.centerXAnchor.constraint(equalTo: ratingRow.centerXAnchor)
    NSLayoutConstraint.activate([
      ratingRow.leadingAnchor.constraint(equalTo: infoStack.leadingAnchor),
      ratingRow.trailingAnchor.constraint(equalTo: infoStack.trailingAnchor),
      ratingStack.topAnchor.constraint(equalTo: ratingRow.topAnchor, constant: Self.ratingTopPadding),
      ratingStack.bottomAnchor.constraint(equalTo: ratingRow.bottomAnchor),
    ])
    ratingRow.isAccessibilityElement = true
  }

  /// Rating of an album, 0 if it isn't shown
  private var displayedRating: Int {
    guard !isEditing, appDelegate.storage.settings.user.isShowRating,
          let album = config?.entityContainer as? Album
    else { return 0 }
    return album.rating
  }

  private func refreshRating() {
    let rating = displayedRating
    for (index, starView) in ratingStarViews.enumerated() {
      starView.isHidden = index >= rating
      starView.tintColor = infoLabel.textColor
    }
    ratingRow.accessibilityLabel = "\(rating) Star\(rating > 1 ? "s" : "")"
    let isVisible = rating > 0
    guard ratingRow.isHidden == isVisible else { return }
    ratingRow.isHidden = !isVisible
    // the compact header height includes the rating row
    applyTraitCollectionChange()
    // the table only picks up a new header height when the header is set again
    if let tableView = config?.tableView, let headerView = tableView.tableHeaderView {
      tableView.tableHeaderView = headerView
    }
  }

  private let coverShadowView = CoverShadowView()

  /// The cover clips its own content, so the shadow is cast by a separate view right behind it.
  /// The view is pinned to the cover, so the shadow never lags behind the cover's frame.
  func enableCoverShadow() {
    guard coverShadowView.superview == nil, let container = entityImage.superview else { return }
    coverShadowView
      .cornerRadiusProvider = { [weak self] in self?.entityImage.layer.cornerRadius ?? 0 }
    container.insertSubview(coverShadowView, belowSubview: entityImage)
    NSLayoutConstraint.activate([
      coverShadowView.leadingAnchor.constraint(equalTo: entityImage.leadingAnchor),
      coverShadowView.trailingAnchor.constraint(equalTo: entityImage.trailingAnchor),
      coverShadowView.topAnchor.constraint(equalTo: entityImage.topAnchor),
      coverShadowView.bottomAnchor.constraint(equalTo: entityImage.bottomAnchor),
    ])
    coverShadowView.fadeInShadow()
  }

  /// Hides the cover but keeps its space, e.g. if a photo is shown behind the header instead.
  var isCoverHidden = false {
    didSet {
      guard isCoverHidden != oldValue, let cover = entityImage.superview else { return }
      cover.alpha = isCoverHidden ? 0 : 1
      cover.isUserInteractionEnabled = !isCoverHidden
      cover.accessibilityElementsHidden = isCoverHidden
    }
  }

  /// Black or white color for the info texts on custom backgrounds.
  func applyContentColor(_ color: UIColor) {
    let secondaryColor = color.withAlphaComponent(0.8)
    infoLabel.textColor = secondaryColor
    descriptionLabel.textColor = secondaryColor
    refreshRating()
  }

  func refresh() {
    guard let config = config else { return }
    let entityContainer = config.entityContainer
    entityImage.display(
      theme: appDelegate.storage.settings.accounts.getSetting(entityContainer.account?.info).read
        .themePreference,
      container: entityContainer,
      cornerRadius: .medium
    )
    if let album = entityContainer as? Album, album.isFavorite {
      titleLabel.attributedText = titleWithFavoriteHeart(album.name)
    } else if hasTitleLink {
      titleLabel.attributedText = titleWithLinkChevron(entityContainer.name)
    } else {
      titleLabel.text = entityContainer.name
    }
    subtitleView.isHidden = entityContainer.subtitle == nil
    subtitleLabel.text = entityContainer.subtitle

    var isCountInfoHidden = false
    if let playShuffleInfoConfig = config.playShuffleInfoConfig {
      isCountInfoHidden = !playShuffleInfoConfig.isInfoAlwaysHidden && playShuffleInfoConfig
        .isShuffleHidden && (traitCollection.horizontalSizeClass == .regular)
    }
    let detailLevel = isCountInfoHidden ? DetailType.noCountInfo : DetailType.long

    let infoText = entityContainer.info(
      for: entityContainer.account?.apiType.asServerApiType,
      details: DetailInfoType(type: detailLevel, settings: appDelegate.storage.settings)
    )
    infoLabel.isHidden = infoText.isEmpty
    infoLabel.text = infoText

    if isEditing {
      titleLabel.isHidden = true
      nameTextField.isHidden = false
      nameTextField.text = entityContainer.name
    } else {
      titleLabel.isHidden = false
      nameTextField.isHidden = true
    }

    refreshRating()
    updateCoverEditOverlay()
    playShuffleInfoView?.refresh()
  }

  /// Marks the title as tappable with a trailing chevron, the owner attaches the tap gesture.
  var hasTitleLink = false {
    didSet { if hasTitleLink != oldValue { refresh() } }
  }

  /// Size of the link chevron relative to the title font size.
  private static let linkChevronRelativeSize: CGFloat = 0.7
  /// Moves the chevron down from the centered position.
  private static let linkChevronYOffset: CGFloat = 4

  /// Title followed by a chevron like the home section headers, centered on the capital letters.
  private func titleWithLinkChevron(_ title: String) -> NSAttributedString {
    let font = titleLabel.font ?? .preferredFont(forTextStyle: .title2)
    let config = UIImage.SymbolConfiguration(
      pointSize: (font.pointSize * Self.linkChevronRelativeSize).rounded(),
      weight: .semibold,
      scale: .small
    )
    let chevron = UIImage(systemName: "chevron.right", withConfiguration: config)?
      .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal) ?? UIImage()
    let attachment = NSTextAttachment(image: chevron)
    attachment.bounds = CGRect(
      x: 0,
      y: ((font.capHeight - chevron.size.height) / 2).rounded() - Self.linkChevronYOffset,
      width: chevron.size.width,
      height: chevron.size.height
    )
    let text = NSMutableAttributedString(string: title + "\u{00A0}")
    text.append(NSAttributedString(attachment: attachment))
    return text
  }

  /// Size of the favorite heart relative to the title font size.
  private static let favoriteHeartRelativeSize: CGFloat = 0.5
  private static let favoriteHeartAlpha: CGFloat = 0.5

  /// Title followed by a small, translucent heart centered on the capital letters.
  /// The heart wraps together with the last word.
  private func titleWithFavoriteHeart(_ title: String) -> NSAttributedString {
    let font = titleLabel.font ?? .preferredFont(forTextStyle: .title2)
    let heart = UIImage.heartFill.applyingSymbolConfiguration(
      UIImage.SymbolConfiguration(
        pointSize: (font.pointSize * Self.favoriteHeartRelativeSize).rounded(),
        weight: .semibold,
        scale: .medium
      )
    ) ?? UIImage.heartFill
    let attachment = NSTextAttachment(image: heart)
    attachment.bounds = CGRect(
      x: 0,
      y: ((font.capHeight - heart.size.height) / 2).rounded(),
      width: heart.size.width,
      height: heart.size.height
    )
    let heartText = NSMutableAttributedString(attachment: attachment)
    heartText.addAttribute(
      .foregroundColor,
      value: (titleLabel.textColor ?? .label).withAlphaComponent(Self.favoriteHeartAlpha),
      range: NSRange(location: 0, length: heartText.length)
    )
    let text = NSMutableAttributedString(string: title + "\u{00A0}")
    text.append(heartText)
    return text
  }

  func applyTraitCollectionChange() {
    guard let config = config, let rootView = config.rootView else { return }

    let textAlignment: NSTextAlignment = (traitCollection.horizontalSizeClass == .compact) ?
      .center : .left
    titleLabel.textAlignment = textAlignment
    nameTextField.textAlignment = textAlignment
    subtitleLabel.textAlignment = textAlignment
    infoLabel.textAlignment = textAlignment
    let isCompact = traitCollection.horizontalSizeClass == .compact
    // deactivate first, both at once would conflict
    let ratingAlignment = [ratingLeadingConstraint, ratingCenterXConstraint].compactMap { $0 }
    NSLayoutConstraint.deactivate(ratingAlignment)
    NSLayoutConstraint.activate([isCompact ? ratingCenterXConstraint : ratingLeadingConstraint]
      .compactMap { $0 })
    let ratingRowHeight = ratingRow.isHidden ? 0 : Self.ratingRowHeight

    var height = (traitCollection.horizontalSizeClass == .compact) ?
      GenericDetailTableHeader.frameHeightCompact :
      GenericDetailTableHeader.frameHeightRegular
    if traitCollection.horizontalSizeClass == .compact {
      if config.playShuffleInfoConfig == nil {
        titlePlayButtonContainerHeightConstraint.constant = Self
          .titlePlayButtonContainerHeightWithoutButtons + ratingRowHeight
        height -=
          (
            Self.titlePlayButtonContainerHeightCompact - Self
              .titlePlayButtonContainerHeightWithoutButtons
          )
      } else {
        titlePlayButtonContainerHeightConstraint.constant = Self
          .titlePlayButtonContainerHeightCompact + ratingRowHeight
      }
      height += ratingRowHeight
    }
    if config.descriptionText != nil {
      height += GenericDetailTableHeader.frameHeightForDescription
    }
    config.tableView?.tableHeaderView?.frame = CGRect(
      x: 0,
      y: 0,
      width: rootView.view.bounds.size.width,
      height: height
    )
    frame = CGRect(x: 0, y: 0, width: rootView.view.bounds.size.width, height: height)
  }

  /// Set by the owner if the cover can be changed, the cover is a button while editing.
  var onCoverEditTap: ((_ sourceView: UIView) -> ())? {
    didSet { updateCoverEditOverlay() }
  }

  private var coverEditOverlay: CoverEditOverlayView?

  private func updateCoverEditOverlay() {
    guard isEditing, onCoverEditTap != nil, let container = entityImage.superview else {
      coverEditOverlay?.removeFromSuperview()
      coverEditOverlay = nil
      return
    }
    guard coverEditOverlay == nil else { return }
    let overlay = CoverEditOverlayView()
    overlay.cornerRadiusProvider = { [weak self] in self?.entityImage.layer.cornerRadius ?? 0 }
    overlay.addAction(UIAction { [weak self, weak overlay] _ in
      guard let overlay else { return }
      self?.onCoverEditTap?(overlay)
    }, for: .touchUpInside)
    container.addSubview(overlay)
    NSLayoutConstraint.activate([
      overlay.leadingAnchor.constraint(equalTo: entityImage.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: entityImage.trailingAnchor),
      overlay.topAnchor.constraint(equalTo: entityImage.topAnchor),
      overlay.bottomAnchor.constraint(equalTo: entityImage.bottomAnchor),
    ])
    coverEditOverlay = overlay
    applyThemeColorToCoverEditOverlay()
  }

  private func applyThemeColorToCoverEditOverlay() {
    guard let overlay = coverEditOverlay else { return }
    overlay.themeColor = appDelegate.storage.settings.accounts
      .getSetting(config?.entityContainer.account?.info).read.themePreference.asColor
  }

  func startEditing() {
    isEditing = true
    refresh()
  }

  func endEditing() {
    isEditing = false
    defer { refresh() }
    guard let nameText = nameTextField.text, let playlist = config?.entityContainer as? Playlist,
          nameText != playlist.name, let account = playlist.account else { return }
    playlist.name = nameText
    titleLabel.text = nameText
    guard appDelegate.storage.settings.user.isOnlineMode else { return }

    Task { @MainActor in do {
      try await self.appDelegate.getMeta(account.info).librarySyncer
        .syncUpload(playlistToUpdateName: playlist)
    } catch {
      self.appDelegate.eventLogger.report(topic: "Playlist Update Name", error: error)
    }}
  }

  @IBAction
  func subtitleButtonPressed(_ sender: Any) {
    guard let album = config?.entityContainer as? Album,
          let artist = album.artist,
          let account = album.account,
          let navController = config?.rootView?.navigationController
    else { return }
    appDelegate.userStatistics.usedAction(.alertGoToAlbum)
    navController.pushViewController(
      AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
      animated: true
    )
  }
}

// MARK: - CoverShadowView

/// Transparent view that only casts a soft shadow. The shadow fades in after the screen is
/// visible, so no blurred box shows up behind a cover that is still being laid out or loaded.
private final class CoverShadowView: UIView {
  private static let shadowOpacity: Float = 0.1
  var cornerRadiusProvider: (() -> CGFloat)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    isUserInteractionEnabled = false
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0
    layer.shadowRadius = 8
    layer.shadowOffset = CGSize(width: 0, height: 6)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.shadowPath = UIBezierPath(
      roundedRect: bounds,
      cornerRadius: cornerRadiusProvider?() ?? 0
    ).cgPath
  }

  func fadeInShadow() {
    let fade = CABasicAnimation(keyPath: "shadowOpacity")
    fade.fromValue = 0
    fade.toValue = Self.shadowOpacity
    fade.duration = 0.3
    fade.beginTime = CACurrentMediaTime() + 0.25
    fade.fillMode = .backwards
    layer.shadowOpacity = Self.shadowOpacity
    layer.add(fade, forKey: "fadeIn")
  }
}

// MARK: - CoverEditOverlayView

/// Whole cover as a button, marked with a photo symbol in the theme color on a circle in the background color.
private class CoverEditOverlayView: UIControl {
  /// Relative to the cover size.
  private static let circleRelativeSize: CGFloat = 0.36
  private static let symbolRelativeSize: CGFloat = 0.45

  var cornerRadiusProvider: (() -> CGFloat)?
  var themeColor = UIColor.tintColor {
    didSet { symbolView.tintColor = themeColor }
  }

  private let circleView = UIView()
  private let symbolView = UIImageView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    clipsToBounds = true
    isAccessibilityElement = true
    accessibilityLabel = "Change Cover"
    accessibilityTraits = .button

    circleView.isUserInteractionEnabled = false
    circleView.backgroundColor = .systemBackground
    circleView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(circleView)

    symbolView.image = UIImage.photo
    symbolView.tintColor = themeColor
    symbolView.contentMode = .scaleAspectFit
    symbolView.translatesAutoresizingMaskIntoConstraints = false
    circleView.addSubview(symbolView)

    NSLayoutConstraint.activate([
      circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
      circleView.centerYAnchor.constraint(equalTo: centerYAnchor),
      circleView.widthAnchor.constraint(
        equalTo: widthAnchor,
        multiplier: Self.circleRelativeSize
      ),
      circleView.heightAnchor.constraint(equalTo: circleView.widthAnchor),
      symbolView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
      symbolView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
      symbolView.widthAnchor.constraint(
        equalTo: circleView.widthAnchor,
        multiplier: Self.symbolRelativeSize
      ),
      symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = cornerRadiusProvider?() ?? 0
    circleView.layer.cornerRadius = circleView.bounds.width / 2
  }

  override var isHighlighted: Bool {
    didSet { alpha = isHighlighted ? 0.7 : 1 }
  }
}

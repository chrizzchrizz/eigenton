//
//  LibraryElementDetailTableHeaderView.swift
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

typealias GetInfoCallback = () -> String

// MARK: - PlayShuffleInfoConfiguration

struct PlayShuffleInfoConfiguration {
  var infoCB: GetInfoCallback?
  var playContextCb: GetPlayContextCallback?
  var player: PlayerFacade
  let isInfoAlwaysHidden: Bool
  var customPlayName: String?
  var isShuffleHidden = false
  var isShuffleOnContextNeccessary: Bool = true
  var shuffleContextCb: GetPlayContextCallback?
  var isEmbeddedInOtherView: Bool = false
}

// MARK: - LibraryElementDetailTableHeaderView

class LibraryElementDetailTableHeaderView: UIView {
  @IBOutlet
  weak var playAllButton: UIButton!
  @IBOutlet
  weak var playShuffledButton: UIButton!
  @IBOutlet
  weak var infoContainerView: UIView!
  @IBOutlet
  weak var infoLabel: UILabel!

  static let frameHeight: CGFloat = 40.0 + margin.top + margin.bottom
  static let margin = UIView.defaultMarginMiddleElement

  private var config: PlayShuffleInfoConfiguration?
  /// Set when the screen has a custom background; buttons then invert against it.
  private var customBackgroundColor: UIColor?
  private var shuffleButtonSquareConstraint: NSLayoutConstraint?
  private var leadingAlignmentSpacer: UIView?
  private var trailingAlignmentSpacer: UIView?
  private var centeringConstraint: NSLayoutConstraint?

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    self.layoutMargins = UIEdgeInsets(
      top: 0.0,
      left: UIView.defaultMarginX,
      bottom: 0.0,
      right: UIView.defaultMarginX
    )

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.refresh()
      }
    )
  }

  public static func createTableHeader(
    rootView: BasicTableViewController,
    configuration: PlayShuffleInfoConfiguration
  )
    -> LibraryElementDetailTableHeaderView? {
    rootView.tableView.tableHeaderView = UIView(frame: CGRect(
      x: 0,
      y: 0,
      width: rootView.view.bounds.size.width,
      height: Self.frameHeight
    ))
    let genericDetailTableHeaderView = ViewCreator<LibraryElementDetailTableHeaderView>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: 0,
        width: rootView.view.bounds.size.width,
        height: Self.frameHeight
      ))!
    #if targetEnvironment(macCatalyst)
      // aligned with the rows and the large title (see MacLargeTitle) via the table's margins
      genericDetailTableHeaderView.followsTableMargins = true
    #endif
    genericDetailTableHeaderView.prepare(configuration: configuration)
    rootView.tableView.tableHeaderView?.addSubview(genericDetailTableHeaderView)
    return genericDetailTableHeaderView
  }

  /// Takes the horizontal margins of the table it is the header of instead of its own.
  private var followsTableMargins = false
  /// Horizontal margins given by the embedding view (see `alignHorizontally`).
  private var fixedHorizontalMargins: (leading: CGFloat, trailing: CGFloat)?

  /// Aligns the content with the surrounding content instead of the default margins.
  func alignHorizontally(leading: CGFloat, trailing: CGFloat) {
    fixedHorizontalMargins = (leading, trailing)
    layoutMargins = UIEdgeInsets(top: 0.0, left: leading, bottom: 0.0, right: trailing)
  }

  override func layoutSubviews() {
    if followsTableMargins {
      applyTableMargins()
    }
    super.layoutSubviews()
  }

  /// Only the horizontal margins, preserving the superview's margins would add its vertical ones.
  private func applyTableMargins() {
    var view = superview
    while let current = view, !(current is UITableView) {
      view = current.superview
    }
    guard let tableView = view else { return }
    // the table's margins include its safe area (e.g. under the Mac sidebar), the header adds
    // its own safe area to its margins itself
    let margins = UIEdgeInsets(
      top: 0.0,
      left: max(0, tableView.layoutMargins.left - tableView.safeAreaInsets.left),
      bottom: 0.0,
      right: max(0, tableView.layoutMargins.right - tableView.safeAreaInsets.right)
    )
    if layoutMargins != margins {
      layoutMargins = margins
    }
  }

  func refresh() {
    guard let config = config else { return }
    if followsTableMargins {
      applyTableMargins()
    } else if let fixedHorizontalMargins {
      layoutMargins = UIEdgeInsets(
        top: 0.0,
        left: fixedHorizontalMargins.leading,
        bottom: 0.0,
        right: fixedHorizontalMargins.trailing
      )
    } else if config.isEmbeddedInOtherView {
      layoutMargins = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
    } else {
      if traitCollection.horizontalSizeClass == .compact {
        layoutMargins = UIEdgeInsets(
          top: 0.0,
          left: UIView.defaultMarginCellX,
          bottom: 0.0,
          right: UIView.defaultMarginCellX
        )
      } else {
        layoutMargins = UIEdgeInsets(
          top: 0.0,
          left: UIView.defaultMarginX,
          bottom: 0.0,
          right: UIView.defaultMarginX
        )
      }
    }
    infoContainerView.isHidden = config
      .isInfoAlwaysHidden || (traitCollection.horizontalSizeClass == .compact)
    infoLabel.text = config.infoCB?() ?? ""
    updateButtonAlignment()
  }

  @IBAction
  func playAllButtonPressed(_ sender: Any) {
    Haptics.success.vibrate(isHapticsEnabled: appDelegate.storage.settings.user.isHapticsEnabled)
    bounceIcon(of: playAllButton)
    play(isShuffled: false)
  }

  @IBAction
  func addAllShuffledButtonPressed(_ sender: Any) {
    Haptics.success.vibrate(isHapticsEnabled: appDelegate.storage.settings.user.isHapticsEnabled)
    bounceIcon(of: playShuffledButton)
    shuffle()
  }

  private func bounceIcon(of button: UIButton) {
    if #available(iOS 17.0, *) {
      button.imageView?.addSymbolEffect(.bounce.down.byLayer, options: .nonRepeating)
    }
  }

  private func play(isShuffled: Bool) {
    guard let playContext = config?.playContextCb?(), let player = config?.player else { return }
    isShuffled ? player.playShuffled(context: playContext) : player.play(context: playContext)
  }

  private func shuffle() {
    guard let player = config?.player else { return }
    if let shuffleContext = config?.shuffleContextCb?() {
      if config?.isShuffleOnContextNeccessary ?? true {
        player.playShuffled(context: shuffleContext)
      } else {
        player.play(context: shuffleContext)
      }
    } else {
      play(isShuffled: true)
    }
  }

  /// isShuffleOnContextNeccessary: In AlbumsVC the albums are shuffled, keep the order when shuffle button is pressed
  func prepare(configuration: PlayShuffleInfoConfiguration) {
    config = configuration
    Self.applyModernStyle(
      to: playAllButton,
      title: config?.customPlayName ?? "Play",
      symbolName: "play.fill"
    )
    Self.applyModernStyle(
      to: playShuffledButton,
      title: nil,
      symbolName: "shuffle"
    )
    playShuffledButton.accessibilityLabel = configuration
      .isShuffleOnContextNeccessary ? "Shuffle" : "Random"
    playShuffledButton.isHidden = configuration.isShuffleHidden
    makeShuffleButtonRound()
    applyCustomBackgroundColor()
    activate()
    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        self.refresh()
      }
    )
  }

  /// Black or white buttons (whichever contrasts) with label and symbol in the screen's background color
  func applyContentColors(forBackground backgroundColor: UIColor) {
    customBackgroundColor = backgroundColor
    applyCustomBackgroundColor()
  }

  private func applyCustomBackgroundColor() {
    guard let backgroundColor = customBackgroundColor else { return }
    let buttonColor: UIColor = backgroundColor.prefersDarkContent ? .black : .white
    for button in [playAllButton, playShuffledButton] {
      // the buttons use a UIButton.Configuration, so colors are set through it
      // the shuffle button is slightly translucent to stay secondary to Play
      // and its icon takes the (opaque) button color, since the fill is too faint to contrast with
      let isShuffle = button === playShuffledButton
      let alpha: CGFloat = isShuffle ? 0.1 : 1.0
      button?.configuration?.baseBackgroundColor = buttonColor.withAlphaComponent(alpha)
      button?.configuration?.baseForegroundColor = isShuffle ? buttonColor : backgroundColor
    }
  }

  /// Shuffle is icon only and as wide as it is high, Play is as wide as its content
  private func makeShuffleButtonRound() {
    guard let buttonStack = playShuffledButton.superview as? UIStackView else { return }
    buttonStack.distribution = .fill
    buttonStack.spacing = 16
    playAllButton.setContentHuggingPriority(.required, for: .horizontal)
    playAllButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    playShuffledButton.setContentHuggingPriority(.required, for: .horizontal)
    playShuffledButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    if shuffleButtonSquareConstraint == nil {
      // the spacers take the remaining width so both buttons keep their content size
      let trailingSpacer = UIView()
      trailingSpacer.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
      trailingSpacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
      buttonStack.addArrangedSubview(trailingSpacer)
      let leadingSpacer = UIView()
      leadingSpacer.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
      leadingSpacer.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
      buttonStack.insertArrangedSubview(leadingSpacer, at: 0)
      centeringConstraint = leadingSpacer.widthAnchor
        .constraint(equalTo: trailingSpacer.widthAnchor)
      leadingAlignmentSpacer = leadingSpacer
      trailingAlignmentSpacer = trailingSpacer
      playAllButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
      let constraint = playShuffledButton.widthAnchor
        .constraint(equalTo: playShuffledButton.heightAnchor)
      constraint.isActive = true
      shuffleButtonSquareConstraint = constraint
    }
    updateButtonAlignment()
  }

  /// Detail pages: compact width (artwork above the buttons): centered,
  /// regular width (artwork left of the buttons): left aligned next to the artwork.
  /// Otherwise compact width: left aligned, regular width: right aligned.
  private func updateButtonAlignment() {
    let isEmbedded = config?.isEmbeddedInOtherView ?? false
    let isCompact = traitCollection.horizontalSizeClass == .compact
    let isCentered = isEmbedded && isCompact
    let isLeftAligned = isEmbedded || isCompact
    centeringConstraint?.isActive = false
    leadingAlignmentSpacer?.isHidden = isLeftAligned && !isCentered
    trailingAlignmentSpacer?.isHidden = !isLeftAligned && !isCentered
    centeringConstraint?.isActive = isCentered
  }

  /// Capsule button with solid neutral fill and neutral (non tinted) label and symbol
  private static func applyModernStyle(to button: UIButton, title: String?, symbolName: String) {
    var configuration = UIButton.Configuration.filled()
    configuration.cornerStyle = .capsule
    configuration.title = title
    configuration.image = UIImage(systemName: symbolName)
    configuration.imagePadding = title == nil ? 0 : 8
    configuration.baseForegroundColor = .label
    configuration.baseBackgroundColor = .secondarySystemFill
    configuration
      .titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
        var attributes = attributes
        attributes.font = UIFont.preferredFont(forTextStyle: .headline)
        return attributes
      }
    button.backgroundColor = .clear
    button.layer.cornerRadius = 0.0
    button.setTitle(nil, for: .normal)
    button.configuration = configuration
  }

  func activate() {
    playAllButton.isEnabled = true
    playShuffledButton.isEnabled = !(config?.isShuffleOnContextNeccessary ?? true) || appDelegate
      .storage.settings.user.isPlayerShuffleButtonEnabled
  }

  func deactivate() {
    playAllButton.isEnabled = false
    playShuffledButton.isEnabled = false
  }
}

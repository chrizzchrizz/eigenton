//
//  ContinuePlaybackSheetVC.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 29.10.26.
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

import AmperfyKit
import UIKit

/// Bottom sheet of Sync Play Queue: shows the play queue another device saved with a button to
/// sync it, or a message why there is nothing to sync.
/// Built in UIKit, buttons of SwiftUI views in a sheet don't receive clicks on Mac Catalyst.
class ContinuePlaybackSheetVC: UIViewController {
  enum Content {
    case playQueue(ServerPlayQueue, deviceName: String?, onContinue: () -> ())
    case message(title: String, message: String, systemImage: String)
  }

  private static let margin: CGFloat = 24
  private static let artworkSize: CGFloat = 132
  private static let formSheetWidth: CGFloat = 480

  private let content: Content
  private let contentStack = UIStackView()

  init(content: Content) {
    self.content = content
    super.init(nibName: nil, bundle: nil)
    // iPad and Mac show a narrow card instead of a sheet over the full width
    if isFormSheet {
      modalPresentationStyle = .formSheet
    }
  }

  private var isFormSheet: Bool {
    UIDevice.current.userInterfaceIdiom != .phone
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // opaque, the default sheet background lets the content behind it shine through
    view.backgroundColor = UIColor {
      $0.userInterfaceStyle == .dark ? .systemGray6.resolvedColor(with: $0) : .white
    }

    contentStack.axis = .vertical
    contentStack.alignment = .fill
    contentStack.spacing = 16
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(contentStack)
    NSLayoutConstraint.activate([
      contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.margin),
      contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.margin),
      contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.margin),
    ])

    switch content {
    case let .playQueue(playQueue, deviceName, onContinue):
      fillPlayQueue(playQueue, deviceName: deviceName, onContinue: onContinue)
    case let .message(title, message, systemImage):
      fillMessage(title: title, message: message, systemImage: systemImage)
    }
    addCloseButton()

    if isFormSheet {
      // a form sheet ignores the detents and would be far taller than the content
      preferredContentSize = CGSize(
        width: Self.formSheetWidth,
        height: contentHeight(forWidth: Self.formSheetWidth) + Self.margin
      )
    }
    if let sheet = sheetPresentationController {
      sheet.detents = [.custom { [weak self] context in
        self?.preferredSheetHeight(maximum: context.maximumDetentValue)
      }]
      sheet.preferredCornerRadius = 32
    }
  }

  private func preferredSheetHeight(maximum: CGFloat) -> CGFloat {
    let height = contentHeight(forWidth: view.bounds.width) + max(
      view.safeAreaInsets.bottom,
      Self.margin
    )
    return min(height, maximum)
  }

  /// Height of the content including the top margin.
  private func contentHeight(forWidth width: CGFloat) -> CGFloat {
    let contentWidth = max(width - 2 * Self.margin, 280)
    return Self.margin + contentStack.systemLayoutSizeFitting(
      CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
  }

  // MARK: Content

  private func fillPlayQueue(
    _ playQueue: ServerPlayQueue,
    deviceName: String?,
    onContinue: @escaping () -> ()
  ) {
    let song = playQueue.songs[playQueue.startIndex]

    var subtitle = ""
    if let changed = playQueue.info.changed {
      let formatter = RelativeDateTimeFormatter()
      formatter.unitsStyle = .full
      subtitle = "Saved \(formatter.localizedString(for: changed, relativeTo: Date()))"
    }
    addHeader(title: deviceName ?? "Another Device", subtitle: subtitle)

    let artwork = LibraryEntityImage(frame: .zero)
    // the songs of the saved queue may have no artwork downloaded yet
    artwork.displayAndUpdate(entity: song)
    artwork.layer.cornerRadius = CornerRadius.medium.asCGFloat
    artwork.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      artwork.widthAnchor.constraint(equalToConstant: Self.artworkSize),
      artwork.heightAnchor.constraint(equalToConstant: Self.artworkSize),
    ])
    let artworkContainer = UIView()
    artworkContainer.addSubview(artwork)
    NSLayoutConstraint.activate([
      artwork.centerXAnchor.constraint(equalTo: artworkContainer.centerXAnchor),
      artwork.topAnchor.constraint(equalTo: artworkContainer.topAnchor),
      artwork.bottomAnchor.constraint(equalTo: artworkContainer.bottomAnchor),
    ])
    contentStack.addArrangedSubview(artworkContainer)

    // like the popup player: title and artist left aligned above the progress
    let titleLabel = makeLabel(song.title, style: .title3, color: .label, alignment: .natural)
    titleLabel.font = UIFontMetrics(forTextStyle: .title3)
      .scaledFont(for: .systemFont(ofSize: 20, weight: .bold))
    let artistLabel = makeLabel(
      song.creatorName,
      style: .title3,
      color: .label,
      alignment: .natural
    )
    contentStack.setCustomSpacing(20, after: artworkContainer)
    contentStack.addArrangedSubview(titleLabel)
    contentStack.setCustomSpacing(2, after: titleLabel)
    contentStack.addArrangedSubview(artistLabel)

    if song.duration > 0 {
      let position = min(Int(playQueue.startPositionInSeconds), song.duration)
      contentStack.setCustomSpacing(20, after: artistLabel)
      let progressBar = makeProgressBar(progress: CGFloat(position) / CGFloat(song.duration))
      contentStack.addArrangedSubview(progressBar)
      contentStack.setCustomSpacing(8, after: progressBar)
      contentStack.addArrangedSubview(makeTimeRow(
        elapsed: position.asDurationString,
        duration: song.duration.asDurationString
      ))
    }

    contentStack.setCustomSpacing(24, after: contentStack.arrangedSubviews.last ?? artistLabel)

    var configuration = UIButton.Configuration.prominentGlass()
    configuration.title = "Sync Play Queue"
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = UIFont.systemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
        weight: .semibold
      )
      return attributes
    }
    configuration.cornerStyle = .capsule
    configuration.buttonSize = .large
    configuration.baseBackgroundColor = .systemGreen
    configuration.baseForegroundColor = .white
    let button = UIButton(
      configuration: configuration,
      primaryAction: UIAction { [weak self] action in
        // a second tap during the dismiss animation must not sync twice
        (action.sender as? UIButton)?.isEnabled = false
        self?.dismiss(animated: true) { onContinue() }
      }
    )
    // Mac would draw its own button style without the glass background
    button.preferredBehavioralStyle = .pad
    // only as wide as its title
    let buttonContainer = UIView()
    button.translatesAutoresizingMaskIntoConstraints = false
    buttonContainer.addSubview(button)
    NSLayoutConstraint.activate([
      button.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
      button.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
      button.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
      button.leadingAnchor.constraint(greaterThanOrEqualTo: buttonContainer.leadingAnchor),
    ])
    contentStack.addArrangedSubview(buttonContainer)
  }

  private func fillMessage(title: String, message: String, systemImage: String) {
    let imageView = UIImageView(image: UIImage(systemName: systemImage))
    imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44)
    imageView.tintColor = .secondaryLabel
    imageView.contentMode = .scaleAspectFit
    contentStack.addArrangedSubview(imageView)
    contentStack.setCustomSpacing(12, after: imageView)
    addHeader(title: title, subtitle: message)
  }

  private func addHeader(title: String, subtitle: String) {
    // keeps the title clear of the close button
    let titleLabel = makeLabel(title, style: .title1, color: .label)
    titleLabel.font = UIFontMetrics(forTextStyle: .title1)
      .scaledFont(for: .systemFont(ofSize: 28, weight: .bold))
    let titleContainer = UIView()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleContainer.addSubview(titleLabel)
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor),
      titleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 32),
      titleLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -32),
    ])
    contentStack.addArrangedSubview(titleContainer)
    guard !subtitle.isEmpty else { return }
    contentStack.setCustomSpacing(4, after: titleContainer)
    contentStack.addArrangedSubview(makeLabel(
      subtitle,
      style: .subheadline,
      color: .secondaryLabel
    ))
  }

  /// Bar of the popup player: the played part in the text color on a translucent track.
  private func makeProgressBar(progress: CGFloat) -> UIView {
    let height: CGFloat = 6
    let track = UIView()
    track.backgroundColor = .label.withAlphaComponent(0.25)
    track.layer.cornerRadius = height / 2
    track.clipsToBounds = true
    let fill = UIView()
    fill.backgroundColor = .label
    fill.layer.cornerRadius = height / 2
    fill.translatesAutoresizingMaskIntoConstraints = false
    track.addSubview(fill)
    NSLayoutConstraint.activate([
      track.heightAnchor.constraint(equalToConstant: height),
      fill.topAnchor.constraint(equalTo: track.topAnchor),
      fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
      fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
      fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: max(progress, 0.001)),
    ])
    return track
  }

  /// Elapsed time on the left, duration on the right.
  private func makeTimeRow(elapsed: String, duration: String) -> UIView {
    let elapsedLabel = makeLabel(elapsed, style: .subheadline, color: .label, alignment: .left)
    let durationLabel = makeLabel(duration, style: .subheadline, color: .label, alignment: .right)
    for label in [elapsedLabel, durationLabel] {
      label.font = UIFont.monospacedDigitSystemFont(
        ofSize: label.font.pointSize,
        weight: .regular
      )
    }
    let row = UIStackView(arrangedSubviews: [elapsedLabel, durationLabel])
    row.axis = .horizontal
    row.distribution = .fillEqually
    return row
  }

  private func makeLabel(
    _ text: String,
    style: UIFont.TextStyle,
    color: UIColor,
    alignment: NSTextAlignment = .center
  )
    -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: style)
    label.textColor = color
    label.textAlignment = alignment
    label.numberOfLines = 0
    return label
  }

  private func addCloseButton() {
    var configuration = UIButton.Configuration.gray()
    configuration.image = UIImage(systemName: "xmark")
    configuration.cornerStyle = .capsule
    configuration.buttonSize = .small
    // the smaller symbol must not shrink the button, its size is the one with the default symbol
    let sizeButton = UIButton(configuration: configuration)
    sizeButton.preferredBehavioralStyle = .pad
    let size = sizeButton.intrinsicContentSize
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 11,
      weight: .heavy
    )
    let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
      self?.dismiss(animated: true)
    })
    button.preferredBehavioralStyle = .pad
    button.accessibilityLabel = "Close"
    button.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: size.width),
      button.heightAnchor.constraint(equalToConstant: size.height),
      button.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
      button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
    ])
  }
}

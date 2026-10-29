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
  private static let macSheetWidth: CGFloat = 480

  private let content: Content
  private let contentStack = UIStackView()

  init(content: Content) {
    self.content = content
    super.init(nibName: nil, bundle: nil)
    #if targetEnvironment(macCatalyst)
      modalPresentationStyle = .formSheet
    #endif
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

    #if targetEnvironment(macCatalyst)
      // a form sheet on Mac ignores the detents and would be far taller than the content
      preferredContentSize = CGSize(
        width: Self.macSheetWidth,
        height: contentHeight(forWidth: Self.macSheetWidth) + Self.margin
      )
    #endif
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
    contentStack.setCustomSpacing(12, after: artworkContainer)

    let titleLabel = makeLabel(song.title, style: .headline, color: .label)
    let artistLabel = makeLabel(song.creatorName, style: .subheadline, color: .secondaryLabel)
    contentStack.addArrangedSubview(titleLabel)
    contentStack.setCustomSpacing(2, after: titleLabel)
    contentStack.addArrangedSubview(artistLabel)

    let position = Int(playQueue.startPositionInSeconds)
    if song.duration > 0, position > 0 {
      let progress = UIProgressView(progressViewStyle: .bar)
      progress.progress = Float(min(Double(position) / Double(song.duration), 1))
      contentStack.addArrangedSubview(progress)
      contentStack.addArrangedSubview(makeLabel(
        "\(position.asDurationString) / \(song.duration.asDurationString)",
        style: .footnote,
        color: .secondaryLabel
      ))
    }

    contentStack.setCustomSpacing(24, after: contentStack.arrangedSubviews.last ?? artworkContainer)

    var configuration = UIButton.Configuration.tinted()
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
    configuration.baseForegroundColor = .systemGreen
    let button = UIButton(
      configuration: configuration,
      primaryAction: UIAction { [weak self] action in
        // a second tap during the dismiss animation must not sync twice
        (action.sender as? UIButton)?.isEnabled = false
        self?.dismiss(animated: true) { onContinue() }
      }
    )
    // Mac would draw its own button style without the tinted background
    button.preferredBehavioralStyle = .pad
    contentStack.addArrangedSubview(button)
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

  private func makeLabel(_ text: String, style: UIFont.TextStyle, color: UIColor) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: style)
    label.textColor = color
    label.textAlignment = .center
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

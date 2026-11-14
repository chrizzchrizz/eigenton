//
//  PlaylistCollectionCell.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 02.11.26.
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

/// Home tile of a playlist: square cover on top, title and artists below, the tile is filled
/// with the main color of the cover. The height is set by `textAreaHeightRatio`.
class PlaylistCollectionCell: UICollectionViewCell {
  private static let cornerRadius = CornerRadius.medium.asCGFloat
  private static let textInsets = NSDirectionalEdgeInsets(
    top: 12,
    leading: 12,
    bottom: 12,
    trailing: 12
  )

  /// Tile color without artwork: light gray in light mode, dark gray in dark mode
  private static let fallbackColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? .systemGray5 : .systemGray6
  }

  /// Height of the text area below the cover relative to the tile width at the default text
  /// size (0.33 = a third of the width, 0.67 = two thirds). Change this to tune the tile height.
  static let textAreaHeightRatio: CGFloat = 0.45

  /// Tile height for the given width (set by the layout): square cover plus the text area,
  /// which grows with the text size of `traits` like the labels of the album tiles
  static func height(forWidth width: CGFloat, compatibleWith traits: UITraitCollection) -> CGFloat {
    let textAreaHeight = TextScaling.scaledValue(
      width * textAreaHeightRatio,
      compatibleWith: traits,
      maximum: AlbumCollectionCell.maxContentSizeCategory
    )
    return (width + textAreaHeight).rounded()
  }

  private let tileView = UIView()
  private let entityImage = EntityImageView(frame: .zero)
  // same fonts as the album tiles (`AlbumCollectionCell`), scaled with the text size
  private let titleLabel = ScaledLabel()
  private let subtitleLabel = ScaledLabel()

  private var artwork: UIImage?

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupViews()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupViews()
  }

  private func setupViews() {
    tileView.translatesAutoresizingMaskIntoConstraints = false
    tileView.layer.cornerRadius = Self.cornerRadius
    tileView.layer.cornerCurve = .continuous
    tileView.clipsToBounds = true
    contentView.addSubview(tileView)

    entityImage.translatesAutoresizingMaskIntoConstraints = false
    entityImage.setSquareImageCorners(true)
    entityImage.artworkDidChange = { [weak self] image in
      self?.setArtwork(image)
    }
    tileView.addSubview(entityImage)

    // the labels take the text size from the traits, so they stop growing like the album tiles
    maximumContentSizeCategory = AlbumCollectionCell.maxContentSizeCategory
    titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    titleLabel.numberOfLines = 1
    titleLabel.lineBreakMode = .byTruncatingTail
    subtitleLabel.font = .systemFont(ofSize: 13)
    subtitleLabel.numberOfLines = 2
    subtitleLabel.lineBreakMode = .byTruncatingTail

    let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    textStack.axis = .vertical
    textStack.alignment = .fill
    textStack.spacing = 1
    textStack.translatesAutoresizingMaskIntoConstraints = false
    tileView.addSubview(textStack)

    let insets = Self.textInsets
    NSLayoutConstraint.activate([
      tileView.topAnchor.constraint(equalTo: contentView.topAnchor),
      tileView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      tileView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      tileView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      entityImage.topAnchor.constraint(equalTo: tileView.topAnchor),
      entityImage.leadingAnchor.constraint(equalTo: tileView.leadingAnchor),
      entityImage.trailingAnchor.constraint(equalTo: tileView.trailingAnchor),
      entityImage.heightAnchor.constraint(equalTo: entityImage.widthAnchor),

      textStack.topAnchor.constraint(equalTo: entityImage.bottomAnchor, constant: insets.top),
      textStack.leadingAnchor.constraint(equalTo: tileView.leadingAnchor, constant: insets.leading),
      textStack.trailingAnchor.constraint(
        equalTo: tileView.trailingAnchor,
        constant: -insets.trailing
      ),
      textStack.bottomAnchor.constraint(
        lessThanOrEqualTo: tileView.bottomAnchor,
        constant: -insets.bottom
      ),
    ])

    updateColors()

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self],
      handler: { (self: PlaylistCollectionCell, _: UITraitCollection) in
        self.updateColors()
      }
    )
  }

  func display(playlist: Playlist, subtitle: String?) {
    titleLabel.text = playlist.name
    subtitleLabel.text = subtitle
    entityImage.display(
      theme: appDelegate.storage.settings.accounts.getSetting(playlist.account?.info).read
        .themePreference,
      container: playlist,
      // the cover is clipped by the rounded tile, it has no rounded corners itself
      cornerRadius: .none
    )
    // an unchanged cover does not report a change
    setArtwork(entityImage.shownArtwork)
  }

  /// The main color is only computed again for a different artwork, an image view reports
  /// the same artwork several times (e.g. once per quad image).
  private func setArtwork(_ image: UIImage?) {
    guard image !== artwork else { return }
    artwork = image
    updateColors()
  }

  private func updateColors() {
    let isDark = traitCollection.userInterfaceStyle == .dark
    guard let artwork else {
      tileView.backgroundColor = Self.fallbackColor
      titleLabel.textColor = .label
      subtitleLabel.textColor = .secondaryLabel
      return
    }
    let tileColor = artwork.mainColor(forDarkBackground: isDark)
    tileView.backgroundColor = tileColor
    let textColor: UIColor = tileColor.prefersDarkContent ? .black : .white
    titleLabel.textColor = textColor
    subtitleLabel.textColor = textColor.withAlphaComponent(0.75)
  }
}

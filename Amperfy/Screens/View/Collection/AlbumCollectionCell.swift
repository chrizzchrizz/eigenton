//
//  AlbumCollectionCell.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 21.01.22.
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

class AlbumCollectionCell: BasicCollectionCell {
  @IBOutlet
  weak var titleLabel: UILabel!
  @IBOutlet
  weak var subtitleLabel: UILabel!
  @IBOutlet
  weak var entityImage: EntityImageView!
  @IBOutlet
  weak var artworkImageWidthConstraint: NSLayoutConstraint!

  static let maxWidth: CGFloat = 250.0
  /// The short labels below the artwork stop growing beyond this text size
  static let maxContentSizeCategory: UIContentSizeCategory = .extraExtraExtraLarge

  /// Height below the artwork that a layout reserves for the labels: `defaultHeight` at the
  /// default text size, scaled for the given traits
  static func labelAreaHeight(
    for traits: UITraitCollection,
    defaultHeight: CGFloat = 45.0
  )
    -> CGFloat {
    scaledHeight(defaultHeight, for: traits)
  }

  private static func scaledHeight(_ height: CGFloat, for traits: UITraitCollection) -> CGFloat {
    TextScaling.scaledValue(height, compatibleWith: traits, maximum: maxContentSizeCategory)
  }

  private var container: PlayableContainable?
  private weak var rootView: UICollectionViewController?
  private weak var rootFlowLayout: UICollectionViewDelegateFlowLayout?
  private var itemWidth: CGFloat?

  func display(
    container: PlayableContainable,
    rootView: UICollectionViewController,
    itemWidth: CGFloat,
    initialIndexPath: IndexPath,
    isImageCircular: Bool = false
  ) {
    self.itemWidth = itemWidth
    rootFlowLayout = nil
    apply(
      container: container,
      rootView: rootView,
      initialIndexPath: initialIndexPath,
      isImageCircular: isImageCircular
    )
  }

  func display(
    container: PlayableContainable,
    rootView: UICollectionViewController,
    rootFlowLayout: UICollectionViewDelegateFlowLayout,
    initialIndexPath: IndexPath
  ) {
    self.rootFlowLayout = rootFlowLayout
    itemWidth = nil
    apply(
      container: container,
      rootView: rootView,
      initialIndexPath: initialIndexPath
    )
  }

  private func apply(
    container: PlayableContainable,
    rootView: UICollectionViewController,
    initialIndexPath: IndexPath,
    isImageCircular: Bool = false
  ) {
    self.container = container
    self.rootView = rootView
    titleLabel.text = container.name
    subtitleLabel.text = container.subtitle
    entityImage.display(
      theme: appDelegate.storage.settings.accounts.getSetting(container.account?.info).read
        .themePreference,
      container: container,
      cornerRadius: .medium
    )
    // circular image on a frame filled with the main color of the image
    entityImage.setCircularImage(frameColor: isImageCircular ? { [weak self] image in
      image.mainColor(forDarkBackground: self?.traitCollection.userInterfaceStyle == .dark)
    } : nil)
    updateArtworkImageConstraint(indexPath: initialIndexPath)
    layoutIfNeeded()
  }

  override func layoutSubviews() {
    if let indexPath = rootView?.collectionView.indexPath(for: self) {
      updateArtworkImageConstraint(indexPath: indexPath)
    }
    super.layoutSubviews()
  }

  func updateArtworkImageConstraint(indexPath: IndexPath) {
    guard let rootView else { return }
    if let rootFlowLayout = rootFlowLayout,
       let itemSize = rootFlowLayout.collectionView?(
         rootView.collectionView,
         layout: rootView.collectionView.collectionViewLayout,
         sizeForItemAt: indexPath
       ) {
      let newImageWidth = min(itemSize.width, itemSize.height)
      artworkImageWidthConstraint.constant = newImageWidth
    } else if let itemWidth {
      artworkImageWidthConstraint.constant = itemWidth
    }
  }
}

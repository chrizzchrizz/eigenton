//
//  EntityImageView.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 20.02.22.
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

import Foundation
import UIKit

open class EntityImageView: UIView {
  @IBOutlet
  weak var singleImage: LibraryEntityImage!
  @IBOutlet
  weak var quadImage1: LibraryEntityImage!
  @IBOutlet
  weak var quadImage2: LibraryEntityImage!
  @IBOutlet
  weak var quadImage3: LibraryEntityImage!
  @IBOutlet
  weak var quadImage4: LibraryEntityImage!

  private var view: UIView!

  /// Inset of the circular image relative to the frame size.
  private var circularImageInset: CGFloat = 0.1
  private var circularFrameColor: ((UIImage) -> UIColor)?
  private var isCircularPlaceholder = false
  /// Images inside the frame have square corners, only the frame itself is rounded
  private var hasSquareImageCorners = false

  /// Called whenever the shown artwork changes. The image is the artwork the colors of the
  /// cover can be derived from (the first one of a quad cover), nil while only a placeholder
  /// for missing artwork is shown.
  public var artworkDidChange: ((UIImage?) -> ())?

  /// Shown collection whose server cover is not downloaded yet; shown again once it is
  private var collectionWaitingForServerArtwork: (
    theme: ThemePreference,
    collection: ArtworkCollection,
    cornerRadius: CornerRadius
  )?
  /// Accounts whose artwork downloads are observed
  private var observedAccounts = Set<AccountInfo>()

  private var quadImages: [LibraryEntityImage] {
    [
      quadImage1,
      quadImage2,
      quadImage3,
      quadImage4,
    ]
  }

  required public init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    loadViewFromNib()
  }

  override public init(frame: CGRect) {
    super.init(frame: frame)
    loadViewFromNib()
  }

  public func loadViewFromNib() {
    let bundle = Bundle(for: type(of: self))
    let nib = UINib(nibName: String(describing: type(of: self)), bundle: bundle)
    let view = nib.instantiate(withOwner: self, options: nil).first as! UIView
    view.frame = bounds
    view.autoresizingMask = [
      UIView.AutoresizingMask.flexibleWidth,
      UIView.AutoresizingMask.flexibleHeight,
    ]
    addSubview(view)
    self.view = view

    backgroundColor = .clear

    layer.masksToBounds = true
    self.view.backgroundColor = .clear
    self.view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    quadImages[0].layer.maskedCorners = [
      .layerMinXMinYCorner,
      .layerMaxXMinYCorner,
      .layerMinXMaxYCorner,
      .layerMaxXMaxYCorner,
    ]
    quadImages[0].layer.maskedCorners = [.layerMinXMinYCorner]
    quadImages[1].layer.maskedCorners = [.layerMaxXMinYCorner]
    quadImages[2].layer.maskedCorners = [.layerMinXMaxYCorner]
    quadImages[3].layer.maskedCorners = [.layerMaxXMaxYCorner]
    singleImage.imageDidChange = { [weak self] _ in self?.imageDidChange() }
    quadImages.forEach { $0.imageDidChange = { [weak self] _ in self?.imageDidChange() } }

    registerForTraitChanges(
      [UITraitUserInterfaceStyle.self],
      handler: { (self: EntityImageView, previousTraitCollection: UITraitCollection) in
        self.updateCircularStyle()
      }
    )
  }

  /// Shows the single image as a circle inside the frame, the frame is filled with the color
  /// `frameColor` derives from the shown image. `inset` is the gap between circle and frame
  /// relative to the frame size. The placeholder of an entity without artwork is only shown
  /// as a circle if `isPlaceholderCircular` is set, otherwise it and nil show the image
  /// across the whole frame.
  public func setCircularImage(
    frameColor: ((UIImage) -> UIColor)?,
    inset: CGFloat = 0.1,
    isPlaceholderCircular: Bool = false
  ) {
    let wasCircular = circularFrameColor != nil
    circularFrameColor = frameColor
    circularImageInset = inset
    isCircularPlaceholder = isPlaceholderCircular
    if frameColor != nil {
      updateCircularStyle()
    } else if wasCircular {
      resetCircularStyle()
    }
  }

  /// Square corners for the images inside the frame, e.g. when the frame is part of a rounded
  /// tile. The frame corners are still set by `display(cornerRadius:)`.
  public func setSquareImageCorners(_ isSquare: Bool) {
    hasSquareImageCorners = isSquare
    applyImageCornerRadius()
  }

  private var imageCornerRadius: CGFloat {
    hasSquareImageCorners ? 0 : RoundedImage.cornerRadius
  }

  private func applyImageCornerRadius() {
    quadImages.forEach { $0.layer.cornerRadius = imageCornerRadius }
    if !showsCircularImage {
      singleImage.layer.cornerRadius = imageCornerRadius
    }
  }

  /// The artwork the cover colors are derived from, nil if only a placeholder is shown
  public var shownArtwork: UIImage? {
    if !singleImage.isHidden {
      return singleImage.isShowingPlaceholder ? nil : singleImage.image
    }
    return quadImages.first { !$0.isHidden && !$0.isShowingPlaceholder && $0.image != nil }?.image
  }

  private func imageDidChange() {
    updateCircularStyle()
    artworkDidChange?(shownArtwork)
  }

  private var showsCircularImage: Bool {
    circularFrameColor != nil && (isCircularPlaceholder || !singleImage.isShowingPlaceholder)
  }

  private func updateCircularStyle() {
    guard let circularFrameColor else { return }
    if showsCircularImage, let image = singleImage.image {
      view.backgroundColor = circularFrameColor(image)
      setNeedsLayout()
    } else {
      resetCircularStyle()
    }
  }

  private func resetCircularStyle() {
    singleImage.layer.cornerRadius = imageCornerRadius
    view.layoutMargins = .zero
    view.backgroundColor = .clear
    setNeedsLayout()
  }

  override open func layoutSubviews() {
    if showsCircularImage {
      let side = min(bounds.width, bounds.height)
      let inset = (side * circularImageInset).rounded()
      view.layoutMargins = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
      singleImage.layer.cornerRadius = (side - 2 * inset) / 2
    }
    super.layoutSubviews()
  }

  public func display(
    theme: ThemePreference,
    container: PlayableContainable,
    cornerRadius: CornerRadius = .small
  ) {
    display(
      theme: theme,
      collection: container.getArtworkCollection(theme: theme),
      cornerRadius: cornerRadius
    )
  }

  public func configureStyling(
    image: UIImage,
    imageSizeType: ArtworkIconSizeType,
    imageTintColor: UIColor,
    backgroundColor: UIColor
  ) {
    collectionWaitingForServerArtwork = nil
    singleImage.tintColor = imageTintColor
    view.backgroundColor = backgroundColor
    view.layoutMargins = UIEdgeInsets(
      top: imageSizeType.rawValue,
      left: imageSizeType.rawValue,
      bottom: imageSizeType.rawValue,
      right: imageSizeType.rawValue
    )
    let modImage = image.withRenderingMode(.alwaysTemplate)
    singleImage.display(image: modImage)
  }

  private func display(
    theme: ThemePreference,
    collection: ArtworkCollection,
    cornerRadius: CornerRadius = .small
  ) {
    layer.cornerRadius = cornerRadius.asCGFloat
    quadImages.forEach { $0.isHidden = true }
    singleImage.isHidden = false

    let display = collection.display
    collectionWaitingForServerArtwork = nil
    if case .standalone = display {
      // downloaded by the single image
    } else if let serverArtwork = collection.serverArtwork {
      collectionWaitingForServerArtwork = (theme, collection, cornerRadius)
      download(serverArtwork: serverArtwork)
    }

    switch display {
    case let .quad(quadEntities):
      singleImage.isHidden = true
      quadImages.forEach {
        $0.display(image: UIImage.getGeneratedArtwork(theme: theme, artworkType: .song))
        $0.isHidden = false
      }
      for (index, entity) in quadEntities.enumerated() {
        guard index < quadImages.count else { break }
        quadImages[index].display(entity: entity)
      }
    case let .single(entity):
      singleImage.displayAndUpdate(entity: entity)
    case let .standalone(artwork):
      singleImage.displayAndUpdate(
        artwork: artwork,
        artworkType: collection.defaultArtworkType
      )
    case .placeholder:
      singleImage.display(artworkType: collection.defaultArtworkType)
    }
  }

  private func download(serverArtwork: Artwork) {
    guard let accountInfo = serverArtwork.account?.info else { return }
    let appDelegate = AmperKit.shared
    let artworkDownloadManager = appDelegate.getMeta(accountInfo).artworkDownloadManager
    if observedAccounts.insert(accountInfo).inserted {
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: artworkDownloadManager
      )
    }
    artworkDownloadManager.download(object: serverArtwork)
  }

  @objc
  private func downloadFinishedSuccessful(notification: Notification) {
    guard let downloadNotification = DownloadNotification.fromNotification(notification)
    else { return }
    Task { @MainActor in
      guard let waiting = collectionWaitingForServerArtwork,
            waiting.collection.serverArtwork?.uniqueID == downloadNotification.id
      else { return }
      display(
        theme: waiting.theme,
        collection: waiting.collection,
        cornerRadius: waiting.cornerRadius
      )
    }
  }
}

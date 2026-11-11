//
//  LyricTableCell.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 17.06.24.
//  Copyright (c) 2021 Maximilian Bauer. All rights reserved.
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
import CoreData
import CoreImage
import UIKit

// MARK: - LyricTableCellModel

@MainActor
class LyricTableCellModel {
  var lyric: LyricsLine? {
    didSet {
      cell?.refresh()
    }
  }

  var isActiveLine = false {
    didSet {
      guard oldValue != isActiveLine else { return }
      cell?.refresh()
    }
  }

  /// Active and inactive lines share the font, so a line keeps its height when it becomes active.
  static let defaultFontSize: CGFloat = 34

  private var attributedString: NSAttributedString?
  private var highlightedAttributedString: NSAttributedString?

  internal weak var cell: LyricTableCell?

  var displayString: NSAttributedString? {
    if isActiveLine {
      return highlightedAttributedString
    } else {
      return attributedString
    }
  }

  /// Shown instead of the text during pauses, e.g. an intro or an empty line of the lyrics.
  static let pauseText = "● ● ●"
  static let pauseFont = UIFont.systemFont(ofSize: 16, weight: .bold)

  /// Pauses (intro, empty lines) only show dots and cannot be selected.
  let isPause: Bool

  init(lyric: LyricsLine, isPause: Bool = false, fontSize: CGFloat = defaultFontSize) {
    self.lyric = lyric
    self.isPause = isPause
    self.isActiveLine = false
    let text = isPause ? Self.pauseText : lyric.value
    let font = isPause ? Self.pauseFont : UIFont.systemFont(ofSize: fontSize, weight: .bold)
    self.attributedString = NSAttributedString(
      string: text,
      attributes:
      [
        .font: font,
        .foregroundColor: UIColor.label.withAlphaComponent(0.35),
      ]
    )
    self.highlightedAttributedString = NSAttributedString(
      string: text,
      attributes:
      [
        .font: font,
        .foregroundColor: UIColor.label,
      ]
    )
  }

  nonisolated private static let blurRadius: CGFloat = 2.5
  /// Space around the text, so the blur is not cut off at the edges.
  nonisolated static let blurPadding: CGFloat = 3 * blurRadius
  nonisolated private static let ciContext = CIContext()
  private var blurredImageCache: (size: CGSize, image: UIImage)?
  private var renderingBlurSize: CGSize?

  /// Blurred inactive line as template image, the cell tints it. Text is vertically centered.
  /// Rendering takes a while, so it happens in the background: returns nil until the image is
  /// ready and then tells the cell.
  func blurredImage(width: CGFloat, height: CGFloat, scale: CGFloat) -> UIImage? {
    let size = CGSize(width: width, height: height)
    if let cache = blurredImageCache, cache.size == size { return cache.image }
    prepareBlurredImage(width: width, height: height, scale: scale)
    return nil
  }

  /// Starts rendering the blurred image, e.g. before the line scrolls into view.
  func prepareBlurredImage(width: CGFloat, height: CGFloat, scale: CGFloat) {
    let size = CGSize(width: width, height: height)
    if let cache = blurredImageCache, cache.size == size { return }
    guard renderingBlurSize != size, let attributedString, width > 0, height > 0 else { return }
    renderingBlurSize = size
    let textHeight = calcHeight(containerWidth: width + 2 * UIView.defaultMarginX)
    // only the shape counts, the cell tints the template image
    let blackText = NSMutableAttributedString(attributedString: attributedString)
    blackText.addAttribute(
      .foregroundColor,
      value: UIColor.black,
      range: NSRange(location: 0, length: blackText.length)
    )
    // a label wraps exactly like the label of the active line; UIKit views need the main thread
    let padding = Self.blurPadding
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    let textImage = UIGraphicsImageRenderer(
      size: CGSize(width: width + 2 * padding, height: height + 2 * padding),
      format: format
    ).image {
      let label = Self.makeLabel()
      label.attributedText = blackText
      label.frame = CGRect(x: 0, y: 0, width: width, height: textHeight)
      $0.cgContext.translateBy(x: padding, y: padding + (height - textHeight) / 2)
      label.layer.render(in: $0.cgContext)
    }
    // the blur is the expensive part and runs in the background
    Task { [weak self] in
      let image = await Self.blur(textImage)
      guard let self, renderingBlurSize == size else { return }
      renderingBlurSize = nil
      guard let image else { return }
      blurredImageCache = (size, image)
      cell?.updateBlurredImage()
    }
  }

  @concurrent
  private static func blur(_ textImage: UIImage) async -> UIImage? {
    guard let ciImage = CIImage(image: textImage),
          let blurFilter = CIFilter(name: "CIGaussianBlur")
    else { return nil }
    blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
    // the radius is given in pixels
    blurFilter.setValue(blurRadius * textImage.scale, forKey: kCIInputRadiusKey)
    guard let output = blurFilter.outputImage,
          let cgImage = ciContext.createCGImage(output, from: ciImage.extent)
    else { return nil }
    return UIImage(cgImage: cgImage, scale: textImage.scale, orientation: .up)
      .withRenderingMode(.alwaysTemplate)
  }

  private var heightCache: (containerWidth: CGFloat, height: CGFloat)?

  /// Active and inactive line share the font, so the height only depends on the width.
  /// The table asks for it again and again while scrolling.
  public func calcHeight(containerWidth: CGFloat) -> CGFloat {
    if let heightCache, heightCache.containerWidth == containerWidth {
      return heightCache.height
    }
    let height = calcUncachedHeight(containerWidth: containerWidth)
    heightCache = (containerWidth, height)
    return height
  }

  /// Measured with a label, so the height matches the line wrapping of the displayed label.
  private func calcUncachedHeight(containerWidth: CGFloat) -> CGFloat {
    let label = Self.makeLabel()
    label.attributedText = isActiveLine ? highlightedAttributedString : attributedString
    let width = LyricTableCell.adjustContainerWidthForMargins(containerWidth: containerWidth)
    return ceil(label.sizeThatFits(CGSize(width: width, height: 9_999)).height)
  }

  static func makeLabel() -> UILabel {
    let label = UILabel()
    label.textAlignment = .left
    label.lineBreakMode = .byWordWrapping
    label.numberOfLines = 0
    return label
  }
}

// MARK: - LyricTableCell

class LyricTableCell: UITableViewCell {
  private weak var viewModel: LyricTableCellModel? = nil

  private var lyricLabel: UILabel!
  private let blurredImageView = UIImageView()
  /// Same horizontal margin as the artwork of the player, so text and artwork are aligned.
  override var layoutMargins: UIEdgeInsets {
    get {
      UIEdgeInsets(
        top: BasicTableCell.margin.top,
        left: UIView.defaultMarginX,
        bottom: BasicTableCell.margin.bottom,
        right: UIView.defaultMarginX
      )
    }
    set {}
  }

  static func adjustContainerWidthForMargins(containerWidth: CGFloat) -> CGFloat {
    containerWidth - (2 * UIView.defaultMarginX)
  }

  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    commonInit()
  }

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    commonInit()
  }

  private func commonInit() {
    lyricLabel = LyricTableCellModel.makeLabel()
    lyricLabel.frame = CGRect(
      x: layoutMargins.left,
      y: 0,
      width: bounds.width - (2 * layoutMargins.right),
      height: bounds.height
    )
    selectionStyle = .none
    blurredImageView.tintColor = UIColor.label.withAlphaComponent(0.35)
    contentView.addSubview(blurredImageView)
    contentView.addSubview(lyricLabel)
    backgroundColor = .clear
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    lyricLabel.frame = CGRect(
      x: layoutMargins.left,
      y: 0,
      width: bounds.width - (2 * layoutMargins.right),
      height: bounds.height
    )
    let padding = LyricTableCellModel.blurPadding
    blurredImageView.frame = lyricLabel.frame.insetBy(dx: -padding, dy: -padding)
    updateBlurredImage()
  }

  func display(model: LyricTableCellModel) {
    viewModel = model
    model.cell = self
    refresh(animated: false)
  }

  func refresh(animated: Bool = true) {
    guard let model = viewModel else { return }
    lyricLabel.attributedText = model.displayString
    lyricLabel.sizeThatFits(CGSize(width: bounds.width, height: bounds.height))
    updateBlurredImage()

    // inactive lines are shown as blurred image, the active one as sharp text
    let applyState = {
      self.lyricLabel.alpha = model.isActiveLine ? 1.0 : 0.0
      self.blurredImageView.alpha = model.isActiveLine ? 0.0 : 1.0
    }
    if animated, window != nil {
      UIView.animate(withDuration: 0.25, animations: applyState)
    } else {
      applyState()
    }
  }

  func updateBlurredImage() {
    guard let model = viewModel, !model.isActiveLine else { return }
    blurredImageView.image = model.blurredImage(
      width: lyricLabel.bounds.width,
      height: lyricLabel.bounds.height,
      scale: traitCollection.displayScale
    )
  }
}

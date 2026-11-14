//
//  CommonCollectionSectionHeader.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 27.09.22.
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

class CommonCollectionSectionHeader: UICollectionReusableView {
  /// Scales with the user's text size (30pt at the default text size)
  static var frameHeight: CGFloat { TextScaling.scaledValue(30.0) }

  @IBOutlet
  weak var titleLabel: UILabel!

  private var detailHeader: LibraryElementDetailTableHeaderView?
  /// Height of the view above the play header, see `displayTopView`.
  private var topViewHeight: CGFloat = 0
  private var topView: UIView?

  /// Aligns the title with the items of the section.
  func applyHorizontalInset(leading: CGFloat) {
    titleLabel.superview?.directionalLayoutMargins.leading = leading
  }

  func display(title: String?) {
    titleLabel.text = title
    titleLabel.isHidden = (title == nil)
  }

  /// A full width view at the very top, above the play header (e.g. the large title on Mac).
  func displayTopView(_ view: UIView, height: CGFloat) {
    topView?.removeFromSuperview()
    topView = view
    topViewHeight = height
    view.frame = CGRect(x: 0, y: 0, width: bounds.size.width, height: height)
    view.autoresizingMask = [.flexibleWidth]
    addSubview(view)
  }

  /// `horizontalInset` aligns the play header with the items instead of the default margins.
  func displayPlayHeader(
    configuration: PlayShuffleInfoConfiguration,
    horizontalInset: (leading: CGFloat, trailing: CGFloat)? = nil
  ) {
    detailHeader = ViewCreator<LibraryElementDetailTableHeaderView>
      .createFromNib(withinFixedFrame: CGRect(
        x: 0,
        y: topViewHeight,
        width: bounds.size.width,
        height: LibraryElementDetailTableHeaderView.frameHeight
      ))
    detailHeader?.prepare(configuration: configuration)
    if let horizontalInset {
      detailHeader?.alignHorizontally(
        leading: horizontalInset.leading,
        trailing: horizontalInset.trailing
      )
    }
    detailHeader?.refresh()
    if let detailHeader = detailHeader {
      addSubview(detailHeader)
    }
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    // once per header, registering on every reuse added another handler each time
    MainActor.assumeIsolated {
      _ = registerForTraitChanges(
        [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self],
        handler: { (self: Self, previousTraitCollection: UITraitCollection) in
          self.detailHeader?.refresh()
        }
      )
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    topView?.removeFromSuperview()
    topView = nil
    topViewHeight = 0
    detailHeader?.removeFromSuperview()
    detailHeader?.isHidden = true
    detailHeader = nil
  }
}

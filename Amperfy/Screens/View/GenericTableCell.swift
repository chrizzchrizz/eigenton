//
//  GenericTableCell.swift
//  Amperfy
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

import AmperfyKit
import UIKit

class GenericTableCell: BasicTableCell {
  override var usesSystemHorizontalMargins: Bool { true }

  @IBOutlet
  weak var titleLabel: UILabel!
  @IBOutlet
  weak var subtitleLabel: UILabel!
  @IBOutlet
  weak var entityImage: EntityImageView!
  @IBOutlet
  weak var infoLabel: UILabel!
  @IBOutlet
  weak var favoriteIconImage: UIImageView!

  @IBOutlet
  weak var infoLabelWidthConstraint: NSLayoutConstraint!

  // fixed sizes in the xib that scale with the text size (see `applyTextSize`)
  @IBOutlet
  private var titleHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var subtitleHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var infoHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var labelsHeightConstraint: NSLayoutConstraint!
  @IBOutlet
  private var entityImageWidthConstraint: NSLayoutConstraint!
  @IBOutlet
  private var favoriteIconHeightConstraint: NSLayoutConstraint!

  /// Both scale with the user's text size (see `TextScaling`)
  static var rowHeight: CGFloat { scaledRowHeight(contentHeight: 56.0) }
  static var rowHeightWithoutImage: CGFloat { scaledRowHeight(contentHeight: 28.0) }

  private var container: PlayableContainable?
  private weak var rootView: UITableViewController?

  override func awakeFromNib() {
    super.awakeFromNib()
    // This must be called in Main thread
    MainActor.assumeIsolated {
      applyTextSize()
      registerForTraitChanges([
        UITraitPreferredContentSizeCategory.self,
        UITraitHorizontalSizeClass.self,
      ]) { (self: Self, _) in
        self.applyTextSize()
      }
    }
  }

  /// Scales the fixed sizes of the xib with the user's text size, the fonts scale themselves
  /// (`ScaledLabel`). The title, subtitle and labels heights are only installed in regular width.
  private func applyTextSize() {
    let isRegularWidth = traitCollection.horizontalSizeClass == .regular
    titleHeightConstraint.constant = scaledConstant(18)
    subtitleHeightConstraint.constant = scaledConstant(18)
    infoHeightConstraint.constant = scaledConstant(isRegularWidth ? 18 : 15)
    labelsHeightConstraint.constant = scaledConstant(35)
    entityImageWidthConstraint.constant = scaledConstant(56)
    favoriteIconHeightConstraint.constant = scaledConstant(12)
    updateInfoLabelWidth()
  }

  /// Wide enough for the longest info text of the container type. Only installed in regular
  /// width, where the width is required: it stops growing at XXXL to leave room for the title.
  private func updateInfoLabelWidth() {
    let width: CGFloat
    switch container {
    case is Album: width = 75
    case is Artist: width = 230
    case is Genre: width = 260
    case is Podcast: width = 140
    default: width = 200
    }
    infoLabelWidthConstraint.constant = scaledConstant(width, maximum: .extraExtraExtraLarge)
  }

  func display(container: PlayableContainable, rootView: UITableViewController) {
    self.container = container
    self.rootView = rootView
    selectionStyle = .none
    titleLabel.text = container.name
    subtitleLabel.isHidden = container.subtitle == nil
    subtitleLabel.text = container.subtitle
    entityImage.display(
      theme: appDelegate.storage.settings.accounts.getSetting(container.account?.info).read
        .themePreference,
      container: container
    )
    let infoText = container.info(
      for: container.account?.apiType.asServerApiType,
      details: DetailInfoType(type: .short, settings: appDelegate.storage.settings)
    )
    infoLabel.isHidden = infoText.isEmpty
    infoLabel.text = infoText
    infoLabel.textAlignment = (traitCollection.horizontalSizeClass == .regular) ? .right : .left
    favoriteIconImage.isHidden = !container.isFavorite
    favoriteIconImage.tintColor = .red

    updateInfoLabelWidth()
    accessoryType = .disclosureIndicator
    backgroundColor = .systemBackground
  }
}

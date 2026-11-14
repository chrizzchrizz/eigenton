//
//  BasicTableCell.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 06.03.21.
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

import UIKit

class BasicTableCell: UITableViewCell {
  static let margin = UIView.defaultMarginCell

  // MARK: Text size

  /// Row height for a cell whose content (without the cell margins) is `contentHeight` tall at
  /// the default text size. Scales with the user's text size (see `TextScaling`).
  static func scaledRowHeight(contentHeight: CGFloat) -> CGFloat {
    TextScaling.scaledValue(contentHeight) + margin.top + margin.bottom
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    self.layoutMargins = BasicTableCell.margin
  }

  /// If true, the leading/trailing layout margins are provided by the table view (safe area plus
  /// system margin) so constraints to the content view margins follow it, e.g. below a sidebar.
  /// Top/bottom stay fixed.
  var usesSystemHorizontalMargins: Bool { false }

  override var layoutMargins: UIEdgeInsets {
    get {
      guard usesSystemHorizontalMargins else { return BasicTableCell.margin }
      var margins = super.layoutMargins
      margins.top = BasicTableCell.margin.top
      margins.bottom = BasicTableCell.margin.bottom
      return margins
    }
    set {
      guard usesSystemHorizontalMargins else { return }
      super.layoutMargins = newValue
    }
  }

  // MARK: - Separators

  /// The table view always draws the separator above the first and below the last row edge to
  /// edge, ignoring all insets. Therefore the cell draws its separators itself if the table view
  /// uses `separatorStyle = .none`. The lines are pinned to the margins of the content view.
  ///
  /// View whose leading edge the row separator starts at, defaults to the content margin.
  var separatorLeadingView: UIView? { nil }

  /// Hides the line above the first and below the last row, e.g. if the surrounding sections
  /// bring their own spacing.
  var hidesEdgeSeparators = false

  private enum SeparatorStyle {
    case row // below a row, ends slightly inside the margins
    case edge // above the first and below the last row, reaches slightly beyond the margins
  }

  private let topSeparator = BasicTableCell.createSeparatorLine()
  private let bottomSeparator = BasicTableCell.createSeparatorLine()
  private var topSeparatorHeight: NSLayoutConstraint?
  private var bottomSeparatorHeight: NSLayoutConstraint?
  private var bottomSeparatorHorizontal: [NSLayoutConstraint] = []
  private var appliedBottomStyle: SeparatorStyle?
  private weak var appliedLeadingView: UIView?

  private static func createSeparatorLine() -> UIView {
    let line = UIView()
    line.translatesAutoresizingMaskIntoConstraints = false
    line.backgroundColor = .separator
    line.isUserInteractionEnabled = false
    return line
  }

  var enclosingTableView: UITableView? {
    var view = superview
    while let current = view, !(current is UITableView) { view = current.superview }
    return view as? UITableView
  }

  private func installSeparatorsIfNeeded() {
    guard topSeparator.superview == nil else { return }
    let guide = contentView.layoutMarginsGuide
    contentView.addSubview(topSeparator)
    contentView.addSubview(bottomSeparator)
    let topHeight = topSeparator.heightAnchor.constraint(equalToConstant: 1)
    let bottomHeight = bottomSeparator.heightAnchor.constraint(equalToConstant: 1)
    topSeparatorHeight = topHeight
    bottomSeparatorHeight = bottomHeight
    NSLayoutConstraint.activate([
      topSeparator.topAnchor.constraint(equalTo: contentView.topAnchor),
      topSeparator.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
      topSeparator.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
      topHeight,
      bottomSeparator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      bottomHeight,
    ])
  }

  private func updateSeparators() {
    guard let table = enclosingTableView, table.separatorStyle == .none else {
      topSeparator.isHidden = true
      bottomSeparator.isHidden = true
      return
    }
    installSeparatorsIfNeeded()
    topSeparator.backgroundColor = table.separatorColor ?? .separator
    bottomSeparator.backgroundColor = table.separatorColor ?? .separator
    let indexPath = table.indexPath(for: self)
    let lastSection = table.numberOfSections - 1
    let isFirst = indexPath?.section == 0 && indexPath?.row == 0
    let isLast = indexPath?.section == lastSection &&
      indexPath?.row == table.numberOfRows(inSection: lastSection) - 1

    let height = 1.0 / max(traitCollection.displayScale, 1.0)
    topSeparatorHeight?.constant = height
    bottomSeparatorHeight?.constant = height
    topSeparator.isHidden = !isFirst || hidesEdgeSeparators
    bottomSeparator.isHidden = isLast && hidesEdgeSeparators

    let style: SeparatorStyle = isLast ? .edge : .row
    guard style != appliedBottomStyle || separatorLeadingView !== appliedLeadingView else { return }
    appliedBottomStyle = style
    appliedLeadingView = separatorLeadingView
    NSLayoutConstraint.deactivate(bottomSeparatorHorizontal)
    let guide = contentView.layoutMarginsGuide

    switch style {
    case .edge:
      bottomSeparatorHorizontal = [
        bottomSeparator.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
        bottomSeparator.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
      ]
    case .row:
      let leading = separatorLeadingView
        .map { bottomSeparator.leadingAnchor.constraint(equalTo: $0.leadingAnchor) }
        ?? bottomSeparator.leadingAnchor.constraint(equalTo: guide.leadingAnchor)
      bottomSeparatorHorizontal = [
        leading,
        bottomSeparator.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
      ]
    }
    NSLayoutConstraint.activate(bottomSeparatorHorizontal)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateSeparators()
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    markAsUnfocused()
  }
}

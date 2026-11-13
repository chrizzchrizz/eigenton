//
//  MacLargeTitle.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 13.11.26.
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

#if targetEnvironment(macCatalyst)
  import UIKit

  // MARK: - MacLargeTitle

  /// The Mac idiom shows no large navigation titles. This shows the view controller's title large
  /// at the top of its scroll view and, like the inline title on iOS, shows the title in the
  /// window's title bar only once the large title has scrolled away.
  ///
  /// Placement of the large title, depending on the scroll view:
  /// - table view: `installAsTableHeader()` once, after any own table header view was set
  /// - compositional layout: add `MacLargeTitle.layoutItem()` to the layout configuration's
  ///   boundary supplementary items, call `register()` once and return `header(for:)` from the
  ///   supplementary view provider for `MacLargeTitle.elementKind`
  /// - anything else: embed `makeTitleView()` at the top of the content, `titleHeight` tall
  ///
  /// In every case call `update()` in `viewIsAppearing`, the navigation controller resets the
  /// title bar for every shown screen. Scrolling is observed by the class itself.
  @MainActor
  final class MacLargeTitle {
    static let elementKind = "MacLargeTitle"

    /// Global header for the top of a compositional layout.
    static func layoutItem() -> NSCollectionLayoutBoundarySupplementaryItem {
      NSCollectionLayoutBoundarySupplementaryItem(
        layoutSize: NSCollectionLayoutSize(
          widthDimension: .fractionalWidth(1.0),
          heightDimension: .estimated(titleHeight)
        ),
        elementKind: elementKind,
        alignment: .top
      )
    }

    /// Height of the view returned by `makeTitleView()`.
    static let titleHeight: CGFloat = {
      let sizingView = MacLargeTitleView()
      sizingView.title = "Title"
      return sizingView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
    }()

    private weak var viewController: UIViewController?
    private let scrollView: UIScrollView
    /// The view showing the large title. Its frame stays valid while it is scrolled out of view.
    private weak var titleView: MacLargeTitleView?
    private var observations = [NSKeyValueObservation]()
    /// Table header holding only the large title; its height follows `updateTableHeaderSpacing`.
    private weak var titleOnlyTableHeader: UIView?
    private var tableHeaderSpacing: CGFloat = 0
    private var isTableHeaderSpacingCheckPending = false
    /// Bottom of the large title in scroll view coordinates, nil until it was laid out. The title
    /// sits at the top of the content, so the value stays valid while its view is scrolled away
    /// (and even after a reused header dropped it).
    private var largeTitleMaxY: CGFloat?
    /// Below the title when the content starts with a row instead of a header, like on Home where
    /// the first section header keeps this distance.
    private static let spacingAboveRows: CGFloat = 24

    init(viewController: UIViewController, scrollView: UIScrollView) {
      self.viewController = viewController
      self.scrollView = scrollView
      // content offset covers scrolling, content size data and layout changes
      self.observations = [
        scrollView.observe(\.contentOffset) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.updateTitleVisibility() }
        },
        scrollView.observe(\.contentSize) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.update() }
        },
      ]
    }

    private var title: String? {
      viewController?.navigationItem.title ?? viewController?.title
    }

    /// The view to show the large title in; the most recently created one is tracked.
    func makeTitleView() -> MacLargeTitleView {
      let titleView = MacLargeTitleView()
      titleView.title = title
      // a view embedded in a cell or header gets its frame only later
      titleView.didLayout = { [weak self] in
        self?.refreshLargeTitleMaxY()
        self?.updateTitleVisibility()
      }
      self.titleView = titleView
      return titleView
    }

    // MARK: Table view

    /// Puts the large title above the table's current header view, if any.
    func installAsTableHeader() {
      guard let tableView = scrollView as? UITableView else { return }
      let width = tableView.bounds.width
      let titleView = makeTitleView()
      titleView.frame = CGRect(x: 0, y: 0, width: width, height: Self.titleHeight)
      titleView.autoresizingMask = [.flexibleWidth]

      let existingHeader = tableView.tableHeaderView
      // replacing the header later would remove the old one from its new superview, the container
      tableView.tableHeaderView = nil
      let height = titleView.frame.height + (existingHeader?.frame.height ?? 0)
      // sized before the subviews are added, autoresizing would otherwise widen them
      let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
      container.preservesSuperviewLayoutMargins = true
      container.addSubview(titleView)
      if let existingHeader {
        existingHeader.frame = CGRect(
          x: 0,
          y: titleView.frame.height,
          width: width,
          height: existingHeader.frame.height
        )
        existingHeader.autoresizingMask = [.flexibleWidth]
        container.addSubview(existingHeader)
      } else {
        titleOnlyTableHeader = container
      }
      tableView.tableHeaderView = container
    }

    /// Checked after the current layout pass: replacing the table header from within the table's
    /// own layout (content size changes) would relayout it re-entrantly.
    private func scheduleTableHeaderSpacingCheck() {
      guard titleOnlyTableHeader != nil, !isTableHeaderSpacingCheckPending else { return }
      isTableHeaderSpacingCheckPending = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        isTableHeaderSpacingCheckPending = false
        updateTableHeaderSpacing()
      }
    }

    /// The first section header (if the sort order has headers) keeps its distance to the title
    /// itself, the first row needs extra space.
    private func updateTableHeaderSpacing() {
      guard let tableView = scrollView as? UITableView, let container = titleOnlyTableHeader,
            tableView.tableHeaderView === container else { return }
      let hasSectionHeader = tableView.numberOfSections > 0 &&
        tableView.rectForHeader(inSection: 0).height > 0
      let spacing = hasSectionHeader ? 0 : Self.spacingAboveRows
      guard spacing != tableHeaderSpacing else { return }
      tableHeaderSpacing = spacing
      container.frame.size.height = Self.titleHeight + spacing
      // reassigning makes the table apply the new height
      tableView.tableHeaderView = container
    }

    // MARK: Compositional layout

    func register() {
      guard let collectionView = scrollView as? UICollectionView else { return }
      collectionView.register(
        MacLargeTitleCollectionHeader.self,
        forSupplementaryViewOfKind: Self.elementKind,
        withReuseIdentifier: Self.elementKind
      )
    }

    func header(for indexPath: IndexPath) -> UICollectionReusableView? {
      guard let collectionView = scrollView as? UICollectionView else { return nil }
      let header = collectionView.dequeueReusableSupplementaryView(
        ofKind: Self.elementKind,
        withReuseIdentifier: Self.elementKind,
        for: indexPath
      ) as! MacLargeTitleCollectionHeader
      header.embed(makeTitleView())
      return header
    }

    // MARK: Title bar

    /// Full check, after appearing and content changes; scrolling only updates the visibility.
    func update() {
      if let titleView, titleView.title != title {
        // the title may be set after the large title was created
        titleView.title = title
      }
      scheduleTableHeaderSpacingCheck()
      refreshLargeTitleMaxY()
      updateTitleVisibility()
    }

    private func refreshLargeTitleMaxY() {
      // a removed title view (e.g. of a reused header) keeps the last known position
      guard let titleView, titleView.isDescendant(of: scrollView) else { return }
      largeTitleMaxY = titleView.convert(titleView.bounds, to: scrollView).maxY
    }

    private func updateTitleVisibility() {
      guard let viewController,
            viewController.navigationController?.topViewController === viewController,
            let titlebar = viewController.view.window?.windowScene?.titlebar,
            // without a title the navigation controller hides the title bar title (app name)
            let title, !title.isEmpty else { return }
      let isLargeTitleDisplayed = titleView?.isDescendant(of: scrollView) ?? false
      let isLargeTitleVisible: Bool
      if viewController.contentUnavailableConfiguration != nil, !isLargeTitleDisplayed {
        // an empty grid has no header to show the large title in
        isLargeTitleVisible = false
      } else if let largeTitleMaxY {
        let visibleTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        isLargeTitleVisible = visibleTop < largeTitleMaxY
      } else {
        // not laid out yet, it appears at the top: avoid showing the title twice meanwhile
        isLargeTitleVisible = true
      }
      let visibility: UITitlebarTitleVisibility = isLargeTitleVisible ? .hidden : .visible
      if titlebar.titleVisibility != visibility {
        titlebar.titleVisibility = visibility
      }
    }
  }

  // MARK: - MacLargeTitleView

  /// Large bold title aligned with the content via the superview's layout margins.
  final class MacLargeTitleView: UIView {
    private let titleLabel: UILabel = {
      let lbl = UILabel()
      lbl.translatesAutoresizingMaskIntoConstraints = false
      let font = UIFont.preferredFont(forTextStyle: .largeTitle)
      lbl.font = UIFont(
        descriptor: font.fontDescriptor.addingAttributes([
          .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold],
        ]),
        size: font.pointSize
      )
      lbl.textColor = .label
      lbl.accessibilityTraits = .header
      return lbl
    }()

    var title: String? {
      get { titleLabel.text }
      set { titleLabel.text = newValue }
    }

    var didLayout: (() -> ())?

    override init(frame: CGRect) {
      super.init(frame: frame)
      // a full width header, align the title with the content
      preservesSuperviewLayoutMargins = true
      addSubview(titleLabel)
      NSLayoutConstraint.activate([
        titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
        titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
        titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
        titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      didLayout?()
    }
  }

  // MARK: - MacLargeTitleCollectionHeader

  final class MacLargeTitleCollectionHeader: UICollectionReusableView {
    private var titleView: MacLargeTitleView?

    override init(frame: CGRect) {
      super.init(frame: frame)
      preservesSuperviewLayoutMargins = true
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func embed(_ titleView: MacLargeTitleView) {
      self.titleView?.removeFromSuperview()
      self.titleView = titleView
      titleView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(titleView)
      NSLayoutConstraint.activate([
        titleView.leadingAnchor.constraint(equalTo: leadingAnchor),
        titleView.trailingAnchor.constraint(equalTo: trailingAnchor),
        titleView.topAnchor.constraint(equalTo: topAnchor),
        titleView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }
  }
#endif

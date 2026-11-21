//
//  SimilarContentFooterView.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 15.10.26.
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

import AmperfyKit
import UIKit

// MARK: - SimilarContentTile

private class SimilarContentTile: UIControl {
  static let imageSize: CGFloat = 120.0

  private let container: PlayableContainable
  private let onTap: () -> ()

  init(
    container: PlayableContainable,
    theme: ThemePreference,
    isImageCircular: Bool,
    onTap: @escaping () -> ()
  ) {
    self.container = container
    self.onTap = onTap
    super.init(frame: .zero)

    let imageView = EntityImageView(frame: CGRect(
      x: 0,
      y: 0,
      width: Self.imageSize,
      height: Self.imageSize
    ))
    imageView.display(theme: theme, container: container, cornerRadius: .medium)
    // circular image across the whole tile without a colored frame, as the footer itself
    // already sits on the artwork color of the detail screen
    if isImageCircular {
      imageView.setCircularImage(frameColor: { _ in .clear }, inset: 0, isPlaceholderCircular: true)
    }
    imageView.isUserInteractionEnabled = false

    let titleLabel = UILabel()
    titleLabel.font = .preferredFont(forTextStyle: .footnote)
    titleLabel.textColor = .label
    titleLabel.text = container.name
    titleLabel.textAlignment = isImageCircular ? .center : .natural
    let subtitleLabel = UILabel()
    subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.text = container.subtitle
    subtitleLabel.isHidden = container.subtitle == nil
    subtitleLabel.textAlignment = titleLabel.textAlignment

    let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, subtitleLabel])
    stack.axis = .vertical
    stack.spacing = 2
    // gap between the image and the title, like the tiles on Home
    stack.setCustomSpacing(8, after: imageView)
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.widthAnchor.constraint(equalToConstant: Self.imageSize),
      imageView.heightAnchor.constraint(equalToConstant: Self.imageSize),
    ])
    addTarget(self, action: #selector(tapped), for: .touchUpInside)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc
  private func tapped() {
    onTap()
  }
}

// MARK: - SimilarContentFooterView

/// Table footer showing horizontally scrollable rows of similar artists and albums.
/// Rows without content are hidden; the whole view is hidden if nothing is left.
/// Selecting an item pushes its detail screen onto the navigation controller of the owner.
/// The content only comes from the server and is never stored, so the footer is taken out of the
/// table in offline mode; back online it returns with its rows and loads the empty ones.
class SimilarContentFooterView: UIView {
  private let account: Account
  private weak var owner: UIViewController?
  private let stack = UIStackView()
  private let artistsRow = UIStackView()
  private let albumsRow = UIStackView()
  private let artistsSection: UIView
  private let albumsSection: UIView
  private let backgroundView = UIView()
  /// Padding between the top of the darker background and the first title,
  /// also used as the gap between the content above and the background.
  private static let topPadding: CGFloat = 32

  init(account: Account, owner: UIViewController) {
    self.account = account
    self.owner = owner
    self.artistsSection = Self.createSection(
      title: NSLocalizedString("Similar Artists", comment: ""),
      row: artistsRow
    )
    self.albumsSection = Self.createSection(
      title: NSLocalizedString("You might also like", comment: ""),
      row: albumsRow
    )
    super.init(frame: .zero)
    // darkens whatever background the screen shows, also the artwork color of the detail screens
    backgroundView.backgroundColor = .black.withAlphaComponent(0.15)
    addSubview(backgroundView)

    stack.axis = .vertical
    stack.spacing = 32
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.isLayoutMarginsRelativeArrangement = true
    stack.layoutMargins = UIEdgeInsets(top: 2 * Self.topPadding, left: 0, bottom: 16, right: 0)
    stack.addArrangedSubview(artistsSection)
    stack.addArrangedSubview(albumsSection)
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    artistsSection.isHidden = true
    albumsSection.isHidden = true
    appDelegate.notificationHandler.register(
      self,
      selector: #selector(offlineModeChanged),
      name: .offlineModeChanged,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private var theme: ThemePreference {
    appDelegate.storage.settings.accounts.getSetting(account.info).read.themePreference
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // the footer is the last content of the table, so its background continues below it to the
    // end of the page: into the bottom inset behind the tab bar and the bounce area
    let extensionHeight = max(superview?.bounds.height ?? 0, 1000)
    backgroundView.frame = CGRect(
      x: 0,
      y: Self.topPadding,
      width: bounds.width,
      height: bounds.height - Self.topPadding + extensionHeight
    )
  }

  var hasContent: Bool { !artistsSection.isHidden || !albumsSection.isHidden }

  private weak var tableView: UITableView?
  /// What the last `load` was for, to load it again when going back online
  private var artist: Artist?
  private var album: Album?
  private var artistsTask: Task<(), Never>?
  private var albumsTask: Task<(), Never>?

  deinit {
    // the owner was closed: don't keep the server requests and the tiles alive for nobody
    artistsTask?.cancel()
    albumsTask?.cancel()
  }

  /// Requests the artists similar to `artist` and the albums similar to `album` in parallel and
  /// shows the footer below `tableView` once a row has content, so the artists don't wait for the
  /// albums (those need the server's external agents and can take several seconds).
  /// Rows that are still empty, because their request failed or returned nothing, are requested
  /// again on the next call; rows that have content are kept.
  /// Similar content is optional, so a failing server agent is only logged and never shown.
  /// Nothing is requested in offline mode.
  func load(similarTo artist: Artist?, album: Album? = nil, in tableView: UITableView) {
    self.tableView = tableView
    self.artist = artist
    self.album = album
    guard appDelegate.storage.settings.user.isOnlineMode else { return }
    let librarySyncer = appDelegate.getMeta(account.info).librarySyncer
    // a cancelled task (deinit, offline mode) leaves the state alone: a new task may run already
    if let artist, artistsSection.isHidden, artistsTask == nil {
      artistsTask = Task { [weak self] in
        let artists: [Artist]
        do {
          artists = try await librarySyncer.requestSimilarArtists(artist: artist, count: 15)
        } catch {
          guard let self, !Task.isCancelled else { return }
          report(topic: "Similar Artists", error: error)
          artistsTask = nil
          return
        }
        guard let self, !Task.isCancelled else { return }
        artistsTask = nil
        display(artists: artists)
      }
    }
    if let album, albumsSection.isHidden, albumsTask == nil {
      albumsTask = Task { [weak self] in
        let albums: [Album]
        do {
          albums = try await librarySyncer.requestSimilarAlbums(album: album, count: 40)
        } catch {
          guard let self, !Task.isCancelled else { return }
          report(topic: "Similar Albums", error: error)
          albumsTask = nil
          return
        }
        // the artists row is above the albums row: showing it after the albums would push the
        // albums down while the user may already look at them or tap one
        let artistsTask = self?.artistsTask
        await artistsTask?.value
        guard let self, !Task.isCancelled else { return }
        albumsTask = nil
        display(albums: Array(albums.prefix(12)))
      }
    }
  }

  @objc
  private func offlineModeChanged() {
    guard let tableView else { return }
    if appDelegate.storage.settings.user.isOnlineMode {
      showInTableView()
      // the album's artist may only be known since the last load
      load(similarTo: album?.artist ?? artist, album: album, in: tableView)
    } else {
      hide()
    }
  }

  /// Stops the requests and takes the footer out of the table; the loaded rows are kept for
  /// going back online.
  private func hide() {
    artistsTask?.cancel()
    artistsTask = nil
    albumsTask?.cancel()
    albumsTask = nil
    if let tableView, tableView.tableFooterView === self {
      tableView.tableFooterView = nil
    }
  }

  private func report(topic: String, error: Error) {
    appDelegate.eventLogger.report(topic: topic, error: error, displayPopup: false)
  }

  /// Makes the footer the table's footer once it has content and sizes it.
  private func showInTableView() {
    guard hasContent, let tableView else { return }
    if tableView.tableFooterView !== self {
      tableView.tableFooterView = self
    }
    layout(in: tableView)
  }

  /// Sizes the footer to fit the width of the table view; the table view only picks up
  /// a changed footer height when the footer is assigned again.
  func layout(in tableView: UITableView) {
    guard tableView.tableFooterView === self, tableView.bounds.width > 0 else { return }
    setNeedsLayout() // the background below the footer follows the height of the table view
    let height = systemLayoutSizeFitting(
      CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    guard frame.size != CGSize(width: tableView.bounds.width, height: height) else { return }
    frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: height)
    tableView.tableFooterView = self
  }

  private func display(artists: [Artist]) {
    fill(
      row: artistsRow,
      section: artistsSection,
      containers: artists,
      isImageCircular: true
    ) { [weak self] artist in
      guard let self else { return }
      owner?.navigationController?.pushViewController(
        AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
        animated: true
      )
    }
  }

  private func display(albums: [Album]) {
    fill(row: albumsRow, section: albumsSection, containers: albums) { [weak self] album in
      guard let self else { return }
      owner?.navigationController?.pushViewController(
        AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
        animated: true
      )
    }
  }

  private func fill<T: PlayableContainable>(
    row: UIStackView,
    section: UIView,
    containers: [T],
    isImageCircular: Bool = false,
    onSelect: @escaping (T) -> ()
  ) {
    guard !containers.isEmpty else { return }
    row.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for container in containers {
      row.addArrangedSubview(SimilarContentTile(
        container: container,
        theme: theme,
        isImageCircular: isImageCircular
      ) {
        onSelect(container)
      })
    }
    section.isHidden = false
    showInTableView()
  }

  private static func createSection(title: String, row: UIStackView) -> UIView {
    let titleLabel = UILabel()
    titleLabel.font = .preferredFont(forTextStyle: .title3).bold
    titleLabel.text = title

    row.axis = .horizontal
    row.spacing = 12
    row.alignment = .top
    row.translatesAutoresizingMaskIntoConstraints = false

    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.addSubview(row)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      // the scroll view takes exactly the height of its tiles, so no blank space is left below them
      scrollView.heightAnchor.constraint(equalTo: row.heightAnchor),
    ])
    scrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

    let titleContainer = UIStackView(arrangedSubviews: [titleLabel])
    titleContainer.isLayoutMarginsRelativeArrangement = true
    titleContainer.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

    let section = UIStackView(arrangedSubviews: [titleContainer, scrollView])
    section.axis = .vertical
    section.spacing = 8
    return section
  }
}

extension UIFont {
  fileprivate var bold: UIFont {
    guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
    return UIFont(descriptor: descriptor, size: 0)
  }
}

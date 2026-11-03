//
//  PopupPlayer+Animations.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 12.02.24.
//  Copyright (c) 2024 Maximilian Bauer. All rights reserved.
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

extension PopupPlayerVC {
  static let displaStyleAnimationDuration = TimeInterval(0.2)

  /// Stores the queue as the popup player's view, also if the lyrics were shown before.
  static func showQueuePersistent(appDelegate: AppDelegate) {
    appDelegate.userStatistics.usedAction(.changePlayerDisplayStyle)
    appDelegate.storage.settings.user.isPlayerLyricsDisplayed = false
    appDelegate.storage.settings.user.playerDisplayStyle = .compact
  }

  func switchDisplayStyleOptionPersistent() {
    if currentLayout == .lyrics {
      // the playlist button leaves the lyrics and shows the queue
      Self.showQueuePersistent(appDelegate: appDelegate)
    } else {
      appDelegate.userStatistics.usedAction(.changePlayerDisplayStyle)
      var displayStyle = appDelegate.storage.settings.user.playerDisplayStyle
      displayStyle.switchToNextStyle()
      appDelegate.storage.settings.user.playerDisplayStyle = displayStyle
    }
    applyDisplayLayout(animated: true)
  }

  var targetLayout: PopupPlayerLayout {
    if appDelegate.storage.settings.user.isPlayerLyricsDisplayed,
       largeCurrentlyPlayingView?.isLyricsButtonAllowedToDisplay ?? false {
      return .lyrics
    }
    switch appDelegate.storage.settings.user.playerDisplayStyle {
    case .compact: return .compact
    case .large: return .large
    }
  }

  private struct LayoutElements {
    let view: UIView
    let container: UIView
    let artwork: UIView
    let favorite: UIView
    let options: UIView
  }

  private func layoutView(of layout: PopupPlayerLayout) -> UIView {
    switch layout {
    case .large: return largePlayerPlaceholderView
    case .compact: return tableView
    case .lyrics: return lyricsLayoutView
    }
  }

  private func elements(of layout: PopupPlayerLayout) -> LayoutElements? {
    switch layout {
    case .large:
      guard let large = largeCurrentlyPlayingView else { return nil }
      return LayoutElements(
        view: largePlayerPlaceholderView,
        container: large,
        artwork: large.artworkImage,
        favorite: large.favoriteButton,
        options: large.optionsButton
      )
    case .compact:
      guard let cell = currentlyPlayingTableCell else { return nil }
      return LayoutElements(
        view: tableView,
        container: cell,
        artwork: cell.artworkImage,
        favorite: cell.favoriteButton,
        options: cell.optionsButton
      )
    case .lyrics:
      guard let header = lyricsHeaderCell else { return nil }
      return LayoutElements(
        view: lyricsLayoutView,
        container: header,
        artwork: header.artworkImage,
        favorite: header.favoriteButton,
        options: header.optionsButton
      )
    }
  }

  func applyDisplayLayout(animated: Bool = true) {
    let target = targetLayout
    let previous = currentLayout
    // the large view decides what it shows: artwork or the lyrics of the lyrics layout.
    // Showing the same element again would reload the lyrics and reset their scroll position.
    if let largeView = largeCurrentlyPlayingView {
      let element = largeView.getDisplayElementBasedOnConfig()
      if element != largeView.displayElement {
        largeView.display(element: element)
      }
    }
    guard previous != target || !animated else { return }
    currentLayout = target

    switch target {
    case .compact:
      scrollToCurrentlyPlayingRow()
      currentlyPlayingTableCell?.refresh()
    case .large:
      largeCurrentlyPlayingView?.refresh()
    case .lyrics:
      lyricsHeaderCell?.refresh()
    }

    if isSideBySide {
      applySideBySideLayout(target: target, animated: animated && previous != nil)
      return
    }

    let allViews: [UIView] = [largePlayerPlaceholderView, tableView, lyricsLayoutView]
    // the cells may not exist yet, the visibility must not depend on them
    func showInstantly() {
      let targetView = layoutView(of: target)
      for layoutView in allViews {
        let isTarget = layoutView === targetView
        layoutView.alpha = isTarget ? 1.0 : 0.0
        layoutView.isHidden = !isTarget
      }
      lyricsContainerView.alpha = 1.0
    }

    guard animated, let previous, previous != target,
          let sourceElements = elements(of: previous),
          let targetElements = elements(of: target)
    else {
      showInstantly()
      return
    }

    // a scrolled queue would make the artwork start at a stale position
    if previous == .compact {
      scrollToCurrentlyPlayingRow()
      tableView.layoutIfNeeded()
    }

    // 1. Force autolayout to layout
    // the containers, not only the artwork: their margins decide where the artwork ends up
    targetElements.view.isHidden = false
    view.layoutIfNeeded()
    sourceElements.container.layoutIfNeeded()
    targetElements.container.layoutIfNeeded()
    targetElements.artwork.layoutIfNeeded()
    // 2. Calculate source and target frames and 3. animate replicas of the elements
    animateArtwork(
      image: largeCurrentlyPlayingView?.artworkImage.image,
      sourceView: sourceElements.artwork,
      targetView: targetElements.artwork,
      sourceFrame: frameInsideThePlaceholder(of: sourceElements.artwork),
      targetFrame: frameInsideThePlaceholder(of: targetElements.artwork)
    )
    targetElements.favorite.layoutIfNeeded()
    animateFavorite(
      sourceView: sourceElements.favorite,
      targetView: targetElements.favorite,
      sourceFrame: frameInsideThePlaceholder(of: sourceElements.favorite),
      targetFrame: frameInsideThePlaceholder(of: targetElements.favorite)
    )
    targetElements.options.layoutIfNeeded()
    animateOptions(
      sourceView: sourceElements.options,
      targetView: targetElements.options,
      sourceFrame: frameInsideThePlaceholder(of: sourceElements.options),
      targetFrame: frameInsideThePlaceholder(of: targetElements.options)
    )

    let viewToDisapper = sourceElements.view
    let viewToApper = targetElements.view
    viewToDisapper.isHidden = false
    viewToApper.isHidden = false
    // queue and lyrics have the same header at the same place: a cross fade would dim the title for
    // a moment, so the incoming view stays opaque below the fading one and only the lyrics fade in
    let isHeaderShared = Set([previous, target]) == Set([.compact, .lyrics])
    lyricsContainerView.alpha = 1.0
    if isHeaderShared {
      viewToApper.alpha = 1.0
      if target == .lyrics {
        lyricsContainerView.alpha = 0.0
        UIView.animate(
          withDuration: Self.displaStyleAnimationDuration * 2 / 3,
          delay: Self.displaStyleAnimationDuration / 3,
          animations: { self.lyricsContainerView.alpha = 1.0 }
        )
      }
    }
    UIView.animate(
      withDuration: Self.displaStyleAnimationDuration * 2 / 3,
      delay: 0,
      animations: ({
        viewToDisapper.alpha = 0.0
      }),
      completion: { _ in
        // a faded out view must not swallow touches; side by side the views are managed there
        if self.currentLayout != previous, !self.isSideBySide {
          viewToDisapper.isHidden = true
        }
      }
    )
    if !isHeaderShared {
      UIView.animate(
        withDuration: Self.displaStyleAnimationDuration * 2 / 3,
        delay: Self.displaStyleAnimationDuration / 3,
        animations: ({
          viewToApper.alpha = 1.0
        }),
        completion: nil
      )
    }
  }

  /// The large view stays visible in the player column, queue or lyrics fade in on the right.
  private func applySideBySideLayout(target: PopupPlayerLayout, animated: Bool) {
    let listView: UIView? = switch target {
    case .large: nil
    case .compact: tableView
    case .lyrics: lyricsLayoutView
    }
    let otherListViews: [UIView] = [tableView, lyricsLayoutView].filter { $0 !== listView }
    largePlayerPlaceholderView.isHidden = false
    largePlayerPlaceholderView.alpha = 1.0
    lyricsContainerView.alpha = 1.0
    largeCurrentlyPlayingView?.refresh()
    setPlayerColumnCentered(target == .large)
    listView?.isHidden = false

    guard animated else {
      for otherView in otherListViews {
        otherView.alpha = 0.0
        otherView.isHidden = true
      }
      listView?.alpha = 1.0
      return
    }
    UIView.animate(
      withDuration: Self.displaStyleAnimationDuration * 1.5,
      delay: 0,
      options: .curveEaseInOut,
      animations: {
        self.view.layoutIfNeeded()
        for otherView in otherListViews {
          otherView.alpha = 0.0
        }
        listView?.alpha = 1.0
      },
      completion: { _ in
        // a faded out view must not swallow touches, a later switch might have shown it again
        for otherView in otherListViews where otherView.alpha == 0.0 {
          otherView.isHidden = true
        }
      }
    )
  }

  /// Frame of the view in the coordinate space of the player, limited to the placeholder.
  private func frameInsideThePlaceholder(of view: UIView) -> CGRect {
    limitSizeToInsideThePlaceholder(
      targetFrame: self.view.convert(view.bounds, from: view),
      placeholderFrame: largePlayerPlaceholderView.frame
    )
  }

  private func limitSizeToInsideThePlaceholder(
    targetFrame: CGRect,
    placeholderFrame: CGRect
  )
    -> CGRect {
    if targetFrame.origin.y < placeholderFrame.origin.y - targetFrame.height {
      return CGRect(
        x: targetFrame.origin.x,
        y: placeholderFrame.origin.y - targetFrame.height,
        width: targetFrame.width,
        height: targetFrame.height
      )
    } else if targetFrame.origin.y > placeholderFrame.origin.y + placeholderFrame.height {
      return CGRect(
        x: targetFrame.origin.x,
        y: placeholderFrame.origin.y + placeholderFrame.height,
        width: targetFrame.width,
        height: targetFrame.height
      )
    } else {
      return targetFrame
    }
  }

  private func animateArtwork(
    image: UIImage?,
    sourceView: UIView,
    targetView: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect
  ) {
    // 3. Create a replica of the artwork
    let fakeImageView = RoundedImage(frame: sourceFrame)
    fakeImageView.backgroundColor = .clear
    fakeImageView.image = image
    fakeImageView.contentMode = .scaleAspectFill
    fakeImageView.clipsToBounds = true
    fakeImageView.alpha = sourceView.alpha
    fakeImageView.layer.cornerRadius = sourceView.layer.cornerRadius

    // animate alpha for active lyrics view
    UIView.animate(
      withDuration: Self.displaStyleAnimationDuration,
      delay: 0,
      options: .curveEaseOut,
      animations: {
        fakeImageView.alpha = targetView.alpha
        fakeImageView.layer.cornerRadius = targetView.layer.cornerRadius
      },
      completion: { _ in
        fakeImageView.alpha = targetView.alpha
      }
    )

    animatePlayStyleObject(
      object: fakeImageView,
      sourceView: sourceView,
      targetView: targetView,
      sourceFrame: sourceFrame,
      targetFrame: targetFrame
    )
  }

  private func animateFavorite(
    sourceView: UIView,
    targetView: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect
  ) {
    let fakeButton = UIButton(frame: sourceFrame)
    refreshFavoriteButton(button: fakeButton)
    animatePlayStyleObject(
      object: fakeButton,
      sourceView: sourceView,
      targetView: targetView,
      sourceFrame: sourceFrame,
      targetFrame: targetFrame
    )
  }

  private func animateOptions(
    sourceView: UIView,
    targetView: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect
  ) {
    let fakeButton = UIButton(frame: sourceFrame)
    refreshOptionButton(button: fakeButton, rootView: self)
    animatePlayStyleObject(
      object: fakeButton,
      sourceView: sourceView,
      targetView: targetView,
      sourceFrame: sourceFrame,
      targetFrame: targetFrame
    )
  }

  private func animatePlayStyleObject(
    object: UIView,
    sourceView: UIView,
    targetView: UIView,
    sourceFrame: CGRect,
    targetFrame: CGRect
  ) {
    sourceView.isHidden = true
    targetView.isHidden = true

    view.addSubview(object)

    UIView.animate(
      withDuration: Self.displaStyleAnimationDuration,
      delay: 0,
      options: .curveEaseOut,
      animations: {
        object.frame = targetFrame
      },
      completion: { _ in
        sourceView.isHidden = false
        targetView.isHidden = false
        object.removeFromSuperview()
      }
    )
  }
}

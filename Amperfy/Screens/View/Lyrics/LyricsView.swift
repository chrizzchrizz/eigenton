//
//  LyricsView.swift
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
import CoreMedia
import Foundation
import UIKit

class LyricsView: UITableView, UITableViewDataSource, UITableViewDataSourcePrefetching,
  UITableViewDelegate {
  private var lyrics: StructuredLyrics? = nil
  private var lyricModels: [LyricTableCellModel] = []
  private var lastIndex: Int?
  private var lineSpacing: CGFloat = 16

  /// Size of the lyrics text; the line spacing scales with it.
  var fontSize: CGFloat = LyricTableCellModel.defaultFontSize {
    didSet {
      guard oldValue != fontSize else { return }
      lineSpacing = 16 * fontSize / LyricTableCellModel.defaultFontSize
      reloadViewModels()
    }
  }
  /// A gap before the first line longer than this is shown as pause.
  private let introPauseThreshold = CMTime(value: 5, timescale: 1)
  /// A seek to the start of a line can end a few milliseconds before it, the line still has to be active.
  /// Synced lyrics have no end time: the last line stays current this long before it is blurred.
  private let lastLineHoldTime = CMTime(value: 5, timescale: 1)
  private let lineStartTolerance = CMTime(value: 250, timescale: 1_000)
  /// Start of the line the user tapped, the tolerance only applies until playback reaches it.
  private var selectedLineStart: CMTime?
  private var suppressAutoScrollUntil: Date?
  private let autoScrollSuppressionInterval: TimeInterval = 5.0

  public var onLyricSelected: ((LyricsLine) -> ())?

  override init(frame: CGRect, style: UITableView.Style) {
    super.init(frame: frame, style: style)
    commonInit()
  }

  public required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    commonInit()
  }

  private func commonInit() {
    register(LyricTableCell.self, forCellReuseIdentifier: LyricTableCell.typeName)

    separatorStyle = .none
    clipsToBounds = true

    dataSource = self
    prefetchDataSource = self
    delegate = self
    allowsSelection = true

    backgroundColor = .clear
  }

  private lazy var fadeMask: CAGradientLayer = {
    let mask = CAGradientLayer()
    mask.colors = [
      UIColor.white.withAlphaComponent(0).cgColor,
      UIColor.white.cgColor,
      UIColor.white.cgColor,
      UIColor.white.withAlphaComponent(0).cgColor,
    ]
    mask.locations = [0, 0.2, 0.8, 1]
    return mask
  }()

  override func layoutSubviews() {
    super.layoutSubviews()
    // layout runs on every scroll step: reuse the mask and skip unchanged insets
    reloadInsets()

    if layer.mask == nil {
      layer.mask = fadeMask
      layer.masksToBounds = true
    }
    // the table scrolls its bounds, the mask has to stay at the visible part
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fadeMask.frame = bounds
    CATransaction.commit()
  }

  public func display(lyrics: StructuredLyrics) {
    self.lyrics = lyrics
    reloadViewModels()
  }

  public func highlightAllLyrics() {
    lyricModels.forEach { $0.isActiveLine = true }
  }

  public func clear() {
    lyrics = nil
    reloadViewModels()
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    lyricModels.count
  }

  public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    guard let model = lyricModels.object(at: indexPath.row) else { return 0.0 }
    return lineSpacing + model.calcHeight(containerWidth: bounds.width)
  }

  public func tableView(
    _ tableView: UITableView,
    estimatedHeightForRowAt indexPath: IndexPath
  )
    -> CGFloat {
    guard let model = lyricModels.object(at: indexPath.row) else { return 0.0 }
    return lineSpacing + model.calcHeight(containerWidth: bounds.width)
  }

  public func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    let cell = dequeueReusableCell(
      withIdentifier: LyricTableCell.typeName,
      for: indexPath
    ) as! LyricTableCell
    if let model = lyricModels.object(at: indexPath.row) {
      cell.display(model: model)
    }
    return cell
  }

  /// Renders the blurred images before the rows scroll into view.
  public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
    let width = LyricTableCell.adjustContainerWidthForMargins(containerWidth: bounds.width)
    for indexPath in indexPaths {
      guard let model = lyricModels.object(at: indexPath.row), !model.isActiveLine else { continue }
      model.prepareBlurredImage(
        width: width,
        height: lineSpacing + model.calcHeight(containerWidth: bounds.width),
        scale: traitCollection.displayScale
      )
    }
  }

  public func tableView(
    _ tableView: UITableView,
    shouldHighlightRowAt indexPath: IndexPath
  )
    -> Bool {
    guard lyrics?.synced == true,
          let model = lyricModels.object(at: indexPath.row),
          !model.isPause,
          model.lyric?.start != nil
    else { return false }
    return true
  }

  public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    guard lyrics?.synced == true,
          let model = lyricModels.object(at: indexPath.row),
          !model.isPause,
          let lyric = model.lyric,
          lyric.start != nil
    else { return }
    suppressAutoScrollUntil = Date().addingTimeInterval(autoScrollSuppressionInterval)
    onLyricSelected?(lyric)
    // do not wait for the next player tick to highlight the selected line;
    // scrolling to the start would reset the tolerance, so it is set afterwards
    selectedLineStart = nil
    scroll(toTime: lyric.startTime)
    selectedLineStart = lyric.startTime
  }

  public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    suppressAutoScrollUntil = Date().addingTimeInterval(autoScrollSuppressionInterval)
  }

  public func scrollViewDidEndDragging(
    _ scrollView: UIScrollView,
    willDecelerate decelerate: Bool
  ) {
    if !decelerate {
      suppressAutoScrollUntil = Date().addingTimeInterval(autoScrollSuppressionInterval)
    }
  }

  public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    suppressAutoScrollUntil = Date().addingTimeInterval(autoScrollSuppressionInterval)
  }

  private func reloadViewModels() {
    lyricModels.removeAll()
    lastIndex = nil
    reloadInsets()

    guard let lyrics = lyrics else {
      reloadData()
      return
    }

    if lyrics.synced, let firstStart = lyrics.line.first?.startTime,
       firstStart > introPauseThreshold {
      var intro = LyricsLine()
      intro.start = 0
      let model = LyricTableCellModel(lyric: intro, isPause: true, fontSize: fontSize)
      model.isActiveLine = false
      lyricModels.append(model)
    }
    for lyric in lyrics.line {
      // synced lyrics mark pauses with empty lines; unsynced ones use them as paragraph breaks
      let isPause = lyrics.synced && lyric.value.trimmingCharacters(in: .whitespaces).isEmpty
      let model = LyricTableCellModel(lyric: lyric, isPause: isPause, fontSize: fontSize)
      // without timing there is no current line, so nothing may be blurred
      model.isActiveLine = !lyrics.synced
      lyricModels.append(model)
    }
    reloadData()
  }

  func reloadInsets() {
    let newInset = UIEdgeInsets(
      top: frame.height / 4,
      left: 0,
      bottom: frame.height / 2,
      right: 0
    )
    guard contentInset != newInset else { return }
    contentInset = newInset
  }

  func scroll(toTime time: CMTime) {
    guard let lyrics = lyrics,
          !lyricModels.isEmpty,
          lyrics.synced // if the lyrics are not synced -> only display
    else { return }

    let isAutoScrollAllowed: Bool = {
      guard let suppressUntil = suppressAutoScrollUntil else { return true }
      return Date() >= suppressUntil
    }()

    var tolerance = CMTime.zero
    if let selectedLineStart {
      if time >= selectedLineStart {
        self.selectedLineStart = nil
      } else if selectedLineStart - time <= lineStartTolerance {
        tolerance = lineStartTolerance
      }
    }

    // after the last line there is no next one, the last line stays the current line
    let indexOfNextLine = lyricModels.firstIndex(where: {
      ($0.lyric?.startTime ?? .zero) > time + tolerance
    }) ?? lyricModels.count

    var prevIndex: Int?
    let indexOfCurrentLine = max(indexOfNextLine - 1, 0)
    if let lastIndex = lastIndex,
       let lastIndexModel = lyricModels.object(at: lastIndex) {
      // resetting the current line would make it flicker between blurred and sharp
      if lastIndex != indexOfCurrentLine {
        lastIndexModel.isActiveLine = false
      }
      prevIndex = lastIndex
    }
    lastIndex = indexOfCurrentLine
    let curIndexModel = lyricModels.object(at: indexOfCurrentLine)
    // nothing follows the last line: once it is over, no line is current anymore
    let isLastLineOver = indexOfCurrentLine == lyricModels.count - 1 &&
      curIndexModel?.isPause == false &&
      time > (curIndexModel?.lyric?.startTime ?? .zero) + lastLineHoldTime
    let wasActive = curIndexModel?.isActiveLine
    curIndexModel?.isActiveLine = !isLastLineOver

    if prevIndex != indexOfCurrentLine || wasActive != curIndexModel?.isActiveLine {
      if curIndexModel != nil {
        reconfigureRows(at: [IndexPath(row: indexOfCurrentLine, section: 0)])
      }
      if let prevIndex = prevIndex, prevIndex != indexOfCurrentLine,
         lyricModels.object(at: prevIndex) != nil {
        reconfigureRows(at: [IndexPath(row: prevIndex, section: 0)])
      }
    }
    if isAutoScrollAllowed {
      scrollToRow(
        at: IndexPath(row: indexOfCurrentLine, section: 0),
        at: .middle,
        animated: true
      )
    }
  }
}

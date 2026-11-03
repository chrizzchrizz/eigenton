//
//  SeekableTimeSlider.swift
//  Amperfy
//
//  Created by Jerome Gangneux for Amperfy on 2026-03-02.
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

// MARK: - SeekableTimeSlider

class SeekableTimeSlider: UISlider {
  static let verticalHitAreaExpansion: CGFloat = 20
  static let horizontalHitAreaExpansion: CGFloat = 8

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let expandedBounds = bounds.inset(
      by: UIEdgeInsets(
        top: -Self.verticalHitAreaExpansion,
        left: -Self.horizontalHitAreaExpansion,
        bottom: -Self.verticalHitAreaExpansion,
        right: -Self.horizontalHitAreaExpansion
      )
    )
    return expandedBounds.contains(point)
  }

  /// A pointer drag is in progress, UISlider's own tracking isn't involved
  private var isPointerTracking = false

  // For pointer/mouse: the track follows the pointer directly (click and drag),
  // instead of UISlider's thumb-relative drag; the seek happens once on release.
  // While the player completes the seek, it reports the target as elapsed time.
  override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    guard isPointerSeekAllowed(touch) else {
      return super.beginTracking(touch, with: event)
    }
    isPointerTracking = true
    setValue(for: touch.location(in: self))
    sendActions(for: .touchDragInside)
    return true
  }

  override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    guard isPointerTracking else {
      return super.continueTracking(touch, with: event)
    }
    setValue(for: touch.location(in: self))
    sendActions(for: .touchDragInside)
    return true
  }

  override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
    guard isPointerTracking else {
      super.endTracking(touch, with: event)
      return
    }
    isPointerTracking = false
    // without a touch the drag was cancelled: no seek, the next playback update resets the value
    guard let touch else { return }
    setValue(for: touch.location(in: self))
    sendActions(for: .valueChanged)
  }

  override func cancelTracking(with event: UIEvent?) {
    guard isPointerTracking else {
      super.cancelTracking(with: event)
      return
    }
    isPointerTracking = false
  }

  private func setValue(for location: CGPoint) {
    guard let value = valueFromLocation(location) else { return }
    self.value = value
  }

  private func valueFromLocation(_ location: CGPoint) -> Float? {
    let trackRect = trackRect(forBounds: bounds)
    guard trackRect.width > 0 else { return nil }
    let clampedX = min(max(location.x, trackRect.minX), trackRect.maxX)
    let fraction = (clampedX - trackRect.minX) / trackRect.width
    return minimumValue + Float(fraction) * (maximumValue - minimumValue)
  }

  private func isPointerSeekAllowed(_ touch: UITouch) -> Bool {
    #if targetEnvironment(macCatalyst)
      return true
    #else
      return touch.type == .indirectPointer
    #endif
  }
}

// MARK: - ExpandableTrackTimeSlider

/// Seekable slider that draws its own track so the track height can change,
/// e.g. thin while idle and thicker while the pointer hovers over it (Mac mini player).
/// The system track is hidden; the track tint colors are applied to the custom track.
class ExpandableTrackTimeSlider: SeekableTimeSlider {
  static let collapsedTrackHeight: CGFloat = 3.5
  static let expandedTrackHeight: CGFloat = 7

  private let maximumTrackView = UIView()
  private let minimumTrackView = UIView()
  private(set) var isTrackExpanded = false
  /// The user is dragging or clicking. Own flag, UIControl's isTracking is set only after
  /// beginTracking returns and reset only after endTracking returns.
  private var isUserTracking = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupTrack()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupTrack()
  }

  private func setupTrack() {
    maximumTrackView.isUserInteractionEnabled = false
    maximumTrackView.clipsToBounds = true
    minimumTrackView.isUserInteractionEnabled = false
    maximumTrackView.addSubview(minimumTrackView)
    addSubview(maximumTrackView)
    // track tint colors are unsupported in the Mac idiom (throws), only in the pad style
    preferredBehavioralStyle = .pad
    super.minimumTrackTintColor = .clear
    super.maximumTrackTintColor = .clear
  }

  override var minimumTrackTintColor: UIColor? {
    get { minimumTrackView.backgroundColor }
    set {
      minimumTrackView.backgroundColor = newValue
      super.minimumTrackTintColor = .clear
    }
  }

  override var maximumTrackTintColor: UIColor? {
    get { maximumTrackView.backgroundColor }
    set {
      maximumTrackView.backgroundColor = newValue
      super.maximumTrackTintColor = .clear
    }
  }

  override var value: Float {
    didSet { setNeedsLayout() }
  }

  override var minimumValue: Float {
    didSet { if minimumValue != oldValue { setNeedsLayout() } }
  }

  override var maximumValue: Float {
    didSet { if maximumValue != oldValue { setNeedsLayout() } }
  }

  override func setValue(_ value: Float, animated: Bool) {
    super.setValue(value, animated: animated)
    setNeedsLayout()
  }

  /// The pointer hovers over the track area. The track is expanded while hovering or dragging,
  /// as long as the slider is enabled.
  var isHoverActive = false {
    didSet { if isHoverActive != oldValue { updateTrackExpansion() } }
  }

  override var isEnabled: Bool {
    didSet { if isEnabled != oldValue { updateTrackExpansion() } }
  }

  override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    isUserTracking = super.beginTracking(touch, with: event)
    updateTrackExpansion()
    return isUserTracking
  }

  override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
    super.endTracking(touch, with: event)
    isUserTracking = false
    updateTrackExpansion()
  }

  override func cancelTracking(with event: UIEvent?) {
    super.cancelTracking(with: event)
    isUserTracking = false
    updateTrackExpansion()
  }

  private func updateTrackExpansion() {
    setTrackExpanded((isHoverActive || isUserTracking) && isEnabled, animated: window != nil)
  }

  private func setTrackExpanded(_ expanded: Bool, animated: Bool) {
    guard expanded != isTrackExpanded else { return }
    isTrackExpanded = expanded
    setNeedsLayout()
    guard animated else { return }
    UIView.animate(
      springDuration: 0.35,
      bounce: 0.3,
      initialSpringVelocity: 0,
      delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState]
    ) {
      self.layoutIfNeeded()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // keep the visible track aligned with the area used for pointer seeking
    let systemTrack = trackRect(forBounds: bounds)
    let height = trackHeight
    maximumTrackView.frame = CGRect(
      x: systemTrack.minX,
      y: bounds.midY - height / 2,
      width: systemTrack.width,
      height: height
    )
    maximumTrackView.layer.cornerRadius = height / 2
    minimumTrackView.frame = minimumTrackFrame()
  }

  private var trackHeight: CGFloat {
    isTrackExpanded ? Self.expandedTrackHeight : Self.collapsedTrackHeight
  }

  /// Frame of the fill inside the track for the current value.
  private func minimumTrackFrame() -> CGRect {
    let trackWidth = trackRect(forBounds: bounds).width
    let range = maximumValue - minimumValue
    let fraction = range > 0 ? CGFloat(min(max((value - minimumValue) / range, 0), 1)) : 0
    return CGRect(x: 0, y: 0, width: trackWidth * fraction, height: trackHeight)
  }
}

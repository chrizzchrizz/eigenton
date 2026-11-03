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

  #if targetEnvironment(macCatalyst)
    /// A mouse button is down on the slider
    private var isPointerPressed = false
    /// The seek on release is being sent
    private var isSendingSeekOnRelease = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      isPointerPressed = true
      super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesEnded(touches, with: event)
      sendSeekOnReleaseIfPressed()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesCancelled(touches, with: event)
      sendSeekOnReleaseIfPressed()
    }

    /// The seek happens exactly once, when the mouse button is released
    private func sendSeekOnReleaseIfPressed() {
      guard isPointerPressed else { return }
      isPointerPressed = false
      // e.g. a radio stream can't seek
      guard isEnabled else { return }
      isSendingSeekOnRelease = true
      sendActions(for: .valueChanged)
      isSendingSeekOnRelease = false
    }

    // UISlider's own slider interaction sends valueChanged on mouse down (it jumps to the clicked
    // position, even before touchesBegan) and again after release. Seeking on mouse down would
    // seek while the user only starts to drag, so only the seek on release above is sent.
    override func sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
      if !isSendingSeekOnRelease, isValueChangedAction(action, target: target) {
        return
      }
      super.sendAction(action, to: target, for: event)
    }

    private func isValueChangedAction(_ action: Selector, target: Any?) -> Bool {
      let actionName = NSStringFromSelector(action)
      return actions(forTarget: target, forControlEvent: .valueChanged)?
        .contains(actionName) ?? false
    }
  #endif

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
    #if !targetEnvironment(macCatalyst)
      // Mac: sent on touchesEnded instead
      sendActions(for: .valueChanged)
    #endif
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
  /// The player reports the playback position periodically (value unit: seconds). Forward steps
  /// are animated linearly over the time since the previous update, so the fill moves continuously.
  /// Faster changes (value units per second, above the highest playback rate) are seeks.
  static let maxSmoothProgressSpeed: Float = 3
  /// Longer gaps between updates (e.g. after a pause) aren't animated
  static let maxSmoothProgressInterval: TimeInterval = 2

  private let maximumTrackView = UIView()
  private let minimumTrackView = UIView()
  private(set) var isTrackExpanded = false
  /// Value the fill shows or animates to
  private var displayedValue: Float = 0
  /// The user is dragging or clicking. Own flag, UIControl's isTracking is set only after
  /// beginTracking returns and reset only after endTracking returns.
  private var isUserTracking = false
  private var lastValueChangeDate: Date?

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
    didSet { valueDidChange() }
  }

  override var minimumValue: Float {
    didSet { if minimumValue != oldValue { valueRangeDidChange() } }
  }

  override var maximumValue: Float {
    didSet { if maximumValue != oldValue { valueRangeDidChange() } }
  }

  override func setValue(_ value: Float, animated: Bool) {
    super.setValue(value, animated: animated)
    // UIKit may route this through the value setter as well; displayedValue dedupes it
    valueDidChange()
  }

  private func valueRangeDidChange() {
    minimumTrackView.layer.removeAllAnimations()
    setNeedsLayout()
  }

  private func valueDidChange() {
    guard value != displayedValue else { return }
    let step = value - displayedValue
    displayedValue = value
    let now = Date()
    let interval = lastValueChangeDate.map { now.timeIntervalSince($0) } ?? 0
    lastValueChangeDate = now
    guard !isUserTracking, window != nil, step > 0, interval > 0,
          interval <= Self.maxSmoothProgressInterval,
          step <= Float(interval) * Self.maxSmoothProgressSpeed else {
      // seek, drag or song change: jump to the new position
      minimumTrackView.layer.removeAllAnimations()
      setNeedsLayout()
      return
    }
    // playback progress: move the fill linearly, arriving about when the next update is due
    UIView.animate(
      withDuration: interval,
      delay: 0,
      options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]
    ) {
      self.minimumTrackView.frame = self.minimumTrackFrame()
    }
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
    // set before super: a click already changes the value there, which has to jump
    isUserTracking = true
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

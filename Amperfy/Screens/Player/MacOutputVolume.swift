//
//  MacOutputVolume.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 04.11.26.
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

#if targetEnvironment(macCatalyst) // ok
  import AmperfyKit
  import CoreAudio
  import UIKit

  // MARK: - MacOutputVolume

  /// The volume the player's volume button controls on Mac.
  ///
  /// - AirPlay: as soon as one AirPlay room is selected, the system volume no longer applies.
  ///   There is no public API for the AirPlay volume (the system route picker only shows a
  ///   slider per room), so this uses the private `AVOutputContext`: its
  ///   `defaultSharedOutputContext` holds the rooms the app plays to, and setting its `volume`
  ///   changes all rooms and keeps their ratio, like the group slider in Apple Music. Every
  ///   access is guarded, a changed or missing API only falls back to the system volume.
  /// - Otherwise: the system volume of the default output device via CoreAudio.
  @MainActor
  final class MacOutputVolume: NSObject {
    enum Target {
      case none
      case system
      case airPlay
    }

    static let shared = MacOutputVolume()
    static let didChangeNotification = Notification.Name("MacOutputVolumeDidChange")

    private(set) var target = Target.none
    /// 0...1
    private(set) var volume: Float = 0
    /// True while the app plays to at least one AirPlay room, also without a settable volume
    private(set) var isAirPlayActive = false

    private var pollTimer: Timer?

    override private init() {
      airPlayContext = Self.loadAirPlayContext()
      super.init()
      observeAirPlayContext()
      observeSystemOutput()
      // no notification from inside the initializer of `shared`: an observer reading `shared`
      // would re-enter it
      (target, volume, isAirPlayActive) = currentState()
      // KVO doesn't fire for every route change (e.g. Mac → one AirPlay room): poll as fallback
      pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        MainActor.assumeIsolated {
          // also while visible but not frontmost (inactive) on Mac
          guard UIApplication.shared.applicationState != .background else { return }
          MacOutputVolume.shared.refresh()
        }
      }
    }

    func setVolume(_ newVolume: Float) {
      // the cached target can be stale, route changes aren't always reported
      refresh()
      let clamped = min(max(newVolume, 0), 1)
      switch target {
      case .none:
        return
      case .airPlay:
        airPlayContext?.setValue(NSNumber(value: clamped), forKey: Self.volumeKey)
      case .system:
        setSystemVolume(clamped)
      }
      guard clamped != volume else { return }
      // post here: the callbacks for this change report the same value and won't post
      volume = clamped
      NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func refresh() {
      let (newTarget, newVolume, newIsAirPlayActive) = currentState()
      guard newTarget != target || newVolume != volume || newIsAirPlayActive != isAirPlayActive
      else { return }
      target = newTarget
      volume = newVolume
      isAirPlayActive = newIsAirPlayActive
      NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func currentState() -> (Target, Float, isAirPlayActive: Bool) {
      switch currentAirPlayState() {
      case let .settable(airPlayVolume):
        return (.airPlay, airPlayVolume, true)
      case .fixed:
        // the system volume doesn't apply to AirPlay output
        return (.none, 0, true)
      case .inactive:
        if let systemVolume = currentSystemVolume() {
          return (.system, systemVolume, false)
        }
        return (.none, 0, false)
      }
    }

    // MARK: AirPlay (private AVOutputContext)

    private static let volumeKey = "volume"
    private static let outputDevicesKey = "outputDevices"
    /// `AVOutputDevice.transportType` of AirPlay devices (observed value, not documented)
    private static let airPlayTransportType = 3

    private let airPlayContext: NSObject?

    private static func loadAirPlayContext() -> NSObject? {
      guard let cls = NSClassFromString("AVOutputContext") else { return nil }
      // bridge the class object via AnyObject: unsafeBitCast to NSObject crashes in objc_retain
      let classObject = cls as AnyObject
      let selector = Selector(("defaultSharedOutputContext"))
      guard classObject.responds(to: selector),
            let context = classObject.perform(selector)?.takeUnretainedValue() as? NSObject,
            context.responds(to: Selector(volumeKey)),
            context.responds(to: Selector(("setVolume:"))),
            context.responds(to: Selector(outputDevicesKey))
      else { return nil }
      return context
    }

    private func observeAirPlayContext() {
      guard let airPlayContext else { return }
      airPlayContext.addObserver(self, forKeyPath: Self.volumeKey, options: [], context: nil)
      airPlayContext.addObserver(self, forKeyPath: Self.outputDevicesKey, options: [], context: nil)
    }

    private enum AirPlayState {
      /// the app doesn't play to an AirPlay room
      case inactive
      /// AirPlay room(s) without a settable volume
      case fixed
      case settable(Float)
    }

    private func currentAirPlayState() -> AirPlayState {
      guard let airPlayContext else { return .inactive }
      let devices = (airPlayContext.value(forKey: Self.outputDevicesKey) as? [NSObject]) ?? []
      guard devices.contains(where: { Self.isAirPlay(device: $0) }) else { return .inactive }
      let canSetVolume = (airPlayContext.value(forKey: "canSetVolume") as? Bool) ?? true
      guard canSetVolume else { return .fixed }
      return .settable((airPlayContext.value(forKey: Self.volumeKey) as? NSNumber)?.floatValue ?? 0)
    }

    private static func isAirPlay(device: NSObject) -> Bool {
      guard device.responds(to: Selector(("transportType"))) else { return false }
      return (device.value(forKey: "transportType") as? NSNumber)?.intValue == airPlayTransportType
    }

    // KVO may arrive on any thread
    nonisolated override func observeValue(
      forKeyPath keyPath: String?,
      of object: Any?,
      change: [NSKeyValueChangeKey: Any]?,
      context: UnsafeMutableRawPointer?
    ) {
      Task { @MainActor in
        self.refresh()
      }
    }

    // MARK: System volume (CoreAudio)

    /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` ('vmvc'), not exposed to Mac Catalyst
    private static let virtualMainVolumeSelector = AudioObjectPropertySelector(0x766D_7663)

    private static var defaultOutputDeviceAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    private static var volumeAddress = AudioObjectPropertyAddress(
      mSelector: virtualMainVolumeSelector,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )

    private var observedOutputDevice = AudioObjectID(kAudioObjectUnknown)
    private var systemListener: AudioObjectPropertyListenerBlock?

    private func observeSystemOutput() {
      let listener: AudioObjectPropertyListenerBlock = { _, _ in
        MainActor.assumeIsolated {
          MacOutputVolume.shared.systemOutputDidChange()
        }
      }
      systemListener = listener
      AudioObjectAddPropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject),
        &Self.defaultOutputDeviceAddress,
        .main,
        listener
      )
      observeVolume(of: Self.defaultOutputDevice())
    }

    private func systemOutputDidChange() {
      let device = Self.defaultOutputDevice()
      if device != observedOutputDevice {
        observeVolume(of: device)
      }
      refresh()
    }

    /// Moves the volume listener to the given output device
    private func observeVolume(of device: AudioObjectID) {
      guard let systemListener else { return }
      if observedOutputDevice != kAudioObjectUnknown {
        AudioObjectRemovePropertyListenerBlock(
          observedOutputDevice,
          &Self.volumeAddress,
          .main,
          systemListener
        )
      }
      observedOutputDevice = device
      guard device != kAudioObjectUnknown,
            AudioObjectHasProperty(device, &Self.volumeAddress)
      else { return }
      AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, .main, systemListener)
    }

    private static func defaultOutputDevice() -> AudioObjectID {
      var device = AudioObjectID(kAudioObjectUnknown)
      var size = UInt32(MemoryLayout<AudioObjectID>.size)
      let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &defaultOutputDeviceAddress,
        0,
        nil,
        &size,
        &device
      )
      return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    /// The system volume, nil if the default output device has no settable volume
    private func currentSystemVolume() -> Float? {
      let device = Self.defaultOutputDevice()
      guard device != kAudioObjectUnknown,
            AudioObjectHasProperty(device, &Self.volumeAddress)
      else { return nil }
      var isSettable: DarwinBoolean = false
      guard AudioObjectIsPropertySettable(device, &Self.volumeAddress, &isSettable) == noErr,
            isSettable.boolValue
      else { return nil }
      var value = Float32(0)
      var size = UInt32(MemoryLayout<Float32>.size)
      guard AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &value) == noErr
      else { return nil }
      return value
    }

    private func setSystemVolume(_ newVolume: Float) {
      let device = Self.defaultOutputDevice()
      guard device != kAudioObjectUnknown else { return }
      var value = Float32(newVolume)
      AudioObjectSetPropertyData(
        device,
        &Self.volumeAddress,
        0,
        nil,
        UInt32(MemoryLayout<Float32>.size),
        &value
      )
    }

    // MARK: Button

    static func makeButton(pointSize: CGFloat? = nil) -> UIButton {
      let button = UIButton(configuration: .plain())
      button.tintColor = .label
      button.accessibilityLabel = "Volume"
      button.toolTip = "Volume"
      shared.update(button: button, pointSize: pointSize)
      return button
    }

    /// Visibility and symbol of a volume button for the current target and volume
    func update(button: UIButton, pointSize: CGFloat? = nil) {
      button.isHidden = target == .none
      let symbolName: String
      switch volume {
      case ..<0.005: symbolName = "speaker.slash.fill"
      case ..<0.34: symbolName = "speaker.wave.1.fill"
      case ..<0.67: symbolName = "speaker.wave.2.fill"
      default: symbolName = "speaker.wave.3.fill"
      }
      var image = UIImage(systemName: symbolName)
      if let pointSize {
        image = image?.withConfiguration(UIImage.SymbolConfiguration(pointSize: pointSize))
      }
      button.configuration?.image = image
      button.toolTip = target == .airPlay ? "AirPlay Volume" : "Volume"
      button.accessibilityLabel = button.toolTip
    }

    // MARK: Popover

    /// Shows the volume slider anchored at the given button
    func presentSlider(
      from sourceButton: UIView,
      on presenter: UIViewController?,
      arrowDirection: UIPopoverArrowDirection
    ) {
      guard let presenter else { return }
      let popover = VolumePopover()
      popover.modalPresentationStyle = .popover
      popover.preferredContentSize = CGSize(width: 250, height: 50)
      if let popoverController = popover.popoverPresentationController {
        popoverController.permittedArrowDirections = arrowDirection
        popoverController.delegate = popover
        popoverController.sourceView = sourceButton
      }
      presenter.present(popover, animated: true)
    }
  }

  // MARK: - VolumePopover

  /// Slider for the output volume; follows changes made elsewhere (keyboard, Control Center,
  /// system route picker)
  private final class VolumePopover: SliderMenuPopover {
    private let outputVolume = MacOutputVolume.shared

    override func viewDidLoad() {
      super.viewDidLoad()
      let slider = sliderMenuView.slider
      slider.minimumValue = 0
      slider.maximumValue = 1
      sliderMenuView.stepValue = 0.01
      slider.value = outputVolume.volume
      sliderMenuView.sliderValueChangedCB = { [weak self] in
        guard let self else { return }
        outputVolume.setVolume(sliderMenuView.slider.value)
      }
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(outputVolumeDidChange),
        name: MacOutputVolume.didChangeNotification,
        object: nil
      )
    }

    @objc
    private func outputVolumeDidChange() {
      guard outputVolume.target != .none else {
        dismiss(animated: true)
        return
      }
      if !sliderMenuView.slider.isTracking {
        sliderMenuView.slider.value = outputVolume.volume
      }
    }
  }
#endif

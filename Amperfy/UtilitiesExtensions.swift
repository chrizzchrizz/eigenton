//
//  UtilitiesExtensions.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 06.06.22.
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
import Foundation
import MarqueeLabel
import os.log
import SwiftUI
import UIKit

extension MarqueeLabel {
  func applyAmperfyStyle() {
    if trailingBuffer != 30.0 {
      trailingBuffer = 30.0
    }
    if leadingBuffer != 0.0 {
      leadingBuffer = 0.0
    }
    if animationDelay != 2.0 {
      animationDelay = 2.0
    }
    if type != .continuous {
      type = .continuous
    }
    speed = .rate(30.0)
    if fadeLength != 10.0 {
      fadeLength = 10.0
    }
  }
}

extension UIColor {
  static let hardLabelColor = UIColor(named: "hardLabelColor")
}

extension Color {
  static let error = Color.red
  static let success = Color.green

  // MARK: - Text Colors

  static let lightText = Color(UIColor.lightText)
  static let darkText = Color(UIColor.darkText)
  static let placeholderText = Color(UIColor.placeholderText)

  // MARK: - Label Colors

  static let label = Color(UIColor.label)
  static let secondaryLabel = Color(UIColor.secondaryLabel)
  static let tertiaryLabel = Color(UIColor.tertiaryLabel)
  static let quaternaryLabel = Color(UIColor.quaternaryLabel)

  // MARK: - Background Colors

  static let systemBackground = Color(UIColor.systemBackground)
  static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
  static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)

  // MARK: - Fill Colors

  static let systemFill = Color(UIColor.systemFill)
  static let secondarySystemFill = Color(UIColor.secondarySystemFill)
  static let tertiarySystemFill = Color(UIColor.tertiarySystemFill)
  static let quaternarySystemFill = Color(UIColor.quaternarySystemFill)

  // MARK: - Grouped Background Colors

  static let systemGroupedBackground = Color(UIColor.systemGroupedBackground)
  static let secondarySystemGroupedBackground = Color(UIColor.secondarySystemGroupedBackground)
  static let tertiarySystemGroupedBackground = Color(UIColor.tertiarySystemGroupedBackground)

  // MARK: - Gray Colors

  static let systemGray = Color(UIColor.systemGray)
  static let systemGray2 = Color(UIColor.systemGray2)
  static let systemGray3 = Color(UIColor.systemGray3)
  static let systemGray4 = Color(UIColor.systemGray4)
  static let systemGray5 = Color(UIColor.systemGray5)
  static let systemGray6 = Color(UIColor.systemGray6)

  // MARK: - Other Colors

  static let separator = Color(UIColor.separator)
  static let opaqueSeparator = Color(UIColor.opaqueSeparator)
  static let link = Color(UIColor.link)

  // MARK: System Colors

  static let systemBlue = Color(UIColor.systemBlue)
  static let systemPurple = Color(UIColor.systemPurple)
  static let systemGreen = Color(UIColor.systemGreen)
  static let systemYellow = Color(UIColor.systemYellow)
  static let systemOrange = Color(UIColor.systemOrange)
  static let systemPink = Color(UIColor.systemPink)
  static let systemRed = Color(UIColor.systemRed)
  static let systemTeal = Color(UIColor.systemTeal)
  static let systemIndigo = Color(UIColor.systemIndigo)
}

public func withPopupAnimation<Result>(_ body: () throws -> Result) rethrows -> Result {
  try withAnimation(.easeInOut(duration: 0.2)) {
    try body()
  }
}

extension View {
  var appDelegate: AppDelegate {
    (UIApplication.shared.delegate as! AppDelegate)
  }
}

extension UIColor {
  static let slideOverBackgroundColor: UIColor = .systemBackground.withAlphaComponent(0.5)
  static let hoveredBackgroundColor: UIColor = .systemGray2.withAlphaComponent(0.2)
}

extension UIButton.Configuration {
  static func player(isSelected: Bool) -> UIButton.Configuration {
    var config = UIButton.Configuration.tinted()
    if isSelected {
      config.background.strokeColor = .label
      config.background.strokeWidth = 1.0
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .medium)
    }
    config.buttonSize = .small
    config.baseForegroundColor = !isSelected ? .label : .systemBackground
    config.baseBackgroundColor = !isSelected ? .clear : .label
    config.cornerStyle = .capsule
    return config
  }

  static func playerRound() -> UIButton.Configuration {
    var config = UIButton.Configuration.plain()
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .large)
    config.buttonSize = .small
    return config
  }
}

extension UIView {
  static let forceTouchClickLimit: Float = 1.0

  func normalizedForce(touches: Set<UITouch>) -> Float? {
    guard is3DTouchAvailable, let touch = touches.first else { return nil }
    let maximumForce = touch.maximumPossibleForce
    let force = touch.force
    let normalizedForce = (force / maximumForce)
    return Float(normalizedForce)
  }

  func isForceClicked(_ touches: Set<UITouch>) -> Bool {
    guard let force = normalizedForce(touches: touches) else { return false }
    if force < UIView.forceTouchClickLimit {
      return false
    } else {
      return true
    }
  }

  var is3DTouchAvailable: Bool {
    forceTouchCapability() == .available
  }

  func forceTouchCapability() -> UIForceTouchCapability {
    UIApplication.shared.mainWindow?.rootViewController?.traitCollection
      .forceTouchCapability ?? .unknown
  }

  public func setBackgroundBlur(style: UIBlurEffect.Style, alpha: CGFloat = 1.0) {
    backgroundColor = UIColor.clear
    let blurEffect = UIBlurEffect(style: style)
    let blurEffectView = UIVisualEffectView(effect: blurEffect)
    blurEffectView.alpha = alpha
    blurEffectView.frame = bounds
    blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    insertSubview(blurEffectView, at: 0)
  }
}

extension UINavigationController {
  func replaceCurrentlyActiveVC(with vc: UIViewController, animated: Bool) {
    var vcs = viewControllers
    vcs = vcs.dropLast()
    vcs.append(vc)
    setViewControllers(vcs, animated: animated)
  }
}

extension UITableView {
  func register(nibName: String) {
    register(UINib(nibName: nibName, bundle: nil), forCellReuseIdentifier: nibName)
  }

  func dequeueCell<CellType: UITableViewCell>(
    for tableView: UITableView,
    at indexPath: IndexPath
  )
    -> CellType {
    guard let cell = dequeueReusableCell(
      withIdentifier: CellType.typeName,
      for: indexPath
    ) as? CellType else {
      os_log(.error, "The dequeued cell is not an instance of %s", CellType.typeName)
      return CellType()
    }
    return cell
  }

  func hasRowAt(indexPath: IndexPath) -> Bool {
    indexPath.section < numberOfSections && indexPath
      .row < numberOfRows(inSection: indexPath.section)
  }

  // MARK: Text size

  /// Keeps the rows up to date with the user's text size (see `TextScaling`): whenever it
  /// changes, the table is reloaded, so that cells and `tableView(_:heightForRowAt:)` pick up
  /// the new size. Tables with one height for all rows pass it as `rowHeight`: it is applied to
  /// `rowHeight` and `estimatedRowHeight` now and before every reload.
  func reloadOnTextSizeChange(rowHeight: (@MainActor () -> CGFloat)? = nil) {
    let applyRowHeight = { (tableView: UITableView) in
      guard let rowHeight else { return }
      tableView.rowHeight = rowHeight()
      tableView.estimatedRowHeight = tableView.rowHeight
    }
    applyRowHeight(self)
    registerForTraitChanges(
      [UITraitPreferredContentSizeCategory.self],
      handler: { (self: Self, previousTraitCollection: UITraitCollection) in
        applyRowHeight(self)
        self.reloadData()
      }
    )
  }
}

// MARK: - TextScaling

/// Proxy for everything that scales with the user's text size: fonts of `ScaledLabel`s, row
/// heights and other text dependent sizes. The text size is the system's or the in-app text size
/// (Settings > Display), which `AppDelegate.applyTextSize()` sets as `preferredContentSizeCategory`
/// trait override on all windows, so views get notified like for Dynamic Type changes.
/// - iOS/iPadOS: forwards to Dynamic Type (text styles in the xibs, `UIFontMetrics`).
/// - Mac Catalyst: macOS has no Dynamic Type, text styles always have the same size. Fonts and
///   sizes are scaled with the factors of the iOS text sizes instead.
@MainActor
enum TextScaling {
  /// Text sizes that can be chosen in the settings
  static let textSizes: [UIContentSizeCategory] = [
    .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
    .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
    .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
  ]

  /// The in-app text size, nil: system text size (iOS) / default text size (Mac)
  static var textSize: UIContentSizeCategory?

  /// Size of the body text style on iOS for each text size (17pt at the default size)
  private static let bodySizes: [UIContentSizeCategory: CGFloat] = [
    .extraSmall: 14, .small: 15, .medium: 16, .large: 17, .extraLarge: 19,
    .extraExtraLarge: 21, .extraExtraExtraLarge: 23, .accessibilityMedium: 28,
    .accessibilityLarge: 33, .accessibilityExtraLarge: 40, .accessibilityExtraExtraLarge: 47,
    .accessibilityExtraExtraExtraLarge: 53,
  ]

  /// `.footnote` scales slightly stronger than `.body`, so scaled sizes leave enough room
  private static let metrics = UIFontMetrics(forTextStyle: .footnote)

  /// iOS: unchanged, Dynamic Type scales the font. Mac: scaled to the traits' text size.
  static func scaledFont(_ font: UIFont, compatibleWith traits: UITraitCollection) -> UIFont {
    #if targetEnvironment(macCatalyst)
      return font.withSize((font.pointSize * factor(for: currentTextSize(traits))).rounded())
    #else
      return font
    #endif
  }

  /// iOS: text style fonts are unchanged (Dynamic Type scales them), fonts with a fixed size
  /// (e.g. "System 16" in a xib) are scaled like the body text style. Mac: like `scaledFont`.
  static func scaledFixedSizeFont(
    _ font: UIFont,
    compatibleWith traits: UITraitCollection
  )
    -> UIFont {
    #if targetEnvironment(macCatalyst)
      return scaledFont(font, compatibleWith: traits)
    #else
      // system fonts carry a usage in this attribute too, only real text styles scale themselves
      let usage = font.fontDescriptor.object(forKey: .textStyle) as? String
      guard !(usage?.hasPrefix("UICTFontTextStyle") ?? false) else { return font }
      return UIFontMetrics(forTextStyle: .body).scaledFont(
        for: font,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: currentTextSize(traits))
      )
    #endif
  }

  /// `value` at the default text size, scaled to the text size of `traits` (or the app's)
  static func scaledValue(
    _ value: CGFloat,
    compatibleWith traits: UITraitCollection? = nil,
    maximum: UIContentSizeCategory? = nil
  )
    -> CGFloat {
    var textSize = currentTextSize(traits)
    if let maximum, textSize > maximum {
      textSize = maximum
    }
    #if targetEnvironment(macCatalyst)
      return value * factor(for: textSize)
    #else
      return metrics.scaledValue(
        for: value,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: textSize)
      )
    #endif
  }

  /// The traits of a view in a window already contain the in-app text size (and its maximum)
  private static func currentTextSize(_ traits: UITraitCollection?) -> UIContentSizeCategory {
    if let traitsTextSize = traits?.preferredContentSizeCategory,
       traitsTextSize != .unspecified {
      return traitsTextSize
    }
    return textSize ?? UIApplication.shared.preferredContentSizeCategory
  }

  private static func factor(for textSize: UIContentSizeCategory) -> CGFloat {
    (bodySizes[textSize] ?? 17.0) / 17.0
  }
}

// MARK: - ScaledLabel

/// Label whose text scales with the user's text size. Use it as custom class in xibs together
/// with a text style font or a font with a fixed size (incl. size class variations).
/// Every font that gets assigned (by the xib or code) is the unscaled base font, the label
/// displays it scaled by `TextScaling.scaledFixedSizeFont`:
/// - iOS/iPadOS: text styles are scaled by Dynamic Type, fixed sizes like the body text style.
/// - Mac Catalyst: all fonts are scaled with the factors of the iOS text sizes.
class ScaledLabel: UILabel {
  private var unscaledFont: UIFont?
  private var isRegisteredForTextSizeChanges = false

  override var font: UIFont! {
    get { super.font }
    set {
      unscaledFont = newValue
      guard newValue != nil else {
        super.font = nil
        return
      }
      applyScaledFont()
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    // the text size comes from the window's traits, nothing to do when leaving it
    guard window != nil else { return }
    if !isRegisteredForTextSizeChanges {
      isRegisteredForTextSizeChanges = true
      registerForTraitChanges(
        [UITraitPreferredContentSizeCategory.self],
        handler: { (self: Self, previousTraitCollection: UITraitCollection) in
          self.applyScaledFont()
        }
      )
    }
    applyScaledFont()
  }

  private func applyScaledFont() {
    if unscaledFont == nil {
      unscaledFont = super.font
    }
    guard let unscaledFont else { return }
    #if !targetEnvironment(macCatalyst)
      // Dynamic Type already scales the font (e.g. a UIFontMetrics font) and assigns updates
      // through this setter, scaling it again would scale it twice
      guard !adjustsFontForContentSizeCategory else {
        super.font = unscaledFont
        return
      }
    #endif
    super.font = TextScaling.scaledFixedSizeFont(unscaledFont, compatibleWith: traitCollection)
  }
}

extension UICollectionView {
  func hasItemAt(indexPath: IndexPath) -> Bool {
    indexPath.section < numberOfSections && indexPath
      .row < numberOfItems(inSection: indexPath.section)
  }
}

@MainActor
extension UITableViewController {
  func dequeueCell<CellType: UITableViewCell>(
    for tableView: UITableView,
    at indexPath: IndexPath
  )
    -> CellType {
    self.tableView.dequeueCell(for: tableView, at: indexPath)
  }

  func refreshAllVisibleCells() {
    let visibleIndexPaths = tableView.visibleCells.compactMap { tableView.indexPath(for: $0) }
    tableView.reconfigureRows(at: visibleIndexPaths)
  }

  func exectueAfterAnimation(body: @escaping () -> ()) {
    Task { @MainActor in
      body()
    }
  }
}

extension UIViewController {
  var typeName: String {
    Self.typeName
  }
}

extension NSObject {
  @MainActor
  var appDelegate: AppDelegate {
    (UIApplication.shared.delegate as! AppDelegate)
  }
}

extension UIApplication {
  var mainWindow: UIWindow? {
    let scenes = UIApplication.shared.connectedScenes
    for uiScene in scenes {
      if let windowScene = uiScene as? UIWindowScene {
        for window in windowScene.windows {
          if window.isKeyWindow {
            return window
          }
        }
      }
    }
    return nil
  }
}

extension UITraitCollection {
  static let maxDisplayScale = UITraitCollection(displayScale: 3.0)
}

extension UITableViewCell {
  func animateActivation() {
    UIView.animate(withDuration: 0.2, animations: {
      self.markAsFocused()
    }, completion: { _ in
      self.markAsFocused()
      UIView.animate(withDuration: 0.2, animations: {
        self.markAsUnfocused()
      }, completion: { _ in
        self.markAsUnfocused()
      })
    })
  }

  func markAsFocused() {
    backgroundColor = .systemGray4
  }

  func markAsUnfocused() {
    backgroundColor = .clear
  }
}

extension UICollectionViewCell {
  func animateActivation() {
    UIView.animate(withDuration: 0.2, animations: {
      self.markAsFocused()
    }, completion: { _ in
      self.markAsFocused()
      UIView.animate(withDuration: 0.2, animations: {
        self.markAsUnfocused()
      }, completion: { _ in
        self.markAsUnfocused()
      })
    })
  }

  /// `@objc` so that subclasses can override it (e.g. `KeyboardFocusableListCell`)
  @objc
  func markAsFocused() {
    let focuseBackground = UIView(frame: bounds)
    focuseBackground.backgroundColor = .systemGray4
    backgroundView = focuseBackground
  }

  @objc
  func markAsUnfocused() {
    backgroundView = nil
  }
}

extension UIMenu {
  /// rebuilds menu on every access
  static func lazyMenu(
    title: String = "",
    builder: @escaping () -> [UIMenuElement]
  )
    -> UIMenu {
    UIMenu(title: title, children: [
      UIDeferredMenuElement.uncached { completion in
        let actions = builder()
        completion(actions)
      },
    ])
  }
}

extension UIImage {
  func carPlayImage(carTraitCollection traits: UITraitCollection) -> UIImage {
    let imageAsset = UIImageAsset()
    imageAsset.register(self, with: traits)
    return imageAsset.image(with: traits)
  }
}

extension UICollectionViewLayout {
  static var verticalLayout: UICollectionViewFlowLayout {
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .vertical
    return layout
  }
}

extension UIDevice.BatteryState {
  public var description: String {
    switch self {
    case .unknown:
      return "unknown"
    case .unplugged:
      return "unplugged"
    case .charging:
      return "charging"
    case .full:
      return "full"
    @unknown default:
      return "@unknown default"
    }
  }
}

/// This fixes in swiftui mutliple picker views side by side to overlapp their touch areas
/// This is effective in addition to use .clipped() which only fixes the overlapping area visually
extension UIPickerView {
  open override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: 150)
  }
}

extension Notification.Name {
  static let LibraryItemsChanged = Notification.Name("de.familie-zimba.Amperfy.LibraryItemsChanged")
}

extension UIViewController {
  @objc
  var sceneTitle: String? { nil }

  func extendSafeAreaToAccountForMiniPlayer() {
    guard let hostVC = AppDelegate.mainWindowHostVC else { return }
    additionalSafeAreaInsets = UIEdgeInsets(
      top: 0,
      left: 0,
      bottom: hostVC.getSafeAreaExtension(),
      right: 0
    )
  }
}

extension UIImage {
  /// Most frequent color of the image; falls back to the average color.
  ///
  /// Uses a cheap histogram on a tiny thumbnail; merging similar colors pairwise (as e.g. the
  /// DominantColors package does) can take very long for noisy artwork and blocked the main thread.
  ///
  /// With `forDarkBackground` the same main color is returned, but its HSL lightness is lowered so
  /// it works behind white content. Hue always stays the artwork's; see `adjustedForBackground`.
  func mainColor(forDarkBackground: Bool = false) -> UIColor {
    let side = 32
    guard let cgImage else { return averageColor() }
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(
        data: buffer.baseAddress,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      context.interpolationQuality = .medium
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
      return true
    }
    guard drewImage else { return averageColor() }

    // 4 bits per channel buckets
    var buckets = [Int: (count: Int, r: Int, g: Int, b: Int)]()
    for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
      let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
      let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
      let bucket = buckets[key] ?? (0, 0, 0, 0)
      buckets[key] = (bucket.count + 1, bucket.r + r, bucket.g + g, bucket.b + b)
    }
    typealias Bucket = (count: Int, r: Int, g: Int, b: Int)
    func average(_ bucket: Bucket) -> UIColor {
      UIColor(
        red: CGFloat(bucket.r) / CGFloat(bucket.count) / 255,
        green: CGFloat(bucket.g) / CGFloat(bucket.count) / 255,
        blue: CGFloat(bucket.b) / CGFloat(bucket.count) / 255,
        alpha: 1
      )
    }
    func hsb(_ bucket: Bucket) -> (s: CGFloat, b: CGFloat) {
      var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
      average(bucket).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
      return (saturation, brightness)
    }
    // prefer saturated, not too dark colors over large neutral or dark areas
    func score(_ bucket: Bucket) -> CGFloat {
      let value = hsb(bucket)
      return CGFloat(bucket.count) * (0.2 + value.s) * (0.3 + value.b)
    }

    guard let best = buckets.values.max(by: { score($0) < score($1) }) else {
      return averageColor().adjustedForBackground(isDark: forDarkBackground)
    }
    return average(best).adjustedForBackground(isDark: forDarkBackground)
  }
}

extension UIColor {
  /// Tweak these to tune how vivid / dark the artwork backgrounds are (HSL values, 0...1).
  private static let darkBackgroundLightness: ClosedRange<CGFloat> = 0.18 ... 0.22
  private static let darkBackgroundMaxSaturation: CGFloat = 0.7
  private static let lightBackgroundLightness: ClosedRange<CGFloat> = 0.3 ... 0.4
  private static let lightBackgroundMaxSaturation: CGFloat = 0.3

  func adjustedForBackground(isDark: Bool) -> UIColor {
    if isDark {
      return withHSL(
        lightness: Self.darkBackgroundLightness,
        maxSaturation: Self.darkBackgroundMaxSaturation
      )
    }
    return withHSL(
      lightness: Self.lightBackgroundLightness,
      maxSaturation: Self.lightBackgroundMaxSaturation
    )
  }

  /// Keeps the hue, limits HSL lightness and saturation to the given bounds.
  func withHSL(lightness range: ClosedRange<CGFloat>, maxSaturation: CGFloat) -> UIColor {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }
    let maxValue = max(red, green, blue)
    let minValue = min(red, green, blue)
    let delta = maxValue - minValue
    let lightness = (maxValue + minValue) / 2
    let originalSaturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
    let saturation = min(originalSaturation, maxSaturation)
    var hue: CGFloat = 0
    if delta > 0 {
      switch maxValue {
      case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
      case green: hue = (blue - red) / delta + 2
      default: hue = (red - green) / delta + 4
      }
      hue /= 6
    }

    let newLightness = min(max(lightness, range.lowerBound), range.upperBound)
    let chroma = (1 - abs(2 * newLightness - 1)) * saturation
    let x = chroma * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1))
    let m = newLightness - chroma / 2
    let (r, g, b): (CGFloat, CGFloat, CGFloat) = switch Int(hue * 6) % 6 {
    case 0: (chroma, x, 0)
    case 1: (x, chroma, 0)
    case 2: (0, chroma, x)
    case 3: (0, x, chroma)
    case 4: (x, 0, chroma)
    default: (chroma, 0, x)
    }
    return UIColor(red: r + m, green: g + m, blue: b + m, alpha: alpha)
  }

  /// WCAG relative luminance (0 = black, 1 = white).
  var relativeLuminance: CGFloat {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
    func linear(_ value: CGFloat) -> CGFloat {
      value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// Whether black content is more readable than white on top of this color.
  var prefersDarkContent: Bool {
    // 0.179 would be the exact contrast tipping point,
    // the slightly higher threshold keeps mid tones on white text.
    relativeLuminance > 0.3
  }
}

extension UISearchBar {
  /// Whether the list is limited to cached entries. Mac Catalyst has no scope bar
  /// (see `configureSearchController`), so offline mode alone decides there.
  @MainActor
  var isCachedScopeSelected: Bool {
    if scopeButtonTitles?.count ?? 0 > 1 {
      return selectedScopeButtonIndex == 1
    }
    return appDelegate.storage.settings.user.isOfflineMode
  }
}

extension UIMenu {
  /// macOS 27 hides menu images by default; the library option menus show their icons like on
  /// iOS, next to the leading checkmarks.
  func showingImagesOnMac() -> UIMenu {
    #if targetEnvironment(macCatalyst)
      if #available(macCatalyst 27.0, *) {
        Self.showImages(of: self)
      }
    #endif
    return self
  }

  #if targetEnvironment(macCatalyst)
    @available(macCatalyst 27.0, *)
    private static func showImages(of element: UIMenuElement) {
      element.preferredImageVisibility = .visible
      (element as? UIMenu)?.children.forEach { showImages(of: $0) }
    }
  #endif
}

//
//  LibraryEntityImage.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 10.06.21.
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

import CoreData
import ImageIO
import UIKit

extension LibraryEntityImage {
  // Cache should not be used between different instances -> iOS and Carplay
  static public func getImageToDisplayImmediately(
    libraryEntity: AbstractLibraryEntity,
    themePreference: ThemePreference,
    artworkDisplayPreference: ArtworkDisplayPreference,
    useCache: Bool,
    maxPixelSize: Int? = nil
  )
    -> UIImage {
    if let artworkImagePath = libraryEntity.imagePath(
      setting: artworkDisplayPreference
    ) {
      if useCache, let cachedImg = Self.cachedImage(
        imagePath: artworkImagePath,
        minPixelSize: 0
      )?.image {
        return cachedImg
      } else if let directlyLoadedImage = loadImage(
        imagePath: artworkImagePath,
        maxPixelSize: maxPixelSize
      ) {
        return directlyLoadedImage
      }
    }
    return UIImage.getGeneratedArtwork(
      theme: themePreference,
      artworkType: libraryEntity.getDefaultArtworkType()
    )
  }

  /// `UIImage(named:)` at full size, or decoded scaled down to `maxPixelSize` without being kept in
  /// the system image cache (e.g. for the many small CarPlay list images).
  private static func loadImage(imagePath: String, maxPixelSize: Int?) -> UIImage? {
    guard let maxPixelSize else { return UIImage(named: imagePath) }
    return decodeArtwork(imagePath: imagePath, maxPixelSize: maxPixelSize)
  }

  /// Same selection as `EntityImageView`, rendered into a single image (e.g. for CarPlay).
  static public func getImageToDisplayImmediately(
    collection: ArtworkCollection,
    themePreference: ThemePreference,
    artworkDisplayPreference: ArtworkDisplayPreference,
    useCache: Bool,
    maxPixelSize: Int? = nil
  )
    -> UIImage {
    switch collection.display {
    case let .single(entity):
      return getImageToDisplayImmediately(
        libraryEntity: entity,
        themePreference: themePreference,
        artworkDisplayPreference: artworkDisplayPreference,
        useCache: useCache,
        maxPixelSize: maxPixelSize
      )
    case let .standalone(artwork):
      if let imagePath = artwork.imagePath,
         let image = loadImage(imagePath: imagePath, maxPixelSize: maxPixelSize) {
        return image
      }
    case let .quad(entities):
      return quadImage(
        entities: entities,
        themePreference: themePreference,
        artworkDisplayPreference: artworkDisplayPreference,
        useCache: useCache,
        maxPixelSize: maxPixelSize
      )
    case .placeholder:
      break
    }
    return UIImage.getGeneratedArtwork(
      theme: themePreference,
      artworkType: collection.defaultArtworkType
    )
  }

  private static let quadImagePixelSize = 400

  private static func quadImage(
    entities: [AbstractLibraryEntity],
    themePreference: ThemePreference,
    artworkDisplayPreference: ArtworkDisplayPreference,
    useCache: Bool,
    maxPixelSize: Int?
  )
    -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    // never larger than the caller can show
    let side = CGFloat(min(maxPixelSize ?? quadImagePixelSize, quadImagePixelSize))
    let imageSize = CGSize(width: side, height: side)
    let tile = CGSize(width: side / 2, height: side / 2)
    let placeholder = UIImage.getGeneratedArtwork(theme: themePreference, artworkType: .song)
    return UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
      for index in 0 ..< 4 {
        let rect = CGRect(
          x: CGFloat(index % 2) * tile.width,
          y: CGFloat(index / 2) * tile.height,
          width: tile.width,
          height: tile.height
        )
        let image = index < entities.count ? getImageToDisplayImmediately(
          libraryEntity: entities[index],
          themePreference: themePreference,
          artworkDisplayPreference: artworkDisplayPreference,
          useCache: useCache,
          maxPixelSize: tileDecodePixelSize(
            entity: entities[index],
            artworkDisplayPreference: artworkDisplayPreference,
            tileSide: tile.width
          )
        ) : placeholder
        context.cgContext.saveGState()
        UIBezierPath(rect: rect).addClip()
        // transparent covers must not show the black of the opaque renderer
        UIColor.systemBackground.setFill()
        context.fill(rect)
        drawAspectFill(image, in: rect)
        context.cgContext.restoreGState()
      }
    }
  }

  /// Longest side to decode an artwork with so that its short side still fills the tile
  /// (the tile is drawn aspect fill)
  private static func tileDecodePixelSize(
    entity: AbstractLibraryEntity,
    artworkDisplayPreference: ArtworkDisplayPreference,
    tileSide: CGFloat
  )
    -> Int {
    guard let imagePath = entity.imagePath(setting: artworkDisplayPreference),
          let size = pixelSize(ofArtworkAt: imagePath),
          min(size.width, size.height) > 0
    else { return Int(tileSide.rounded(.up)) }
    let aspect = max(size.width, size.height) / min(size.width, size.height)
    return Int((tileSide * aspect).rounded(.up))
  }

  private static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
    guard image.size.width > 0, image.size.height > 0 else { return }
    let scale = max(rect.width / image.size.width, rect.height / image.size.height)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    image.draw(in: CGRect(
      x: rect.midX - size.width / 2,
      y: rect.midY - size.height / 2,
      width: size.width,
      height: size.height
    ))
  }
}

// MARK: - LibraryEntityImage

@MainActor
public class LibraryEntityImage: RoundedImage {
  /// Decoded artworks, keyed by image path and pixel size; a decoded bitmap takes 4 bytes per pixel.
  static private let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.totalCostLimit = 100 * 1024 * 1024
    return cache
  }()

  /// Maximum pixel sizes an artwork is decoded with, so a small tile does not keep the
  /// full resolution artwork in memory.
  static private let pixelSizes = [256, 512, 1024, 2048, 4096]

  private let appDelegate: AmperKit

  private var entity: AbstractLibraryEntity?
  private var standaloneArtwork: Artwork?
  private var backupArtworkType: ArtworkType?
  private var accountNotificationHandler: AccountNotificationHandler?
  /// Pixel size of the shown artwork, 0 while the placeholder is shown
  private var shownPixelSize = 0
  /// Image path and pixel size of the artwork that is being loaded
  private var loadingCacheKey: String?
  /// Only the result of the latest load is shown
  private var loadGeneration = 0
  /// Image path and pixel size that could not be decoded, not tried again on layout changes
  private var failedCacheKey: String?
  /// The artwork is loaded once the view has a size
  private var isWaitingForLayout = false

  /// True if the generated placeholder is shown because there is no artwork
  /// (false while an existing artwork is still loading).
  public private(set) var isShowingPlaceholder = false

  /// True while a loaded artwork is shown: false for the generated placeholder, also while the
  /// artwork is still loading or could not be decoded.
  public var isShowingArtwork: Bool { shownPixelSize > 0 }

  /// Called whenever the shown image changes, e.g. when the loaded artwork replaces the placeholder.
  public var imageDidChange: ((UIImage?) -> ())?

  override public var image: UIImage? {
    didSet { imageDidChange?(image) }
  }

  required public init?(coder: NSCoder) {
    self.appDelegate = AmperKit.shared
    super.init(coder: coder)
    self.accountNotificationHandler = AccountNotificationHandler(
      storage: appDelegate.storage,
      notificationHandler: appDelegate.notificationHandler
    )
    accountNotificationHandler?.registerCallbackForAllAccounts { [weak self] accountInfo in
      guard let self else { return }
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).artworkDownloadManager
      )
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).playableDownloadManager
      )
    }
  }

  override public init(frame: CGRect) {
    self.appDelegate = AmperKit.shared
    super.init(frame: .zero)
    self.accountNotificationHandler = AccountNotificationHandler(
      storage: appDelegate.storage,
      notificationHandler: appDelegate.notificationHandler
    )
    accountNotificationHandler?.registerCallbackForAllAccounts { [weak self] accountInfo in
      guard let self else { return }
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).artworkDownloadManager
      )
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: appDelegate.getMeta(accountInfo).playableDownloadManager
      )
    }
  }

  public func display(entity: AbstractLibraryEntity) {
    self.entity = entity
    standaloneArtwork = nil
    backupArtworkType = entity.getDefaultArtworkType()
    refresh()
  }

  public func displayAndUpdate(entity: AbstractLibraryEntity) {
    guard self.entity != entity else { return }

    display(entity: entity)
    if let artwork = entity.artwork, let accountInfo = entity.account?.info {
      appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
    }
  }

  /// Displays an artwork that is not owned by an AbstractLibraryEntity (e.g. playlist server cover)
  public func displayAndUpdate(artwork: Artwork, artworkType: ArtworkType) {
    guard standaloneArtwork != artwork else { return }

    entity = nil
    standaloneArtwork = artwork
    backupArtworkType = artworkType
    refresh()
    if let accountInfo = artwork.account?.info {
      appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
    }
  }

  internal func display(image: UIImage) {
    isShowingPlaceholder = false
    shownPixelSize = 0
    // a load still in progress must not replace this image
    loadGeneration += 1
    loadingCacheKey = nil
    isWaitingForLayout = false
    self.image = image
    entity = nil
    standaloneArtwork = nil
  }

  public func display(artworkType: ArtworkType) {
    backupArtworkType = artworkType
    entity = nil
    standaloneArtwork = nil
    refresh()
  }

  private var placeholderImage: UIImage {
    var theme = appDelegate.storage.settings.accounts.activeSetting.read.themePreference
    if let accountInfo = entity?.account?.info ?? standaloneArtwork?.account?.info {
      theme = appDelegate.storage.settings.accounts.getSetting(accountInfo).read.themePreference
    }
    return UIImage.getGeneratedArtwork(
      theme: theme,
      artworkType: backupArtworkType ?? .song
    )
  }

  private var entityImagePathToDisplay: String? {
    var artworkDisplayPreference = appDelegate.storage.settings.accounts.activeSetting.read
      .artworkDisplayPreference
    if let accountInfo = entity?.account?.info ?? standaloneArtwork?.account?.info {
      artworkDisplayPreference = appDelegate.storage.settings.accounts.getSetting(accountInfo).read
        .artworkDisplayPreference
    }
    if let entity {
      return entity.imagePath(setting: artworkDisplayPreference)
    }
    return standaloneArtwork?.imagePath
  }

  override public func layoutSubviews() {
    super.layoutSubviews()
    guard !bounds.isEmpty else { return }
    if isWaitingForLayout {
      refresh()
      return
    }
    // the view can get larger after the artwork was shown
    guard shownPixelSize > 0, loadingCacheKey == nil, requiredPixelSize > shownPixelSize,
          let imagePath = entityImagePathToDisplay,
          Self.cacheKey(imagePath: imagePath, pixelSize: requiredPixelSize) != failedCacheKey
    else { return }
    refresh()
  }

  /// Smallest pixel size that covers the view on the screen
  private var requiredPixelSize: Int {
    let pixels = max(bounds.width, bounds.height) * traitCollection.displayScale
    return Self.pixelSizes.first { CGFloat($0) >= pixels } ?? Self.pixelSizes.last!
  }

  private static func cacheKey(imagePath: String, pixelSize: Int) -> String {
    "\(imagePath)|\(pixelSize)"
  }

  /// The smallest cached artwork with at least `minPixelSize`
  private static func cachedImage(
    imagePath: String,
    minPixelSize: Int
  )
    -> (image: UIImage, pixelSize: Int)? {
    for pixelSize in pixelSizes where pixelSize >= minPixelSize {
      if let image = cache.object(forKey: cacheKey(
        imagePath: imagePath,
        pixelSize: pixelSize
      ) as NSString) {
        return (image, pixelSize)
      }
    }
    return nil
  }

  private func refresh() {
    let imagePathToDisplay = entityImagePathToDisplay
    let pixelSize = requiredPixelSize

    if let imagePathToDisplay,
       let cached = Self.cachedImage(imagePath: imagePathToDisplay, minPixelSize: pixelSize) {
      isShowingPlaceholder = false
      shownPixelSize = cached.pixelSize
      image = cached.image
      return
    }

    // a smaller artwork is shown until the required size is loaded
    if let imagePathToDisplay,
       let smaller = Self.cachedImage(imagePath: imagePathToDisplay, minPixelSize: 0) {
      isShowingPlaceholder = false
      shownPixelSize = smaller.pixelSize
      image = smaller.image
    } else {
      isShowingPlaceholder = imagePathToDisplay == nil
      shownPixelSize = 0
      image = placeholderImage
    }
    guard let imagePathToDisplay else { return }
    // the required size is only known after layout
    isWaitingForLayout = bounds.isEmpty
    guard !isWaitingForLayout else { return }
    loadImage(imagePath: imagePathToDisplay)
  }

  /// `isForced` loads the file again, e.g. after it was downloaded
  private func loadImage(imagePath: String, isForced: Bool = false) {
    let pixelSize = requiredPixelSize
    let cacheKey = Self.cacheKey(imagePath: imagePath, pixelSize: pixelSize)
    guard isForced || (loadingCacheKey != cacheKey && failedCacheKey != cacheKey) else { return }
    loadingCacheKey = cacheKey
    loadGeneration += 1
    let generation = loadGeneration
    Task.detached(priority: .high) { [weak self] in
      let readyImage = await Self.decodeImage(imagePath: imagePath, maxPixelSize: pixelSize)
      guard !Task.isCancelled else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        let isLatestLoad = generation == loadGeneration
        if isLatestLoad { loadingCacheKey = nil }
        guard let readyImage else {
          if isLatestLoad { failedCacheKey = cacheKey }
          return
        }
        Self.cache.setObject(
          readyImage,
          forKey: cacheKey as NSString,
          cost: Self.byteCount(of: readyImage)
        )
        guard isLatestLoad else { return }
        if failedCacheKey == cacheKey { failedCacheKey = nil }
        refresh()
      }
    }
  }

  /// A downloaded file replaces all sizes of the artwork that were decoded before.
  private func reloadDownloadedImage(imagePath: String) {
    for pixelSize in Self.pixelSizes {
      Self.cache.removeObject(forKey: Self.cacheKey(
        imagePath: imagePath,
        pixelSize: pixelSize
      ) as NSString)
    }
    failedCacheKey = nil
    guard !bounds.isEmpty else {
      refresh()
      return
    }
    loadImage(imagePath: imagePath, isForced: true)
  }

  /// Decodes the artwork, scaled down to `maxPixelSize` if it is larger
  @concurrent
  private static func decodeImage(imagePath: String, maxPixelSize: Int) async -> UIImage? {
    if let image = decodeScaledImage(imagePath: imagePath, maxPixelSize: maxPixelSize) {
      return image
    }
    // formats ImageIO can not scale
    return await UIImage(contentsOfFile: imagePath)?.byPreparingForDisplay()
  }

  /// Decodes the artwork synchronously, scaled down to `maxPixelSize` if it is larger
  /// (formats ImageIO can not scale are decoded at full size).
  /// Not cached; for callers that need one specific size off the main thread
  /// (e.g. the Now Playing artwork on the lock screen and in CarPlay).
  nonisolated public static func decodeArtwork(imagePath: String, maxPixelSize: Int) -> UIImage? {
    decodeScaledImage(imagePath: imagePath, maxPixelSize: maxPixelSize) ??
      // formats ImageIO can not scale, at full size
      UIImage(contentsOfFile: imagePath)?.preparingForDisplay()
  }

  /// Pixel size of the artwork file (orientation applied), read without decoding the image
  nonisolated public static func pixelSize(ofArtworkAt imagePath: String) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(
      URL(fileURLWithPath: imagePath) as CFURL,
      [kCGImageSourceShouldCache: false] as CFDictionary
    ),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { return nil }
    // EXIF orientations 5 to 8 are rotated by 90 degrees
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    return orientation >= 5
      ? CGSize(width: height, height: width)
      : CGSize(width: width, height: height)
  }

  nonisolated private static func decodeScaledImage(
    imagePath: String,
    maxPixelSize: Int
  )
    -> UIImage? {
    let url = URL(fileURLWithPath: imagePath) as CFURL
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    guard let source = CGImageSourceCreateWithURL(
      url,
      [kCGImageSourceShouldCache: false] as CFDictionary
    ),
      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return UIImage(cgImage: cgImage)
  }

  private static func byteCount(of image: UIImage) -> Int {
    guard let cgImage = image.cgImage else {
      return Int(image.size.width * image.scale * image.size.height * image.scale) * 4
    }
    return cgImage.bytesPerRow * cgImage.height
  }

  @objc
  private func downloadFinishedSuccessful(notification: Notification) {
    guard let downloadNotification = DownloadNotification.fromNotification(notification)
    else { return }
    if entity == nil, let artwork = standaloneArtwork,
       artwork.uniqueID == downloadNotification.id {
      Task { @MainActor in
        guard let imagePath = artwork.imagePath else { return }
        self.reloadDownloadedImage(imagePath: imagePath)
      }
      return
    }
    guard let entity else { return }
    if let playable = entity as? AbstractPlayable,
       playable.uniqueID == downloadNotification.id, let accountInfo = playable.account?.info {
      Task { @MainActor in
        guard let imagePath = entity.imagePath(
          setting: appDelegate.storage.settings.accounts.getSetting(accountInfo).read
            .artworkDisplayPreference
        ) else { return }
        self.reloadDownloadedImage(imagePath: imagePath)
      }
    }
    if let artwork = entity.artwork,
       artwork.uniqueID == downloadNotification.id, let accountInfo = artwork.account?.info {
      Task { @MainActor in
        guard let imagePath = entity.imagePath(
          setting: appDelegate.storage.settings.accounts.getSetting(accountInfo).read
            .artworkDisplayPreference
        ) else { return }
        self.reloadDownloadedImage(imagePath: imagePath)
      }
    }
  }
}

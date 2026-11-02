//
//  NowPlayingInfoCenterHandler.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 23.11.21.
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

import Foundation
import MediaPlayer

// MARK: - NowPlayingInfoCenterHandler

@MainActor
public class NowPlayingInfoCenterHandler {
  private let musicPlayer: AudioPlayer
  private let backendAudioPlayer: BackendAudioPlayer
  private let storage: PersistentStorage
  private var nowPlayingInfoCenter: MPNowPlayingInfoCenter
  private let getArtworkDownloaderCB: GetArtworkDownloadManagerCallback
  private var accountNotificationHandler: AccountNotificationHandler?
  /// The Now Playing info is rebuilt every second (elapsed time). The artwork is kept until the
  /// playable or its artwork file changes, so the file is not read and decoded again each time.
  private var currentArtwork: (key: String, artwork: MPMediaItemArtwork)?

  init(
    musicPlayer: AudioPlayer,
    backendAudioPlayer: BackendAudioPlayer,
    nowPlayingInfoCenter: MPNowPlayingInfoCenter,
    storage: PersistentStorage,
    notificationHandler: EventNotificationHandler,
    getArtworkDownloaderCB: @escaping GetArtworkDownloadManagerCallback,
    getPlayableDownloaderCB: @escaping GetPlayableDownloadManagerCallback
  ) {
    self.musicPlayer = musicPlayer
    self.backendAudioPlayer = backendAudioPlayer
    self.nowPlayingInfoCenter = nowPlayingInfoCenter
    self.storage = storage
    self.getArtworkDownloaderCB = getArtworkDownloaderCB

    nowPlayingInfoCenter.playbackState = .stopped

    self.accountNotificationHandler = AccountNotificationHandler(
      storage: storage,
      notificationHandler: notificationHandler
    )
    accountNotificationHandler?.registerCallbackForAllAccounts { [weak self] accountInfo in
      guard let self else { return }
      notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: getArtworkDownloaderCB(accountInfo)
      )
      notificationHandler.register(
        self,
        selector: #selector(downloadFinishedSuccessful(notification:)),
        name: .downloadFinishedSuccess,
        object: getPlayableDownloaderCB(accountInfo)
      )
    }
  }

  private func updateNowPlayingInfo(playable: AbstractPlayable) {
    let albumTitle = playable.asSong?.album?.name ?? ""
    let nowPlaying = displayNowPlayingInfo(for: playable)

    if let accountInfo = playable.account?.info, let artwork = playable.artwork {
      getArtworkDownloaderCB(accountInfo).download(object: artwork)
    }

    nowPlayingInfoCenter.nowPlayingInfo = [
      MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.audio.rawValue),
      MPNowPlayingInfoPropertyServiceIdentifier: AmperKit.name,

      MPMediaItemPropertyIsCloudItem: !playable.isCached,
      MPMediaItemPropertyTitle: nowPlaying.title,
      MPMediaItemPropertyAlbumTitle: albumTitle,
      MPMediaItemPropertyArtist: nowPlaying.artist,

      MPMediaItemPropertyPlaybackDuration: backendAudioPlayer.duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: backendAudioPlayer.elapsedTime,
      MPNowPlayingInfoPropertyIsLiveStream: playable.isRadio,

      MPNowPlayingInfoPropertyDefaultPlaybackRate: NSNumber(value: 1.0),
      MPNowPlayingInfoPropertyPlaybackRate: NSNumber(
        value: backendAudioPlayer.playbackRate
          .asDouble
      ),

      MPMediaItemPropertyArtwork: artwork(for: playable),
    ]
  }

  private func artwork(for playable: AbstractPlayable) -> MPMediaItemArtwork {
    var themePreference = storage.settings.accounts.activeSetting.read.themePreference
    var filePath: String?
    var artworkDisplayPreference = ArtworkDisplayPreference.defaultValue
    if let accountInfo = playable.account?.info {
      let setting = storage.settings.accounts.getSetting(accountInfo).read
      themePreference = setting.themePreference
      artworkDisplayPreference = setting.artworkDisplayPreference
      filePath = playable.imagePath(setting: artworkDisplayPreference)
    }
    let key = "\(playable.uniqueID)|\(filePath ?? "")|\(themePreference)"
    if let currentArtwork, currentArtwork.key == key {
      return currentArtwork.artwork
    }
    let fallbackImage = LibraryEntityImage.getImageToDisplayImmediately(
      libraryEntity: playable,
      themePreference: themePreference,
      artworkDisplayPreference: artworkDisplayPreference,
      useCache: true
    )
    let artwork = Self.createArtwork(filePath: filePath, fallbackImage: fallbackImage)
    currentArtwork = (key, artwork)
    return artwork
  }

  /// The image cache only holds artworks at the size they were shown in the app (often small
  /// list thumbnails), which look blurry on the lock screen and in CarPlay. The artwork file is
  /// therefore decoded at the size the system requests.
  private static func createArtwork(
    filePath: String?,
    fallbackImage: UIImage
  )
    -> MPMediaItemArtwork {
    guard let filePath,
          let pixelSize = LibraryEntityImage.pixelSize(ofArtworkAt: filePath)
    else {
      return MPMediaItemArtwork(
        boundsSize: fallbackImage.size,
        requestHandler: { @Sendable _ -> UIImage in fallbackImage }
      )
    }
    let decodedImages = DecodedArtworkCache()
    return MPMediaItemArtwork(
      boundsSize: pixelSize,
      requestHandler: { @Sendable size -> UIImage in
        // this completion handler is not called in main thread!
        // the requested size is in points, 3 is the highest display scale of the devices
        let maxPixelSize = max(Int((max(size.width, size.height) * 3).rounded(.up)), 1)
        if let image = decodedImages.image(maxPixelSize: maxPixelSize) {
          return image
        }
        guard let image = LibraryEntityImage.decodeArtwork(
          imagePath: filePath,
          maxPixelSize: maxPixelSize
        ) else { return fallbackImage }
        decodedImages.set(image, maxPixelSize: maxPixelSize)
        return image
      }
    )
  }

  private func displayNowPlayingInfo(for playable: AbstractPlayable) -> RadioNowPlayingInfo {
    if playable.isRadio,
       let radioInfo = musicPlayer.currentRadioNowPlaying,
       !radioInfo.isEmpty {
      return radioInfo
    }
    return RadioNowPlayingInfo(title: playable.title, artist: playable.creatorName)
  }

  @objc
  private func downloadFinishedSuccessful(notification: Notification) {
    guard let downloadNotification = DownloadNotification.fromNotification(notification),
          let curPlayable = musicPlayer.currentlyPlaying
    else { return }
    if curPlayable.uniqueID == downloadNotification.id {
      Task { @MainActor in
        // the downloaded file can contain an embedded artwork
        currentArtwork = nil
        updateNowPlayingInfo(playable: curPlayable)
      }
    }
    if let artwork = curPlayable.artwork,
       artwork.uniqueID == downloadNotification.id {
      Task { @MainActor in
        // the file at the same path was replaced
        currentArtwork = nil
        updateNowPlayingInfo(playable: curPlayable)
      }
    }
  }
}

// MARK: MusicPlayable

extension NowPlayingInfoCenterHandler: MusicPlayable {
  public func didStartPlayingFromBeginning() {}

  public func didStartPlaying() {
    if let curPlayable = musicPlayer.currentlyPlaying {
      updateNowPlayingInfo(playable: curPlayable)
    }
    nowPlayingInfoCenter.playbackState = .playing
  }

  public func didPause() {
    if let curPlayable = musicPlayer.currentlyPlaying {
      updateNowPlayingInfo(playable: curPlayable)
    }
    nowPlayingInfoCenter.playbackState = .paused
  }

  public func didStopPlaying() {
    nowPlayingInfoCenter.nowPlayingInfo = nil
    nowPlayingInfoCenter.playbackState = .stopped
  }

  public func didElapsedTimeChange() {
    if let curPlayable = musicPlayer.currentlyPlaying {
      updateNowPlayingInfo(playable: curPlayable)
    }
  }

  public func didPlaylistChange() {}

  public func didArtworkChange() {}

  public func didNowPlayingInfoChange() {
    if let curPlayable = musicPlayer.currentlyPlaying {
      updateNowPlayingInfo(playable: curPlayable)
    }
  }

  public func didShuffleChange() {}

  public func didRepeatChange() {}

  public func didPlaybackRateChange() {}
}

// MARK: - DecodedArtworkCache

/// Artworks decoded for the Now Playing info, by pixel size. The system requests the artwork
/// from a background thread, usually in only a few sizes.
private final class DecodedArtworkCache: @unchecked Sendable {
  private let lock = NSLock()
  private var images = [Int: UIImage]()

  func image(maxPixelSize: Int) -> UIImage? {
    lock.withLock { images[maxPixelSize] }
  }

  func set(_ image: UIImage, maxPixelSize: Int) {
    lock.withLock {
      // only the latest sizes are kept, a size change replaces the old images
      if images.count >= 2 { images.removeAll() }
      images[maxPixelSize] = image
    }
  }
}

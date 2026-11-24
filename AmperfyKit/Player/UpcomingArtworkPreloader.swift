//
//  UpcomingArtworkPreloader.swift
//  AmperfyKit
//
//  Created by Chrizz Gelbach on 24.11.26.
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

import Foundation

typealias DownloadArtworkCallback = @MainActor (Artwork, AccountInfo) -> ()

// MARK: - UpcomingArtworkPreloader

/// Downloads the missing server artworks of the next playables of the queue, so their cover is
/// shown right away when the player changes to them. A song can have its own artwork (e.g.
/// Navidrome for files with an embedded cover), which the album screens don't download, and the
/// embedded cover is only read from downloaded files, not from streams.
/// Requested when a playable starts and when the queue changes (also while paused). Offline or
/// without network, the download manager keeps the requests and starts them once online again;
/// it also applies the artwork download setting and retries transiently failed downloads.
/// Independent of the Preload setting: artworks are small and also needed for downloaded songs.
@MainActor
final class UpcomingArtworkPreloader {
  /// Also covers a skip to a song further ahead, the ones after it are requested when it starts
  static let upcomingCount = 3

  private let upcomingPlayables: @MainActor (Int) -> [AbstractPlayable]
  private let artworkDisplayPreference: @MainActor (AccountInfo) -> ArtworkDisplayPreference
  private let downloadArtwork: DownloadArtworkCallback
  /// Several changes in a row (e.g. shuffle + queue update) are handled once
  private var isUpdateScheduled = false

  init(
    upcomingPlayables: @escaping @MainActor (Int) -> [AbstractPlayable],
    artworkDisplayPreference: @escaping @MainActor (AccountInfo) -> ArtworkDisplayPreference,
    downloadArtwork: @escaping DownloadArtworkCallback
  ) {
    self.upcomingPlayables = upcomingPlayables
    self.artworkDisplayPreference = artworkDisplayPreference
    self.downloadArtwork = downloadArtwork
  }

  func scheduleUpdate() {
    guard !isUpdateScheduled else { return }
    isUpdateScheduled = true
    Task { @MainActor in
      isUpdateScheduled = false
      update()
    }
  }

  func update() {
    // the queue order, also with repeat single or pause after the current song: the user can
    // still skip
    for playable in upcomingPlayables(Self.upcomingCount) where !playable.isRadio {
      // a downloaded artwork is refreshed (artwork setting) when it is displayed
      guard let artwork = playable.artwork, !artwork.isCached,
            let accountInfo = artwork.account?.info,
            isServerArtworkShown(for: playable, setting: artworkDisplayPreference(accountInfo))
      else { continue }
      downloadArtwork(artwork, accountInfo)
    }
  }

  private func isServerArtworkShown(
    for playable: AbstractPlayable,
    setting: ArtworkDisplayPreference
  )
    -> Bool {
    switch setting {
    case .id3TagOnly: false
    case .preferId3Tag: playable.embeddedArtwork == nil
    case .preferServerArtwork, .serverArtworkOnly: true
    }
  }
}

// MARK: MusicPlayable

extension UpcomingArtworkPreloader: MusicPlayable {
  func didStartPlayingFromBeginning() { scheduleUpdate() }
  func didPlaylistChange() { scheduleUpdate() }
  func didShuffleChange() { scheduleUpdate() }
  func didRepeatChange() { scheduleUpdate() }
  func didStartPlaying() {}
  func didPause() {}
  func didStopPlaying() {}
  func didElapsedTimeChange() {}
  func didArtworkChange() {}
  func didPlaybackRateChange() {}
}

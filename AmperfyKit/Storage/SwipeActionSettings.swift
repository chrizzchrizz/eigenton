//
//  SwipeActionSettings.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 06.02.22.
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

import Foundation
import UIKit

// MARK: - SwipeActionType

public enum SwipeActionType: Int, CaseIterable, Sendable, Codable {
  case insertUserQueue = 0
  case appendUserQueue = 1
  case insertContextQueue = 2
  case appendContextQueue = 3
  case download = 4
  case removeFromCache = 5
  case addToPlaylist = 6
  case play = 7
  case playShuffled = 8
  case insertPodcastQueue = 9
  case appendPodcastQueue = 10
  case favorite = 11

  /// The user queue actions are no longer offered; "Insert in Queue" and "Append to Queue" use the context queue.
  public var isSelectable: Bool {
    switch self {
    case .appendUserQueue, .insertUserQueue:
      return false
    default:
      return true
    }
  }

  /// Replaces a no longer selectable action by its context queue counterpart.
  fileprivate var selectableReplacement: SwipeActionType {
    switch self {
    case .insertUserQueue:
      return .insertContextQueue
    case .appendUserQueue:
      return .appendContextQueue
    default:
      return self
    }
  }

  public var displayName: String {
    switch self {
    case .insertUserQueue:
      return "Insert User Queue"
    case .appendUserQueue:
      return "Append User Queue"
    case .insertContextQueue:
      return "Insert"
    case .appendContextQueue:
      return "Append"
    case .download:
      return "Download"
    case .removeFromCache:
      return "Remove from Cache"
    case .addToPlaylist:
      return "Add to Playlist"
    case .play:
      return "Play"
    case .playShuffled:
      return "Play shuffled"
    case .insertPodcastQueue:
      return "Insert Podcast Queue"
    case .appendPodcastQueue:
      return "Append Podcast Queue"
    case .favorite:
      return "Favorite"
    }
  }

  public var settingsName: String {
    switch self {
    case .insertUserQueue:
      return "Insert in User Queue"
    case .appendUserQueue:
      return "Append to User Queue"
    case .insertContextQueue:
      return "Insert in Queue"
    case .appendContextQueue:
      return "Append to Queue"
    case .download:
      return "Download"
    case .removeFromCache:
      return "Remove from Cache"
    case .addToPlaylist:
      return "Add to Playlist"
    case .play:
      return "Play"
    case .playShuffled:
      return "Play shuffled"
    case .insertPodcastQueue:
      return "Insert in Podcast Queue"
    case .appendPodcastQueue:
      return "Append to Podcast Queue"
    case .favorite:
      return "Mark as Favorite"
    }
  }

  @MainActor
  public var image: UIImage {
    switch self {
    case .insertUserQueue:
      return UIImage.userQueueInsert.withTintColor(.white)
    case .appendUserQueue:
      return UIImage.userQueueAppend.withTintColor(.white)
    case .insertContextQueue:
      return UIImage.contextQueueInsert.withTintColor(.white)
    case .appendContextQueue:
      return UIImage.contextQueueAppend.withTintColor(.white)
    case .download:
      return UIImage.download.withTintColor(.white)
    case .removeFromCache:
      return UIImage.trash.withTintColor(.white)
    case .addToPlaylist:
      return UIImage.playlist.withTintColor(.white)
    case .play:
      return UIImage.play.withTintColor(.white)
    case .playShuffled:
      return UIImage.shuffle.withTintColor(.white)
    case .insertPodcastQueue:
      return UIImage.podcastQueueInsert.withTintColor(.white)
    case .appendPodcastQueue:
      return UIImage.podcastQueueAppend.withTintColor(.white)
    case .favorite:
      return UIImage.heartFill.withTintColor(.white)
    }
  }
}

// MARK: - SwipeActionSettings

public struct SwipeActionSettings: Sendable, Codable {
  public var combined: [[SwipeActionType]]

  public var leading: [SwipeActionType] {
    combined[0]
  }

  public var trailing: [SwipeActionType] {
    combined[1]
  }

  public var notUsed: [SwipeActionType] {
    combined[2]
  }

  public init(leading: [SwipeActionType], trailing: [SwipeActionType]) {
    let leading = Self.selectable(leading)
    let trailing = Self.selectable(trailing).filter { !leading.contains($0) }
    let notUsedSet = Set(SwipeActionType.allCases.filter { $0.isSelectable })
      .subtracting(Set(leading))
      .subtracting(Set(trailing))
    self.combined = [leading, trailing, Array(notUsedSet)]
  }

  private static func selectable(_ actions: [SwipeActionType]) -> [SwipeActionType] {
    var result = [SwipeActionType]()
    for action in actions.map({ $0.selectableReplacement }) where !result.contains(action) {
      result.append(action)
    }
    return result
  }

  // Explicit Codable conformance to ensure stable schema
  private enum CodingKeys: String, CodingKey {
    case combined
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Decode combined as an array of arrays of SwipeActionType
    let decodedCombined = try container.decode([[SwipeActionType]].self, forKey: .combined)
    // The stored notUsed bucket is ignored, it is derived from leading and trailing
    if decodedCombined.count >= 2 {
      self.init(leading: decodedCombined[0], trailing: decodedCombined[1])
    } else {
      // Fallback to defaults if data is malformed
      self = SwipeActionSettings.defaultSettings
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(combined, forKey: .combined)
  }

  public static var defaultSettings: SwipeActionSettings {
    SwipeActionSettings(
      leading: [
        .insertContextQueue,
        .appendContextQueue,

      ], trailing: [
        .appendPodcastQueue,
        .insertPodcastQueue,
        .download,
      ]
    )
  }
}

// MARK: - SwipeActionContext

public struct SwipeActionContext {
  public let containable: PlayableContainable
  private let customPlayContext: PlayContext?

  public var playables: [AbstractPlayable] { containable.playables }
  public var playContext: PlayContext {
    customPlayContext ?? PlayContext(containable: containable)
  }

  public init(containable: PlayableContainable, playContext: PlayContext? = nil) {
    self.containable = containable
    self.customPlayContext = playContext
  }
}

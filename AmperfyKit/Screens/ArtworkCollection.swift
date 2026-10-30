//
//  ArtworkCollection.swift
//  AmperfyKit
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

import Foundation
import UIKit

public class ArtworkCollection {
  public let defaultArtworkType: ArtworkType
  public let singleImageEntity: AbstractLibraryEntity?
  public let quadImageEntity: [AbstractLibraryEntity]?
  /// Cover provided by the server (e.g. for a playlist). Shown instead of the entities as soon
  /// as it is downloaded, until then the entities are shown.
  public let serverArtwork: Artwork?

  init(
    defaultArtworkType: ArtworkType,
    singleImageEntity: AbstractLibraryEntity?,
    quadImageEntity: [AbstractLibraryEntity]? = nil,
    serverArtwork: Artwork? = nil
  ) {
    self.serverArtwork = serverArtwork
    self.defaultArtworkType = defaultArtworkType
    self.singleImageEntity = singleImageEntity
    self.quadImageEntity = quadImageEntity
  }

  /// What is shown for this collection; shared by the app screens and CarPlay.
  public enum Display {
    case quad([AbstractLibraryEntity])
    case single(AbstractLibraryEntity)
    case standalone(Artwork)
    case placeholder
  }

  public var display: Display {
    if let serverArtwork, serverArtwork.imagePath != nil {
      return .standalone(serverArtwork)
    }
    if let quadEntities = quadImageEntity {
      if quadEntities.count > 1 {
        // all images are the same
        if Set(quadEntities.compactMap { $0.artwork?.id }).count == 1 {
          return .single(quadEntities[0])
        }
        return .quad(quadEntities)
      } else if let firstEntity = quadEntities.first {
        return .single(firstEntity)
      }
      return .placeholder
    } else if let singleImageEntity {
      return .single(singleImageEntity)
    }
    return .placeholder
  }

  /// Artworks that have to be downloaded to show this collection. Contains the server cover
  /// until it is downloaded, so it replaces the entities afterwards.
  public var artworks: [Artwork] {
    var all: [Artwork?]
    switch display {
    case let .quad(entities): all = entities.map { $0.artwork }
    case let .single(entity): all = [entity.artwork]
    case let .standalone(artwork): all = [artwork]
    case .placeholder: all = []
    }
    all.append(serverArtwork)
    var seenIDs = Set<String>()
    return all.compactMap { $0 }.filter { seenIDs.insert($0.uniqueID).inserted }
  }
}

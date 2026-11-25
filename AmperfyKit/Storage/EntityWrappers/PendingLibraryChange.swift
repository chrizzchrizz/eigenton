//
//  PendingLibraryChange.swift
//  AmperfyKit
//
//  Created by Chrizz Gelbach on 25.11.26.
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

// MARK: - PendingLibraryChangeKind

public enum PendingLibraryChangeKind: Int16, Sendable {
  case favorite = 0
  case rating = 1
}

// MARK: - PendingLibraryChangeEntityType

public enum PendingLibraryChangeEntityType: Int16, Sendable {
  case song = 0
  case album = 1
  case artist = 2

  /// The type of a favoritable or rateable entity, nil for all others
  public static func of(_ entity: AbstractLibraryEntity) -> PendingLibraryChangeEntityType? {
    if let playable = entity as? AbstractPlayable {
      return playable.isSong ? .song : nil
    } else if entity is Album {
      return .album
    } else if entity is Artist {
      return .artist
    }
    return nil
  }
}

// MARK: - PendingLibraryChange

/// A favorite or rating change that is set locally but not yet on the server (offline mode,
/// no network or a failed request). There is at most one per entity and kind: the last change
/// wins.
public class PendingLibraryChange: NSObject {
  public let managedObject: PendingLibraryChangeMO

  public init(managedObject: PendingLibraryChangeMO) {
    self.managedObject = managedObject
  }

  public var account: Account? {
    get {
      guard let accountMO = managedObject.account else { return nil }
      return Account(managedObject: accountMO)
    }
    set {
      if managedObject.account != newValue?
        .managedObject { managedObject.account = newValue?.managedObject }
    }
  }

  public var changeDate: Date? {
    get { managedObject.changeDate }
    set { managedObject.changeDate = newValue }
  }

  public var entityId: String {
    get { managedObject.entityId ?? "" }
    set { managedObject.entityId = newValue }
  }

  public var entityType: PendingLibraryChangeEntityType? {
    get { PendingLibraryChangeEntityType(rawValue: managedObject.entityType) }
    set { managedObject.entityType = newValue?.rawValue ?? 0 }
  }

  public var kind: PendingLibraryChangeKind? {
    get { PendingLibraryChangeKind(rawValue: managedObject.kind) }
    set { managedObject.kind = newValue?.rawValue ?? 0 }
  }

  public var isFavorite: Bool {
    get { managedObject.isFavorite }
    set { managedObject.isFavorite = newValue }
  }

  public var rating: Int {
    get { Int(managedObject.rating) }
    set { managedObject.rating = Int16(clamping: newValue) }
  }

  /// Sets the change on the entity, e.g. again after a server sync has overwritten it
  public func apply(to entity: AbstractLibraryEntity) {
    switch kind {
    case .favorite:
      Self.setFavorite(isFavorite, on: entity)
    case .rating:
      entity.rating = rating
    case .none:
      break
    }
  }

  static func setFavorite(_ isFavorite: Bool, on entity: AbstractLibraryEntity) {
    entity.isFavorite = isFavorite
    if !isFavorite {
      entity.starredDate = nil
    } else if entity.starredDate == nil {
      entity.starredDate = Date()
    }
  }

  override public func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? PendingLibraryChange else { return false }
    return managedObject == object.managedObject
  }
}

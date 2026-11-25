//
//  PendingLibraryChangeMO+CoreDataProperties.swift
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

import CoreData
import Foundation

extension PendingLibraryChangeMO {
  @nonobjc
  public class func fetchRequest() -> NSFetchRequest<PendingLibraryChangeMO> {
    NSFetchRequest<PendingLibraryChangeMO>(entityName: "PendingLibraryChange")
  }

  @NSManaged
  public var account: AccountMO?
  @NSManaged
  public var changeDate: Date?
  @NSManaged
  public var entityId: String?
  @NSManaged
  public var entityType: Int16
  @NSManaged
  public var isFavorite: Bool
  @NSManaged
  public var kind: Int16
  @NSManaged
  public var rating: Int16
}

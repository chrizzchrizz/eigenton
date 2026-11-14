//
//  AppIconOption.swift
//  Amperfy
//
//  Created by David Klopp on 09.11.26.
//  Copyright (c) 2026 Maximilian Bauer. All rights reserved.
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

/// An app icon that can be chosen in Settings > Display. The alternate icons are Icon Composer
/// files in `AmperfyKit/Assets` and are listed in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`;
/// their previews are generated with `BuildTools/GenerateIconPreviews.sh`.
struct AppIconOption: Identifiable {
  let title: String
  /// nil: the primary app icon
  let iconName: String?
  let previewName: String

  var id: String { iconName ?? "Default" }

  static let all: [AppIconOption] = [
    AppIconOption(
      title: "Default",
      iconName: nil,
      previewName: "AmperfyAppIconPreview"
    ),
  ]
}

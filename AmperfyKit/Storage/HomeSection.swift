//
//  HomeSection.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 26.11.25.
//  Copyright (c) 2025 Maximilian Bauer. All rights reserved.
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

public enum HomeSection: Int, Sendable, CaseIterable, Codable {
  // add new section always at the end to keep the Int consitent
  case lastTimePlayedPlaylists
  case recentlyPlayedAlbums
  case newestAlbums
  case randomAlbums
  case newestPodcastEpisodes
  case podcasts
  case radios
  case randomArtists
  case randomGenres
  case randomSongs
  case latestReleasedAlbums
  // removed sections, only kept so that stored raw values still decode (see `isRemoved`)
  case decadeAlbums
  case genreAlbums
  case compilations
  case favoriteAlbums
  case favoriteArtists
  case decade1950
  case decade1960
  case decade1970
  case decade1980
  case decade1990
  case decade2000
  case decade2010
  case decade2020
  case genreAlternative
  case genreIndie
  case genreHipHop
  case genreElectronic
  case genreDance
  case genreFunk
  case genreCountry
  case genreFolk
  case genrePop
  case genreRock
  case moreLikeAlbums

  static let defaultValue: [HomeSection] = [
    .randomAlbums,
    .compilations,
    .latestReleasedAlbums,
    .recentlyPlayedAlbums,
    .lastTimePlayedPlaylists,
    .newestAlbums,
  ]

  /// Order of the sections in the home editor (`allCases` order is bound to the raw values).
  public static let displayOrder: [HomeSection] = [
    .lastTimePlayedPlaylists,
    .recentlyPlayedAlbums,
    .moreLikeAlbums,
    .newestAlbums,
    .favoriteAlbums,
    .favoriteArtists,
    .randomAlbums,
    .newestPodcastEpisodes,
    .podcasts,
    .radios,
    .randomArtists,
    .randomGenres,
    .randomSongs,
    .latestReleasedAlbums,
    .compilations,
  ] + fixedDecadeSections + fixedGenreSections

  /// Sections for one specific decade, ordered by decade.
  public static let fixedDecadeSections: [HomeSection] = [
    .decade1950, .decade1960, .decade1970, .decade1980,
    .decade1990, .decade2000, .decade2010, .decade2020,
  ]

  /// Sections for one specific genre group, ordered like `GenreGroups.all`.
  public static let fixedGenreSections: [HomeSection] = [
    .genreAlternative, .genreIndie, .genreHipHop, .genreElectronic, .genreDance,
    .genreFunk, .genreCountry, .genreFolk, .genrePop, .genreRock,
  ]

  /// Start year of the decade for the sections of one specific decade.
  public var fixedDecade: Int? {
    switch self {
    case .decade1950: return 1950
    case .decade1960: return 1960
    case .decade1970: return 1970
    case .decade1980: return 1980
    case .decade1990: return 1990
    case .decade2000: return 2000
    case .decade2010: return 2010
    case .decade2020: return 2020
    default: return nil
    }
  }

  /// Name of the genre group for the sections of one specific genre group.
  public var fixedGenreGroup: GenreGroup? {
    let name: String
    switch self {
    case .genreAlternative: name = "Alternative"
    case .genreIndie: name = "Indie"
    case .genreHipHop: name = "Hip Hop"
    case .genreElectronic: name = "Electronic"
    case .genreDance: name = "Dance"
    case .genreFunk: name = "Funk"
    case .genreCountry: name = "Country"
    case .genreFolk: name = "Folk"
    case .genrePop: name = "Pop"
    case .genreRock: name = "Rock"
    default: return nil
    }
    return GenreGroups.all.first(where: { $0.name == name })
  }

  /// Sections that show albums of one specific decade or genre group (hidden while empty).
  public var isFixedDecadeOrGenre: Bool {
    fixedDecade != nil || fixedGenreGroup != nil
  }

  /// Sections that are hidden on Home and in CarPlay as long as they have no content.
  public var isHiddenWhenEmpty: Bool {
    isFixedDecadeOrGenre || self == .moreLikeAlbums
  }

  /// Title of the section header on the home screen.
  public var headerTitle: String {
    if let fixedDecade { return HomeSection.decadeHeaderTitle(for: fixedDecade) }
    if let fixedGenreGroup { return fixedGenreGroup.name }
    return title
  }

  public static func decadeHeaderTitle(for decade: Int) -> String {
    let label = decade < 2000 ? "\(decade % 100)s" : "\(decade)s"
    return "Albums from the \(label)"
  }

  public var title: String {
    switch self {
    case .recentlyPlayedAlbums: return "Recently Played"
    case .newestAlbums: return "Recently Added"
    case .randomAlbums: return "Random Albums"
    case .lastTimePlayedPlaylists: return "Recently Played Playlists"
    case .newestPodcastEpisodes: return "Newest Podcast Episodes"
    case .podcasts: return "Podcasts"
    case .radios: return "Radios"
    case .randomArtists: return "Random Artists"
    case .randomGenres: return "Random Genres"
    case .randomSongs: return "Random Songs"
    case .latestReleasedAlbums: return "Latest Releases"
    case .decadeAlbums, .genreAlbums: return ""
    case .compilations: return "Compilations"
    case .favoriteAlbums: return "Favorite Albums"
    case .favoriteArtists: return "Favorite Artists"
    case .moreLikeAlbums: return "More Like a Recently Played Album"
    default:
      if let fixedDecade { return "Decade: \(fixedDecade)s" }
      if let fixedGenreGroup { return "Genre: \(fixedGenreGroup.name)" }
      return ""
    }
  }

  /// Sections that no longer exist; filtered out of the stored settings.
  public var isRemoved: Bool {
    self == .decadeAlbums || self == .genreAlbums
  }

  public static func create(fromTitle: String) -> HomeSection? {
    allCases.first(where: { !$0.isRemoved && $0.title == fromTitle })
  }

  public var isRandomSection: Bool {
    switch self {
    case .recentlyPlayedAlbums: return false
    case .newestAlbums: return false
    case .randomAlbums: return true
    case .lastTimePlayedPlaylists: return false
    case .newestPodcastEpisodes: return false
    case .podcasts: return false
    case .radios: return false
    case .randomArtists: return true
    case .randomGenres: return true
    case .randomSongs: return true
    case .latestReleasedAlbums: return false
    case .decadeAlbums, .genreAlbums: return false
    case .compilations: return true
    case .favoriteAlbums: return true
    case .favoriteArtists: return true
    default: return true
    }
  }
}

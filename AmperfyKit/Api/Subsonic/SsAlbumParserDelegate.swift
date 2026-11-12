//
//  SsAlbumParserDelegate.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 05.04.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
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
import os.log
import UIKit

class SsAlbumParserDelegate: SsXmlLibWithArtworkParser {
  var guessedArtist: Artist?
  var guessedGenre: Genre?
  var parsedAlbums = [Album]()
  private var albumBuffer: Album?
  private var isReleaseDateParsed = false
  private var songDepth = 0

  override func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String]
  ) {
    super.parser(
      parser,
      didStartElement: elementName,
      namespaceURI: namespaceURI,
      qualifiedName: qName,
      attributes: attributeDict
    )

    if elementName == "song" {
      songDepth += 1
    }
    // the release date of the album itself, not of its songs
    if elementName == "releaseDate", songDepth == 0, let albumBuffer, !isReleaseDateParsed {
      if let releaseDate = Self.parseReleaseDate(attributes: attributeDict) {
        albumBuffer.releaseSortDate = releaseDate
        isReleaseDateParsed = true
      }
    }

    if elementName == "album" {
      guard let albumId = attributeDict["id"] else { return }

      if let prefetchedAlbum = prefetch.prefetchedAlbumDict[albumId] {
        albumBuffer = prefetchedAlbum
        guessedArtist = prefetchedAlbum.artist
        guessedGenre = prefetchedAlbum.genre
      } else {
        albumBuffer = library.createAlbum(account: account)
        prefetch.prefetchedAlbumDict[albumId] = albumBuffer
        albumBuffer?.id = albumId
        guessedArtist = nil
        guessedGenre = nil
      }
      albumBuffer?.remoteStatus = .available

      if let attributeAlbumtName = attributeDict["name"] {
        albumBuffer?.name = attributeAlbumtName
      }
      if let attributeCoverArt = attributeDict["coverArt"] {
        albumBuffer?.artwork = parseArtwork(id: attributeCoverArt)
      }
      albumBuffer?.rating = Int(attributeDict["userRating"] ?? "0") ?? 0
      albumBuffer?.isFavorite = attributeDict["starred"] != nil
      if let attributeYear = attributeDict["year"], let year = Int(attributeYear) {
        albumBuffer?.year = year
      }
      // fallback for the release date, which is delivered by a child element (OpenSubsonic)
      isReleaseDateParsed = false
      let createdDate = attributeDict["created"].flatMap { Self.parseDate($0) }
      albumBuffer?.releaseSortDate = createdDate
      // keep a known added date if a response leaves out created
      if let createdDate {
        albumBuffer?.addedDate = createdDate
      }
      // OpenSubsonic: isCompilation attribute (absent on plain Subsonic servers)
      if let attributeIsCompilation = attributeDict["isCompilation"] {
        albumBuffer?.isCompilation = attributeIsCompilation.lowercased() == "true"
      }
      if let attributeSongCount = attributeDict["songCount"],
         let songCount = Int(attributeSongCount) {
        albumBuffer?.remoteSongCount = songCount
      }
      if let attributeDuration = attributeDict["duration"], let duration = Int(attributeDuration) {
        albumBuffer?.remoteDuration = duration
      }

      if let artistId = attributeDict["artistId"] {
        if let guessedArtist, guessedArtist.id == artistId {
          albumBuffer?.artist = guessedArtist
        } else if let prefetchedArtist = prefetch.prefetchedArtistDict[artistId] {
          albumBuffer?.artist = prefetchedArtist
        } else if let artistName = attributeDict["artist"] {
          let artist = library.createArtist(account: account)
          prefetch.prefetchedArtistDict[artistId] = artist
          artist.id = artistId
          artist.name = artistName
          os_log(
            "Artist <%s> with id %s has been created",
            log: log,
            type: .error,
            artistName,
            artistId
          )
          albumBuffer?.artist = artist
        }
      }

      if let genreName = attributeDict["genre"] {
        if let guessedGenre, guessedGenre.name == genreName {
          albumBuffer?.genre = guessedGenre
        } else if let prefetchedGenre = prefetch.prefetchedGenreDict[genreName] {
          albumBuffer?.genre = prefetchedGenre
        } else {
          let genre = library.createGenre(account: account)
          prefetch.prefetchedGenreDict[genreName] = genre
          genre.name = genreName
          os_log("Genre <%s> has been created", log: log, type: .error, genreName)
          albumBuffer?.genre = genre
        }
      }
    }
  }

  override func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch elementName {
    case "song":
      songDepth = max(0, songDepth - 1)
    case "album":
      parsedCount += 1
      if let album = albumBuffer {
        parsedAlbums.append(album)
      }
      albumBuffer = nil
    default:
      break
    }

    super.parser(
      parser,
      didEndElement: elementName,
      namespaceURI: namespaceURI,
      qualifiedName: qName
    )
  }

  /// Date of "releaseDate" element; a missing month or day is set to the first one, nil without a year.
  static func parseReleaseDate(attributes: [String: String]) -> Date? {
    guard let year = attributes["year"].flatMap({ Int($0) })
    else { return nil }
    let month = attributes["month"].flatMap { Int($0) } ?? 1
    let day = attributes["day"].flatMap { Int($0) } ?? 1
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar.date(from: DateComponents(year: year, month: month, day: day))
  }

  /// ISO 8601 date with or without fractional seconds
  static func parseDate(_ text: String) -> Date? {
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = dateFormatter.date(from: text) {
      return date
    }
    dateFormatter.formatOptions = [.withInternetDateTime]
    if let date = dateFormatter.date(from: text) {
      return date
    }
    dateFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
    return dateFormatter.date(from: text)
  }
}

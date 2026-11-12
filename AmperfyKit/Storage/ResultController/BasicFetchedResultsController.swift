//
//  BasicFetchedResultsController.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 19.04.21.
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
import Foundation

extension NSFetchedResultsController {
  @objc
  func fetch() {
    do {
      try performFetch()
    } catch let error as NSError {
      print("Unable to perform fetch: \(error.localizedDescription)")
    }
  }

  @objc
  func clearResults() {
    let oldPredicate = fetchRequest.predicate
    fetchRequest.predicate = NSPredicate(value: false)
    fetch()
    fetchRequest.predicate = oldPredicate
  }
}

// MARK: - SectionIndexType

public enum SectionIndexType: Int, Sendable {
  case alphabet = 0
  case rating = 1
  case newestOrRecent = 2
  case durationSong = 3
  case durationAlbum = 4
  case durationArtist = 5
  case none = 6
  case year = 7

  public static let defaultValue: SectionIndexType = .alphabet
  public static let noRatingIndexSymbol = "#"
  public static let noDurationSymbol = "#"
  public static let noYearSymbol = "#"
}

// MARK: - AddedDateSectionBoundaries

/// Groups by how long ago something was added: "This Month", "Last 3 Months", "Last 6 Months",
/// "This Year" and then the year ("2025", "2024", …). The groups follow each other in descending
/// date order, so a list sorted by date descending gets contiguous sections. The boundaries are
/// computed once, so grouping many items only compares dates.
public struct AddedDateSectionBoundaries: Sendable {
  public let referenceDate: Date
  let calendar: Calendar
  private let monthStart: Date
  private let threeMonthsAgo: Date
  private let sixMonthsAgo: Date
  private let yearStart: Date

  public init(now: Date = Date(), calendar: Calendar = .current) {
    self.referenceDate = now
    self.calendar = calendar
    self.monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
    self.threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now
    self.sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
    self.yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? now
  }

  /// Empty if there is no date
  public func title(for date: Date?) -> String {
    guard let date else { return "" }
    if date >= monthStart { return "This Month" }
    if date >= threeMonthsAgo { return "Last 3 Months" }
    if date >= sixMonthsAgo { return "Last 6 Months" }
    if date >= yearStart { return "This Year" }
    return "\(calendar.component(.year, from: date))"
  }

  /// The date range of each group, newest first, back to the year of `oldestDate`: all dates in
  /// `start ..< end` (no end if nil) get `title`, the same as `title(for:)` returns
  public func ranges(
    oldestDate: Date
  )
    -> [(title: String, start: Date, end: Date?)] {
    var ranges: [(title: String, start: Date, end: Date?)] = [
      ("This Month", monthStart, nil),
      ("Last 3 Months", threeMonthsAgo, monthStart),
      ("Last 6 Months", sixMonthsAgo, threeMonthsAgo),
    ]
    if yearStart < sixMonthsAgo {
      ranges.append(("This Year", yearStart, sixMonthsAgo))
    }
    // older dates are grouped by their year
    let yearsEnd = min(yearStart, sixMonthsAgo)
    var yearInterval = calendar.dateInterval(of: .year, for: yearsEnd.addingTimeInterval(-1))
    while let interval = yearInterval, interval.end > oldestDate {
      ranges.append((
        "\(calendar.component(.year, from: interval.start))",
        interval.start,
        min(interval.end, yearsEnd)
      ))
      yearInterval = calendar.dateInterval(of: .year, for: interval.start.addingTimeInterval(-1))
    }
    return ranges
  }
}

// MARK: - IndexHeaderNameGenerator

public class IndexHeaderNameGenerator {
  public static func sortByRating(forSectionName sectionName: String) -> String {
    guard !sectionName.isEmpty else { return SectionIndexType.noRatingIndexSymbol }
    let initial = String(sectionName.prefix(1))
    switch initial {
    case "5": return "5"
    case "4": return "4"
    case "3": return "3"
    case "2": return "2"
    case "1": return "1"
    default: return SectionIndexType.noRatingIndexSymbol
    }
  }

  public static func sortByDurationSong(forSectionName sectionName: String) -> String {
    if let durationInSec = Int(sectionName) {
      if durationInSec == 0 {
        return SectionIndexType.noDurationSymbol
      } else if durationInSec >= 3 * 60 * 60 {
        return Int(180 * 60).asColonDurationString
      } else if durationInSec >= 1 * 60 * 60 {
        return durationInSec.roundDownToFractionOf(30 * 60).asColonDurationString
      } else if durationInSec >= 30 * 60 {
        return durationInSec.roundDownToFractionOf(10 * 60).asColonDurationString
      } else if durationInSec >= 10 * 60 {
        return durationInSec.roundDownToFractionOf(5 * 60).asColonDurationString
      } else if durationInSec >= 5 * 60 {
        return durationInSec.roundDownToFractionOf(1 * 60).asColonDurationString
      } else {
        return durationInSec.roundDownToFractionOf(30).asColonDurationString
      }
    } else {
      return SectionIndexType.noDurationSymbol
    }
  }

  public static func sortByDurationAlbum(forSectionName sectionName: String) -> String {
    if let durationInSec = Int(sectionName) {
      if durationInSec == 0 {
        return SectionIndexType.noDurationSymbol
      } else if durationInSec >= 5 * 60 * 60 {
        return Int(5 * 60 * 60).asColonDurationString
      } else if durationInSec >= 100 * 60 {
        if durationInSec < 2 * 60 * 60 {
          return Int(100 * 60).asColonDurationString
        } else {
          return durationInSec.roundDownToFractionOf(60 * 60).asColonDurationString
        }
      } else if durationInSec >= 70 * 60 {
        return durationInSec.roundDownToFractionOf(10 * 60).asColonDurationString
      } else if durationInSec >= 30 * 60 {
        return durationInSec.roundDownToFractionOf(5 * 60).asColonDurationString
      } else if durationInSec >= 10 * 60 {
        return durationInSec.roundDownToFractionOf(10 * 60).asColonDurationString
      } else if durationInSec >= 1 * 60 {
        return durationInSec.roundDownToFractionOf(2 * 60).asColonDurationString
      } else {
        return Int(0).asColonDurationString
      }
    } else {
      return SectionIndexType.noDurationSymbol
    }
  }

  public static func sortByDurationArtist(forSectionName sectionName: String) -> String {
    if let durationInSec = Int(sectionName) {
      if durationInSec == 0 {
        return SectionIndexType.noDurationSymbol
      } else if durationInSec >= 20 * 60 * 60 {
        return Int(20 * 60 * 60).asColonDurationString
      } else if durationInSec >= 5 * 60 * 60 {
        return durationInSec.roundDownToFractionOf(5 * 60 * 60).asColonDurationString
      } else if durationInSec >= 60 * 60 {
        return durationInSec.roundDownToFractionOf(30 * 60).asColonDurationString
      } else if durationInSec >= 20 * 60 {
        return durationInSec.roundDownToFractionOf(10 * 60).asColonDurationString
      } else if durationInSec >= 5 * 60 {
        return durationInSec.roundDownToFractionOf(Int(2 * 60)).asColonDurationString
      } else {
        return Int(0).asColonDurationString
      }
    } else {
      return SectionIndexType.noDurationSymbol
    }
  }

  /// Boundaries all added date sections (`AlbumMO.addedDateSection`) are computed with, fixed
  /// for the lifetime of the app process. Every album therefore gets its group with the same
  /// boundaries, so the sections of the recently added list stay contiguous and unique.
  /// Moving them while lists are alive would sort changed albums into groups that don't match
  /// their neighbours. Trade-off: after midnight the titles are a day behind until the next start.
  public static let currentAddedDateBoundaries = AddedDateSectionBoundaries()

  public static func sortByYear(forSectionName sectionName: String) -> String {
    if let year = Int(sectionName), year > 0 {
      return "\(year)"
    } else {
      return SectionIndexType.noYearSymbol
    }
  }
}

// MARK: - CustomSectionIndexFetchedResultsController

public class CustomSectionIndexFetchedResultsController<
  ResultType: NSFetchRequestResult
>: NSFetchedResultsController<NSFetchRequestResult> {
  public var sectionIndexType: SectionIndexType

  public init(
    fetchRequest: NSFetchRequest<ResultType>,
    coreDataCompanion: CoreDataCompanion,
    sectionNameKeyPath: String?,
    cacheName name: String?,
    sectionIndexType: SectionIndexType = .defaultValue
  ) {
    self.sectionIndexType = sectionIndexType
    super.init(
      fetchRequest: fetchRequest as! NSFetchRequest<NSFetchRequestResult>,
      managedObjectContext: coreDataCompanion.context,
      sectionNameKeyPath: sectionNameKeyPath,
      cacheName: name
    )
  }

  override public func sectionIndexTitle(forSectionName sectionName: String) -> String? {
    switch sectionIndexType {
    case .alphabet:
      return sectionName
    case .rating:
      return IndexHeaderNameGenerator.sortByRating(forSectionName: sectionName)
    case .newestOrRecent:
      return nil
    case .durationSong:
      return IndexHeaderNameGenerator.sortByDurationSong(forSectionName: sectionName)
    case .durationAlbum:
      return IndexHeaderNameGenerator.sortByDurationAlbum(forSectionName: sectionName)
    case .durationArtist:
      return IndexHeaderNameGenerator.sortByDurationArtist(forSectionName: sectionName)
    case .none:
      return nil
    case .year:
      return IndexHeaderNameGenerator.sortByYear(forSectionName: sectionName)
    }
  }
}

// MARK: - BasicFetchedResultsController

public class BasicFetchedResultsController<ResultType>: NSObject
  where ResultType: NSFetchRequestResult {
  public var fetchResultsController: CustomSectionIndexFetchedResultsController<ResultType>
  let coreDataCompanion: CoreDataCompanion
  let defaultPredicate: NSPredicate?
  public var delegate: NSFetchedResultsControllerDelegate? {
    set { fetchResultsController.delegate = newValue }
    get { fetchResultsController.delegate }
  }

  public var isSearchActive = false

  public init(
    coreDataCompanion: CoreDataCompanion,
    fetchRequest: NSFetchRequest<ResultType>,
    isGroupedInAlphabeticSections: Bool
  ) {
    self.coreDataCompanion = coreDataCompanion
    self.defaultPredicate = fetchRequest.predicate?.copy() as? NSPredicate
    let sectionNameKeyPath: String? = isGroupedInAlphabeticSections ? fetchRequest
      .sortDescriptors![0].key : nil
    self.fetchResultsController = CustomSectionIndexFetchedResultsController<ResultType>(
      fetchRequest: fetchRequest.copy() as! NSFetchRequest<ResultType>,
      coreDataCompanion: coreDataCompanion,
      sectionNameKeyPath: sectionNameKeyPath,
      cacheName: nil
    )
  }

  public func search(predicate: NSPredicate?) {
    isSearchActive = true
    fetchResultsController.fetchRequest.predicate = predicate
    fetchResultsController.fetch()
  }

  public func fetch() {
    fetchResultsController.fetch()
  }

  public func clearResults() {
    fetchResultsController.clearResults()
  }

  public func showAllResults() {
    isSearchActive = false
    fetchResultsController.fetchRequest.predicate = defaultPredicate
    fetch()
  }

  public var fetchedObjects: [ResultType]? {
    fetchResultsController.fetchedObjects as? [ResultType]
  }

  public var sections: [NSFetchedResultsSectionInfo]? {
    fetchResultsController.sections
  }

  public var numberOfSections: Int {
    fetchResultsController.sections?.count ?? 0
  }

  public func titleForHeader(inSection section: Int) -> String? {
    fetchResultsController.sectionIndexTitles.object(at: section)
  }

  public func numberOfRows(inSection section: Int) -> Int {
    fetchResultsController.sections?[section].numberOfObjects ?? 0
  }

  public var sectionIndexTitles: [String]? {
    fetchResultsController.sectionIndexTitles
  }

  public func section(forSectionIndexTitle title: String, at index: Int) -> Int {
    fetchResultsController.section(forSectionIndexTitle: title, at: index)
  }
}

extension BasicFetchedResultsController where ResultType == SearchHistoryItemMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> SearchHistoryItem {
    let searchHistoryItemMO = fetchResultsController.object(at: indexPath) as! ResultType
    return SearchHistoryItem(managedObject: searchHistoryItemMO)
  }
}

extension BasicFetchedResultsController where ResultType == GenreMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> Genre {
    let genreMO = fetchResultsController.object(at: indexPath) as! ResultType
    return Genre(managedObject: genreMO)
  }
}

extension BasicFetchedResultsController where ResultType == ArtistMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> Artist {
    let artistMO = fetchResultsController.object(at: indexPath) as! ResultType
    return Artist(managedObject: artistMO)
  }

  public func getWrappedEntity(at index: Int) -> Artist? {
    guard let fetchedObjects = fetchResultsController.fetchedObjects,
          index < fetchedObjects.count
    else { return nil }
    let managedObject = fetchedObjects[index] as! ResultType
    return Artist(managedObject: managedObject)
  }
}

extension BasicFetchedResultsController where ResultType == AlbumMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> Album {
    let albumMO = fetchResultsController.object(at: indexPath) as! ResultType
    return Album(managedObject: albumMO)
  }

  public func getWrappedEntity(at index: Int) -> Album? {
    guard let fetchedObjects = fetchResultsController.fetchedObjects,
          index < fetchedObjects.count
    else { return nil }
    let managedObject = fetchedObjects[index] as! ResultType
    return Album(managedObject: managedObject)
  }
}

extension BasicFetchedResultsController where ResultType == SongMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> Song {
    let songMO = fetchResultsController.object(at: indexPath) as! ResultType
    return Song(managedObject: songMO)
  }

  public func getWrappedEntity(at index: Int) -> Song? {
    guard let fetchedObjects = fetchResultsController.fetchedObjects,
          index < fetchedObjects.count
    else { return nil }
    let managedObject = fetchedObjects[index] as! ResultType
    return Song(managedObject: managedObject)
  }

  public func getContextSongs(onlyCachedSongs: Bool) -> [AbstractPlayable]? {
    guard let basicPredicate = defaultPredicate else { return nil }
    let cachedFetchRequest = fetchResultsController.fetchRequest.copy() as! NSFetchRequest<SongMO>
    cachedFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      basicPredicate,
      coreDataCompanion.library.getFetchPredicate(onlyCachedSongs: onlyCachedSongs),
    ])
    let songsMO = try? coreDataCompanion.context.fetch(cachedFetchRequest)
    let songs = songsMO?.compactMap { Song(managedObject: $0) }
    return songs
  }
}

extension BasicFetchedResultsController where ResultType == RadioMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> Radio {
    let radioMO = fetchResultsController.object(at: indexPath) as! ResultType
    return Radio(managedObject: radioMO)
  }

  public func getContextRadios() -> [AbstractPlayable]? {
    guard let basicPredicate = defaultPredicate else { return nil }
    let cachedFetchRequest = fetchResultsController.fetchRequest.copy() as! NSFetchRequest<RadioMO>
    cachedFetchRequest.predicate = basicPredicate
    let radiosMO = try? coreDataCompanion.context.fetch(cachedFetchRequest)
    let radios = radiosMO?.compactMap { Radio(managedObject: $0) }
    return radios
  }
}

extension BasicFetchedResultsController where ResultType == PlaylistMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> Playlist {
    let playlistMO = fetchResultsController.object(at: indexPath) as! ResultType
    return Playlist(library: coreDataCompanion.library, managedObject: playlistMO)
  }
}

extension BasicFetchedResultsController where ResultType == PlaylistItemMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> PlaylistItem {
    let itemMO = fetchResultsController.object(at: indexPath) as! ResultType
    return PlaylistItem(library: coreDataCompanion.library, managedObject: itemMO)
  }

  public func getContextSongs(onlyCachedSongs: Bool) -> [AbstractPlayable]? {
    guard let basicPredicate = defaultPredicate else { return nil }
    let cachedFetchRequest = fetchResultsController.fetchRequest
      .copy() as! NSFetchRequest<PlaylistItemMO>
    cachedFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      basicPredicate,
      coreDataCompanion.library.getFetchPredicate(onlyCachedPlaylistItems: onlyCachedSongs),
    ])
    let playlistItemsMO = try? coreDataCompanion.context.fetch(cachedFetchRequest)
    let playables = playlistItemsMO?.compactMap { $0.playable }
      .compactMap { AbstractPlayable(managedObject: $0) }
    return playables
  }
}

extension BasicFetchedResultsController where ResultType == LogEntryMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> LogEntry {
    let itemMO = fetchResultsController.object(at: indexPath) as! ResultType
    return LogEntry(managedObject: itemMO)
  }
}

extension BasicFetchedResultsController where ResultType == MusicFolderMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> MusicFolder {
    let musicFolderMO = fetchResultsController.object(at: indexPath) as! ResultType
    return MusicFolder(managedObject: musicFolderMO)
  }
}

extension BasicFetchedResultsController where ResultType == DirectoryMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> Directory {
    let directoryMO = fetchResultsController.object(at: indexPath) as! ResultType
    return Directory(managedObject: directoryMO)
  }
}

extension BasicFetchedResultsController where ResultType == PodcastMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> Podcast {
    let podcastMO = fetchResultsController.object(at: indexPath) as! ResultType
    return Podcast(managedObject: podcastMO)
  }
}

extension BasicFetchedResultsController where ResultType == PodcastEpisodeMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> PodcastEpisode {
    let podcastEpisodeMO = fetchResultsController.object(at: indexPath) as! ResultType
    return PodcastEpisode(managedObject: podcastEpisodeMO)
  }

  public func getWrappedEntity(at index: Int) -> PodcastEpisode? {
    guard let fetchedObjects = fetchResultsController.fetchedObjects,
          index < fetchedObjects.count
    else { return nil }
    let managedObject = fetchedObjects[index] as! ResultType
    return PodcastEpisode(managedObject: managedObject)
  }

  public func getContextPodcastEpisodes(onlyCachedSongs: Bool) -> [AbstractPlayable]? {
    guard let basicPredicate = defaultPredicate else { return nil }
    let cachedFetchRequest = fetchResultsController.fetchRequest
      .copy() as! NSFetchRequest<PodcastEpisodeMO>
    cachedFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      basicPredicate,
      coreDataCompanion.library.getFetchPredicate(onlyCachedPlaylistItems: onlyCachedSongs),
    ])
    let podcastEpisodesMO = try? coreDataCompanion.context.fetch(cachedFetchRequest)
    let playables = podcastEpisodesMO?.compactMap { PodcastEpisode(managedObject: $0) }
    return playables
  }
}

extension BasicFetchedResultsController where ResultType == DownloadMO {
  public func getWrappedEntity(at indexPath: IndexPath) -> Download {
    let downloadMO = fetchResultsController.object(at: indexPath) as! ResultType
    return Download(managedObject: downloadMO)
  }
}

// MARK: - CachedFetchedResultsController

public class CachedFetchedResultsController<ResultType>: BasicFetchedResultsController<ResultType>
  where ResultType: NSFetchRequestResult {
  let account: Account
  var keepAllResultsUpdated = true
  private var didFetchAll = false
  private var didFetchSearch = false
  private var lastSearchPredicateFormat: String?
  private let allFetchResulsController: CustomSectionIndexFetchedResultsController<ResultType>
  private let searchFetchResulsController: CustomSectionIndexFetchedResultsController<ResultType>
  private var sectionIndexType: SectionIndexType

  /// weak like the delegate of NSFetchedResultsController, the delegate usually owns this controller
  private weak var delegateInternal: NSFetchedResultsControllerDelegate?
  override public var delegate: NSFetchedResultsControllerDelegate? {
    set {
      delegateInternal = newValue
      updateFetchResultsControllerDelegate()
    }
    get { delegateInternal }
  }

  private var isSearchActiveInternal = false
  override public var isSearchActive: Bool {
    set {
      isSearchActiveInternal = newValue
      updateFetchResultsControllerDelegate()
    }
    get { isSearchActiveInternal }
  }

  public init(
    coreDataCompanion: CoreDataCompanion,
    fetchRequest: NSFetchRequest<ResultType>,
    account: Account,
    sectionIndexType: SectionIndexType = .defaultValue,
    isGroupedInAlphabeticSections: Bool,
    customSectionNameKeyPath: String? = nil
  ) {
    self.account = account
    self.sectionIndexType = sectionIndexType
    let sectionNameKeyPath: String? = isGroupedInAlphabeticSections ?
      (customSectionNameKeyPath ?? fetchRequest.sortDescriptors![0].key) : nil
    self.allFetchResulsController = CustomSectionIndexFetchedResultsController<ResultType>(
      fetchRequest: fetchRequest.copy() as! NSFetchRequest<ResultType>,
      coreDataCompanion: coreDataCompanion,
      sectionNameKeyPath: sectionNameKeyPath,
      // groups like the recently added sections are moved at app start (see
      // `LibraryStorage.updateAddedDateSections`) while no controller observes; a section
      // cache would keep the old sections
      cacheName: customSectionNameKeyPath == nil ?
        "\(Self.typeName)-\(account.serverHash)-\(account.userHash)" : nil
    )
    allFetchResulsController.sectionIndexType = sectionIndexType
    self.searchFetchResulsController = CustomSectionIndexFetchedResultsController<ResultType>(
      fetchRequest: fetchRequest.copy() as! NSFetchRequest<ResultType>,
      coreDataCompanion: coreDataCompanion,
      sectionNameKeyPath: sectionNameKeyPath,
      cacheName: nil
    )
    searchFetchResulsController.sectionIndexType = sectionIndexType
    super.init(
      coreDataCompanion: coreDataCompanion,
      fetchRequest: fetchRequest,
      isGroupedInAlphabeticSections: isGroupedInAlphabeticSections
    )
    fetchResultsController = allFetchResulsController
  }

  override public func search(predicate: NSPredicate?) {
    isSearchActive = true
    let predicateFormat = predicate?.predicateFormat
    if didFetchSearch,
       lastSearchPredicateFormat == predicateFormat,
       searchFetchResulsController.fetchedObjects != nil {
      return
    }
    didFetchSearch = true
    lastSearchPredicateFormat = predicateFormat
    searchFetchResulsController.fetchRequest.predicate = predicate
    searchFetchResulsController.fetch()
  }

  public static func deleteCache() {
    NSFetchedResultsController<ResultType>.deleteCache(withName: Self.typeName)
  }

  override public func fetch() {
    let wasSearchActive = isSearchActive
    isSearchActive = false
    didFetchSearch = false
    lastSearchPredicateFormat = nil
    if !wasSearchActive,
       didFetchAll,
       keepAllResultsUpdated,
       allFetchResulsController.fetchedObjects != nil {
      return
    }
    didFetchAll = true
    allFetchResulsController.fetch()
  }

  override public func showAllResults() {
    fetch()
  }

  override public func clearResults() {
    isSearchActive = true
    didFetchSearch = false
    lastSearchPredicateFormat = nil
    searchFetchResulsController.clearResults()
  }

  private func updateFetchResultsControllerDelegate() {
    fetchResultsController.delegate = nil
    if isSearchActiveInternal {
      fetchResultsController = searchFetchResulsController
      fetchResultsController.delegate = delegateInternal
    } else {
      fetchResultsController = allFetchResulsController
      if keepAllResultsUpdated {
        fetchResultsController.delegate = delegateInternal
      }
    }
  }

  public func hideResults() {
    isSearchActive = true
    didFetchSearch = false
    lastSearchPredicateFormat = nil
    searchFetchResulsController.fetchRequest.predicate = NSPredicate(format: "id == nil")
    searchFetchResulsController.fetch()
  }

  public func isOneOfThis(_ controller: NSFetchedResultsController<NSFetchRequestResult>) -> Bool {
    (controller == allFetchResulsController) || (controller == searchFetchResulsController)
  }
}

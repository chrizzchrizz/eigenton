//
//  CarPlayHomeTabExtension.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 02.01.26.
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

import AmperfyKit
import CarPlay
import CoreData
import Foundation

// The home tab shows one image row per home section, like Apple Music: at most
// homeImageRowMaxElements tiles that wrap into several lines. On iOS 27.2.1 CarPlayTemplateUIHost
// lays out single-line image rows (which scroll horizontally) endlessly as soon as they are
// updated, until the watchdog kills it, which ends CarPlay for the app. Rows that wrap don't.
// The section title opens the whole section as a plain list.
extension CarPlaySceneDelegate {
  static let homeImageRowMaxElements = 8

  func updateHomeSections() {
    guard let sharedHome else { return }
    let requestedData = sharedHome.data
    guard homeShownData != requestedData else { return }
    let previousData = homeShownData
    homeShownData = requestedData
    homeTab.updateSections([CPListSection(items: createHomeImageRows())])
    // a shown section list follows its section (e.g. after a refresh), but only if its own data
    // changed: a rebuild decodes all its images again
    if let homeSectionTemplate, let homeSectionTemplateSection,
       previousData[homeSectionTemplateSection] != requestedData[homeSectionTemplateSection],
       interfaceController?.templates.contains(homeSectionTemplate) == true {
      homeSectionTemplate.updateSections(createHomeSectionListSections(
        section: homeSectionTemplateSection
      ))
    }
  }

  /// Rows are created anew on every data change instead of changing their elements
  private func createHomeImageRows() -> [CPListImageRowItem] {
    guard let sharedHome else { return [] }
    homeImageRowArtworkTargets = [:]
    // like in the app home, decade and genre sections are hidden as long as they have no albums
    // (other sections stay, e.g. to refresh an empty random section)
    return sharedHome.orderedVisibleSections
      .filter { !$0.isFixedDecadeOrGenre || !(sharedHome.data[$0] ?? []).isEmpty }
      .map { section in
        let containables = (sharedHome.data[section] ?? [])
          .prefix(Self.homeImageRowMaxElements)
          .map { $0.playableContainable }
        let elements = containables.map { createHomeImageRowElement(for: $0) }
        let row = CPListImageRowItem(
          text: section.headerTitle,
          elements: elements,
          allowsMultipleLines: true
        )
        // the section title opens the whole section as a list
        row.handler = { [weak self] _, completion in
          guard let self else { completion(); return }
          pushHomeSectionList(section: section, completion: completion)
        }
        row.listImageRowHandler = { [weak self] _, index, completion in
          guard let self, index < containables.count else { completion(); return }
          Task { @MainActor in
            await selectHomeItem(containables[index])
            completion()
          }
        }
        return row
      }
  }

  private func createHomeImageRowElement(for containable: PlayableContainable)
    -> CPListImageRowItemRowElement {
    let collection = containable.getArtworkCollection(theme: getPreference(activeAccountInfo).theme)
    let element = CPListImageRowItemRowElement(
      image: getImage(for: collection),
      title: containable.name,
      subtitle: containable.subtitle
    )
    downloadHomeArtworks(of: collection)
    // row elements have no userInfo: refreshHomeImageRowArtwork finds them by artwork
    for artwork in collection.artworks {
      homeImageRowArtworkTargets[artwork.uniqueID, default: []]
        .append(HomeImageRowArtworkTarget(element: element, containable: containable))
    }
    return element
  }

  /// Sets the image of the home row elements that show the downloaded artwork
  func refreshHomeImageRowArtwork(downloadID: String) {
    guard let targets = homeImageRowArtworkTargets[downloadID] else { return }
    for target in targets {
      target.element.image = getImage(for: target.containable)
    }
  }

  private func downloadHomeArtworks(of collection: ArtworkCollection) {
    for artwork in collection.artworks {
      if let accountInfo = artwork.account?.info {
        appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
      }
    }
  }

  private func pushHomeSectionList(section: HomeSection, completion: @escaping () -> ()) {
    let template = CPListTemplate(
      title: section.headerTitle,
      sections: createHomeSectionListSections(section: section)
    )
    homeSectionTemplate = template
    homeSectionTemplateSection = section
    Task { @MainActor in
      let _ = try? await interfaceController?.pushTemplate(template, animated: true)
      completion()
    }
  }

  private func createHomeSectionListSections(section: HomeSection) -> [CPListSection] {
    guard let sharedHome else { return [] }
    var items = [CPListItem]()
    if section.isRandomSection {
      items.append(createHomeRefreshItem(section: section))
    }
    let homeItems = (sharedHome.data[section] ?? [])
      .prefix(CPListTemplate.maximumItemCount - items.count)
    items.append(contentsOf: homeItems.map { createHomeListItem(for: $0.playableContainable) })
    return [CPListSection(items: items)]
  }

  private func createHomeRefreshItem(section: HomeSection) -> CPListItem {
    let image = UIImage.createArtwork(
      with: UIImage.shuffle,
      iconSizeType: .small,
      theme: getPreference(activeAccountInfo).theme,
      lightDarkMode: traits.userInterfaceStyle.asModeType,
      switchColors: true
    ).carPlayImage(carTraitCollection: traits)
    let item = CPListItem(text: "Refresh", detailText: nil, image: image)
    item.handler = { [weak self] _, completion in
      guard let self, let sharedHome else { completion(); return }
      switch section {
      case .randomAlbums:
        sharedHome.updateRandomAlbums(isOfflineMode: isOfflineMode)
      case .compilations:
        sharedHome.updateCompilations(isOfflineMode: isOfflineMode)
      case .randomArtists:
        sharedHome.updateRandomArtists(isOfflineMode: isOfflineMode)
      case .favoriteAlbums:
        sharedHome.updateFavoriteAlbums(isOfflineMode: isOfflineMode)
      case .favoriteArtists:
        sharedHome.updateFavoriteArtists(isOfflineMode: isOfflineMode)
      case .randomGenres:
        sharedHome.updateRandomGenres()
      case .randomSongs:
        sharedHome.updateRandomSongs(isOfflineMode: isOfflineMode)
      default:
        // decade and genre sections ("Albums from the 90s", "Rock") are random sections too
        if section.isFixedDecadeOrGenre {
          sharedHome.updateFixedDecadeOrGenreAlbums(section, isOfflineMode: isOfflineMode)
        }
      }
      // the new content arrives via updateHomeSections
      completion()
    }
    return item
  }

  private func createHomeListItem(for containable: PlayableContainable) -> CPListItem {
    let collection = containable.getArtworkCollection(theme: getPreference(activeAccountInfo).theme)
    let item = CPListItem(
      text: containable.name,
      detailText: containable.subtitle,
      image: getImage(for: collection),
      accessoryImage: nil,
      accessoryType: containable is Album || containable is Playlist ? .disclosureIndicator : .none
    )
    downloadHomeArtworks(of: collection)
    // lets downloadFinishedSuccessful refresh the image once an artwork is downloaded
    if let playlist = containable as? Playlist {
      item.userInfo = [
        CarPlayListUserInfoKeys.artworkDownloadIDs.rawValue: collection.artworks
          .map { $0.uniqueID },
        CarPlayListUserInfoKeys.containableObjectID.rawValue: playlist.managedObject.objectID,
      ]
    } else if let entity = containable as? AbstractLibraryEntity,
              let ownerType = homeArtworkOwnerType(of: entity) {
      item.userInfo = [
        CarPlayListUserInfoKeys.artworkDownloadID.rawValue: entity.artwork?.uniqueID as Any,
        CarPlayListUserInfoKeys.artworkOwnerObjectID.rawValue: entity.objectID,
        CarPlayListUserInfoKeys.artworkOwnerType.rawValue: ownerType,
      ]
    }
    item.handler = { [weak self] _, completion in
      guard let self else { completion(); return }
      Task { @MainActor in
        await selectHomeItem(containable)
        completion()
      }
    }
    return item
  }

  /// The owner types downloadFinishedSuccessful can refresh
  private func homeArtworkOwnerType(of entity: AbstractLibraryEntity) -> ArtworkType? {
    switch entity {
    case is Song: return .song
    case is Album: return .album
    case is Artist: return .artist
    case is Podcast: return .podcast
    case is PodcastEpisode: return .podcastEpisode
    case is Radio: return .radio
    case is Genre: return .genre
    default: return nil
    }
  }

  private func selectHomeItem(_ containable: PlayableContainable) async {
    if !isOfflineMode {
      do {
        try await containable.fetch(
          storage: appDelegate.storage,
          librarySyncer: appDelegate.getMeta(activeAccountInfo).librarySyncer,
          playableDownloadManager: appDelegate.getMeta(activeAccountInfo)
            .playableDownloadManager
        )
      } catch {
        // ignore online fetch in CarPlay
      }
    }
    if let album = containable as? Album {
      let albumTemplate = createAlbumSongListTemplate(for: album, onlyCached: isOfflineMode)
      let _ = try? await interfaceController?.pushTemplate(albumTemplate, animated: true)
    } else if let playlist = containable as? Playlist {
      let playlistDetailTemplate = createPlaylistDetailTemplate(for: playlist)
      let _ = try? await interfaceController?.pushTemplate(playlistDetailTemplate, animated: true)
    } else {
      appDelegate.player.play(context: PlayContext(containable: containable))
      await withCheckedContinuation { continuation in
        displayNowPlaying {
          continuation.resume()
        }
      }
    }
  }
}

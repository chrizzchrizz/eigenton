//
//  CarPlayCommonListExtension.swift
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

extension CarPlaySceneDelegate {
  func createArtistItems(
    from fetchedController: ArtistFetchedResultsController?,
    onlyCached: Bool
  )
    -> [CPListSection] {
    guard let fetchedController else { return [] }
    return createAlphabeticSections(
      fetchSections: { fetchedController.sections },
      isAlphabetic: fetchedController.sortType.asSectionIndexType == .alphabet
    ) { [weak self] (artistMO: ArtistMO) in
      self?.createDetailTemplate(for: Artist(managedObject: artistMO), onlyCached: onlyCached)
    }
  }

  func createAlbumItems(
    from fetchedController: AlbumFetchedResultsController?,
    onlyCached: Bool
  )
    -> [CPListSection] {
    guard let fetchedController else { return [] }
    return createAlphabeticSections(
      fetchSections: { fetchedController.sections },
      isAlphabetic: fetchedController.sortType.asSectionIndexType == .alphabet
    ) { [weak self] (albumMO: AlbumMO) in
      self?.createDetailTemplate(for: Album(managedObject: albumMO), onlyCached: onlyCached)
    }
  }

  /// Alphabetic lists with at least this many entries get an "A–Z" row on top
  private static let letterPickerMinItemCount = 30

  /// Splits the item budget over the fetch sections and, for long alphabetic lists, puts an
  /// "A–Z" row on top. It opens the list of initials, because CarPlay on iOS 27 doesn't show the
  /// `sectionIndexTitle` index anymore and the shortened sections hide most entries anyway.
  private func createAlphabeticSections<MO: NSManagedObject>(
    fetchSections: @escaping () -> [NSFetchedResultsSectionInfo]?,
    isAlphabetic: Bool,
    createItem: @escaping (MO) -> CPListTemplateItem?
  )
    -> [CPListSection] {
    guard let currentSections = fetchSections(), !currentSections.isEmpty else { return [] }
    let totalCount = currentSections.reduce(0) { $0 + $1.numberOfObjects }
    // also when the list doesn't fit: cars with a low item limit cut it off after a few letters
    let fitsInList = totalCount <= CPListTemplate.maximumItemCount
    let showsLetterPicker = isAlphabetic && currentSections.count > 1 &&
      (totalCount >= Self.letterPickerMinItemCount || !fitsInList)

    var sections = [CPListSection]()
    var itemBudget = CPListTemplate.maximumItemCount
    if showsLetterPicker {
      sections.append(CPListSection(
        items: [createLetterPickerItem(fetchSections: fetchSections, createItem: createItem)],
        header: nil,
        sectionIndexTitle: nil
      ))
      itemBudget -= 1
    }
    let maxSectionCount = totalCount <= itemBudget ? itemBudget :
      max(1, itemBudget / currentSections.count)
    for fetchSection in currentSections {
      guard itemBudget > 0 else { break }
      guard let fetchObjects = fetchSection.objects as? [MO] else { continue }
      let items = fetchObjects.prefix(min(maxSectionCount, itemBudget)).compactMap(createItem)
      itemBudget -= items.count
      sections.append(CPListSection(
        items: items,
        header: nil,
        sectionIndexTitle: isAlphabetic && !fetchSection.name.isEmpty ? fetchSection.name : nil
      ))
    }
    return sections
  }

  private func createLetterPickerItem<MO: NSManagedObject>(
    fetchSections: @escaping () -> [NSFetchedResultsSectionInfo]?,
    createItem: @escaping (MO) -> CPListTemplateItem?
  )
    -> CPListItem {
    let img = UIImage.createArtwork(
      with: UIImage.letterPicker,
      iconSizeType: .small,
      theme: getPreference(activeAccountInfo).theme,
      lightDarkMode: traits.userInterfaceStyle.asModeType,
      switchColors: true
    ).carPlayImage(carTraitCollection: traits)
    let pickerItem = CPListItem(
      text: "A–Z",
      detailText: nil,
      image: img,
      accessoryImage: nil,
      accessoryType: .disclosureIndicator
    )
    pickerItem.handler = { [weak self] _, completion in
      guard let self, let currentSections = fetchSections() else { completion(); return }
      let letterItems = currentSections.map { fetchSection in
        let letterItem = CPListItem(
          text: fetchSection.name,
          detailText: "\(fetchSection.numberOfObjects)",
          image: nil,
          accessoryImage: nil,
          accessoryType: .disclosureIndicator
        )
        let letter = fetchSection.name
        letterItem.handler = { [weak self] _, completion in
          guard let self,
                let letterSection = fetchSections()?.first(where: { $0.name == letter }),
                let fetchObjects = letterSection.objects as? [MO]
          else { completion(); return }
          let items = fetchObjects.prefix(CPListTemplate.maximumItemCount).compactMap(createItem)
          let letterTemplate = CPListTemplate(title: letter, sections: [
            CPListSection(items: items),
          ])
          // replace the picker by the letter list: CarPlay allows audio apps only 5 templates
          // (root included), and list -> artist -> album needs all of them
          Task { @MainActor in
            let _ = try? await self.interfaceController?.popTemplate(animated: false)
            let _ = try? await self.interfaceController?.pushTemplate(
              letterTemplate,
              animated: true
            )
          }
          completion()
        }
        return letterItem
      }
      let pickerTemplate = CPListTemplate(title: "A–Z", sections: [
        CPListSection(items: letterItems),
      ])
      interfaceController?.pushTemplate(pickerTemplate, animated: true, completion: nil)
      completion()
    }
    return pickerItem
  }

  func createSongItems(from fetchedController: BasicFetchedResultsController<SongMO>?)
    -> [CPListTemplateItem] {
    var items = [CPListTemplateItem]()
    var playables = [AbstractPlayable]()
    guard let fetchedController = fetchedController else { return items }
    for index in 0 ... (CPListTemplate.maximumSectionCount - 2) {
      guard let entity = fetchedController.getWrappedEntity(at: index) else { break }
      playables.append(entity)
    }
    if !playables.isEmpty {
      items.append(createPlayShuffledListItem(playContext: PlayContext(
        name: "Favorite Songs",
        playables: playables
      )))
    }
    for (index, playable) in playables.enumerated() {
      let detailTemplate = createDetailTemplate(
        for: playable,
        playContext: PlayContext(name: "Favorite Songs", index: index, playables: playables)
      )
      items.append(detailTemplate)
    }
    return items
  }

  func createPlaylistDetailItems(
    from fetchedController: PlaylistItemsFetchedResultsController
  )
    -> [CPListTemplateItem] {
    let playlist = fetchedController.playlist
    var items = [CPListItem]()

    guard let playables = fetchedController.getContextSongs(onlyCachedSongs: isOfflineMode)
    else { return items }

    // with a header (iOS 26.4) its buttons play and shuffle
    if #unavailable(iOS 26.4) {
      items.append(createPlayShuffledListItem(playContext: PlayContext(
        containable: playlist,
        playables: playlist.playables.filterCached(dependigOn: isOfflineMode)
      )))
    }
    let displayedSongs = playables.prefix(CPListTemplate.maximumSectionCount - (items.count + 1))
    for (index, song) in displayedSongs.enumerated() {
      let listItem = createDetailTemplate(
        for: song,
        playContext: PlayContext(containable: playlist, index: index, playables: playables)
      )
      items.append(listItem)
      if index >= CPListTemplate.maximumItemCount - 1 {
        break
      }
    }
    return items
  }

  func createPodcastDetailItems(
    from fetchedController: PodcastEpisodesFetchedResultsController
  )
    -> [CPListTemplateItem] {
    let podcast = fetchedController.podcast
    var items = [CPListItem]()

    var playables = [AbstractPlayable]()
    for index in 0 ... (CPListTemplate.maximumSectionCount - 2) {
      guard let entity = fetchedController.getWrappedEntity(at: index) else { break }
      playables.append(entity)
    }
    for (index, song) in playables.enumerated() {
      let listItem = createDetailTemplate(
        for: song,
        playContext: PlayContext(containable: podcast, index: index, playables: playables)
      )
      items.append(listItem)
    }
    return items
  }

  func createDetailTemplate(for artist: Artist, onlyCached: Bool) -> CPListItem {
    let section = CPListItem(
      text: artist.name,
      detailText: artist.subtitle,
      image: LibraryEntityImage.getImageToDisplayImmediately(
        libraryEntity: artist,
        themePreference: getPreference(activeAccountInfo).theme,
        artworkDisplayPreference: getPreference(activeAccountInfo).artworkDisplayPreference,
        useCache: false,
        maxPixelSize: listImagePixelSize
      ).carPlayImage(carTraitCollection: traits),
      accessoryImage: nil,
      accessoryType: .disclosureIndicator
    )
    if let artwork = artist.artwork, let accountInfo = artwork.account?.info {
      appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
    }
    section.userInfo = [
      CarPlayListUserInfoKeys.artworkDownloadID.rawValue: artist.artwork?.uniqueID as Any,
      CarPlayListUserInfoKeys.artworkOwnerObjectID.rawValue: artist.managedObject.objectID as Any,
      CarPlayListUserInfoKeys.artworkOwnerType.rawValue: ArtworkType.artist as Any,
    ]
    section.handler = { [weak self] item, completion in
      guard let self = self else { completion(); return }
      let artistTemplate = createArtistTemplate(for: artist, onlyCached: onlyCached)
      interfaceController?.pushTemplate(artistTemplate, animated: true, completion: nil)
      completion()
    }
    return section
  }

  private func createArtistTemplate(for artist: Artist, onlyCached: Bool) -> CPListTemplate {
    let isOnlyCached = onlyCached || isOfflineMode
    let artistAlbums = appDelegate.storage.main.library.getAlbums(
      for: activeAccount,
      whichContainsSongsWithArtist: artist,
      onlyCached: isOnlyCached
    )
    var items = [CPListItem]()
    items.append(createDetailAllSongsTemplate(for: artist, onlyCached: onlyCached))
    items.append(contentsOf: artistAlbums.prefix(LibraryStorage.carPlayMaxElements).map {
      createDetailTemplate(for: $0, onlyCached: onlyCached)
    })

    if #available(iOS 26.4, *) {
      let songs = artist.playables.filterCached(dependigOn: isOnlyCached).filterSongs()
      let albumCount = artistAlbums.count
      let songCount = songs.count
      let header = createDetailsHeader(
        for: artist,
        image: getHeaderImage(for: artist),
        title: artist.name,
        subtitleParts: [
          "\(albumCount) Album\(albumCount == 1 ? "" : "s")",
          "\(songCount) Song\(songCount == 1 ? "" : "s")",
        ],
        hasPlayables: !songs.isEmpty,
        // like the play/shuffle buttons of the artist screen in the app: songs in album order
        playables: { songs.sortByAlbum() }
      )
      return createDetailsHeaderTemplate(
        title: artist.name,
        header: header,
        artworkOwner: artist,
        items: items
      )
    } else {
      let shuffleItem = createPlayShuffledListItem(playContext: PlayContext(
        containable: artist,
        playables: artist.playables.filterCached(dependigOn: isOnlyCached)
      ))
      return CPListTemplate(title: artist.name, sections: [
        CPListSection(items: [shuffleItem] + items),
      ])
    }
  }

  func createDetailAllSongsTemplate(for artist: Artist, onlyCached: Bool) -> CPListItem {
    let section = CPListItem(
      text: "All Songs",
      detailText: nil,
      image: UIImage.createArtwork(
        with: UIImage.musicalNotes,
        iconSizeType: .small,
        theme: getPreference(activeAccountInfo).theme,
        lightDarkMode: traits.userInterfaceStyle.asModeType,
        switchColors: true
      ).carPlayImage(carTraitCollection: traits),
      accessoryImage: nil,
      accessoryType: .disclosureIndicator
    )
    section.handler = { [weak self] item, completion in
      guard let self = self else { completion(); return }
      var songItems = [CPListItem]()
      songItems.append(createPlayShuffledListItem(playContext: PlayContext(
        containable: artist,
        playables: artist.playables.filterCached(dependigOn: onlyCached || isOfflineMode)
      )))
      let artistSongs = artist.playables.filterCached(dependigOn: onlyCached || isOfflineMode)
        .sortByTitle().prefix(LibraryStorage.carPlayMaxElements)
      for (index, song) in artistSongs.enumerated() {
        let listItem = createDetailTemplate(
          for: song,
          playContext: PlayContext(containable: artist, index: index, playables: Array(artistSongs))
        )
        songItems.append(listItem)
      }
      let albumTemplate = CPListTemplate(title: artist.name, sections: [
        CPListSection(items: songItems),
      ])
      interfaceController?.pushTemplate(albumTemplate, animated: true, completion: nil)
      completion()
    }
    return section
  }

  func createDetailTemplate(for album: Album, onlyCached: Bool) -> CPListItem {
    let section = CPListItem(
      text: album.name,
      detailText: album.subtitle,
      image: LibraryEntityImage.getImageToDisplayImmediately(
        libraryEntity: album,
        themePreference: getPreference(activeAccountInfo).theme,
        artworkDisplayPreference: getPreference(activeAccountInfo).artworkDisplayPreference,
        useCache: false,
        maxPixelSize: listImagePixelSize
      ).carPlayImage(carTraitCollection: traits),
      accessoryImage: nil,
      accessoryType: .disclosureIndicator
    )
    if let artwork = album.artwork, let accountInfo = artwork.account?.info {
      appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
    }
    section.userInfo = [
      CarPlayListUserInfoKeys.artworkDownloadID.rawValue: album.artwork?.uniqueID as Any,
      CarPlayListUserInfoKeys.artworkOwnerObjectID.rawValue: album.managedObject.objectID as Any,
      CarPlayListUserInfoKeys.artworkOwnerType.rawValue: ArtworkType.album as Any,
    ]
    section.handler = { [weak self] item, completion in
      guard let self = self else { completion(); return }
      let albumTemplate = createAlbumSongListTemplate(for: album, onlyCached: onlyCached)
      interfaceController?.pushTemplate(albumTemplate, animated: true, completion: nil)
      completion()
    }
    return section
  }

  func createAlbumSongListTemplate(for album: Album, onlyCached: Bool) -> CPListTemplate {
    let playables = album.playables.filterCached(dependigOn: onlyCached || isOfflineMode)
    let albumSongs = Array(playables.prefix(LibraryStorage.carPlayMaxElements))
    func createSongItems(hiddenCreatorName: String?) -> [CPListItem] {
      albumSongs.enumerated().map { index, song in
        createDetailTemplate(
          for: song,
          playContext: PlayContext(containable: album, index: index, playables: albumSongs),
          isTrackDisplayed: true,
          hiddenCreatorName: hiddenCreatorName
        )
      }
    }

    if #available(iOS 26.4, *) {
      var subtitleParts = [String]()
      if let artistName = album.subtitle { subtitleParts.append(artistName) }
      if let genreName = album.genre?.name { subtitleParts.append(genreName) }
      if album.year > 0 { subtitleParts.append("\(album.year)") }
      let header = createDetailsHeader(
        for: album,
        image: getHeaderImage(for: album),
        title: album.name,
        subtitleParts: subtitleParts,
        hasPlayables: !playables.isEmpty,
        playables: { playables }
      )
      return createDetailsHeaderTemplate(
        title: album.name,
        header: header,
        artworkOwner: album,
        // the header shows the album artist, rows only show a differing artist
        items: createSongItems(hiddenCreatorName: album.artist?.name)
      )
    } else {
      let shuffleItem = createPlayShuffledListItem(playContext: PlayContext(
        containable: album,
        playables: playables
      ))
      return CPListTemplate(title: album.name, sections: [
        CPListSection(items: [shuffleItem] + createSongItems(hiddenCreatorName: nil)),
      ])
    }
  }

  /// Header like Apple Music: cover, title, subtitle (e.g. "artist · genre · year"), play and
  /// shuffle
  @available(iOS 26.4, *)
  private func createDetailsHeader(
    for containable: PlayableContainable,
    image: UIImage,
    title: String,
    subtitleParts: [String],
    hasPlayables: Bool,
    playables: @escaping () -> [AbstractPlayable]
  )
    -> CPListTemplateDetailsHeader {
    // the songs are only prepared (e.g. sorted) when a button is pressed
    let playButton = CPButton(image: UIImage.play) { [weak self] _ in
      guard let self else { return }
      appDelegate.player.play(context: PlayContext(
        containable: containable,
        playables: playables()
      ))
      displayNowPlaying {}
    }
    playButton.title = "Play"
    let shuffleButton = CPButton(image: UIImage.shuffle) { [weak self] _ in
      guard let self else { return }
      appDelegate.player.playShuffled(context: PlayContext(
        containable: containable,
        playables: playables()
      ))
      displayNowPlaying {}
    }
    playButton.isEnabled = hasPlayables
    shuffleButton.isEnabled = hasPlayables

    let subtitle = subtitleParts.filter { !$0.isEmpty }
      .joined(separator: " \(CommonString.oneMiddleDot) ")
    let header = CPListTemplateDetailsHeader(
      thumbnail: CPThumbnailImage(image: image),
      title: title,
      subtitle: subtitle.isEmpty ? nil : subtitle,
      actionButtons: [playButton, shuffleButton]
    )
    // background color derived from the cover, like the artwork background in the app
    header.wantsAdaptiveBackgroundStyle = true
    return header
  }

  /// List with a details header. The cover in the header is refreshed by
  /// `refreshDetailsHeaderArtwork` once the artwork of the owner is downloaded.
  @available(iOS 26.4, *)
  private func createDetailsHeaderTemplate(
    title: String,
    header: CPListTemplateDetailsHeader,
    artworkOwner: AbstractLibraryEntity,
    items: [CPListItem]
  )
    -> CPListTemplate {
    // the page can be opened without the list row that usually starts the artwork download
    // (e.g. an album from Now Playing or Home)
    if let artwork = artworkOwner.artwork, let accountInfo = artwork.account?.info {
      appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
    }
    let template = CPListTemplate(
      title: title,
      listHeader: header,
      sections: [CPListSection(items: items)],
      assistantCellConfiguration: nil
    )
    template.userInfo = [
      CarPlayListUserInfoKeys.artworkDownloadID.rawValue: artworkOwner.artwork?.uniqueID as Any,
      CarPlayListUserInfoKeys.artworkOwnerObjectID.rawValue: artworkOwner.objectID,
    ]
    return template
  }

  @available(iOS 26.4, *)
  func getHeaderImage(for entity: AbstractLibraryEntity) -> UIImage {
    LibraryEntityImage.getImageToDisplayImmediately(
      libraryEntity: entity,
      themePreference: getPreference(activeAccountInfo).theme,
      artworkDisplayPreference: getPreference(activeAccountInfo).artworkDisplayPreference,
      useCache: false,
      maxPixelSize: headerImagePixelSize
    ).carPlayImage(carTraitCollection: traits)
  }

  /// Playlist cover (e.g. a grid of album covers) like the app shows it, at header size
  @available(iOS 26.4, *)
  func getHeaderImage(for playlist: Playlist) -> UIImage {
    LibraryEntityImage.getImageToDisplayImmediately(
      collection: playlist.getArtworkCollection(theme: getPreference(activeAccountInfo).theme),
      themePreference: getPreference(activeAccountInfo).theme,
      artworkDisplayPreference: getPreference(activeAccountInfo).artworkDisplayPreference,
      useCache: false,
      maxPixelSize: headerImagePixelSize
    ).carPlayImage(carTraitCollection: traits)
  }

  /// The playlist page is filled once its fetch controller has the songs, see
  /// `updatePlaylistDetailTemplate`
  func createPlaylistDetailTemplate(for playlist: Playlist) -> CPListTemplate {
    let template: CPListTemplate
    if #available(iOS 26.4, *) {
      let playables = playlist.playables.filterCached(dependigOn: isOfflineMode)
      template = CPListTemplate(
        title: playlist.name,
        listHeader: createPlaylistDetailsHeader(for: playlist, playables: playables),
        sections: [CPListSection(items: [CPListTemplateItem]())],
        assistantCellConfiguration: nil
      )
      template.userInfo = createPlaylistHeaderUserInfo(for: playlist, playables: playables)
      downloadCoverArtworks(of: playlist)
    } else {
      template = CPListTemplate(title: playlist.name, sections: [
        CPListSection(items: [CPListTemplateItem]()),
      ])
    }
    playlistDetailSection = template
    createPlaylistDetailFetchController(playlist: playlist)
    return template
  }

  /// Fills the playlist page with the current songs; the header buttons play them too
  func updatePlaylistDetailTemplate() {
    guard let playlistDetailSection, let playlistDetailFetchController else { return }
    playlistDetailSection.updateSections([
      CPListSection(items: createPlaylistDetailItems(from: playlistDetailFetchController)),
    ])
    if #available(iOS 26.4, *) {
      let playlist = playlistDetailFetchController.playlist
      let playables = playlist.playables.filterCached(dependigOn: isOfflineMode)
      let userInfo = createPlaylistHeaderUserInfo(for: playlist, playables: playables)
      // fetch changes come in bursts during a sync: only rebuild the header (cover image and a
      // new header layout in CarPlay) when its songs or cover artworks changed
      let headerKey = CarPlayListUserInfoKeys.headerContentKey.rawValue
      guard (playlistDetailSection.userInfo as? [String: Any])?[headerKey] as? Int !=
        userInfo[headerKey] as? Int
      else { return }
      playlistDetailSection.listHeader = createPlaylistDetailsHeader(
        for: playlist,
        playables: playables
      )
      // the cover can consist of other artworks after the playlist sync
      playlistDetailSection.userInfo = userInfo
      downloadCoverArtworks(of: playlist)
    }
  }

  /// Lets `refreshDetailsHeaderArtwork` update the header cover once one of its artworks is
  /// downloaded
  private func createPlaylistHeaderUserInfo(
    for playlist: Playlist,
    playables: [AbstractPlayable]
  )
    -> [String: Any] {
    let artworks = playlist.getArtworkCollection(theme: getPreference(activeAccountInfo).theme)
      .artworks
    var hasher = Hasher()
    hasher.combine(playables.map { $0.uniqueID })
    hasher.combine(artworks.map { $0.uniqueID })
    hasher.combine(playlist.name)
    return [
      CarPlayListUserInfoKeys.artworkDownloadIDs.rawValue: artworks.map { $0.uniqueID },
      CarPlayListUserInfoKeys.containableObjectID.rawValue: playlist.managedObject.objectID,
      CarPlayListUserInfoKeys.headerContentKey.rawValue: hasher.finalize(),
    ]
  }

  private func downloadCoverArtworks(of playlist: Playlist) {
    let collection = playlist.getArtworkCollection(theme: getPreference(activeAccountInfo).theme)
    for artwork in collection.artworks {
      if let accountInfo = artwork.account?.info {
        appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
      }
    }
  }

  @available(iOS 26.4, *)
  private func createPlaylistDetailsHeader(
    for playlist: Playlist,
    playables: [AbstractPlayable]
  )
    -> CPListTemplateDetailsHeader {
    // like the info of the playlist screen in the app, but of the shown (e.g. cached) songs
    var subtitleParts = ["\(playables.count) Song\(playables.count == 1 ? "" : "s")"]
    let duration = playables.reduce(0) { $0 + $1.duration }
    if duration > 0 { subtitleParts.append(duration.asDurationShortString) }
    return createDetailsHeader(
      for: playlist,
      image: getHeaderImage(for: playlist),
      title: playlist.name,
      subtitleParts: subtitleParts,
      hasPlayables: !playables.isEmpty,
      playables: { playables }
    )
  }

  func createPlaylistsSections() -> [CPListSection] {
    guard let fetchedController = playlistFetchController else { return [] }
    return createAlphabeticSections(
      fetchSections: { fetchedController.sections },
      isAlphabetic: fetchedController.sortType.asSectionIndexType == .alphabet
    ) { [weak self] (playlistMO: PlaylistMO) in
      self?.createPlaylistItem(for: playlistMO)
    }
  }

  private func createPlaylistItem(for playlistMO: PlaylistMO) -> CPListItem {
    let playlist = Playlist(
      library: appDelegate.storage.main.library,
      managedObject: playlistMO
    )
    let collection = playlist
      .getArtworkCollection(theme: getPreference(activeAccountInfo).theme)
    let item = CPListItem(
      text: playlist.name,
      detailText: playlist.subtitle,
      image: getImage(for: collection),
      accessoryImage: nil,
      accessoryType: .disclosureIndicator
    )
    let artworks = collection.artworks
    for artwork in artworks {
      if let accountInfo = artwork.account?.info {
        appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
      }
    }
    item.userInfo = [
      CarPlayListUserInfoKeys.artworkDownloadIDs.rawValue: artworks.map { $0.uniqueID },
      CarPlayListUserInfoKeys.containableObjectID.rawValue: playlistMO.objectID,
    ]
    item.handler = { [weak self] item, completion in
      guard let self = self else { completion(); return }
      let playlistDetailTemplate = createPlaylistDetailTemplate(for: playlist)
      interfaceController?.pushTemplate(playlistDetailTemplate, animated: true, completion: nil)
      completion()
    }
    return item
  }

  func createPodcastsSections(
    from fetchedController: BasicFetchedResultsController<PodcastMO>?,
    onlyCached: Bool
  )
    -> [CPListSection] {
    var sections = [CPListSection]()
    var itemCount = 0
    guard let fetchedController,
          let fetchSections = fetchedController.sections else { return sections }
    for fetchSection in fetchSections {
      guard let fetchObjects = fetchSection.objects as? [PodcastMO] else { continue }
      var items = [CPListTemplateItem]()

      var indexTitle: String?
      indexTitle = fetchObjects.first?.title?.prefix(1).uppercased()
      if let _ = Int(indexTitle ?? "-") {
        indexTitle = "#"
      }

      for fetchObject in fetchObjects {
        let podcast = Podcast(managedObject: fetchObject)

        let item = CPListItem(
          text: podcast.title,
          detailText: podcast.subtitle,
          image: LibraryEntityImage.getImageToDisplayImmediately(
            libraryEntity: podcast,
            themePreference: getPreference(activeAccountInfo).theme,
            artworkDisplayPreference: getPreference(activeAccountInfo).artworkDisplayPreference,
            useCache: false,
            maxPixelSize: listImagePixelSize
          ).carPlayImage(carTraitCollection: traits),
          accessoryImage: nil,
          accessoryType: .disclosureIndicator
        )
        if let artwork = podcast.artwork, let accountInfo = artwork.account?.info {
          appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
        }
        item.userInfo = [
          CarPlayListUserInfoKeys.artworkDownloadID.rawValue: podcast.artwork?.uniqueID as Any,
          CarPlayListUserInfoKeys.artworkOwnerObjectID.rawValue: podcast.managedObject
            .objectID as Any,
          CarPlayListUserInfoKeys.artworkOwnerType.rawValue: ArtworkType.podcast as Any,
        ]
        item.handler = { [weak self] item, completion in
          guard let self = self else { completion(); return }
          let podcastDetailTemplate = CPListTemplate(title: podcast.name, sections: [
            CPListSection(items: [CPListTemplateItem]()),
          ])
          podcastDetailSection = podcastDetailTemplate
          createPodcastDetailFetchController(podcast: podcast, onlyCached: onlyCached)
          interfaceController?.pushTemplate(podcastDetailTemplate, animated: true, completion: nil)
          completion()
        }
        items.append(item)
        itemCount += 1
        if itemCount > CPListTemplate.maximumItemCount { break }
      }
      let section = CPListSection(items: items, header: nil, sectionIndexTitle: indexTitle)
      sections.append(section)
      if itemCount > CPListTemplate.maximumItemCount { break }
    }
    return sections
  }

  func createGenreSections(
    from fetchedController: BasicFetchedResultsController<GenreMO>?,
    onlyCached: Bool
  )
    -> [CPListSection] {
    var sections = [CPListSection]()
    var itemCount = 0
    guard let fetchedController = fetchedController,
          let fetchSections = fetchedController.sections,
          !fetchSections.isEmpty else { return sections }

    for fetchSection in fetchSections {
      guard let fetchObjects = fetchSection.objects as? [GenreMO] else { continue }
      var items = [CPListTemplateItem]()

      var indexTitle: String?
      indexTitle = fetchObjects.first?.name?.prefix(1).uppercased()
      if let _ = Int(indexTitle ?? "-") {
        indexTitle = "#"
      }

      for fetchObject in fetchObjects {
        let genre = Genre(managedObject: fetchObject)
        let genreInfo = genre.info(
          for: activeAccount.apiType.asServerApiType,
          details: DetailInfoType(
            type: .short,
            settings: appDelegate.storage.settings
          )
        )
        let listItem = CPListItem(
          text: genre.name,
          detailText: genreInfo,
          image: LibraryEntityImage.getImageToDisplayImmediately(
            libraryEntity: genre,
            themePreference: getPreference(activeAccountInfo).theme,
            artworkDisplayPreference: getPreference(activeAccountInfo).artworkDisplayPreference,
            useCache: false,
            maxPixelSize: listImagePixelSize
          ).carPlayImage(carTraitCollection: traits),
          accessoryImage: nil,
          accessoryType: .none
        )
        listItem.handler = { [weak self] item, completion in
          guard let self = self else { completion(); return }
          let songs = genre.playables.filterCached(dependigOn: onlyCached || isOfflineMode)
          let genrePlayContext = PlayContext(name: genre.name, playables: songs)
          appDelegate.player.play(context: genrePlayContext)
          displayNowPlaying {}
          completion()
        }
        items.append(listItem)
        itemCount += 1
        if itemCount > CPListTemplate.maximumItemCount { break }
      }
      let section = CPListSection(items: items, header: nil, sectionIndexTitle: indexTitle)
      sections.append(section)
      if itemCount > CPListTemplate.maximumItemCount { break }
    }
    return sections
  }

  func createRadioSections(from fetchedController: BasicFetchedResultsController<RadioMO>?)
    -> [CPListSection] {
    var sections = [CPListSection]()
    guard let fetchedController = fetchedController,
          let fetchSections = fetchedController.sections,
          !fetchSections.isEmpty else { return sections }

    guard let fetchedRadios = fetchedController.fetchedObjects else { return sections }
    let radios = fetchedRadios.prefix(CPListTemplate.maximumItemCount)
      .compactMap { Radio(managedObject: $0) }

    let playRandomItem = createPlayRandomListItem(playContext: PlayContext(
      name: "Radios",
      playables: radios
    ))
    let randomSection = CPListSection(items: [playRandomItem], header: nil, sectionIndexTitle: nil)
    sections.append(randomSection)
    var itemCount = 1

    for fetchSection in fetchSections {
      guard let fetchObjects = fetchSection.objects as? [RadioMO] else { continue }
      var items = [CPListTemplateItem]()

      var indexTitle: String?
      indexTitle = fetchObjects.first?.title?.prefix(1).uppercased()
      if let _ = Int(indexTitle ?? "-") {
        indexTitle = "#"
      }

      for fetchObject in fetchObjects {
        let radio = Radio(managedObject: fetchObject)
        let listItem = createDetailTemplate(
          for: radio,
          playContext: PlayContext(name: "Radios", index: itemCount - 1, playables: Array(radios)),
          isTrackDisplayed: false
        )
        items.append(listItem)
        itemCount += 1
        if itemCount > CPListTemplate.maximumItemCount { break }
      }
      let section = CPListSection(items: items, header: nil, sectionIndexTitle: indexTitle)
      sections.append(section)
      if itemCount > CPListTemplate.maximumItemCount { break }
    }
    return sections
  }

  func createPlayRandomListItem(
    playContext: PlayContext,
    text: String = "Random"
  )
    -> CPListItem {
    let img = UIImage.createArtwork(
      with: UIImage.shuffle,
      iconSizeType: .small,
      theme: getPreference(activeAccountInfo).theme,
      lightDarkMode: traits.userInterfaceStyle.asModeType,
      switchColors: true
    ).carPlayImage(carTraitCollection: traits)
    let listItem = CPListItem(text: text, detailText: nil, image: img)
    listItem.handler = { [weak self] item, completion in
      guard let self = self else { completion(); return }
      appDelegate.player.play(context: playContext.getWithShuffledIndex())
      displayNowPlaying {
        completion()
      }
    }
    return listItem
  }

  func createPlayShuffledListItem(
    playContext: PlayContext,
    text: String = "Shuffle"
  )
    -> CPListItem {
    let img = UIImage.createArtwork(
      with: UIImage.shuffle,
      iconSizeType: .small,
      theme: getPreference(activeAccountInfo).theme,
      lightDarkMode: traits.userInterfaceStyle.asModeType,
      switchColors: true
    ).carPlayImage(carTraitCollection: traits)
    let listItem = CPListItem(text: text, detailText: nil, image: img)
    listItem.handler = { [weak self] item, completion in
      guard let self = self else { completion(); return }
      appDelegate.player.playShuffled(context: playContext)
      displayNowPlaying {
        completion()
      }
    }
    return listItem
  }

  func createDetailTemplate(for episode: PodcastEpisode) -> CPListItem {
    let accessoryType: CPListItemAccessoryType = episode.isCached ? .cloud : .none
    let listItem = CPListItem(
      text: episode.title,
      detailText: nil,
      image: nil,
      accessoryImage: nil,
      accessoryType: accessoryType
    )
    listItem.handler = { [weak self] item, completion in
      guard let self = self else { completion(); return }
      appDelegate.player.play(context: PlayContext(containable: episode))
      displayNowPlaying {
        completion()
      }
    }
    return listItem
  }

  func createLibraryItem(
    text: String,
    subtitle: String? = nil,
    icon: UIImage,
    sectionToDisplay: CPListTemplate
  )
    -> CPListItem {
    let item = CPListItem(
      text: text,
      detailText: subtitle,
      image: UIImage
        .createArtwork(
          with: icon,
          iconSizeType: .small,
          theme: getPreference(activeAccountInfo).theme,
          lightDarkMode: traits.userInterfaceStyle.asModeType,
          switchColors: true
        )
        .carPlayImage(carTraitCollection: traits),
      accessoryImage: nil,
      accessoryType: .disclosureIndicator
    )
    item.handler = { [weak self] item, completion in
      guard let self = self else { completion(); return }
      Task { @MainActor in
        let _ = try? await interfaceController?
          .pushTemplate(sectionToDisplay, animated: true)
        completion()
      }
    }
    return item
  }

  enum CarPlayListUserInfoKeys: String {
    case playableDownloadID
    case artworkDownloadID
    case artworkOwnerType
    case artworkOwnerObjectID
    case isTrackDisplayed
    case artworkDownloadIDs
    case containableObjectID
    /// details header: hash of what it shows, to skip rebuilding an unchanged header
    case headerContentKey
  }

  /// Image of a container (e.g. a playlist cover grid) like the app shows it.
  func getImage(for containable: PlayableContainable) -> UIImage {
    getImage(for: containable.getArtworkCollection(theme: getPreference(activeAccountInfo).theme))
  }

  func getImage(for collection: ArtworkCollection) -> UIImage {
    let theme = getPreference(activeAccountInfo).theme
    return LibraryEntityImage.getImageToDisplayImmediately(
      collection: collection,
      themePreference: theme,
      artworkDisplayPreference: getPreference(activeAccountInfo).artworkDisplayPreference,
      useCache: false,
      maxPixelSize: listImagePixelSize
    ).carPlayImage(carTraitCollection: traits)
  }

  func createDetailTemplate(
    for playable: AbstractPlayable,
    playContext: PlayContext,
    isTrackDisplayed: Bool = false,
    hiddenCreatorName: String? = nil
  )
    -> CPListItem {
    let accessoryType: CPListItemAccessoryType = playable.isCached ? .cloud : .none
    let image = getImage(for: playable, isTrackDisplayed: isTrackDisplayed)
    // rows with the track number (album page) show no song cover, don't download it
    if !isTrackDisplayed, let artwork = playable.artwork, let accountInfo = artwork.account?.info {
      appDelegate.getMeta(accountInfo).artworkDownloadManager.download(object: artwork)
    }
    let listItem = CPListItem(
      text: playable.title,
      // e.g. on the album page the album artist is already in the header, like in the app
      detailText: hiddenCreatorName != nil && playable.creatorName == hiddenCreatorName ?
        nil : playable.subtitle,
      image: image.carPlayImage(carTraitCollection: traits),
      accessoryImage: nil,
      accessoryType: accessoryType
    )
    listItem.userInfo = [
      CarPlayListUserInfoKeys.playableDownloadID.rawValue: playable.uniqueID,
      CarPlayListUserInfoKeys.artworkDownloadID.rawValue: playable.artwork?.uniqueID as Any,
      CarPlayListUserInfoKeys.artworkOwnerObjectID.rawValue: playable.objectID,
      CarPlayListUserInfoKeys.artworkOwnerType.rawValue: playable.isSong ? ArtworkType
        .song : ArtworkType.podcastEpisode,
      CarPlayListUserInfoKeys.isTrackDisplayed.rawValue: isTrackDisplayed,
    ]
    listItem.handler = { [weak self] item, completion in
      guard let self = self else { completion(); return }
      appDelegate.player.play(context: playContext)
      displayNowPlaying {
        completion()
      }
    }
    return listItem
  }

  func getImage(for playable: AbstractPlayable, isTrackDisplayed: Bool) -> UIImage {
    isTrackDisplayed ? createTrackNumberImage(number: playable.track) :
      LibraryEntityImage.getImageToDisplayImmediately(
        libraryEntity: playable,
        themePreference: getPreference(activeAccountInfo).theme,
        artworkDisplayPreference: getPreference(activeAccountInfo).artworkDisplayPreference,
        useCache: false,
        maxPixelSize: listImagePixelSize
      )
  }

  /// Track number in the row's image slot, styled like Apple Music: regular weight, about the
  /// size of the detail text, in the secondary label color of the car's current light or dark mode
  func createTrackNumberImage(number: Int) -> UIImage {
    let canvasSize = CGSize(width: 100, height: 100)
    let font = UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .regular)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    let text = number > 0 ? "\(number)" : ""

    let format = UIGraphicsImageRendererFormat()
    format.scale = max(traits.displayScale, 1)
    return UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .paragraphStyle: paragraphStyle,
        .foregroundColor: UIColor.secondaryLabel.resolvedColor(with: traits),
      ]
      let textHeight = font.lineHeight
      text.draw(
        in: CGRect(
          x: 0,
          y: (canvasSize.height - textHeight) / 2,
          width: canvasSize.width,
          height: textHeight
        ),
        withAttributes: attributes
      )
    }
  }

  func triggerPlayRandomSongsItem(onlyCached: Bool) {
    let songs = appDelegate.storage.main.library
      .getRandomSongs(for: activeAccount, onlyCached: onlyCached || isOfflineMode)
    let playContext = PlayContext(
      name: "Random\(onlyCached ? " Cached" : "") Songs",
      playables: songs
    )
    appDelegate.player.playShuffled(context: playContext)
    displayNowPlaying {}
  }

  func triggerPlayRandomAlbums(onlyCached: Bool) {
    let randomAlbums = appDelegate.storage.main.library.getRandomAlbums(
      for: activeAccount,
      count: 5,
      onlyCached: onlyCached || isOfflineMode
    )
    var songs = [AbstractPlayable]()
    randomAlbums
      .forEach {
        songs
          .append(
            contentsOf: $0.playables
              .filterCached(dependigOn: onlyCached || self.isOfflineMode)
          )
      }
    let playContext = PlayContext(
      name: "Random\(onlyCached ? " Cached" : "") Albums",
      playables: songs
    )
    appDelegate.player.play(context: playContext)
    displayNowPlaying {}
  }
}

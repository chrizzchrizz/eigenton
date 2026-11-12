//
//  Settings.swift
//  AmperfyKit
//
//  Created by Maximilian Bauer on 09.12.25.
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

import os.log
import UIKit

// MARK: - AppSettings

public struct AppSettings: Sendable, Codable {
  private var _isLibrarySyncInfoReadByUser: Bool = false
  public var isLibrarySyncInfoReadByUser: Bool {
    get { _isLibrarySyncInfoReadByUser }
    set { _isLibrarySyncInfoReadByUser = newValue }
  }

  private var _isLibrarySynced: Bool = false
  public var isLibrarySynced: Bool {
    get { _isLibrarySynced }
    set { _isLibrarySynced = newValue }
  }

  private var _librarySyncVersion: LibrarySyncVersion = .v6
  public var librarySyncVersion: LibrarySyncVersion {
    get { _librarySyncVersion }
    set { _librarySyncVersion = newValue }
  }
}

// MARK: - UserSettings

public struct UserSettings: Sendable, Codable {
  private var _streamingMaxBitrateWifiPreference: StreamingMaxBitratePreference = .defaultValue
  public var streamingMaxBitrateWifiPreference: StreamingMaxBitratePreference {
    get { _streamingMaxBitrateWifiPreference }
    set { _streamingMaxBitrateWifiPreference = newValue }
  }

  private var _streamingMaxBitrateCellularPreference: StreamingMaxBitratePreference = .defaultValue
  public var streamingMaxBitrateCellularPreference: StreamingMaxBitratePreference {
    get { _streamingMaxBitrateCellularPreference }
    set { _streamingMaxBitrateCellularPreference = newValue }
  }

  private var _streamingFormatWifiPreference: StreamingFormatPreference = .defaultValue
  public var streamingFormatWifiPreference: StreamingFormatPreference {
    get { _streamingFormatWifiPreference }
    set { _streamingFormatWifiPreference = newValue }
  }

  private var _streamingFormatCellularPreference: StreamingFormatPreference = .defaultValue
  public var streamingFormatCellularPreference: StreamingFormatPreference {
    get { _streamingFormatCellularPreference }
    set { _streamingFormatCellularPreference = newValue }
  }

  private var _cacheTranscodingFormatPreference: CacheTranscodingFormatPreference = .defaultValue
  public var cacheTranscodingFormatPreference: CacheTranscodingFormatPreference {
    get { _cacheTranscodingFormatPreference }
    set { _cacheTranscodingFormatPreference = newValue }
  }

  private var _cacheTranscodingMaxBitratePreference: StreamingMaxBitratePreference = .defaultValue
  public var cacheTranscodingMaxBitratePreference: StreamingMaxBitratePreference {
    get { _cacheTranscodingMaxBitratePreference }
    set { _cacheTranscodingMaxBitratePreference = newValue }
  }

  private var _isShowDetailedInfo: Bool = false
  public var isShowDetailedInfo: Bool {
    get { _isShowDetailedInfo }
    set { _isShowDetailedInfo = newValue }
  }

  private var _isShowSongDuration: Bool = false
  public var isShowSongDuration: Bool {
    get { _isShowSongDuration }
    set { _isShowSongDuration = newValue }
  }

  private var _isShowAlbumDuration: Bool = false
  public var isShowAlbumDuration: Bool {
    get { _isShowAlbumDuration }
    set { _isShowAlbumDuration = newValue }
  }

  private var _isShowArtistDuration: Bool = false
  public var isShowArtistDuration: Bool {
    get { _isShowArtistDuration }
    set { _isShowArtistDuration = newValue }
  }

  private var _isShowRating: Bool = false
  public var isShowRating: Bool {
    get { _isShowRating }
    set { _isShowRating = newValue }
  }

  private var _isPlayerShuffleButtonEnabled: Bool = true
  public var isPlayerShuffleButtonEnabled: Bool {
    get { _isPlayerShuffleButtonEnabled }
    set { _isPlayerShuffleButtonEnabled = newValue }
  }

  private var _isShowMusicPlayerSkipButtons: Bool = false
  public var isShowMusicPlayerSkipButtons: Bool {
    get { _isShowMusicPlayerSkipButtons }
    set { _isShowMusicPlayerSkipButtons = newValue }
  }

  // limit in byte
  private var _cacheLimit: Int = 0
  public var cacheLimit: Int {
    get { _cacheLimit }
    set { _cacheLimit = newValue }
  }

  private var _isPlayerLyricsDisplayed: Bool = false
  public var isPlayerLyricsDisplayed: Bool {
    get { _isPlayerLyricsDisplayed }
    set { _isPlayerLyricsDisplayed = newValue }
  }

  private var _isOfflineMode: Bool = false
  public var isOfflineMode: Bool {
    get { _isOfflineMode }
    set { _isOfflineMode = newValue }
  }

  public var isOnlineMode: Bool {
    !_isOfflineMode
  }

  private var _isPlaybackStartOnlyOnPlay: Bool = false
  public var isPlaybackStartOnlyOnPlay: Bool {
    get { _isPlaybackStartOnlyOnPlay }
    set { _isPlaybackStartOnlyOnPlay = newValue }
  }

  private var _isPlayerSongPlaybackResumeEnabled: Bool = false
  public var isPlayerSongPlaybackResumeEnabled: Bool {
    get { _isPlayerSongPlaybackResumeEnabled }
    set { _isPlayerSongPlaybackResumeEnabled = newValue }
  }

  private var _isOpenPlayerOnForeground: Bool = false
  public var isOpenPlayerOnForeground: Bool {
    get { _isOpenPlayerOnForeground }
    set { _isOpenPlayerOnForeground = newValue }
  }

  private var _isPlayQueueSyncEnabled: Bool = false
  /// Saves the play queue to the server so another device can continue playback.
  public var isPlayQueueSyncEnabled: Bool {
    get { _isPlayQueueSyncEnabled }
    set { _isPlayQueueSyncEnabled = newValue }
  }

  private var _playQueueDeviceName: String = ""
  /// Name the server shows as the device that saved the play queue; empty uses the device type.
  public var playQueueDeviceName: String {
    get { _playQueueDeviceName }
    set { _playQueueDeviceName = newValue }
  }

  private var _isSimplifiedQueueEnabled: Bool = true
  /// Offers only "Insert" and "Append" on the play queue. Off also offers the separate user queue.
  public var isSimplifiedQueueEnabled: Bool {
    get { _isSimplifiedQueueEnabled }
    set { _isSimplifiedQueueEnabled = newValue }
  }

  private var _isAutoplayEnabled: Bool = false
  public var isAutoplayEnabled: Bool {
    get { _isAutoplayEnabled }
    set { _isAutoplayEnabled = newValue }
  }

  private var _isHapticsEnabled: Bool = true
  public var isHapticsEnabled: Bool {
    get { _isHapticsEnabled }
    set { _isHapticsEnabled = newValue }
  }

  private var _isArtworkBackgroundEnabled: Bool = true
  public var isArtworkBackgroundEnabled: Bool {
    get { _isArtworkBackgroundEnabled }
    set { _isArtworkBackgroundEnabled = newValue }
  }

  private var _isEqualizerEnabled: Bool = false
  public var isEqualizerEnabled: Bool {
    get { _isEqualizerEnabled }
    set { _isEqualizerEnabled = newValue }
  }

  private var _activeEqualizerSetting: EqualizerSetting = .off
  public var activeEqualizerSetting: EqualizerSetting {
    get { _activeEqualizerSetting }
    set { _activeEqualizerSetting = newValue }
  }

  private var _equalizerSettings: [EqualizerSetting] = []
  public var equalizerSettings: [EqualizerSetting] {
    get { _equalizerSettings }
    set { _equalizerSettings = newValue }
  }

  private var _isReplayGainEnabled: Bool = true
  public var isReplayGainEnabled: Bool {
    get { _isReplayGainEnabled }
    set { _isReplayGainEnabled = newValue }
  }

  private var _macSidebarWidth: Double = 0.0
  /// Mac: width of the sidebar as last dragged by the user, 0 for the default width
  public var macSidebarWidth: Double {
    get { _macSidebarWidth }
    set { _macSidebarWidth = newValue }
  }

  private var _macInspectorWidth: Double = 0.0
  /// Mac: width of the inspector as last dragged by the user, 0 for the default width
  public var macInspectorWidth: Double {
    get { _macInspectorWidth }
    set { _macInspectorWidth = newValue }
  }

  private var _playerVolume: Float = 1.0
  public var playerVolume: Float {
    get {
      (_playerVolume >= 0.0 && _playerVolume <= 1.0) ? _playerVolume : 1.0
    }
    set {
      guard newValue >= 0.0, newValue <= 1.0 else { return }
      _playerVolume = newValue
    }
  }

  private var _appearanceMode: UIUserInterfaceStyle = .unspecified
  public var appearanceMode: UIUserInterfaceStyle {
    get { _appearanceMode }
    set { _appearanceMode = newValue }
  }

  private var _screenLockPreventionPreference: ScreenLockPreventionPreference = .defaultValue
  public var screenLockPreventionPreference: ScreenLockPreventionPreference {
    get { _screenLockPreventionPreference }
    set { _screenLockPreventionPreference = newValue }
  }

  private var _playlistsSortSetting: PlaylistSortType = .defaultValue
  public var playlistsSortSetting: PlaylistSortType {
    get { _playlistsSortSetting }
    set { _playlistsSortSetting = newValue }
  }

  private var _artistsSortSetting: ArtistElementSortType = .defaultValue
  public var artistsSortSetting: ArtistElementSortType {
    get { _artistsSortSetting }
    set { _artistsSortSetting = newValue }
  }

  private var _albumsSortSetting: AlbumElementSortType = .defaultValue
  public var albumsSortSetting: AlbumElementSortType {
    get { _albumsSortSetting }
    set { _albumsSortSetting = newValue }
  }

  private var _swipeActionSettings: SwipeActionSettings = .defaultSettings
  public var swipeActionSettings: SwipeActionSettings {
    get { _swipeActionSettings }
    set { _swipeActionSettings = newValue }
  }

  /// The swipe actions that are currently offered.
  public var activeSwipeActionSettings: SwipeActionSettings {
    _swipeActionSettings.normalized(isSimplifiedQueue: _isSimplifiedQueueEnabled)
  }

  private var _songsSortSetting: SongElementSortType = .defaultValue
  public var songsSortSetting: SongElementSortType {
    get { _songsSortSetting }
    set {
      if newValue == SongElementSortType.starredDate {
        _songsSortSetting = .defaultValue
      } else {
        _songsSortSetting = newValue
      }
    }
  }

  private var _favoriteSongSortSetting: SongElementSortType = .defaultValueForFavorite
  public var favoriteSongSortSetting: SongElementSortType {
    get { _favoriteSongSortSetting }
    set { _favoriteSongSortSetting = newValue }
  }

  private var _artistsFilterSetting: ArtistCategoryFilter = .defaultValue
  public var artistsFilterSetting: ArtistCategoryFilter {
    get { _artistsFilterSetting }
    set { _artistsFilterSetting = newValue }
  }

  private var _albumsStyleSetting: AlbumsDisplayStyle = .defaultValue
  public var albumsStyleSetting: AlbumsDisplayStyle {
    get { _albumsStyleSetting }
    set { _albumsStyleSetting = newValue }
  }

  private var _podcastsShowSetting: PodcastsShowType = .defaultValue
  public var podcastsShowSetting: PodcastsShowType {
    get { _podcastsShowSetting }
    set { _podcastsShowSetting = newValue }
  }

  private var _playerDisplayStyle: PlayerDisplayStyle = .defaultValue
  public var playerDisplayStyle: PlayerDisplayStyle {
    get { _playerDisplayStyle }
    set { _playerDisplayStyle = newValue }
  }

  private var _albumsGridSizeSetting: Int?
  @MainActor
  public var albumsGridSizeSetting: Int {
    get {
      _albumsGridSizeSetting ?? ((UIDevice.current.userInterfaceIdiom == .phone) ? 2 : 3)
    }
    set { _albumsGridSizeSetting = newValue }
  }
}

// MARK: - AccountSetting

public struct AccountSetting: Sendable, Codable {
  private var _artworkDisplayPreference: ArtworkDisplayPreference = .defaultValue
  public var artworkDisplayPreference: ArtworkDisplayPreference {
    get { _artworkDisplayPreference }
    set { _artworkDisplayPreference = newValue }
  }

  private var _artworkDownloadSetting: ArtworkDownloadSetting = .defaultValue
  public var artworkDownloadSetting: ArtworkDownloadSetting {
    get { _artworkDownloadSetting }
    set { _artworkDownloadSetting = newValue }
  }

  // ordered visible Home Sections
  private var _homeSections: [HomeSection] = HomeSection.defaultValue
  public var homeSections: [HomeSection] {
    get { _homeSections.filter { !$0.isRemoved } }
    set { _homeSections = newValue }
  }

  // all Home Sections (visible and hidden) in the order arranged by the user
  // optional: settings stored before this property existed must still decode
  private var _homeSectionOrder: [HomeSection]?
  public var homeSectionOrder: [HomeSection] {
    get {
      (_homeSectionOrder ?? _homeSections)
        .filter { !$0.isRemoved }
        .completingOrder(with: HomeSection.displayOrder)
        .completingOrder(with: HomeSection.allCases.filter { !$0.isRemoved })
    }
    set { _homeSectionOrder = newValue }
  }

  private var _initialSyncCompletionStatus: SyncCompletionStatus = .defaultValue
  public var initialSyncCompletionStatus: SyncCompletionStatus {
    get { _initialSyncCompletionStatus }
    set { _initialSyncCompletionStatus = newValue }
  }

  private var _isAutoDownloadLatestPodcastEpisodesActive: Bool = false
  public var isAutoDownloadLatestPodcastEpisodesActive: Bool {
    get { _isAutoDownloadLatestPodcastEpisodesActive }
    set { _isAutoDownloadLatestPodcastEpisodesActive = newValue }
  }

  private var _isAutoDownloadLatestSongsActive: Bool = false
  public var isAutoDownloadLatestSongsActive: Bool {
    get { _isAutoDownloadLatestSongsActive }
    set { _isAutoDownloadLatestSongsActive = newValue }
  }

  private var _isScrobbleStreamedItems: Bool = false
  public var isScrobbleStreamedItems: Bool {
    get { _isScrobbleStreamedItems }
    set { _isScrobbleStreamedItems = newValue }
  }

  private var _libraryDisplaySettings: LibraryDisplaySettings = .defaultSettings
  public var libraryDisplaySettings: LibraryDisplaySettings {
    get { _libraryDisplaySettings }
    set { _libraryDisplaySettings = newValue }
  }

  private var _loginCredentials: LoginCredentials? = nil
  public var loginCredentials: LoginCredentials? {
    get { _loginCredentials }
    set { _loginCredentials = newValue }
  }

  private var _themePreference: ThemePreference = .defaultValue
  public var themePreference: ThemePreference {
    get { _themePreference }
    set { _themePreference = newValue }
  }
}

// MARK: - ReadOnlyAccountSetting

public struct ReadOnlyAccountSetting {
  public let read: AccountSetting
}

// MARK: - AccountSettings

public struct AccountSettings: Sendable, Codable {
  fileprivate var _accounts: [AccountInfo: AccountSetting] = [:]
  fileprivate var _activeAccount: AccountInfo?

  public mutating func switchActiveAccount(_ accountInfo: AccountInfo) {
    _activeAccount = accountInfo
  }

  public mutating func login(_ loginCredentials: LoginCredentials) {
    let accountInfo = Account.createInfo(credentials: loginCredentials)
    let newTheme = themeColorForNextNewAccount
    updateSetting(accountInfo) { accountSettings in
      accountSettings.loginCredentials = loginCredentials
      accountSettings.themePreference = newTheme
    }
    _activeAccount = accountInfo
  }

  public func getSetting(_ accountInfo: AccountInfo?) -> ReadOnlyAccountSetting {
    // Settings Priority:
    // 1.: provided account settings (if not nil)
    // 2.: active account settings (if logged in)
    // 3.: default settings
    if let info = accountInfo ?? _activeAccount, let accountSettings = _accounts[info] {
      return ReadOnlyAccountSetting(read: accountSettings)
    } else {
      return ReadOnlyAccountSetting(read: AccountSetting())
    }
  }

  public mutating func logout(_ accountInfo: AccountInfo) {
    _accounts[accountInfo] = nil
    if _activeAccount == accountInfo {
      _activeAccount = _accounts.first?.key
    }
  }

  public mutating func updateSetting(
    _ accountInfo: AccountInfo,
    _ update: (inout AccountSetting) -> ()
  ) {
    var setting = _accounts[accountInfo] ?? AccountSetting()
    update(&setting)
    _accounts[accountInfo] = setting
  }

  public var active: AccountInfo? {
    _activeAccount
  }

  public var activeSetting: ReadOnlyAccountSetting {
    guard let _activeAccount else { return ReadOnlyAccountSetting(read: AccountSetting()) }
    return ReadOnlyAccountSetting(read: _accounts[_activeAccount] ?? AccountSetting())
  }

  public var availableApiTypes: Set<ServerApiType> {
    Set(_accounts.compactMap { $0.value.loginCredentials?.backendApi.asServerApiType })
  }

  public var allAccounts: [AccountInfo] {
    _accounts.compactMap { $0.key }.sorted(by: {
      guard let cred0 = getSetting($0).read.loginCredentials,
            let cred1 = getSetting($1).read.loginCredentials
      else { return false }

      if cred0.displayServerUrl != cred1.displayServerUrl {
        return cred0.displayServerUrl < cred1.displayServerUrl
      } else {
        return cred0.username < cred1.username
      }
    })
  }

  private var themeColorForNextNewAccount: ThemePreference {
    var theme = ThemePreference.defaultValue
    let usedThemes = Set(_accounts.compactMap { $0.value.themePreference })
    if let firstAvailable = ThemePreference.allCases.first(where: { !usedThemes.contains($0) }) {
      theme = firstAvailable
    } else if let activeAccount = _activeAccount {
      let activeTheme = getSetting(activeAccount).read.themePreference
      theme = ThemePreference.allCases.first(where: { $0 != activeTheme }) ?? .defaultValue
    }
    return theme
  }
}

// MARK: - AmperfySettings

public struct AmperfySettings: Sendable {
  // MARK: - Persistence

  private static let decoder: JSONDecoder = .init()
  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = []
    return e
  }()

  /// Decodes stored settings. Settings stored by an older version lack the keys of settings added
  /// since, so those are filled in from `defaults` instead of discarding all stored values.
  static func decode<T: Codable>(
    _ type: T.Type,
    from data: Data,
    defaults: T,
    storeMergedForKey key: String? = nil
  ) throws
    -> T {
    do {
      return try decoder.decode(type, from: data)
    } catch DecodingError.keyNotFound {
      guard let defaultsObject = try JSONSerialization
        .jsonObject(with: encoder.encode(defaults)) as? [String: Any],
        let storedObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { throw DecodingError.dataCorrupted(.init(
        codingPath: [],
        debugDescription: "Settings are not a JSON object"
      )) }
      let mergedData = try JSONSerialization.data(
        withJSONObject: merge(stored: storedObject, into: defaultsObject)
      )
      let settings = try decoder.decode(type, from: mergedData)
      if let key {
        UserDefaults.standard.set(mergedData, forKey: key)
      }
      return settings
    }
  }

  private static func merge(
    stored: [String: Any],
    into defaults: [String: Any]
  )
    -> [String: Any] {
    defaults.merging(stored) { defaultValue, storedValue in
      if let defaultObject = defaultValue as? [String: Any],
         let storedObject = storedValue as? [String: Any] {
        return merge(stored: storedObject, into: defaultObject)
      }
      return storedValue
    }
  }

  // The settings are decoded once and kept in memory: they are read very often (e.g. for every
  // artwork that is shown), and decoding them from UserDefaults on every read is wasted work.
  // The memory is shared by all copies of AmperfySettings (several components keep their own copy
  // from launch), so a change made through any copy is seen by all of them. Every write goes
  // through the setters, which update the memory and UserDefaults together.
  private static let cache = SettingsCache()

  public init() {}

  /// Drops the settings kept in memory, so they are decoded from UserDefaults again on the next
  /// read (e.g. after a test wrote UserDefaults directly).
  static func reloadFromUserDefaults() {
    cache.removeAll()
  }

  fileprivate static func load<T: Codable>(
    key: PersistentStorage.UserDefaultsKey,
    defaults: T
  )
    -> T {
    guard let data = UserDefaults.standard.data(forKey: key.rawValue) else { return defaults }
    do {
      return try decode(T.self, from: data, defaults: defaults, storeMergedForKey: key.rawValue)
    } catch {
      os_log("Decoding %s failed: %s", type: .error, key.rawValue, String(describing: error))
      return defaults
    }
  }

  /// Returns false if the settings could not be encoded (nothing is stored then)
  fileprivate static func store<T: Codable>(
    _ settings: T,
    key: PersistentStorage.UserDefaultsKey
  )
    -> Bool {
    do {
      let data = try encoder.encode(settings)
      UserDefaults.standard.set(data, forKey: key.rawValue)
      return true
    } catch {
      os_log("Encoding %s failed: %s", type: .error, key.rawValue, String(describing: error))
      return false
    }
  }

  public var app: AppSettings {
    get { Self.cache.read(\.app, key: .SettingsApp) }
    set { Self.cache.write(newValue, to: \.app, key: .SettingsApp) }
  }

  public var user: UserSettings {
    get { Self.cache.read(\.user, key: .SettingsUser) }
    set { Self.cache.write(newValue, to: \.user, key: .SettingsUser) }
  }

  public var accounts: AccountSettings {
    get { Self.cache.read(\.accounts, key: .SettingsAccount) }
    set { Self.cache.write(newValue, to: \.accounts, key: .SettingsAccount) }
  }
}

// MARK: - SettingsCache

/// The decoded settings of all AmperfySettings copies. Read from any thread, so guarded by a lock;
/// the lock only protects each single read or write: `settings.user.x = v` reads and writes
/// separately, so concurrent changes of the same settings struct can still overwrite each other.
private final class SettingsCache: @unchecked Sendable {
  // recursive: UserDefaults.set posts didChangeNotification on the writing thread, an observer
  // that reads settings there would deadlock with a plain lock
  private let lock = NSRecursiveLock()
  fileprivate var app: AppSettings?
  fileprivate var user: UserSettings?
  fileprivate var accounts: AccountSettings?

  func read<T: Codable>(
    _ keyPath: ReferenceWritableKeyPath<SettingsCache, T?>,
    key: PersistentStorage.UserDefaultsKey
  )
    -> T where T: DefaultInitializable {
    lock.lock()
    defer { lock.unlock() }
    if let value = self[keyPath: keyPath] { return value }
    let value = AmperfySettings.load(key: key, defaults: T())
    self[keyPath: keyPath] = value
    return value
  }

  func write<T: Codable>(
    _ value: T,
    to keyPath: ReferenceWritableKeyPath<SettingsCache, T?>,
    key: PersistentStorage.UserDefaultsKey
  ) {
    lock.lock()
    defer { lock.unlock() }
    // memory follows only what is stored, so it never shows a change that is lost on restart
    guard AmperfySettings.store(value, key: key) else { return }
    self[keyPath: keyPath] = value
  }

  func removeAll() {
    lock.lock()
    defer { lock.unlock() }
    app = nil
    user = nil
    accounts = nil
  }
}

// MARK: - DefaultInitializable

private protocol DefaultInitializable {
  init()
}

// MARK: - AppSettings + DefaultInitializable

extension AppSettings: DefaultInitializable {}

// MARK: - UserSettings + DefaultInitializable

extension UserSettings: DefaultInitializable {}

// MARK: - AccountSettings + DefaultInitializable

extension AccountSettings: DefaultInitializable {}

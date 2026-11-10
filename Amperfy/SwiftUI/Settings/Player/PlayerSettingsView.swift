//
//  PlayerSettingsView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 15.09.22.
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

import AmperfyKit
import SwiftUI

// MARK: - PlayerSettingsView

struct PlayerSettingsView: View {
  @EnvironmentObject
  private var settings: Settings

  private func updateBitrate(
    wifi: StreamingMaxBitratePreference? = nil,
    cellular: StreamingMaxBitratePreference? = nil
  ) {
    if let wifi = wifi {
      settings.streamingMaxBitrateWifiPreference = wifi
    }
    if let cellular = cellular {
      settings.streamingMaxBitrateCellularPreference = cellular
    }
    appDelegate.player.setStreamingMaxBitrates(
      to: StreamingMaxBitrates(
        wifi: settings.streamingMaxBitrateWifiPreference,
        cellular: settings.streamingMaxBitrateCellularPreference
      )
    )
  }

  private func updateFormatCell(_ format: StreamingFormatPreference) {
    settings.streamingFormatCellularPreference = format

    appDelegate.player.setStreamingTranscodings(to: StreamingTranscodings(
      wifi: settings.streamingFormatWifiPreference,
      cellular: settings.streamingFormatCellularPreference
    ))
  }

  private func updateFormatWifi(_ format: StreamingFormatPreference) {
    settings.streamingFormatWifiPreference = format

    appDelegate.player.setStreamingTranscodings(to: StreamingTranscodings(
      wifi: settings.streamingFormatWifiPreference,
      cellular: settings.streamingFormatCellularPreference
    ))
  }

  private func updateCacheFormat(_ format: CacheTranscodingFormatPreference) {
    settings.cacheTranscodingFormatPreference = format
  }

  var body: some View {
    ZStack {
      SettingsList {
        // ReplayGain Settings
        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: "Enable ReplayGain",
              isOn: Binding(
                get: { settings.isReplayGainEnabled },
                set: { isEnabled in
                  settings.isReplayGainEnabled = isEnabled
                }
              )
            )
          },
          footer: "Automatically normalize track volume based on replay gain information for consistent loudness."
        )

        // the setting belongs to the active account
        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: "Scrobble streamed Songs",
              isOn: $settings.isScrobbleStreamedItems
            )
          },
          footer: "Enable to scrobble all streamed songs, even if the server already marks them as played. Applies to the active account."
        )

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: "Song Playback Resume",
              isOn: $settings.isPlayerSongPlaybackResumeEnabled
            )
          },
          footer: "Keeps track of song progress so playback continues from the previously saved position."
        )

        #if !targetEnvironment(macCatalyst) // ok
          SettingsSection(
            content: {
              SettingsCheckBoxRow(
                title: "Open Player When Returning",
                isOn: $settings.isOpenPlayerOnForeground
              )
            },
            footer: "While music is playing, the player opens when you return to the app, for example from the Lock Screen."
          )
        #endif

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: "Sync Play Queue",
              isOn: $settings.isPlayQueueSyncEnabled
            )
            if settings.isPlayQueueSyncEnabled {
              SettingsRow(title: "Device Name") {
                TextField(PlayQueueSyncer.defaultDeviceName, text: $settings.playQueueDeviceName)
                  .multilineTextAlignment(.trailing)
              }
            }
          },
          footer: "Saves the play queue and position on the server. Sync Play Queue on another device loads them, playback continues when you press play. The device name tells your devices apart, give each one its own. Requires a Subsonic server."
        )

        SettingsSection(content: {
          SettingsCheckBoxRow(title: "Manual Playback", isOn: $settings.isPlaybackStartOnlyOnPlay)
        }, footer: "Enable to start playback only when the Play button is pressed.")

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: "Autoplay After End",
              isOn: $settings.isAutoplayEnabled
            )
          },
          footer: "When the queue ends, automatically continue playback using Instant Mix to find similar songs."
        )

        SettingsSection(
          content: {
            SettingsCheckBoxRow(
              title: "Simplified Queue",
              isOn: $settings.isSimplifiedQueueEnabled
            )
          },
          footer: "Insert puts songs right after the current one, Append puts them at the end of the queue. Turn off to also use the separate User Queue: its songs play once before the queue continues and stay when you start something new."
        )

        SettingsSection(
          content: {
            SettingsRow(title: "Format") {
              Menu(settings.streamingFormatCellularPreference.description) {
                ForEach(StreamingFormatPreference.allCases, id: \.self) { format in
                  Button(format.description) {
                    updateFormatCell(format)
                  }
                }
              }
            }
            SettingsRow(title: "Bitrate Limit") {
              Menu(
                settings.streamingFormatCellularPreference == .raw
                  ? "Not applicable"
                  : settings.streamingMaxBitrateCellularPreference.description
              ) {
                ForEach(StreamingMaxBitratePreference.allCases, id: \.self) { bitrate in
                  Button(bitrate.description) {
                    updateBitrate(cellular: bitrate)
                  }
                }
              }
              .disabled(settings.streamingFormatCellularPreference == .raw)
            }
          },
          footer: "MP3 and AAC are transcoded by the server. AAC needs a server with an AAC transcoder, e.g. Navidrome; Ampache streams MP3 instead. “Original” streams the file unchanged, so the bitrate limit does not apply. With “Server default”, the codec and quality depend on your server's transcoding settings.",
          header: "Cellular Streaming"
        )

        SettingsSection(
          content: {
            SettingsRow(title: "Format") {
              Menu(settings.streamingFormatWifiPreference.description) {
                ForEach(StreamingFormatPreference.allCases, id: \.self) { format in
                  Button(format.description) {
                    updateFormatWifi(format)
                  }
                }
              }
            }
            SettingsRow(title: "Bitrate Limit") {
              Menu(
                settings.streamingFormatWifiPreference == .raw
                  ? "Not applicable"
                  : settings.streamingMaxBitrateWifiPreference.description
              ) {
                ForEach(StreamingMaxBitratePreference.allCases, id: \.self) { bitrate in
                  Button(bitrate.description) {
                    updateBitrate(wifi: bitrate)
                  }
                }
              }
              .disabled(settings.streamingFormatWifiPreference == .raw)
            }
          },
          footer: "MP3 and AAC are transcoded by the server. AAC needs a server with an AAC transcoder, e.g. Navidrome; Ampache streams MP3 instead. “Original” streams the file unchanged, so the bitrate limit does not apply. With “Server default”, the codec and quality depend on your server's transcoding settings.",
          header: "WiFi Streaming"
        )

        // Download Format Settings
        SettingsSection(
          content: {
            SettingsRow(title: "Format") {
              Menu(settings.cacheTranscodingFormatPreference.description) {
                ForEach(CacheTranscodingFormatPreference.allCases, id: \.self) { format in
                  Button(format.description) {
                    updateCacheFormat(format)
                  }
                }
              }
            }
            SettingsRow(title: "Bitrate Limit") {
              Menu(
                settings.cacheTranscodingFormatPreference == .raw
                  ? "Not applicable"
                  : settings.cacheTranscodingMaxBitratePreference.description
              ) {
                ForEach(StreamingMaxBitratePreference.allCases, id: \.self) { bitrate in
                  Button(bitrate.description) {
                    settings.cacheTranscodingMaxBitratePreference = bitrate
                  }
                }
              }
              .disabled(settings.cacheTranscodingFormatPreference == .raw)
            }
          },
          footer: "AAC needs a server with an AAC transcoder, e.g. Navidrome; Ampache downloads MP3 instead. “Original” downloads the file unchanged, so the bitrate limit does not apply. Ampache ignores the bitrate limit for downloads. Changes do not apply to songs that are already downloaded. Remove the download and redownload if needed.",
          header: "Download"
        )
      }
    }
    .navigationTitle("Player & Stream")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      appDelegate.userStatistics.visited(.settingsPlayer)
    }
  }
}

// MARK: - PlayerSettingsView_Previews

struct PlayerSettingsView_Previews: PreviewProvider {
  @State
  static var settings = Settings()

  static var previews: some View {
    PlayerSettingsView().environmentObject(settings)
  }
}

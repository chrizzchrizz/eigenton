//
//  SettingsView.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 14.09.22.
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

// MARK: - SettingsView

struct SettingsView: View {
  @EnvironmentObject
  private var settings: Settings

  func screenLockPreventionOffPressed() {
    settings.screenLockPreventionPreference = .never
    UIDevice.current.isBatteryMonitoringEnabled = false
    appDelegate.configureLockScreenPrevention()
  }

  func screenLockPreventionOnPressed() {
    settings.screenLockPreventionPreference = .always
    UIDevice.current.isBatteryMonitoringEnabled = false
    appDelegate.configureLockScreenPrevention()
  }

  func screenLockPreventionChargingPressed() {
    settings.screenLockPreventionPreference = .onlyIfCharging
    UIDevice.current.isBatteryMonitoringEnabled = true
    appDelegate.configureLockScreenPrevention()
  }

  func addAccountPressed() {
    var loginVC = AppStoryboard.Main.segueToLogin()
    #if targetEnvironment(macCatalyst)
      // provides the bar button used to close the login on the Mac
      loginVC = UINavigationController(rootViewController: loginVC)
    #endif
    loginVC.modalPresentationStyle = .formSheet
    // present from the window the user is working in (Settings is its own window on Mac)
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }
    // topViewController stops at the tab bar / split view, but on iPad and iPhone Settings is
    // presented on top of it: follow the presented chain, otherwise the presentation is rejected
    var presenter = AppDelegate.topViewController(base: keyWindow?.rootViewController)
    while let presented = presenter?.presentedViewController, !presented.isBeingDismissed {
      presenter = presented
    }
    presenter?.present(loginVC, animated: true)
  }

  func accountRow(_ accountInfo: AccountInfo) -> some View {
    let accounts = appDelegate.storage.settings.accounts
    let credentials = accounts.getSetting(accountInfo).read.loginCredentials
    let isActive = (accountInfo == settings.activeAccountInfo)
    return Button {
      guard !isActive else { return }
      appDelegate.switchAccount(accountInfo: accountInfo)
    } label: {
      HStack {
        Label {
          VStack(alignment: .leading) {
            Text(credentials?.username ?? "Unknown")
            if let url = credentials?.displayServerUrl {
              SecondaryText(url)
            }
          }
        } icon: {
          Image(systemName: "person.crop.circle")
        }
        Spacer()
        if isActive {
          Image(systemName: "checkmark")
        }
      }
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
  }

  func navigationLink(_ item: NavigationTarget) -> some View {
    NavigationLink(value: item) {
      Text(item.displayName)
    }
  }

  var body: some View {
    let list =
      SettingsList {
        SettingsSection {
          ForEach(settings.accounts, id: \.self) { accountInfo in
            accountRow(accountInfo)
          }
          Button(action: addAccountPressed) {
            Label("Add Account", systemImage: "person.crop.circle.fill.badge.plus")
          }
        }

        SettingsSection(
          content: {
            SettingsCheckBoxRow(title: "Offline Mode", isOn: $settings.isOfflineMode)
          },
          footer:
          "Songs, podcasts, and artworks won’t download offline. Searches are limited to the device, and playlists won’t sync with the server."
        )

        SettingsSection {
          SettingsRow(title: "Prevent Screen Lock") {
            Menu(settings.screenLockPreventionPreference.description) {
              Button(
                ScreenLockPreventionPreference.never.description,
                action: screenLockPreventionOffPressed
              )
              Button(
                ScreenLockPreventionPreference.always.description,
                action: screenLockPreventionOnPressed
              )
              Button(
                ScreenLockPreventionPreference.onlyIfCharging.description,
                action: screenLockPreventionChargingPressed
              )
            }
          }
        }

        #if !targetEnvironment(macCatalyst) // ok
          SettingsSection {
            navigationLink(.account)
            navigationLink(.displayAndInteraction)
            navigationLink(.library)
            navigationLink(.player)
            navigationLink(.equalizer)
            navigationLink(.swipe)
            navigationLink(.artwork)
          }

          SettingsSection {
            navigationLink(.support)
            navigationLink(.license)
            navigationLink(.xcallback)
          }
        #endif

        SettingsSection(
          content: { EmptyView() },
          footer: "Version \(AppDelegate.version) – Build Number \(AppDelegate.buildNumber)"
        )
        .listSectionSpacing(.custom(10))
      }

    #if targetEnvironment(macCatalyst) // ok
      ZStack {
        list
      }
      .navigationTitle("General")
      .navigationBarTitleDisplayMode(.inline)
    #else
      NavigationStack {
        list
          .contentMargins(.top, 16, for: .scrollContent)
          .navigationTitle("Settings")
          .navigationBarTitleDisplayMode(.inline)
          // All pushes in this stack must be value based. Mixing view based links
          // (NavigationLink(destination:)) with the value based links of the sub pages
          // results in a navigation loop.
          .navigationDestination(for: NavigationTarget.self) { item in
            AnyView(item.view())
          }
      }
    #endif
  }
}

// MARK: - SettingsView_Previews

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}

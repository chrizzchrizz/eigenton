//
//  AppDelegatePlayQueueSyncExtension.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 28.10.26.
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

import AmperfyKit
import Foundation
import UIKit

extension AppDelegate {
  private var activePlayQueueSyncer: PlayQueueSyncer? {
    guard let accountInfo = storage.settings.accounts.active else { return nil }
    return getMeta(accountInfo).activePlayQueueSyncer
  }

  /// Ampache has no play queue on the server; whether the Subsonic server supports it is only
  /// known after the first request, the action reports it then.
  var isContinuePlaybackAvailable: Bool {
    guard storage.settings.user.isPlayQueueSyncEnabled, storage.settings.user.isOnlineMode,
          let accountInfo = storage.settings.accounts.active
    else { return false }
    return storage.main.library.getAccount(info: accountInfo).apiType != .ampache
  }

  func createContinuePlaybackAction(presentingVC: UIViewController? = nil) -> UIAction {
    UIAction(title: "Sync Play Queue", image: .continuePlayback) { _ in
      self.continuePlaybackFromOtherDevice(presentingVC: presentingVC)
    }
  }

  /// Saves the play queue of all accounts before the app moves to the background.
  func savePlayQueueBeforeBackground() {
    guard storage.settings.user.isPlayQueueSyncEnabled else { return }
    let syncers = storage.settings.accounts.allAccounts.compactMap {
      getMeta($0).activePlayQueueSyncer
    }
    guard !syncers.isEmpty else { return }
    var backgroundTask = UIBackgroundTaskIdentifier.invalid
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save Play Queue") {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
    Task { @MainActor in
      for syncer in syncers {
        await syncer.saveNow()
      }
      guard backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }

  /// Loads the play queue another device saved and asks before it replaces the current queue.
  func continuePlaybackFromOtherDevice(presentingVC: UIViewController? = nil) {
    guard let syncer = activePlayQueueSyncer else { return }
    // without a connection the server would seem to have no saved queue
    guard networkMonitor.isConnectedToNetwork else {
      presentContinuePlayback(
        .message(
          title: "No Connection",
          message: "The saved play queue can only be loaded from the server with a network connection.",
          systemImage: "wifi.slash"
        ),
        presentingVC: presentingVC
      )
      return
    }
    Task { @MainActor in
      do {
        guard try await syncer.isContinuePlaybackAvailable() else {
          presentContinuePlayback(
            .message(
              title: "Not Supported",
              message: "The server doesn't store a play queue.",
              systemImage: "xmark.icloud"
            ),
            presentingVC: presentingVC
          )
          return
        }
        guard let playQueue = try await syncer.requestServerPlayQueue(),
              !playQueue.songs.isEmpty
        else {
          presentContinuePlayback(
            .message(
              title: "No Saved Play Queue",
              message: "No device has saved a play queue on the server yet.",
              systemImage: "music.note.list"
            ),
            presentingVC: presentingVC
          )
          return
        }
        guard !syncer.isSavedByThisDevice(playQueue) else {
          presentContinuePlayback(
            .message(
              title: "No Other Device",
              message: "The saved play queue is the one of this device. Play something on the other device first.",
              systemImage: "laptopcomputer.and.iphone"
            ),
            presentingVC: presentingVC
          )
          return
        }
        var deviceName: String?
        if let changedBy = playQueue.info.changedBy, !changedBy.isEmpty {
          deviceName = Self.deviceName(clientName: changedBy)
        }
        presentContinuePlayback(
          .playQueue(playQueue, deviceName: deviceName) {
            syncer.continuePlayback(of: playQueue)
          },
          presentingVC: presentingVC
        )
      } catch {
        eventLogger.report(topic: "Sync Play Queue", error: error, displayPopup: false)
        presentContinuePlayback(
          .message(
            title: "Sync Play Queue Failed",
            message: error.localizedDescription,
            systemImage: "exclamationmark.triangle"
          ),
          presentingVC: presentingVC
        )
      }
    }
  }

  /// "Amperfy (iPhone)" -> "iPhone", other clients are shown as they are.
  private static func deviceName(clientName: String) -> String {
    guard clientName.hasPrefix("Amperfy ("), clientName.hasSuffix(")") else { return clientName }
    return String(clientName.dropFirst("Amperfy (".count).dropLast())
  }

  private func presentContinuePlayback(
    _ content: ContinuePlaybackSheetVC.Content,
    presentingVC: UIViewController?
  ) {
    // a repeated tap while the request ran must not stack a second sheet
    guard !(Self.topViewController() is ContinuePlaybackSheetVC) else { return }
    present(sheet: ContinuePlaybackSheetVC(content: content), on: presentingVC)
  }

  /// The view controller of the menu may be gone after the request.
  private func present(sheet: UIViewController, on presentingVC: UIViewController?) {
    if let presentingVC, presentingVC.viewIfLoaded?.window != nil,
       presentingVC.presentedViewController == nil {
      presentingVC.present(sheet, animated: true)
    } else {
      Self.topViewController()?.present(sheet, animated: true)
    }
  }
}

//
//  SyncVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 09.03.19.
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

import AmperfyKit
import Foundation
import SwiftUI
import UIKit

// MARK: - SyncVC

class SyncVC: UIViewController {
  var state: ParsedObjectType = .genre
  var parsedObjectCount: Int = 0
  var parsedObjectPercent: Float = 0.0
  var libObjectsToParseCount: Int = 1
  var syncFinished = false
  var account: Account!
  private var syncTask: Task<(), Never>?

  private let progressModel = SyncProgressModel(steps: SyncProgressModel.initialSyncSteps)

  private lazy var hostingController: UIHostingController<SyncView> = {
    let rootView = SyncView(
      model: progressModel,
      theme: appDelegate.storage.settings.accounts.getSetting(account.info).read.themePreference,
      onSkip: { [weak self] in self?.skipPressed() }
    )
    return UIHostingController(rootView: rootView)
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    if let credentials = appDelegate.storage.settings.accounts.getSetting(account.info).read
      .loginCredentials {
      progressModel.serverUrl = credentials.displayServerUrl
      progressModel.username = credentials.username
    }

    addChild(hostingController)
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    hostingController.view.backgroundColor = .clear
    view.addSubview(hostingController.view)
    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    hostingController.didMove(toParent: self)

    appDelegate.isKeepScreenAlive = true
  }

  override func viewDidAppear(_ animated: Bool) {
    // Called again after a cancelled swipe on the sheet: only one sync, the one Skip cancels
    guard syncTask == nil else { return }
    syncTask = Task { @MainActor in
      self.appDelegate.eventLogger.supressAlerts = true
      let isResumingSync = self.appDelegate.storage.settings.accounts.getSetting(account.info)
        .read.isInitialSyncResumable
      if !isResumingSync {
        // Not on a resume: a resume keeps isLibrarySynced as it was. When it is set, other windows
        // open the partial library and a killed resume goes through SceneDelegate's check again
        if self.appDelegate.storage.settings.accounts.allAccounts.count <= 1 {
          self.appDelegate.storage.settings.app.isLibrarySynced = false
        }
        self.appDelegate.storage.settings.accounts.updateSetting(account.info) {
          $0.clearInitialSyncCheckpoint()
        }
        self.appDelegate.storage.main.library
          .cleanStorageOfObsoleteAccountEntries(account: account)
      }
      self.appDelegate.storage.settings.accounts.updateSetting(account.info) { accountSettings in
        accountSettings.initialSyncCompletionStatus = .aborted
      }

      do {
        try await self.appDelegate.getMeta(account.info).librarySyncer
          .syncInitial(statusNotifyier: self)
        // Skip already finished the sync and stored .skipped: a sync that still completed
        // afterwards must not overwrite it
        guard !self.syncFinished else { return }
        self.appDelegate.storage.settings.accounts.updateSetting(account.info) { accountSettings in
          accountSettings.initialSyncCompletionStatus = .completed
        }
        self.finishSync()
      } catch {
        guard !self.syncFinished else { return }
        self.appDelegate.eventLogger.report(
          topic: "Initial Sync",
          error: error,
          displayPopup: false
        )
        self.appDelegate.storage.settings.accounts.updateSetting(account.info) { accountSettings in
          accountSettings.initialSyncCompletionStatus = .aborted
        }
        self.finishSync()
      }
    }
  }

  /// `cancelledSyncTask`: the account's background managers start only once this skipped sync has
  /// ended, so they don't write to the library while its last step still does
  private func finishSync(cancelledSyncTask: Task<(), Never>? = nil) {
    guard !syncFinished else { return }

    syncFinished = true
    progressModel.finish()

    appDelegate.storage.settings.app.librarySyncVersion = .newestVersion
    appDelegate.storage.settings.app.isLibrarySynced = true
    appDelegate.startManagerAfterSync()
    if let cancelledSyncTask {
      let account = account!
      Task { @MainActor in
        await cancelledSyncTask.value
        // the account may have been switched or logged out meanwhile
        guard self.appDelegate.storage.settings.accounts.active == account.info else { return }
        self.appDelegate.getMeta(account.info)
          .startManagerAfterSync(player: self.appDelegate.player)
      }
    } else {
      appDelegate.getMeta(account.info).startManagerAfterSync(player: appDelegate.player)
    }
    appDelegate.isKeepScreenAlive = false
    appDelegate.eventLogger.supressAlerts = false

    appDelegate
      .setAppTheme(
        color: appDelegate.storage.settings.accounts.getSetting(account.info).read
          .themePreference.asColor
      )
    appDelegate.applyAppThemeToAlreadyLoadedViews()
    guard let mainScene = AppDelegate.mainSceneDelegate else { return }
    mainScene
      .replaceMainRootViewController(vc: AppStoryboard.Main.segueToMainWindow(account: account))
  }

  private func skipPressed() {
    let alert = UIAlertController(
      title: "Skip Sync",
      message: "Skipping initial sync results in an incomplete library. Missing library elements can later be synced via various search/update functionalities.",
      preferredStyle: .alert
    )
    let skip = UIAlertAction(title: "Skip", style: .destructive, handler: { action in
      self.syncTask?.cancel()
      self.appDelegate.storage.settings.accounts
        .updateSetting(self.account.info) { accountSettings in
          accountSettings.initialSyncCompletionStatus = .skipped
          accountSettings.clearInitialSyncCheckpoint()
        }
      self.finishSync(cancelledSyncTask: self.syncTask)
    })
    let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
    alert.addAction(skip)
    alert.addAction(cancel)
    present(alert, animated: true, completion: nil)
  }
}

// MARK: SyncCallbacks

extension SyncVC: SyncCallbacks {
  nonisolated func notifyParsedObject(ofType parsedObjectType: ParsedObjectType) {
    Task { @MainActor in
      guard parsedObjectType == state else {
        return
      }
      self.parsedObjectCount += 1

      var parsePercent: Float = 0.0
      if self.libObjectsToParseCount > 0 {
        parsePercent = min(Float(self.parsedObjectCount) / Float(self.libObjectsToParseCount), 1.0)
      }
      let percentDiff = Int(parsePercent * 1000) - Int(self.parsedObjectPercent * 1000)
      // Steps without a known total count keep showing the spinner only
      if percentDiff > 0, self.progressModel.progress != nil {
        self.progressModel.progress = parsePercent
      }
      self.parsedObjectPercent = parsePercent
    }
  }

  nonisolated func notifySyncStarted(ofType parsedObjectType: ParsedObjectType, totalCount: Int) {
    Task { @MainActor in
      self.parsedObjectCount = 0
      self.parsedObjectPercent = 0.0
      self.state = parsedObjectType
      self.libObjectsToParseCount = totalCount > 0 ? totalCount : 1
      // Only runs (as first step) if files of this account are already cached on the device
      self.progressModel.start(
        step: parsedObjectType.syncStepTitle,
        totalCount: totalCount,
        isUnknownStepFirst: true
      )
    }
  }
}

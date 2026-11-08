//
//  UpdateVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 25.04.24.
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

// MARK: - UpdateVC

/// Shown once after an app update that needs a longer library update, looks like the initial sync
class UpdateVC: UIViewController {
  var tickCount: Int = 0
  var oprationPercent: Float = 0.0
  var totalTickCount: Int = 1

  private let progressModel = SyncProgressModel()

  private lazy var hostingController: UIHostingController<SyncView> = {
    let theme = appDelegate.storage.settings.accounts.active.map {
      appDelegate.storage.settings.accounts.getSetting($0).read.themePreference
    } ?? .defaultValue
    let rootView = SyncView(
      model: progressModel,
      theme: theme,
      title: "Updating your Library",
      footnote: "This only happens once after an app update.",
      onSkip: nil
    )
    return UIHostingController(rootView: rootView)
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    if let accountInfo = appDelegate.storage.settings.accounts.active,
       let credentials = appDelegate.storage.settings.accounts.getSetting(accountInfo).read
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
    appDelegate.eventLogger.supressAlerts = true

    Task { @MainActor in
      do {
        try await self.appDelegate.libraryUpdater.performLibraryUpdateWithStatus(notifier: self)
      } catch {
        // cancle and do nothing
      }
      self.progressModel.finish()

      self.appDelegate.isKeepScreenAlive = false
      self.appDelegate.eventLogger.supressAlerts = false
      self.appDelegate.startManagerForNormalOperation()

      guard let mainScene = AppDelegate.mainSceneDelegate else { return }
      if let accountInfo = self.appDelegate.storage.settings.accounts.active {
        let account = self.appDelegate.storage.main.library.getAccount(info: accountInfo)
        mainScene
          .replaceMainRootViewController(vc: AppStoryboard.Main.segueToMainWindow(account: account))
      } else {
        mainScene.replaceMainRootViewController(vc: AppStoryboard.Main.segueToLogin())
      }
    }
  }
}

// MARK: LibraryUpdaterCallbacks

extension UpdateVC: LibraryUpdaterCallbacks {
  nonisolated func startOperation(name: String, totalCount: Int) {
    Task { @MainActor in
      self.tickCount = 0
      self.oprationPercent = 0.0
      self.totalTickCount = totalCount > 0 ? totalCount : 1
      self.progressModel.start(step: name, totalCount: totalCount)
    }
  }

  nonisolated func tickOperation() {
    Task { @MainActor in
      tickCount += 1
      var parsePercent: Float = 0.0
      if self.totalTickCount > 0 {
        parsePercent = min(Float(self.tickCount) / Float(self.totalTickCount), 1.0)
      }
      let percentDiff = Int(parsePercent * 1000) - Int(self.oprationPercent * 1000)
      // Steps without a known total count keep showing the spinner only
      if percentDiff > 0, self.progressModel.progress != nil {
        self.progressModel.progress = parsePercent
      }
      self.oprationPercent = parsePercent
    }
  }
}

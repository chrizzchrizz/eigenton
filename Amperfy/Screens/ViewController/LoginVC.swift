//
//  LoginVC.swift
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
import Network
import SwiftUI
import UIKit

extension String {
  var isHyperTextProtocolProvided: Bool {
    hasPrefix("https://") || hasPrefix("http://")
  }
}

// MARK: - LocalNetworkAuthorization

/// Triggers the local network permission prompt by browsing for a Bonjour service.
/// iOS only asks on the first local network access, which would otherwise be the login request itself.
@MainActor
final class LocalNetworkAuthorization {
  static let shared = LocalNetworkAuthorization()
  // Must be listed in NSBonjourServices in Info.plist
  private static let serviceType = "_eigenton-lnp._tcp"

  private(set) var isDenied = false
  private var browser: NWBrowser?

  func trigger() {
    guard browser == nil else { return }
    let browser = NWBrowser(
      for: .bonjour(type: Self.serviceType, domain: nil),
      using: NWParameters()
    )
    browser.stateUpdateHandler = { [weak self] state in
      MainActor.assumeIsolated {
        guard let self else { return }
        switch state {
        case let .waiting(error):
          self.isDenied = error == .dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))
        case .ready:
          self.isDenied = false
        case .failed:
          self.stop()
        default:
          break
        }
      }
    }
    browser.start(queue: .main)
    self.browser = browser
  }

  func stop() {
    browser?.cancel()
    browser = nil
  }
}

// MARK: - LoginVC

class LoginVC: UIViewController {
  private let formModel = LoginFormModel()

  private lazy var hostingController: UIHostingController<LoginView> = {
    let rootView = LoginView(
      model: formModel,
      theme: appDelegate.storage.settings.accounts.getSetting(nil).read.themePreference,
      onLogin: { [weak self] in self?.login() },
      onClose: { [weak self] in self?.closePressed() }
    )
    return UIHostingController(rootView: rootView)
  }()

  private var isModal: Bool {
    presentingViewController != nil || navigationController?.presentingViewController != nil
  }

  func closePressed() {
    // Dismiss when presented modally (e.g., as a sheet)
    if isModal {
      dismiss(animated: true)
    }
  }

  func login() {
    guard !formModel.isLoggingIn else { return }
    let serverUrl = formModel.serverUrl
    guard !serverUrl.isEmpty else {
      showErrorMsg(message: "No server URL given!")
      return
    }
    let username = formModel.username
    guard !username.isEmpty else {
      showErrorMsg(message: "No username given!")
      return
    }
    let password = formModel.password
    guard !password.isEmpty else {
      showErrorMsg(message: "No password given!")
      return
    }

    var credentials = LoginCredentials(serverUrl: serverUrl, username: username, password: password)
    credentials.httpHeaders = formModel.httpHeaders
    var accountInfo = Account.createInfo(credentials: credentials)

    guard !appDelegate.storage.settings.accounts.allAccounts.contains(where: { $0 == accountInfo })
    else {
      showErrorMsg(message: "Account already added!")
      return
    }

    formModel.isLoggingIn = true
    Task { @MainActor in
      defer { self.formModel.isLoggingIn = false }
      do {
        let meta = self.appDelegate.getMeta(accountInfo)
        let authenticatedApiType = try await meta.backendApi.login(
          apiType: formModel.apiType,
          credentials: credentials
        )
        credentials.backendApi = authenticatedApiType
        accountInfo = Account.createInfo(credentials: credentials)
        meta.backendApi.selectedApi = authenticatedApiType
        meta.account.assignInfo(info: accountInfo)
        self.appDelegate.storage.main.saveContext()
        self.appDelegate.storage.settings.accounts.login(credentials)
        if meta.backendApi.isScrobbleOfStreamedSongsNeeded {
          // otherwise streamed songs would never count as played on the server
          self.appDelegate.storage.settings.accounts.updateSetting(accountInfo) {
            $0.isScrobbleStreamedItems = true
          }
        }
        meta.backendApi.provideCredentials(credentials: credentials)

        self.appDelegate.notificationHandler.post(name: .accountAdded, object: nil, userInfo: nil)
        self.appDelegate.notificationHandler.post(
          name: .accountActiveChanged,
          object: nil,
          userInfo: nil
        )
        AmperfyAppShortcuts.updateAppShortcutParameters()

        let syncVC = AppStoryboard.Main.segueToSync(account: meta.account)
        if let rootVC = presentingViewController {
          syncVC.modalPresentationStyle = self.modalPresentationStyle
          rootVC.dismiss(animated: false) {
            rootVC.present(syncVC, animated: false)
          }
        } else {
          guard let mainScene = AppDelegate.mainSceneDelegate else { return }
          mainScene
            .replaceMainRootViewController(vc: syncVC)
        }
      } catch {
        if error is AuthenticationError {
          self.showErrorMsg(message: error.localizedDescription)
        } else if LocalNetworkAuthorization.shared.isDenied {
          self.showErrorMsg(
            message: "Not able to login! Access to the local network is denied. If your server is in your local network, allow access in Settings > Privacy & Security > Local Network."
          )
        } else {
          self.showErrorMsg(message: "Not able to login!")
        }
        self.appDelegate.resetMeta(accountInfo)
      }
    }
  }

  func showErrorMsg(message: String) {
    let alert = UIAlertController(title: "Login failed", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true, completion: nil)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

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

    if let credentials = appDelegate.storage.settings.accounts.getSetting(nil).read
      .loginCredentials {
      formModel.prefill(serverUrl: credentials.serverUrl)
      formModel.username = credentials.username
      formModel.httpHeaders = credentials.httpHeaders
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // Show close button only when presented as a sheet/modal
    #if targetEnvironment(macCatalyst)
      // the SwiftUI button gets no clicks inside the form sheet on the Mac: use a bar button
      formModel.isModal = false
      if isModal {
        // the invisible navigation bar would push the centered form down by its height
        hostingController.safeAreaRegions = []
        navigationItem.rightBarButtonItem = UIBarButtonItem(
          systemItem: .close,
          primaryAction: UIAction { [weak self] _ in self?.closePressed() }
        )
      }
    #else
      formModel.isModal = isModal
    #endif
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    LocalNetworkAuthorization.shared.trigger()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    LocalNetworkAuthorization.shared.stop()
  }
}

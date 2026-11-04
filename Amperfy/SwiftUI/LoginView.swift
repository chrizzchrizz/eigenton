//
//  LoginView.swift
//  Amperfy
//
//  Created by Chrizz Gelbach on 21.10.26.
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
import SwiftUI

// MARK: - ServerUrlScheme

enum ServerUrlScheme: String, CaseIterable, Identifiable {
  case https = "https://"
  case http = "http://"

  var id: String { rawValue }
}

// MARK: - LoginFormModel

@MainActor
@Observable
final class LoginFormModel {
  var scheme: ServerUrlScheme = .https
  /// Server address without scheme
  var address = "" {
    didSet { extractScheme() }
  }

  var username = ""
  var password = ""
  var apiType: BackenApiType = .notDetected
  var httpHeaders: [String: String] = [:]
  var isModal = false
  var isLoggingIn = false

  var serverUrl: String {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "" : scheme.rawValue + trimmed
  }

  func prefill(serverUrl: String) {
    address = serverUrl
  }

  /// A typed or pasted URL that contains a scheme selects it in the menu and drops it from the text.
  private func extractScheme() {
    for scheme in ServerUrlScheme.allCases {
      if let range = address.range(of: scheme.rawValue, options: [.anchored, .caseInsensitive]) {
        self.scheme = scheme
        address.removeSubrange(range)
        return
      }
    }
  }
}

// MARK: - LoginView

struct LoginView: View {
  private enum Field: Hashable {
    case address
    case username
    case password
  }

  private static let maxFormWidth: CGFloat = 400
  #if targetEnvironment(macCatalyst)
    private static let fieldHeight: CGFloat = 40
    // Centered in the window while the form fits, scrollable from the top otherwise
    private static let formAlignment = UnitPoint.center
  #else
    private static let fieldHeight: CGFloat = 48
    private static let formAlignment = UnitPoint.top
  #endif
  private static let titleFont = Font.title
  private static let fieldFont = Font.body
  private static let secondaryButtonFont = Font.body
  private static let loginButtonFont = Font.headline
  private static let apiTypes: [BackenApiType] = [
    .notDetected,
    .ampache,
    .subsonic,
    .subsonic_legacy,
  ]

  @Bindable
  var model: LoginFormModel
  let theme: ThemePreference
  let onLogin: () -> ()
  let onClose: () -> ()

  @FocusState
  private var focusedField: Field?
  @State
  private var isHttpHeadersEditorShown = false

  private var themeColor: Color {
    theme.asSwiftUIColor
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 0) {
          header
            .padding(.bottom, 32)
          VStack(spacing: 24) {
            credentialsGroup
            httpHeadersButton
          }
          loginButton
            .padding(.top, 32)
        }
        .frame(maxWidth: Self.maxFormWidth)
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
      }
      .defaultScrollAnchor(Self.formAlignment, for: .alignment)
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: focusedField) { _, field in
        guard let field else { return }
        withAnimation {
          proxy.scrollTo(field, anchor: .center)
        }
      }
    }
    .background { background }
    .overlay(alignment: .topTrailing) {
      if model.isModal {
        closeButton
      }
    }
    .sheet(isPresented: $isHttpHeadersEditorShown) {
      NavigationStack {
        CustomHTTPHeadersView(headers: model.httpHeaders) { updated in
          model.httpHeaders = updated
        }
        .toolbar {
          // Headers are applied on every change, so closing is all that is left to do.
          // Needed on macOS, where a sheet cannot be swiped down.
          ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) {
              isHttpHeadersEditorShown = false
            }
            .keyboardShortcut(.cancelAction)
          }
        }
      }
    }
  }

  private var background: some View {
    // Grouped background keeps the white fields distinguishable
    Color(.systemGroupedBackground)
      .ignoresSafeArea()
  }

  private var header: some View {
    VStack(spacing: 24) {
      Image("LoginLogo")
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 107, height: 92)
        .foregroundStyle(themeColor)
        .accessibilityHidden(true)
      Text("Connect with your library")
        .font(Self.titleFont)
        .fontWeight(.semibold)
        .multilineTextAlignment(.center)
    }
  }

  /// URL, username, password and API share one card, separated by hairlines
  private var credentialsGroup: some View {
    VStack(spacing: 0) {
      serverUrlField
        .id(Field.address)
      rowDivider
      usernameField
        .id(Field.username)
      rowDivider
      passwordField
        .id(Field.password)
      rowDivider
      apiTypePicker
    }
    .background(
      Color("LoginFieldBackground"),
      in: RoundedRectangle(cornerRadius: Self.fieldHeight / 3, style: .continuous)
    )
  }

  private var rowDivider: some View {
    Divider()
      .padding(.horizontal, 16)
  }

  private var serverUrlField: some View {
    HStack(spacing: 0) {
      Menu {
        Picker("Protocol", selection: $model.scheme) {
          ForEach(ServerUrlScheme.allCases) { scheme in
            Text(scheme.rawValue).tag(scheme)
          }
        }
        // Inline keeps the options at the top level of the menu (macOS would show a submenu otherwise)
        .pickerStyle(.inline)
        .labelsHidden()
      } label: {
        HStack(spacing: 8) {
          Text(model.scheme.rawValue)
            .font(Self.fieldFont)
            .foregroundStyle(.primary)
          Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Protocol")
      .accessibilityValue(model.scheme.rawValue)

      Rectangle()
        .fill(Color(.separator))
        .frame(width: 1, height: 30)

      TextField("Enter URL", text: $model.address)
        .textContentType(.URL)
        .keyboardType(.URL)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .submitLabel(.next)
        .focused($focusedField, equals: .address)
        .onSubmit { focusedField = .username }
        .padding(.leading, 16)
        .padding(.trailing, 16)
    }
    .font(Self.fieldFont)
    .frame(minHeight: Self.fieldHeight)
  }

  private var usernameField: some View {
    TextField("Username", text: $model.username)
      .textContentType(.username)
      .autocorrectionDisabled()
      .textInputAutocapitalization(.never)
      .submitLabel(.next)
      .focused($focusedField, equals: .username)
      .onSubmit { focusedField = .password }
      .font(Self.fieldFont)
      .padding(.horizontal, 16)
      .frame(minHeight: Self.fieldHeight)
  }

  private var passwordField: some View {
    SecureField("Password", text: $model.password)
      .textContentType(.password)
      .autocorrectionDisabled()
      .textInputAutocapitalization(.never)
      .submitLabel(.go)
      .focused($focusedField, equals: .password)
      .onSubmit(login)
      .font(Self.fieldFont)
      .padding(.horizontal, 16)
      .frame(minHeight: Self.fieldHeight)
  }

  private var apiTypePicker: some View {
    Menu {
      Picker("Select API", selection: $model.apiType) {
        ForEach(Self.apiTypes, id: \.self) { apiType in
          Text(apiType.selectorDescription).tag(apiType)
        }
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      HStack {
        Text(model.apiType.selectorDescription)
          .foregroundStyle(.primary)
        Spacer()
        Image(systemName: "chevron.down")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .font(Self.fieldFont)
      .padding(.horizontal, 16)
      .frame(minHeight: Self.fieldHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("API")
    .accessibilityValue(model.apiType.selectorDescription)
  }

  private var httpHeadersButton: some View {
    Button {
      isHttpHeadersEditorShown = true
    } label: {
      Text("Custom HTTP Headers")
        .font(Self.secondaryButtonFont)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Self.fieldHeight)
        .background(Color("LoginFieldBackground"), in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private var loginButtonLabel: some View {
    ZStack {
      Text("Log In")
        .opacity(model.isLoggingIn ? 0 : 1)
      if model.isLoggingIn {
        ProgressView()
          .tint(Color(uiColor: theme.contrastColor))
      }
    }
    .font(Self.loginButtonFont)
    .foregroundStyle(Color(uiColor: theme.contrastColor))
    .frame(maxWidth: .infinity)
  }

  private var loginButton: some View {
    #if targetEnvironment(macCatalyst)
      // a large bordered button is much lower on the Mac: as high as the fields instead
      Button(action: login) {
        loginButtonLabel
          .frame(minHeight: Self.fieldHeight)
          .background(themeColor, in: Capsule())
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .disabled(model.isLoggingIn)
      .keyboardShortcut(.defaultAction)
    #else
      Button(action: login) {
        loginButtonLabel
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .controlSize(.large)
      .tint(themeColor)
      .disabled(model.isLoggingIn)
      .keyboardShortcut(.defaultAction)
    #endif
  }

  private var closeButton: some View {
    Button(action: onClose) {
      Image(systemName: "xmark")
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .controlSize(.large)
    .accessibilityLabel("Close")
    .padding(16)
  }

  private func login() {
    focusedField = nil
    onLogin()
  }
}

#Preview {
  LoginView(
    model: LoginFormModel(),
    theme: .eigenton,
    onLogin: {},
    onClose: {}
  )
}

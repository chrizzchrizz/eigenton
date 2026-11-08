//
//  SyncView.swift
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

// MARK: - SyncProgressModel

@MainActor
@Observable
final class SyncProgressModel {
  enum StepStatus {
    case done
    case current
    case pending
  }

  /// Step titles in the order they run
  private(set) var steps: [String]
  private(set) var currentStep: String?
  /// nil while the total count of the current step is unknown
  var progress: Float?
  private(set) var isFinished = false

  var serverUrl = ""
  var username = ""

  /// - Parameter steps: The steps known in advance. Others are added when they start.
  init(steps: [String] = []) {
    self.steps = steps
  }

  /// Order in which the backends run the initial sync
  static let initialSyncSteps = [ParsedObjectType]([.genre, .artist, .album, .playlist, .podcast])
    .map { $0.syncStepTitle }

  /// - Parameter isUnknownStepFirst: Add a step that is not known yet in front of the others
  ///   instead of after them.
  func start(step: String, totalCount: Int, isUnknownStepFirst: Bool = false) {
    guard !steps.contains(step) else {
      currentStep = step
      progress = totalCount > 0 ? 0 : nil
      return
    }
    // A new row appears without animation, the card would grow from a smaller frame otherwise
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      if isUnknownStepFirst {
        steps.insert(step, at: 0)
      } else {
        steps.append(step)
      }
      currentStep = step
      progress = totalCount > 0 ? 0 : nil
    }
  }

  func finish() {
    isFinished = true
    currentStep = nil
    progress = nil
  }

  func status(of step: String) -> StepStatus {
    if isFinished { return .done }
    guard let currentStep,
          let currentIndex = steps.firstIndex(of: currentStep),
          let index = steps.firstIndex(of: step)
    else { return .pending }
    if index < currentIndex { return .done }
    return index == currentIndex ? .current : .pending
  }
}

// MARK: - SyncView

struct SyncView: View {
  private static let maxFormWidth: CGFloat = 400
  #if targetEnvironment(macCatalyst)
    private static let rowHeight: CGFloat = 40
    private static let formAlignment = UnitPoint.center
  #else
    private static let rowHeight: CGFloat = 48
    private static let formAlignment = UnitPoint.top
  #endif
  private static let titleFont = Font.title2
  private static let rowFont = Font.body
  private static let skipButtonFont = Font.body
  private static let statusIconWidth: CGFloat = 22
  private static let statusIconSpacing: CGFloat = 12

  var model: SyncProgressModel
  let theme: ThemePreference
  var title = "Setting up your Library"
  var footnote = "Large libraries can take a few minutes to sync."
  /// Hides the skip button if nil
  var onSkip: (() -> ())?

  private var themeColor: Color {
    theme.asSwiftUIColor
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        header
          .padding(.bottom, 32)
        if model.steps.isEmpty, !model.isFinished {
          // Before the first step starts, e.g. while the update fetches what it has to do
          ProgressView()
            .tint(themeColor)
            .frame(height: Self.rowHeight)
        } else {
          stepsGroup
        }
        Text(footnote)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.top, 16)
      }
      .frame(maxWidth: Self.maxFormWidth)
      .padding(.horizontal, 20)
      .padding(.top, 32)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity)
    }
    .defaultScrollAnchor(Self.formAlignment, for: .alignment)
    .scrollBounceBehavior(.basedOnSize)
    .safeAreaInset(edge: .bottom) {
      if let onSkip {
        skipButton(action: onSkip)
          .frame(maxWidth: Self.maxFormWidth)
          .padding(.horizontal, 20)
          .padding(.bottom, 20)
          .frame(maxWidth: .infinity)
      }
    }
    .background { background }
  }

  private var background: some View {
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
      VStack(spacing: 6) {
        Text(title)
          .font(Self.titleFont)
          .fontWeight(.semibold)
          .multilineTextAlignment(.center)
        Text([model.serverUrl, model.username].filter { !$0.isEmpty }.joined(separator: " · "))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)
      }
    }
  }

  /// All sync steps share one card, separated by hairlines
  private var stepsGroup: some View {
    VStack(spacing: 0) {
      ForEach(Array(model.steps.enumerated()), id: \.element) { index, step in
        if index > 0 {
          Divider()
            .padding(.horizontal, 16)
        }
        stepRow(step)
      }
    }
    .background(
      Color("LoginFieldBackground"),
      in: RoundedRectangle(cornerRadius: Self.rowHeight / 3, style: .continuous)
    )
    .animation(.default, value: model.currentStep)
    .animation(.default, value: model.isFinished)
  }

  private func stepRow(_ step: String) -> some View {
    let status = model.status(of: step)
    let progress = status == .current ? model.progress : nil
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: Self.statusIconSpacing) {
        statusIcon(status)
          .frame(width: Self.statusIconWidth)
        Text(step)
          .foregroundStyle(status == .pending ? .secondary : .primary)
        Spacer()
        if let progress {
          Text("\(Int(progress * 100)) %")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
      .font(Self.rowFont)
      .frame(height: Self.rowHeight)
      if let progress {
        ProgressView(value: progress)
          .tint(themeColor)
          .padding(.leading, Self.statusIconWidth + Self.statusIconSpacing)
          .padding(.bottom, 14)
      }
    }
    .padding(.horizontal, 16)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func statusIcon(_ status: SyncProgressModel.StepStatus) -> some View {
    switch status {
    case .done:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(themeColor)
        .accessibilityLabel("Done")
    case .current:
      ProgressView()
        .controlSize(.small)
        .tint(themeColor)
    case .pending:
      Image(systemName: "circle")
        .foregroundStyle(.tertiary)
        .accessibilityLabel("Pending")
    }
  }

  private func skipButton(action: @escaping () -> ()) -> some View {
    Button(action: action) {
      Text("Skip Sync")
        .font(Self.skipButtonFont)
        .fontWeight(.semibold)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(height: Self.rowHeight)
        .background(Color("LoginFieldBackground"), in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(model.isFinished)
  }
}

extension ParsedObjectType {
  /// Title of the initial sync step
  var syncStepTitle: String {
    switch self {
    case .artist: "Artists"
    case .album: "Albums"
    case .song: "Songs"
    case .playlist: "Playlists"
    case .genre: "Genres"
    case .podcast: "Podcasts"
    case .cache: "Downloaded Files"
    }
  }
}

#Preview {
  let model = SyncProgressModel(steps: SyncProgressModel.initialSyncSteps)
  model.serverUrl = "music.example.com"
  model.username = "user"
  model.start(step: ParsedObjectType.album.syncStepTitle, totalCount: 100)
  model.progress = 0.42
  return SyncView(model: model, theme: .eigenton, onSkip: {})
}

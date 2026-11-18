//
//  AssistedOptOutStepsPanel.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import DataBrokerProtectionCore
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import SwiftUIExtensions

enum AssistedOptOutStepState: Equatable {
    case done
    case running
    /// A step only the user can do on the page, such as a CAPTCHA.
    case userTurn
    case upcoming

    var accessibilityLabel: String {
        switch self {
        case .done: return AssistedOptOutText.completedStep
        case .running: return AssistedOptOutText.runningStep
        case .userTurn: return AssistedOptOutText.yourTurn
        case .upcoming: return AssistedOptOutText.upcomingStep
        }
    }
}

@MainActor
extension AssistedOptOutSession {
    var stepStates: [AssistedOptOutStepState] {
        steps.titles.indices.map { index in
            if phase == .submitted || index < currentStepIndex { return .done }
            if index > currentStepIndex || phase == .queued || phase == .ready { return .upcoming }
            return phase == .userTurn ? .userTurn : .running
        }
    }

    var isAttemptRunning: Bool {
        switch phase {
        case .queued, .agentInControl, .userTurn: return true
        case .ready, .submitted: return false
        }
    }
}

/// The side panel of the attempt window. It lists the broker's steps with their progress and holds the Stop and close buttons.
@MainActor
struct AssistedOptOutStepsPanel: View {
    @Environment(\.designSystemPalette) private var palette
    @ObservedObject var session: AssistedOptOutSession
    let close: () -> Void
    let loadFavicon: @MainActor (AssistedOptOut.DataBroker) async -> Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if session.phase == .submitted {
                whatHappensNext
            } else {
                steps
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(designSystemColor: .surfaceTertiary, palette: palette))
    }

    private var header: some View {
        HStack(spacing: 12) {
            AssistedOptOutBrokerLogo(broker: session.broker, size: 32, loadFavicon: loadFavicon)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.phase == .submitted ? AssistedOptOutText.submittedTo(session.broker.name) : AssistedOptOutText.removingFrom(session.broker.name))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        switch session.phase {
        case .ready: return AssistedOptOutText.readySubtitle(session.broker.name)
        case .submitted: return AssistedOptOutText.submittedSubtitle
        case .userTurn: return AssistedOptOutText.userSubtitle(session.broker.name)
        case .queued: return AssistedOptOutText.openingBroker(session.broker.name)
        case .agentInControl: return session.currentStepTitle ?? AssistedOptOutText.fillingDetails
        }
    }

    private var steps: some View {
        let states = session.stepStates
        return ScrollView {
            VStack(alignment: .leading, spacing: AssistedOptOutStepRow.spacing) {
                ForEach(Array(session.steps.titles.enumerated()), id: \.offset) { index, title in
                    AssistedOptOutStepRow(title: title, state: states[index], isLast: index == states.count - 1,
                                         userInstruction: session.currentStepTitle.map(AssistedOptOutText.userInstruction) ?? AssistedOptOutText.userInstructionFallback)
                }
                if session.phase == .userTurn, session.currentStepTitle == nil {
                    AssistedOptOutUserTurnCard(instruction: AssistedOptOutText.userInstructionFallback)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var whatHappensNext: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AssistedOptOutText.whatHappensNext)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.clock)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsPrimary, palette: palette))
                Text(AssistedOptOutText.followUp)
                    .font(.system(size: 14))
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if session.isAttemptRunning {
                Text(AssistedOptOutText.closingStops)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textTertiary, palette: palette))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            switch session.phase {
            case .ready:
                Button(AssistedOptOutText.cancel, action: close)
                    .buttonStyle(DismissActionButtonStyle(topPadding: 12, bottomPadding: 12,
                                                         stateColors: .assistedOptOutDismiss(palette: palette)))
            case .submitted:
                Button(AssistedOptOutText.backToDashboard, action: close)
                    .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 12, bottomPadding: 12,
                                                          stateColors: .assistedOptOutAction(palette: palette)))
            case .queued, .agentInControl, .userTurn:
                Button(action: session.requestCancel) {
                    HStack(spacing: 8) {
                        Image(nsImage: DesignSystemImages.Glyphs.Size16.stopSquare)
                            .renderingMode(.template)
                            .accessibilityHidden(true)
                        Text(AssistedOptOutText.stop)
                    }
                }
                .buttonStyle(DismissActionButtonStyle(topPadding: 12, bottomPadding: 12,
                                                     stateColors: .assistedOptOutDismiss(palette: palette)))
            }
        }
    }
}

@MainActor
struct AssistedOptOutBrokerLogo: View {
    @Environment(\.designSystemPalette) private var palette
    let broker: AssistedOptOut.DataBroker
    let size: CGFloat
    let loadFavicon: @MainActor (AssistedOptOut.DataBroker) async -> Data?
    @State private var favicon: NSImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(designSystemColor: .controlsFillPrimary, palette: palette))
            if let favicon {
                let fillsCircle = favicon.size.width >= size
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fillsCircle ? size : size * 0.55, height: fillsCircle ? size : size * 0.55)
            } else {
                Text(broker.name.first.map(String.init) ?? "")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: broker.url) {
            favicon = nil
            guard let data = await loadFavicon(broker), !Task.isCancelled else { return }
            favicon = NSImage(data: data)
        }
    }

    static func faviconData(for broker: AssistedOptOut.DataBroker) async -> Data? {
        guard let host = broker.homeURL?.host,
              let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

@MainActor
private struct AssistedOptOutStepRow: View {
    @Environment(\.designSystemPalette) private var palette
    static let spacing: CGFloat = 14
    private static let markerSize: CGFloat = 18

    let title: String
    let state: AssistedOptOutStepState
    let isLast: Bool
    let userInstruction: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                AssistedOptOutStepMarker(state: state)
                    .frame(width: Self.markerSize, height: Self.markerSize)
                    .accessibilityLabel(state.accessibilityLabel)
                if !isLast {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(designSystemColor: state == .done ? .statusGreen : .containerBorderPrimary, palette: palette))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            .padding(.bottom, isLast ? 0 : -Self.spacing)
            .frame(maxHeight: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: state == .running || state == .userTurn ? .medium : .regular))
                    .foregroundColor(Color(designSystemColor: state == .upcoming ? .textSecondary : .textPrimary, palette: palette))
                    .frame(minHeight: Self.markerSize)
                if state == .userTurn {
                    AssistedOptOutUserTurnCard(instruction: userInstruction)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
private struct AssistedOptOutUserTurnCard: View {
    @Environment(\.designSystemPalette) private var palette
    let instruction: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AssistedOptOutText.yourTurn)
                .font(.system(size: 16))
                .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
            Text(instruction)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .assistedOptOutCallout(palette: palette)
    }
}

@MainActor
private struct AssistedOptOutStepMarker: View {
    @Environment(\.designSystemPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: AssistedOptOutStepState
    @State private var isSpinning = false

    var body: some View {
        switch state {
        case .done:
            Circle()
                .fill(Color(designSystemColor: .statusGreen, palette: palette))
                .overlay(
                    Image(nsImage: DesignSystemImages.Glyphs.Size12.check)
                        .renderingMode(.template)
                        .foregroundColor(Color(designSystemColor: .accentContentPrimary, palette: palette))
                )
        case .running:
            ring(.containerBorderSecondary)
                .overlay(
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Color(designSystemColor: .accentPrimary, palette: palette), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .padding(1)
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                )
                .onAppear {
                    if !reduceMotion {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { isSpinning = true }
                    }
                }
        case .upcoming:
            ring(.containerBorderSecondary)
        case .userTurn:
            ring(.statusYellowPrimary)
                .overlay(Circle().fill(Color(designSystemColor: .statusYellowPrimary, palette: palette)).frame(width: 8, height: 8))
        }
    }

    private func ring(_ color: DesignSystemColor) -> some View {
        Circle()
            .fill(Color(designSystemColor: .surfaceTertiary, palette: palette))
            .overlay(Circle().strokeBorder(Color(designSystemColor: color, palette: palette), lineWidth: 2))
    }
}

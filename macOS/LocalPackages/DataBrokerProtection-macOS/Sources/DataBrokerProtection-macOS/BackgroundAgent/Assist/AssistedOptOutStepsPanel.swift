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

enum AssistedOptOutStepState: Equatable {
    case done
    case running
    case userTurn
    case upcoming
}

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

/// The right-hand side of the assisted opt-out window: the broker's steps, and what the user needs to do.
struct AssistedOptOutStepsPanel: View {
    @ObservedObject var session: AssistedOptOutSession
    let close: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topRow
                .padding(.top, -4)
                .padding(.trailing, -4)
                .padding(.bottom, -8)
            header
            if session.phase == .submitted {
                whatHappensNext
                    .padding(.top, 8)
            } else {
                steps
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(designSystemColor: .surfaceTertiary))
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if session.isAttemptRunning {
                Text("Keeps running if you close")
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textTertiary))
            }
            Button(action: close) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.close)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsPrimary))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color(designSystemColor: .controlsFillPrimary)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(session.isAttemptRunning ? "Close \u{2014} removal keeps running" : "Close")
            .accessibilityLabel("Close")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            AssistedOptOutBrokerLogo(broker: session.broker, size: 56)
            Text(session.phase == .submitted ? "Request submitted to \(session.broker.name)" : "Removing you from \(session.broker.name)")
                .font(.system(size: 22))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(designSystemColor: .containerFillPrimary)))
    }

    private var subtitle: String {
        switch session.phase {
        case .ready: return "When you\u{2019}re ready, we\u{2019}ll fill in \(session.broker.name)\u{2019}s opt-out form. We\u{2019}ll pause whenever we need your help."
        case .submitted: return "Nice work. That\u{2019}s the hard part done."
        case .userTurn: return "We\u{2019}ve paused. \(session.broker.name) needs a person for this step."
        case .queued: return "Opening \(session.broker.name)\u{2026}"
        case .agentInControl: return "Filling in your details."
        }
    }

    private var steps: some View {
        let states = session.stepStates
        return ScrollView {
            VStack(alignment: .leading, spacing: AssistedOptOutStepRow.spacing) {
                ForEach(Array(session.steps.titles.enumerated()), id: \.offset) { index, title in
                    AssistedOptOutStepRow(title: title, state: states[index], isLast: index == states.count - 1)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var whatHappensNext: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What happens next")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.clock)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsPrimary))
                Text("We\u{2019}ll follow up on the request and check your info is gone on our next scan.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
    }

    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            switch session.phase {
            case .ready:
                pill(isDark: false, action: stop) { Text("Cancel") }
            case .submitted:
                pill(isDark: true, action: close) { Text("Back to dashboard") }
            case .queued, .agentInControl, .userTurn:
                pill(isDark: false, action: stop) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .frame(width: 10, height: 10)
                        Text("Stop")
                    }
                }
            }
        }
    }

    private func pill<Label: View>(isDark: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDark ? Color(nsColor: .windowBackgroundColor) : Color(designSystemColor: .textPrimary))
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Capsule().fill(isDark ? Color.primary : Color(designSystemColor: .controlsFillPrimary)))
        }
        .buttonStyle(.plain)
    }
}

/// The broker's favicon, or the first letter of its name when there isn't one.
private struct AssistedOptOutBrokerLogo: View {
    let broker: AssistedOptOut.DataBroker
    let size: CGFloat
    @State private var favicon: NSImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(designSystemColor: .controlsFillPrimary))
            if let favicon {
                // Most favicons are small; scaling those up to fill the circle would blur them.
                let fillsCircle = favicon.size.width >= size
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fillsCircle ? size : size * 0.55, height: fillsCircle ? size : size * 0.55)
            } else {
                Text(broker.name.first.map(String.init) ?? "")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: broker.url) {
            guard let data = await Self.faviconData(for: broker) else { return }
            favicon = NSImage(data: data)
        }
    }

    private static func faviconData(for broker: AssistedOptOut.DataBroker) async -> Data? {
        guard let host = broker.homeURL?.host,
              let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

private struct AssistedOptOutStepRow: View {
    static let spacing: CGFloat = 14
    private static let markerSize: CGFloat = 18

    let title: String
    let state: AssistedOptOutStepState
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                AssistedOptOutStepMarker(state: state)
                    .frame(width: Self.markerSize, height: Self.markerSize)
                if !isLast {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(designSystemColor: state == .done ? .statusGreen : .containerBorderPrimary))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            // The connector runs on through the gap between rows, so it ends at the next row's marker.
            .padding(.bottom, isLast ? 0 : -Self.spacing)
            .frame(maxHeight: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: state == .running || state == .userTurn ? .medium : .regular))
                    .foregroundColor(Color(designSystemColor: state == .upcoming ? .textSecondary : .textPrimary))
                    .frame(minHeight: Self.markerSize)
                if state == .userTurn {
                    yourTurnCard
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var yourTurnCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your turn")
                .font(.system(size: 16))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Text("Complete the highlighted part of the page. We\u{2019}ll carry on as soon as it\u{2019}s done.")
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .assistedOptOutCallout()
    }
}

/// Markers are filled with the panel background, so the connector from the row above never shows through them.
private struct AssistedOptOutStepMarker: View {
    let state: AssistedOptOutStepState
    @State private var isSpinning = false

    var body: some View {
        switch state {
        case .done:
            Circle()
                .fill(Color(designSystemColor: .statusGreen))
                .overlay(
                    Image(nsImage: DesignSystemImages.Glyphs.Size12.check)
                        .renderingMode(.template)
                        .foregroundColor(Color(designSystemColor: .accentContentPrimary))
                )
        case .running:
            ring(.containerBorderSecondary)
                .overlay(
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Color(designSystemColor: .accentPrimary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .padding(1)
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                )
                .onAppear {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { isSpinning = true }
                }
        case .upcoming:
            ring(.containerBorderSecondary)
        case .userTurn:
            ring(.statusYellowPrimary)
                .overlay(Circle().fill(Color(designSystemColor: .statusYellowPrimary)).frame(width: 8, height: 8))
        }
    }

    private func ring(_ color: DesignSystemColor) -> some View {
        Circle()
            .fill(Color(designSystemColor: .surfaceTertiary))
            .overlay(Circle().strokeBorder(Color(designSystemColor: color), lineWidth: 2))
    }
}

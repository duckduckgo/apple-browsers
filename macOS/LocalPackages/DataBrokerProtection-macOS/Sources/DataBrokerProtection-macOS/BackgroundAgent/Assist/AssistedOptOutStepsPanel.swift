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
            if index > currentStepIndex || phase == .queued { return .upcoming }
            return phase == .userTurn ? .userTurn : .running
        }
    }
}

/// The right-hand side of the assisted opt-out window: the broker's steps, and what the user needs to do.
struct AssistedOptOutStepsPanel: View {
    @ObservedObject var session: AssistedOptOutSession
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if session.phase == .submitted {
                whatHappensNext
                    .padding(.top, 24)
            } else {
                steps
                    .padding(.top, 16)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(designSystemColor: .surfaceTertiary))
    }

    private var header: some View {
        VStack(spacing: 12) {
            AssistedOptOutBrokerAvatar(name: session.broker.name, size: 48)
            Text(session.phase == .submitted ? "Request submitted to \(session.broker.name)" : "Removing you from \(session.broker.name)")
                .font(.system(size: 20))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(Color(designSystemColor: .textSecondary))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(designSystemColor: .containerFillPrimary)))
    }

    private var subtitle: String {
        switch session.phase {
        case .submitted: return "Nice work. That\u{2019}s the hard part done."
        case .userTurn: return "We\u{2019}ve paused. \(session.broker.name) needs a person for this step."
        case .queued: return "Waiting for another removal to finish."
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
        VStack(alignment: .trailing, spacing: 8) {
            if session.phase != .submitted {
                Text("Closing this window stops the removal. You can start it again from Personal Information Removal.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: close) {
                Text(session.phase == .submitted ? "Done" : "Stop and close")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Capsule().fill(Color(designSystemColor: .controlsFillPrimary)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Stands in for the broker's logo, which the agent doesn't have.
private struct AssistedOptOutBrokerAvatar: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Text(name.first.map(String.init) ?? "")
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(designSystemColor: .controlsFillPrimary)))
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
                .font(.system(size: 12))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(designSystemColor: .statusWarningFillPrimary)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(designSystemColor: .statusYellowPrimary), lineWidth: 1.5))
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

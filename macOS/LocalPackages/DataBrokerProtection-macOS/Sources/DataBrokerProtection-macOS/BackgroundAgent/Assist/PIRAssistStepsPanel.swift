//
//  PIRAssistStepsPanel.swift
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

#if DEBUG
import DataBrokerProtectionCore
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

/// The right-hand side of the "Removing you from…" window: where the request is, and what the user needs to do.
struct PIRAssistStepsPanel: View {
    @ObservedObject var session: PIRAssistSession
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topRow
            header
            steps
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(designSystemColor: .surfacePrimary))
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            Spacer()
            Text("Keeps running if you close")
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textTertiary))
            Button(action: close) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.close)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsPrimary))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color(designSystemColor: .controlsFillPrimary)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close, the removal keeps running")
        }
    }

    private var header: some View {
        VStack(spacing: session.userTurn == nil ? 12 : 8) {
            Text("Removing you from \(session.brokerName)")
                .font(.system(size: 22))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(Color(designSystemColor: .textTertiary))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(session.userTurn == nil ? 24 : 18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(designSystemColor: .surfaceSecondary)))
    }

    private var subtitle: String {
        if session.userTurn != nil {
            return "We\u{2019}ve paused. \(session.brokerName) needs a person for the next step."
        }
        return "Filling in your details."
    }

    private var steps: some View {
        let steps = session.steps
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    PIRAssistStepRow(step: step, isLast: index == steps.count - 1,
                                     userTurnMessage: userTurnMessage,
                                     userConfirmedDone: session.userConfirmedDone)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var userTurnMessage: String {
        switch session.userTurn {
        case .recaptcha:
            return "Check \u{201C}I\u{2019}m not a robot\u{201D} in the form and we\u{2019}ll fill in the rest."
        case .managedChallenge:
            return "Complete \(session.brokerName)\u{2019}s security check on the page and we\u{2019}ll carry on."
        case .turnstile, .generic, .none:
            return "Complete the security check in the form and we\u{2019}ll fill in the rest."
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: session.stop) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).frame(width: 10, height: 10)
                    Text("Stop")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color(designSystemColor: .controlsFillPrimary)))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PIRAssistStepRow: View {
    let step: PIRAssistStep
    let isLast: Bool
    let userTurnMessage: String
    let userConfirmedDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PIRAssistStepMarker(state: step.state)
                .frame(width: 18, height: 18)
                .overlay(alignment: .top) {
                    if !isLast {
                        Capsule()
                            .fill(Color(designSystemColor: step.state == .done ? .statusGreen : .containerBorderPrimary))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .offset(y: 22)
                    }
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(.system(size: 14, weight: isEmphasized ? .medium : .regular))
                    .foregroundColor(Color(designSystemColor: step.state == .upcoming ? .textTertiary : .textPrimary))
                if step.state == .needsUserLater {
                    needsUserNote
                }
                if step.state == .userTurn {
                    yourTurnCard
                }
            }
        }
    }

    private var isEmphasized: Bool {
        step.state != .done && step.state != .upcoming
    }

    private var needsUserNote: some View {
        Text("You\u{2019}ll prove you\u{2019}re human here")
            .font(.system(size: 12))
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(designSystemColor: .statusWarningFillPrimary)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(designSystemColor: .statusYellowPrimary), lineWidth: 1))
    }

    private var yourTurnCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your turn")
                .font(.system(size: 16))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Text(userTurnMessage)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: userConfirmedDone) {
                Text("I\u{2019}ve done it")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(designSystemColor: .accentContentPrimary))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(designSystemColor: .accentPrimary)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(designSystemColor: .statusWarningFillPrimary)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(designSystemColor: .statusYellowPrimary), lineWidth: 1.5))
    }
}

private struct PIRAssistStepMarker: View {
    let state: PIRAssistStepState
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
            Circle()
                .strokeBorder(Color(designSystemColor: .containerBorderPrimary), lineWidth: 2)
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
            Circle().strokeBorder(Color(designSystemColor: .containerBorderPrimary), lineWidth: 2)
        case .needsUserLater:
            Circle().strokeBorder(Color(designSystemColor: .statusYellowPrimary), lineWidth: 2)
        case .userTurn:
            Circle()
                .strokeBorder(Color(designSystemColor: .statusYellowPrimary), lineWidth: 2)
                .overlay(Circle().fill(Color(designSystemColor: .statusYellowPrimary)).frame(width: 8, height: 8))
        }
    }
}
#endif

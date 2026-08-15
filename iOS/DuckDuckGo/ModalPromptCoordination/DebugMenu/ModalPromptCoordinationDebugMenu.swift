//
//  ModalPromptCoordinationDebugMenu.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import SwiftUI

struct ModalPromptCoordinationDebugView: View {
    @StateObject private var viewModel: ModalPromptCoordinationDebugViewModel

    init(
        diagnosticsProvider: PromoCoordinationDiagnosticsProviding?,
        cooldownResetter: PromoCoordinationCooldownResetting?
    ) {
        self._viewModel = StateObject(
            wrappedValue: ModalPromptCoordinationDebugViewModel(
                diagnosticsProvider: diagnosticsProvider,
                cooldownResetter: cooldownResetter
            )
        )
    }

    var body: some View {
        List {
            Section {
                diagnosticRow(title: "Mode", value: viewModel.modeDescription)
                diagnosticRow(title: "Owner", value: viewModel.ownerDescription)
                diagnosticRow(title: "RMF Appearance Confirmed", value: viewModel.remoteMessageAppearanceDescription)
                Button("Refresh") {
                    viewModel.refresh()
                }
            } header: {
                Text(verbatim: "Promo Queue")
            } footer: {
                Text(verbatim: "Feature flag changes require a relaunch.")
            }

            Section {
                diagnosticRow(title: "Last Modal Appearance", value: viewModel.lastConfirmedModalAppearanceDescription)
                diagnosticRow(title: "Last RMF Appearance", value: viewModel.lastConfirmedRemoteMessageAppearanceDescription)
                diagnosticRow(title: "Next RMF Eligibility", value: viewModel.nextRemoteMessageEligibilityDescription)
                diagnosticRow(title: "Next Modal Eligibility", value: viewModel.nextModalEligibilityDescription)
            } header: {
                Text(verbatim: "Cooldowns")
            } footer: {
                Text(verbatim: "Eligibility dates do not schedule retries.")
            }

            Section {
                Button("Reset Modal Cooldown (Debug Only)", role: .destructive) {
                    viewModel.resetModalCooldown()
                }
                .disabled(!viewModel.canResetCooldowns)

                Button("Reset RMF Cooldown (Debug Only)", role: .destructive) {
                    viewModel.resetRemoteMessageCooldown()
                }
                .disabled(!viewModel.canResetCooldowns)
            } header: {
                Text(verbatim: "Manual Testing")
            } footer: {
                Text(verbatim: "Cooldown resets do not release an active owner or dismiss a message.")
            }
        }
    }

    private func diagnosticRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// Internal debug UI contract; coordination state remains available only through the injected providers.
@MainActor
final class ModalPromptCoordinationDebugViewModel: ObservableObject {
    private enum Text {
        static let unavailable = "Unavailable"
        static let never = "Never"
        static let noCooldownBoundary = "No cooldown boundary"
        static let notApplicable = "Not applicable"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current
        return formatter
    }()

    private let diagnosticsProvider: PromoCoordinationDiagnosticsProviding?
    private let cooldownResetter: PromoCoordinationCooldownResetting?
    private let dateFormatting: (Date) -> String

    @Published private(set) var snapshot: PromoCoordinationDiagnosticSnapshot?

    var canResetCooldowns: Bool {
        cooldownResetter != nil
    }

    var modeDescription: String {
        guard let snapshot else { return Text.unavailable }

        switch snapshot.mode {
        case .legacy:
            return "Legacy"
        case .coordinated:
            return "Coordinated"
        }
    }

    var ownerDescription: String {
        guard let snapshot else { return Text.unavailable }

        switch snapshot.owner {
        case .modal(let ownershipIdentity):
            return "Modal (ownership ID: \(ownershipIdentity.diagnosticDescription))"
        case .remoteMessage(let messageID, let acquisitionIdentity, _):
            return "RMF (message ID: \(messageID), acquisition ID: \(acquisitionIdentity.diagnosticDescription))"
        case nil:
            return "None"
        }
    }

    var remoteMessageAppearanceDescription: String {
        guard let snapshot else { return Text.unavailable }
        guard case .remoteMessage(_, _, let appearanceConfirmed) = snapshot.owner else {
            return Text.notApplicable
        }

        return appearanceConfirmed ? "Yes" : "No"
    }

    var lastConfirmedModalAppearanceDescription: String {
        formattedDate(snapshot?.cooldown.lastConfirmedModalAppearance, nilDescription: Text.never)
    }

    var lastConfirmedRemoteMessageAppearanceDescription: String {
        formattedDate(snapshot?.cooldown.lastConfirmedRemoteMessageAppearance, nilDescription: Text.never)
    }

    var nextRemoteMessageEligibilityDescription: String {
        formattedDate(snapshot?.cooldown.nextRemoteMessageEligibility, nilDescription: Text.noCooldownBoundary)
    }

    var nextModalEligibilityDescription: String {
        formattedDate(snapshot?.cooldown.nextModalEligibility, nilDescription: Text.noCooldownBoundary)
    }

    init(
        diagnosticsProvider: PromoCoordinationDiagnosticsProviding?,
        cooldownResetter: PromoCoordinationCooldownResetting?,
        dateFormatting: ((Date) -> String)? = nil
    ) {
        self.diagnosticsProvider = diagnosticsProvider
        self.cooldownResetter = cooldownResetter
        self.dateFormatting = dateFormatting ?? { Self.dateFormatter.string(from: $0) }
        refresh()
    }

    func refresh() {
        snapshot = diagnosticsProvider?.diagnosticSnapshot
    }

    func resetModalCooldown() {
        cooldownResetter?.resetModalCooldown()
        refresh()
    }

    func resetRemoteMessageCooldown() {
        cooldownResetter?.resetRemoteMessageCooldown()
        refresh()
    }

    private func formattedDate(_ date: Date?, nilDescription: String) -> String {
        guard snapshot != nil else { return Text.unavailable }
        guard let date else { return nilDescription }

        return dateFormatting(date)
    }
}

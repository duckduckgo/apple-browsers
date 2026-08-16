//
//  PromptCoordinationDebugViewModelTests.swift
//  DuckDuckGoTests
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

import Foundation
import PersistenceTestingUtils
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Prompt Coordination - Debug View Model")
struct PromptCoordinationDebugViewModelTests {

    @available(iOS 16, *)
    @Test("Refresh passively formats production diagnostics", .timeLimit(.minutes(1)))
    func passiveRefreshAndFormatting() throws {
        let arbiter = PromoQueueLeaseArbiter()

        guard case .acquired(let modalLease) = arbiter.acquireModalLease() else {
            Issue.record("Expected a modal lease")
            return
        }
        let modalOwner = try #require(arbiter.snapshot.owner)
        modalLease.release()

        guard case .acquired(let remoteMessageLease) = arbiter.acquireRemoteMessageLease(for: "message") else {
            Issue.record("Expected an RMF lease")
            return
        }
        let unconfirmedRemoteMessageOwner = try #require(arbiter.snapshot.owner)
        #expect(remoteMessageLease.confirmAppearance())
        let confirmedRemoteMessageOwner = try #require(arbiter.snapshot.owner)

        let modalDate = Date(timeIntervalSince1970: 1_000)
        let remoteMessageDate = Date(timeIntervalSince1970: 2_000)
        let remoteMessageEligibility = Date(timeIntervalSince1970: 3_000)
        let modalEligibility = Date(timeIntervalSince1970: 4_000)
        let cooldown = PromoQueueCooldownSnapshot(
            lastConfirmedModalAppearance: modalDate,
            lastConfirmedRemoteMessageAppearance: remoteMessageDate,
            nextRemoteMessageEligibility: remoteMessageEligibility,
            nextModalEligibility: modalEligibility
        )
        let scenarios = [
            FormattingScenario(
                mode: .legacy,
                owner: nil,
                expectedMode: "Legacy",
                expectedOwner: "None",
                expectedAppearance: "Not applicable"
            ),
            FormattingScenario(
                mode: .coordinated,
                owner: modalOwner,
                expectedMode: "Coordinated",
                expectedOwner: "Modal (ownership ID: \(modalLease.ownershipIdentity.diagnosticDescription))",
                expectedAppearance: "Not applicable"
            ),
            FormattingScenario(
                mode: .coordinated,
                owner: unconfirmedRemoteMessageOwner,
                expectedMode: "Coordinated",
                expectedOwner: "RMF (message ID: message, acquisition ID: \(remoteMessageLease.acquisitionIdentity.diagnosticDescription))",
                expectedAppearance: "No"
            ),
            FormattingScenario(
                mode: .coordinated,
                owner: confirmedRemoteMessageOwner,
                expectedMode: "Coordinated",
                expectedOwner: "RMF (message ID: message, acquisition ID: \(remoteMessageLease.acquisitionIdentity.diagnosticDescription))",
                expectedAppearance: "Yes"
            ),
        ]
        let provider = DiagnosticsProviderSpy(
            snapshot: PromoCoordinationDiagnosticSnapshot(
                mode: scenarios[0].mode,
                owner: scenarios[0].owner,
                cooldown: cooldown
            )
        )
        let viewModel = PromptCoordinationDebugViewModel(
            diagnosticsProvider: provider,
            cooldownResetter: nil,
            dateFormatting: { "Date \(Int($0.timeIntervalSince1970))" }
        )
        #expect(viewModel.lastConfirmedModalAppearanceDescription == "Date 1000")
        #expect(viewModel.lastConfirmedRemoteMessageAppearanceDescription == "Date 2000")
        #expect(viewModel.nextRemoteMessageEligibilityDescription == "Date 3000")
        #expect(viewModel.nextModalEligibilityDescription == "Date 4000")

        for scenario in scenarios {
            provider.snapshot = PromoCoordinationDiagnosticSnapshot(
                mode: scenario.mode,
                owner: scenario.owner,
                cooldown: cooldown
            )
            viewModel.refresh()

            #expect(viewModel.modeDescription == scenario.expectedMode)
            #expect(viewModel.ownerDescription == scenario.expectedOwner)
            #expect(viewModel.remoteMessageAppearanceDescription == scenario.expectedAppearance)
        }

        _ = remoteMessageLease
    }

    @available(iOS 16, *)
    @Test("RMF cooldown reset updates eligibility without changing ownership", .timeLimit(.minutes(1)))
    func remoteMessageCooldownReset() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_775_000_000)
        let keyValueStore = InMemoryThrowingKeyValueStore()
        let remoteMessageHistory = PromoQueueRemoteMessageHistoryStore(keyValueStore: keyValueStore)
        let policy = PromoQueueCooldownPolicy(
            modalPresentationStore: MockPromptCooldownStore(),
            remoteMessageHistory: remoteMessageHistory,
            dateProvider: { referenceDate }
        )
        let arbiter = PromoQueueLeaseArbiter()
        let launchSourceManager = MockLaunchSourceManager()
        launchSourceManager.source = .standard
        let service = PromoCoordinationService(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: MockModalPromptCoordinationManager(),
            mode: .coordinated,
            promoQueueLeaseArbiter: arbiter,
            promoQueueCooldownPolicy: policy
        )
        let lease = try #require(service.tryAcquireRemoteMessageLease(for: "message"))
        #expect(lease.markShown())
        let ownerBeforeReset = try #require(service.diagnosticSnapshot.owner)
        let viewModel = PromptCoordinationDebugViewModel(
            diagnosticsProvider: service,
            cooldownResetter: service,
            dateFormatting: { "Date \(Int($0.timeIntervalSince1970))" }
        )

        #expect(viewModel.lastConfirmedRemoteMessageAppearanceDescription == "Date 1775000000")
        #expect(viewModel.nextRemoteMessageEligibilityDescription == "Date 1775000600")
        #expect(viewModel.nextModalEligibilityDescription == "Date 1775086400")

        viewModel.resetRemoteMessageCooldown()

        #expect(viewModel.lastConfirmedRemoteMessageAppearanceDescription == "Never")
        #expect(viewModel.nextRemoteMessageEligibilityDescription == "No cooldown boundary")
        #expect(viewModel.nextModalEligibilityDescription == "No cooldown boundary")
        #expect(viewModel.remoteMessageAppearanceDescription == "Yes")
        #expect(service.diagnosticSnapshot.owner == ownerBeforeReset)

        let reconstructedHistory = PromoQueueRemoteMessageHistoryStore(keyValueStore: keyValueStore)
        #expect(reconstructedHistory.lastConfirmedAppearance == nil)
        _ = lease
    }
}

private struct FormattingScenario {
    let mode: PromoCoordinationMode
    let owner: PromoQueueLeaseOwnerSnapshot?
    let expectedMode: String
    let expectedOwner: String
    let expectedAppearance: String
}

@MainActor
private final class DiagnosticsProviderSpy: PromoCoordinationDiagnosticsProviding {
    var snapshot: PromoCoordinationDiagnosticSnapshot

    init(snapshot: PromoCoordinationDiagnosticSnapshot) {
        self.snapshot = snapshot
    }

    var diagnosticSnapshot: PromoCoordinationDiagnosticSnapshot {
        snapshot
    }
}

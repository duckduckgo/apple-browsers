//
//  ModalPromptCoordinationDebugMenuTests.swift
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
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination Debug Menu")
final class ModalPromptCoordinationDebugMenuTests {

    @Test("The view model formats service and exposure snapshots")
    func whenSnapshotsChangeThenViewModelFormatsEveryReadOnlyValue() throws {
        let arbiter = PromoQueueLeaseArbiter()
        guard case .acquired(let modalLease) = arbiter.acquireModalLease() else {
            Issue.record("Expected modal lease acquisition")
            return
        }
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
        let rendererID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000234"))
        let generationID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000345"))
        let presentationID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000456"))
        let removalID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000567"))
        let blockerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000678"))
        let remoteMessageSession = PromoQueueRemoteMessageSession(id: sessionID, messageID: "debug-promo")
        let provider = MutablePromoQueueDebugSnapshotProvider(snapshot: PromoQueueDebugSnapshot(
            mode: .coordinated,
            activeOwner: .remoteMessage(remoteMessageSession),
            remoteMessageCoordination: PromoQueueRemoteMessageCoordinationSnapshot(
                state: .draining,
                messageID: remoteMessageSession.messageID,
                sessionID: remoteMessageSession.id,
                rendererID: rendererID,
                registrationGenerationID: generationID,
                presentationID: presentationID,
                isQueueAppearanceConfirmed: true,
                isPresentationAppearanceReported: true,
                removalID: removalID,
                removalTerminal: .hostDetached,
                drainContinuation: .transferSameMessageIfAvailable,
                selectedRemoteMessageRendererID: nil,
                renderers: [
                    PromoQueueRemoteMessageRendererSnapshot(
                        rendererID: rendererID,
                        registrationGenerationID: generationID,
                        candidate: .available(messageID: remoteMessageSession.messageID),
                        isLocallyReady: true,
                        isAttachedToWindow: true,
                        isEffectivelyEligible: false,
                        isDeregistered: false
                    )
                ],
                registeredRendererCount: 1,
                eligibleRendererCount: 0
            ),
            modalAttemptPhase: .committed(modalLease.attemptIdentity),
            hasPendingModalPrompt: true,
            shouldSuppressOtherSessionPromos: true,
            isApplicationActive: true,
            isWaitingForForegroundInteractionReadiness: false,
            cooldown: PromoQueueCooldownSnapshot(
                lastConfirmedModalAppearance: referenceDate,
                lastConfirmedRemoteMessageAppearance: referenceDate.addingTimeInterval(1),
                nextRemoteMessageEligibility: referenceDate.addingTimeInterval(600),
                nextModalEligibility: referenceDate.addingTimeInterval(86_400)
            )
        ))
        let exposureProvider = MutablePromoExposureSnapshotProvider(snapshot: NewTabPagePromoExposureSnapshot(
            mode: .coordinated,
            routeCandidateRendererID: rendererID,
            effectiveSelectedRendererID: nil,
            selectionState: .blocked(candidateRendererID: rendererID, blockerIDs: [blockerID]),
            activeBlockers: [
                PromoSurfaceBlockerRecord(
                    id: blockerID,
                    scope: .renderer(rendererID),
                    reason: .daxOverlay,
                    source: PromoSurfaceBlockerSource("debug-overlay")
                )
            ]
        ))
        let viewModel = ModalPromptCoordinationDebugViewModel(
            store: MockPromptCooldownStore(),
            promoQueueDebugSnapshotProvider: provider,
            promoExposureSnapshotProvider: exposureProvider,
            dateFormatting: { "timestamp:\(Int($0.timeIntervalSince1970))" }
        )

        #expect(viewModel.formattedPromoQueueMode == "Coordinated")
        #expect(viewModel.formattedActiveOwner == "RMF debug-promo — session \(sessionID.uuidString)")
        #expect(viewModel.formattedModalAttemptPhase == "Committed — \(modalLease.attemptIdentity.debugIdentifier)")
        #expect(viewModel.formattedPendingModalState == "Yes")
        #expect(viewModel.formattedSuppressionState == "Yes")
        #expect(viewModel.formattedApplicationState == "Active")
        #expect(viewModel.formattedInteractionReadiness == "Ready")
        #expect(viewModel.formattedRouteCandidate == rendererID.uuidString)
        #expect(viewModel.formattedEffectiveSelection == "None")
        #expect(viewModel.formattedExposureState == "Blocked \(rendererID.uuidString) — \(blockerID.uuidString)")
        #expect(
            viewModel.formattedExposureBlockers
                == "\(blockerID.uuidString) — renderer(\(rendererID.uuidString)) — daxOverlay — debug-overlay"
        )
        #expect(viewModel.formattedRemoteMessageState == "Draining")
        #expect(viewModel.formattedRemoteMessageIdentity == "debug-promo — session \(sessionID.uuidString)")
        #expect(viewModel.formattedSelectedRemoteMessageRenderer == "None")
        #expect(viewModel.formattedRemoteMessageRenderer == "\(rendererID.uuidString) — generation \(generationID.uuidString)")
        #expect(viewModel.formattedRemoteMessagePresentation == presentationID.uuidString)
        #expect(
            viewModel.formattedRemoteMessageRemoval
                == "\(removalID.uuidString) — Host Detached — Transfer Same Message If Available"
        )
        #expect(viewModel.formattedRemoteMessageQueueAppearance == "Confirmed")
        #expect(viewModel.formattedRemoteMessagePhysicalAppearance == "Reported")
        #expect(viewModel.formattedRemoteMessageRendererCounts == "1 registered — 0 eligible")
        #expect(
            viewModel.formattedRemoteMessageRenderers
                == "\(rendererID.uuidString) — generation \(generationID.uuidString) — available(debug-promo) — "
                    + "locally ready — attached — effectively ineligible — registered"
        )
        #expect(viewModel.formattedLastConfirmedModalAppearance == "timestamp:1800000000")
        #expect(viewModel.formattedLastConfirmedRemoteMessageAppearance == "timestamp:1800000001")
        #expect(viewModel.formattedNextRemoteMessageEligibility == "timestamp:1800000600")
        #expect(viewModel.formattedNextModalEligibility == "timestamp:1800086400")

        provider.snapshot = PromoQueueDebugSnapshot(
            mode: .legacy,
            activeOwner: nil,
            remoteMessageCoordination: PromoQueueRemoteMessageCoordinationSnapshot(
                state: .idle,
                messageID: nil,
                sessionID: nil,
                rendererID: nil,
                registrationGenerationID: nil,
                presentationID: nil,
                isQueueAppearanceConfirmed: false,
                isPresentationAppearanceReported: nil,
                removalID: nil,
                removalTerminal: nil,
                drainContinuation: nil,
                selectedRemoteMessageRendererID: nil,
                renderers: [],
                registeredRendererCount: 0,
                eligibleRendererCount: 0
            ),
            modalAttemptPhase: .idle,
            hasPendingModalPrompt: false,
            shouldSuppressOtherSessionPromos: false,
            isApplicationActive: false,
            isWaitingForForegroundInteractionReadiness: true,
            cooldown: .empty
        )
        exposureProvider.snapshot = NewTabPagePromoExposureSnapshot(
            mode: .legacy,
            routeCandidateRendererID: nil,
            effectiveSelectedRendererID: nil,
            selectionState: .noRouteCandidate,
            activeBlockers: []
        )

        viewModel.refresh()

        #expect(provider.snapshotReadCount == 2)
        #expect(exposureProvider.snapshotReadCount == 2)
        #expect(viewModel.formattedPromoQueueMode == "Legacy")
        #expect(viewModel.formattedActiveOwner == "None")
        #expect(viewModel.formattedModalAttemptPhase == "Idle")
        #expect(viewModel.formattedPendingModalState == "No")
        #expect(viewModel.formattedSuppressionState == "No")
        #expect(viewModel.formattedApplicationState == "Inactive")
        #expect(viewModel.formattedInteractionReadiness == "Waiting")
        #expect(viewModel.formattedRouteCandidate == "None")
        #expect(viewModel.formattedEffectiveSelection == "None")
        #expect(viewModel.formattedExposureState == "No Route Candidate")
        #expect(viewModel.formattedExposureBlockers == "None")
        #expect(viewModel.formattedRemoteMessageState == "Idle")
        #expect(viewModel.formattedRemoteMessageIdentity == "None")
        #expect(viewModel.formattedSelectedRemoteMessageRenderer == "None")
        #expect(viewModel.formattedRemoteMessageRenderer == "None")
        #expect(viewModel.formattedRemoteMessagePresentation == "None")
        #expect(viewModel.formattedRemoteMessageRemoval == "None")
        #expect(viewModel.formattedRemoteMessageQueueAppearance == "Not Confirmed")
        #expect(viewModel.formattedRemoteMessagePhysicalAppearance == "None")
        #expect(viewModel.formattedRemoteMessageRendererCounts == "0 registered — 0 eligible")
        #expect(viewModel.formattedRemoteMessageRenderers == "None")
        #expect(viewModel.formattedLastConfirmedModalAppearance == "None")
        #expect(viewModel.formattedLastConfirmedRemoteMessageAppearance == "None")
        #expect(viewModel.formattedNextRemoteMessageEligibility == "None")
        #expect(viewModel.formattedNextModalEligibility == "None")
        _ = modalLease
    }

    @Test("Unavailable Projection Leaves Existing Modal Cooldown Reset Intact")
    func whenSnapshotProviderIsUnavailableThenOnlyExistingCooldownControlRemainsActive() {
        let store = MockPromptCooldownStore()
        store.lastPresentationTimestamp = 1_800_000_000
        let viewModel = ModalPromptCoordinationDebugViewModel(
            store: store,
            promoQueueDebugSnapshotProvider: nil,
            dateFormatting: { _ in "unused" }
        )

        #expect(viewModel.formattedPromoQueueMode == "Unavailable")
        #expect(viewModel.formattedActiveOwner == "Unavailable")
        #expect(viewModel.isCooldownPeriodActive)

        viewModel.resetCoolDownPeriod()

        #expect(store.lastPresentationTimestamp == nil)
        #expect(!viewModel.isCooldownPeriodActive)
        #expect(viewModel.formattedCooldownPeriod == "No Prompt Cooldown active.")
        #expect(viewModel.formattedPromoQueueMode == "Unavailable")
    }
}

@MainActor
private final class MutablePromoQueueDebugSnapshotProvider: PromoQueueDebugSnapshotProviding {
    var snapshot: PromoQueueDebugSnapshot
    private(set) var snapshotReadCount = 0

    init(snapshot: PromoQueueDebugSnapshot) {
        self.snapshot = snapshot
    }

    var promoQueueDebugSnapshot: PromoQueueDebugSnapshot {
        snapshotReadCount += 1
        return snapshot
    }
}

@MainActor
private final class MutablePromoExposureSnapshotProvider: NewTabPagePromoExposureSnapshotProviding {
    var snapshot: NewTabPagePromoExposureSnapshot
    private(set) var snapshotReadCount = 0

    init(snapshot: NewTabPagePromoExposureSnapshot) {
        self.snapshot = snapshot
    }

    var promoExposureSnapshot: NewTabPagePromoExposureSnapshot {
        snapshotReadCount += 1
        return snapshot
    }
}

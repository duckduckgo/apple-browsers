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
import Persistence
import class Common.EventMapping

struct ModalPromptCoordinationDebugView: View {
    @StateObject private var viewModel: ModalPromptCoordinationDebugViewModel

    init(
        keyValueStore: ThrowingKeyValueStoring,
        promoQueueDebugSnapshotProvider: PromoQueueDebugSnapshotProviding? = nil,
        promoExposureSnapshotProvider: NewTabPagePromoExposureSnapshotProviding? = nil
    ) {
        let store = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStore, eventMapper: .init(mapping: { _, _, _, _ in }))
        self._viewModel = StateObject(
            wrappedValue: ModalPromptCoordinationDebugViewModel(
                store: store,
                promoQueueDebugSnapshotProvider: promoQueueDebugSnapshotProvider,
                promoExposureSnapshotProvider: promoExposureSnapshotProvider
            )
        )
    }

    var body: some View {
        List {
            Section {
                snapshotRow(title: "Process Mode", value: viewModel.formattedPromoQueueMode)
                snapshotRow(title: "Active Owner", value: viewModel.formattedActiveOwner)
                snapshotRow(title: "Modal Attempt", value: viewModel.formattedModalAttemptPhase)
                snapshotRow(title: "Pending Modal", value: viewModel.formattedPendingModalState)
                snapshotRow(title: "Suppress Other Promos", value: viewModel.formattedSuppressionState)
                snapshotRow(title: "Application", value: viewModel.formattedApplicationState)
                snapshotRow(title: "Interaction Readiness", value: viewModel.formattedInteractionReadiness)
                snapshotRow(title: "Route Candidate", value: viewModel.formattedRouteCandidate)
                snapshotRow(title: "Effective Selection", value: viewModel.formattedEffectiveSelection)
                snapshotRow(title: "Exposure State", value: viewModel.formattedExposureState)
                snapshotRow(title: "Exposure Blockers", value: viewModel.formattedExposureBlockers)
                snapshotRow(title: "RMF Logical State", value: viewModel.formattedRemoteMessageState)
                snapshotRow(title: "RMF Identity", value: viewModel.formattedRemoteMessageIdentity)
                snapshotRow(title: "Service Selected Renderer", value: viewModel.formattedSelectedRemoteMessageRenderer)
                snapshotRow(title: "RMF Renderer", value: viewModel.formattedRemoteMessageRenderer)
                snapshotRow(title: "RMF Presentation", value: viewModel.formattedRemoteMessagePresentation)
                snapshotRow(title: "RMF Removal", value: viewModel.formattedRemoteMessageRemoval)
                snapshotRow(title: "RMF Queue Appearance", value: viewModel.formattedRemoteMessageQueueAppearance)
                snapshotRow(title: "RMF Physical Appearance", value: viewModel.formattedRemoteMessagePhysicalAppearance)
                snapshotRow(title: "RMF Renderer Counts", value: viewModel.formattedRemoteMessageRendererCounts)
                snapshotRow(title: "RMF Renderer Details", value: viewModel.formattedRemoteMessageRenderers)
                snapshotRow(title: "Last Confirmed Modal", value: viewModel.formattedLastConfirmedModalAppearance)
                snapshotRow(title: "Last Confirmed RMF", value: viewModel.formattedLastConfirmedRemoteMessageAppearance)
                snapshotRow(title: "Next RMF Eligibility", value: viewModel.formattedNextRemoteMessageEligibility)
                snapshotRow(title: "Next Modal Eligibility", value: viewModel.formattedNextModalEligibility)
                Button("Refresh Snapshot") {
                    viewModel.refresh()
                }
            } header: {
                Text(verbatim: "Promo Queue")
            } footer: {
                Text(
                    verbatim: "Process mode changes require force-quit and relaunch. "
                        + "Eligibility boundaries are informational and do not schedule work."
                )
            }

            Section {
                Text(viewModel.formattedCooldownPeriod)
                if viewModel.isCooldownPeriodActive {
                    Button("Reset Cooldown") {
                        viewModel.resetCoolDownPeriod()
                    }
                }
            } header: {
                Text(verbatim: "Prompt Cooldown")
            } footer: {
                if viewModel.isCooldownPeriodActive {
                    Text(verbatim: "Reset Cooldown period to allow modal prompt to show again.")
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func snapshotRow(title: String, value: String) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value)
                .multilineTextAlignment(.trailing)
        }
    }
}

@MainActor
final class ModalPromptCoordinationDebugViewModel: ObservableObject {
    private let store: PromptCooldownStore
    private let promoQueueDebugSnapshotProvider: PromoQueueDebugSnapshotProviding?
    private let promoExposureSnapshotProvider: NewTabPagePromoExposureSnapshotProviding?
    private let formatDate: (Date) -> String

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current
        return formatter
    }()

    @Published private(set) var isCooldownPeriodActive: Bool = false
    @Published private(set) var formattedCooldownPeriod: String = ""
    @Published private(set) var formattedPromoQueueMode = "Unavailable"
    @Published private(set) var formattedActiveOwner = "Unavailable"
    @Published private(set) var formattedModalAttemptPhase = "Unavailable"
    @Published private(set) var formattedPendingModalState = "Unavailable"
    @Published private(set) var formattedSuppressionState = "Unavailable"
    @Published private(set) var formattedApplicationState = "Unavailable"
    @Published private(set) var formattedInteractionReadiness = "Unavailable"
    @Published private(set) var formattedRouteCandidate = "Unavailable"
    @Published private(set) var formattedEffectiveSelection = "Unavailable"
    @Published private(set) var formattedExposureState = "Unavailable"
    @Published private(set) var formattedExposureBlockers = "Unavailable"
    @Published private(set) var formattedRemoteMessageState = "Unavailable"
    @Published private(set) var formattedRemoteMessageIdentity = "Unavailable"
    @Published private(set) var formattedSelectedRemoteMessageRenderer = "Unavailable"
    @Published private(set) var formattedRemoteMessageRenderer = "Unavailable"
    @Published private(set) var formattedRemoteMessagePresentation = "Unavailable"
    @Published private(set) var formattedRemoteMessageRemoval = "Unavailable"
    @Published private(set) var formattedRemoteMessageQueueAppearance = "Unavailable"
    @Published private(set) var formattedRemoteMessagePhysicalAppearance = "Unavailable"
    @Published private(set) var formattedRemoteMessageRendererCounts = "Unavailable"
    @Published private(set) var formattedRemoteMessageRenderers = "Unavailable"
    @Published private(set) var formattedLastConfirmedModalAppearance = "Unavailable"
    @Published private(set) var formattedLastConfirmedRemoteMessageAppearance = "Unavailable"
    @Published private(set) var formattedNextRemoteMessageEligibility = "Unavailable"
    @Published private(set) var formattedNextModalEligibility = "Unavailable"

    init(
        store: PromptCooldownStore,
        promoQueueDebugSnapshotProvider: PromoQueueDebugSnapshotProviding?,
        promoExposureSnapshotProvider: NewTabPagePromoExposureSnapshotProviding? = nil,
        dateFormatting: ((Date) -> String)? = nil
    ) {
        self.store = store
        self.promoQueueDebugSnapshotProvider = promoQueueDebugSnapshotProvider
        self.promoExposureSnapshotProvider = promoExposureSnapshotProvider
        self.formatDate = dateFormatting ?? { Self.dateFormatter.string(from: $0) }
        updateUI()
    }

    func resetCoolDownPeriod() {
        store.lastPresentationTimestamp = nil
        updateUI()
    }

    func refresh() {
        updateUI()
    }

    private func updateUI() {
        isCooldownPeriodActive = isCooldownActive()
        formattedCooldownPeriod = makeFormattedCooldownPeriod()
        updatePromoQueueSnapshot()
        updatePromoExposureSnapshot()
    }

    private func isCooldownActive() -> Bool {
        store.lastPresentationTimestamp != nil
    }

    private func makeFormattedCooldownPeriod() -> String {
        guard let timestamp = store.lastPresentationTimestamp else {
            return "No Prompt Cooldown active."
        }

        let lastTimeStampDate = Date(timeIntervalSince1970: timestamp)
        return "Modal Prompt shown \(Self.dateFormatter.string(from: lastTimeStampDate))."
    }

    private func updatePromoQueueSnapshot() {
        guard let snapshot = promoQueueDebugSnapshotProvider?.promoQueueDebugSnapshot else {
            return
        }

        formattedPromoQueueMode = formattedMode(snapshot.mode)
        formattedActiveOwner = formattedOwner(snapshot.activeOwner)
        formattedModalAttemptPhase = formattedAttemptPhase(snapshot.modalAttemptPhase)
        formattedPendingModalState = formattedBoolean(snapshot.hasPendingModalPrompt)
        formattedSuppressionState = formattedBoolean(snapshot.shouldSuppressOtherSessionPromos)
        formattedApplicationState = snapshot.isApplicationActive ? "Active" : "Inactive"
        formattedInteractionReadiness = snapshot.isWaitingForForegroundInteractionReadiness ? "Waiting" : "Ready"
        updateRemoteMessageSnapshot(snapshot.remoteMessageCoordination)
        formattedLastConfirmedModalAppearance = formattedDate(snapshot.cooldown.lastConfirmedModalAppearance)
        formattedLastConfirmedRemoteMessageAppearance = formattedDate(snapshot.cooldown.lastConfirmedRemoteMessageAppearance)
        formattedNextRemoteMessageEligibility = formattedDate(snapshot.cooldown.nextRemoteMessageEligibility)
        formattedNextModalEligibility = formattedDate(snapshot.cooldown.nextModalEligibility)
    }

    private func formattedMode(_ mode: PromoCoordinationMode) -> String {
        switch mode {
        case .legacy:
            return "Legacy"
        case .coordinated:
            return "Coordinated"
        }
    }

    private func formattedOwner(_ owner: PromoQueueActiveOwnerSnapshot?) -> String {
        switch owner {
        case .modal(let identity):
            return "Modal — \(identity.debugIdentifier)"
        case .remoteMessage(let session):
            return "RMF \(session.messageID) — session \(session.id.uuidString)"
        case nil:
            return "None"
        }
    }

    private func updateRemoteMessageSnapshot(_ snapshot: PromoQueueRemoteMessageCoordinationSnapshot) {
        formattedRemoteMessageState = formattedRemoteMessageState(snapshot.state)
        formattedRemoteMessageIdentity = formattedRemoteMessageIdentity(snapshot)
        formattedSelectedRemoteMessageRenderer = snapshot.selectedRemoteMessageRendererID?.uuidString ?? "None"
        formattedRemoteMessageRenderer = formattedRemoteMessageRenderer(snapshot)
        formattedRemoteMessagePresentation = snapshot.presentationID?.uuidString ?? "None"
        formattedRemoteMessageRemoval = formattedRemoteMessageRemoval(snapshot)
        formattedRemoteMessageQueueAppearance = snapshot.isQueueAppearanceConfirmed ? "Confirmed" : "Not Confirmed"
        formattedRemoteMessagePhysicalAppearance = formattedPhysicalAppearance(snapshot.isPresentationAppearanceReported)
        formattedRemoteMessageRendererCounts = "\(snapshot.registeredRendererCount) registered — \(snapshot.eligibleRendererCount) eligible"
        formattedRemoteMessageRenderers = formattedRemoteMessageRenderers(snapshot.renderers)
    }

    private func updatePromoExposureSnapshot() {
        guard let snapshot = promoExposureSnapshotProvider?.promoExposureSnapshot else {
            return
        }

        formattedRouteCandidate = snapshot.routeCandidateRendererID?.uuidString ?? "None"
        formattedEffectiveSelection = snapshot.effectiveSelectedRendererID?.uuidString ?? "None"
        formattedExposureState = formattedExposureState(snapshot.selectionState)
        formattedExposureBlockers = snapshot.activeBlockers.isEmpty
            ? "None"
            : snapshot.activeBlockers.map { blocker in
                "\(blocker.id.uuidString) — \(blocker.scope) — \(blocker.reason) — \(blocker.source)"
            }.joined(separator: "\n")
    }

    private func formattedExposureState(_ state: NewTabPagePromoExposureSelectionState) -> String {
        switch state {
        case .noRouteCandidate:
            return "No Route Candidate"
        case .blocked(let candidateRendererID, let blockerIDs):
            return "Blocked \(candidateRendererID.uuidString) — \(blockerIDs.map(\.uuidString).joined(separator: ", "))"
        case .selected(let rendererID):
            return "Selected \(rendererID.uuidString)"
        }
    }

    private func formattedRemoteMessageRenderers(_ renderers: [PromoQueueRemoteMessageRendererSnapshot]) -> String {
        guard !renderers.isEmpty else {
            return "None"
        }

        return renderers.map { renderer in
            let candidate: String
            switch renderer.candidate {
            case .none:
                candidate = "none"
            case .available(let messageID):
                candidate = "available(\(messageID))"
            case .unrenderable(let messageID):
                candidate = "unrenderable(\(messageID))"
            }
            let readiness = renderer.isLocallyReady ? "locally ready" : "locally not ready"
            let attachment = renderer.isAttachedToWindow ? "attached" : "detached"
            let eligibility = renderer.isEffectivelyEligible ? "effectively eligible" : "effectively ineligible"
            let registration = renderer.isDeregistered ? "deregistered" : "registered"
            return "\(renderer.rendererID.uuidString) — generation \(renderer.registrationGenerationID.uuidString) — "
                + "\(candidate) — \(readiness) — \(attachment) — \(eligibility) — \(registration)"
        }.joined(separator: "\n")
    }

    private func formattedRemoteMessageState(_ state: PromoQueueRemoteMessageLogicalStateSnapshot) -> String {
        switch state {
        case .idle:
            return "Idle"
        case .owned:
            return "Owned"
        case .draining:
            return "Draining"
        }
    }

    private func formattedRemoteMessageIdentity(_ snapshot: PromoQueueRemoteMessageCoordinationSnapshot) -> String {
        guard let messageID = snapshot.messageID, let sessionID = snapshot.sessionID else {
            return "None"
        }
        return "\(messageID) — session \(sessionID.uuidString)"
    }

    private func formattedRemoteMessageRenderer(_ snapshot: PromoQueueRemoteMessageCoordinationSnapshot) -> String {
        guard let rendererID = snapshot.rendererID, let generationID = snapshot.registrationGenerationID else {
            return "None"
        }
        return "\(rendererID.uuidString) — generation \(generationID.uuidString)"
    }

    private func formattedRemoteMessageRemoval(_ snapshot: PromoQueueRemoteMessageCoordinationSnapshot) -> String {
        guard let removalID = snapshot.removalID else {
            return "None"
        }

        let terminal = snapshot.removalTerminal.map(formattedRemovalTerminal) ?? "Pending"
        let continuation = snapshot.drainContinuation.map(formattedDrainContinuation) ?? "None"
        return "\(removalID.uuidString) — \(terminal) — \(continuation)"
    }

    private func formattedRemovalTerminal(_ terminal: PromoQueueRemoteMessageRemovalTerminal) -> String {
        switch terminal {
        case .animationCompleted:
            return "Animation Completed"
        case .hostDetached:
            return "Host Detached"
        case .sourceRemovedWithoutAnimation:
            return "Source Removed Without Animation"
        }
    }

    private func formattedDrainContinuation(_ continuation: PromoQueueRemoteMessageDrainContinuationSnapshot) -> String {
        switch continuation {
        case .transferSameMessageIfAvailable:
            return "Transfer Same Message If Available"
        case .endSession:
            return "End Session"
        }
    }

    private func formattedPhysicalAppearance(_ appearance: Bool?) -> String {
        switch appearance {
        case true:
            return "Reported"
        case false:
            return "Not Reported"
        case nil:
            return "None"
        }
    }

    private func formattedAttemptPhase(_ phase: ModalPromptAttemptPhase) -> String {
        switch phase {
        case .idle:
            return "Idle"
        case .evaluating(let identity):
            return "Evaluating — \(identity.debugIdentifier)"
        case .committed(let identity):
            return "Committed — \(identity.debugIdentifier)"
        case .presentationActive(let identity):
            return "Presentation Active — \(identity.debugIdentifier)"
        }
    }

    private func formattedBoolean(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func formattedDate(_ date: Date?) -> String {
        date.map(formatDate) ?? "None"
    }
}

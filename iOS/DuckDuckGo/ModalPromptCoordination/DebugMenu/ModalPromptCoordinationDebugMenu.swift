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
        promoQueueDebugSnapshotProvider: PromoQueueDebugSnapshotProviding?
    ) {
        let store = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStore, eventMapper: .init(mapping: { _, _, _, _ in }))
        self._viewModel = StateObject(
            wrappedValue: ModalPromptCoordinationDebugViewModel(
                store: store,
                promoQueueDebugSnapshotProvider: promoQueueDebugSnapshotProvider
            )
        )
    }

    var body: some View {
        List {
            Section {
                snapshotRow(title: "Effective Flag", value: viewModel.formattedEffectiveFlag)
                snapshotRow(title: "Service State", value: viewModel.formattedFeatureState)
                snapshotRow(title: "Arbiter Modal Slot", value: viewModel.formattedModalLeaseState)
                snapshotRow(title: "Manager Phase", value: viewModel.formattedModalAttemptPhase)
                snapshotRow(title: "Pending Modal", value: viewModel.formattedPendingModalState)
                snapshotRow(title: "Active Visible Leases", value: viewModel.formattedActiveVisibleLeaseCount)
                Button("Refresh Snapshot") {
                    viewModel.refresh()
                }
            } header: {
                Text(verbatim: "Promo Queue")
            } footer: {
                Text(verbatim: "Current in-memory coordination state. Refresh after changing app or promo visibility.")
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
private final class ModalPromptCoordinationDebugViewModel: ObservableObject {
    private let store: PromptCooldownStore
    private let promoQueueDebugSnapshotProvider: PromoQueueDebugSnapshotProviding?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current
        return formatter
    }()

    @Published private(set) var isCooldownPeriodActive: Bool = false
    @Published private(set) var formattedCooldownPeriod: String = ""
    @Published private(set) var formattedEffectiveFlag = "Unavailable"
    @Published private(set) var formattedFeatureState = "Unavailable"
    @Published private(set) var formattedModalLeaseState = "Unavailable"
    @Published private(set) var formattedModalAttemptPhase = "Unavailable"
    @Published private(set) var formattedPendingModalState = "Unavailable"
    @Published private(set) var formattedActiveVisibleLeaseCount = "Unavailable"

    init(
        store: PromptCooldownStore,
        promoQueueDebugSnapshotProvider: PromoQueueDebugSnapshotProviding?
    ) {
        self.store = store
        self.promoQueueDebugSnapshotProvider = promoQueueDebugSnapshotProvider
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

        formattedEffectiveFlag = snapshot.isFeatureEnabled ? "Enabled" : "Disabled"
        formattedFeatureState = formattedFeatureState(snapshot.featureState)
        formattedModalLeaseState = snapshot.hasModalLease ? "Occupied" : "Available"
        formattedModalAttemptPhase = formattedModalAttemptPhase(snapshot.modalAttemptPhase)
        formattedPendingModalState = snapshot.hasPendingModalPrompt ? "Yes" : "No"
        formattedActiveVisibleLeaseCount = String(snapshot.activeVisiblePromoLeaseCount)
    }

    private func formattedFeatureState(_ state: PromoQueueFeatureState) -> String {
        switch state {
        case .disabled:
            return "Disabled"
        case .transitioning(to: .disabled):
            return "Transitioning to Disabled"
        case .transitioning(to: .enabled):
            return "Transitioning to Enabled"
        case .enabled:
            return "Enabled"
        }
    }

    private func formattedModalAttemptPhase(_ phase: ModalPromptAttemptPhase) -> String {
        switch phase {
        case .idle:
            return "Idle"
        case .evaluating:
            return "Evaluating"
        case .committed:
            return "Committed"
        case .presentationActive:
            return "Presentation Active"
        }
    }
}

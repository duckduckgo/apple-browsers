//
//  DuckAiUsageLimitsStore.swift
//  DuckDuckGo
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

import AIChat
import Combine
import Core
import FeatureFlags_iOS
import Foundation
import os.log
import PrivacyConfig

/// Owns the app-side flag gating so the shared decision logic stays flag-agnostic, and builds the
/// view model that drives the footer. Mirrors macOS's file of the same name.
struct DuckAiUsageLimitsStore {

#if DEBUG || ALPHA
    @MainActor static var debugOverride: DuckAiUsageSnapshot?
#endif

    private let storageHandler: DuckAiNativeStorageHandling?
    private let storageProvider: DuckAiUsageSnapshotProviding?
    private let featureFlagger: FeatureFlagger
    private let dismissalStore: DuckAiUsageWarningDismissalStoring

    init(storageHandler: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         dismissalStore: DuckAiUsageWarningDismissalStoring = DuckAiUsageWarningDismissalStore(),
         dateProvider: @escaping () -> Date = Date.init) {
        self.storageHandler = storageHandler
        self.storageProvider = storageHandler.map {
            DuckAiUsageSnapshotProvider(storage: $0,
                                        pixelFiring: DuckAiNativeStoragePixelAdapter(),
                                        dateProvider: dateProvider)
        }
        self.featureFlagger = featureFlagger
        self.dismissalStore = dismissalStore
    }

    /// `nil` means inactive (flag off, or no storage bridge), which differs from having nothing to show.
    func makeWarningViewModel(modelSuggester: DuckAiModelSuggesting,
                              isTrialEligible: @escaping () -> Bool,
                              isFireMode: @escaping () -> Bool) -> DuckAiUsageWarningViewModel? {
        guard featureFlagger.isFeatureOn(.utiDuckAIWarnings) else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] inactive: utiDuckAIWarnings flag is off")
            return nil
        }
        guard let limitsProvider = makeLimitsProvider() else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] inactive: no native-storage bridge")
            return nil
        }
        return DuckAiUsageWarningViewModel(
            snapshotProvider: limitsProvider,
            dismissalStore: dismissalStore,
            modelSuggester: modelSuggester,
            isTrialEligible: isTrialEligible,
            isFireMode: isFireMode
        )
    }

    /// Lets an open input update instead of waiting for the next activation, and is what releases
    /// a message the user has already acted on.
    var snapshotUpdates: AnyPublisher<Void, Never>? {
        guard featureFlagger.isFeatureOn(.utiDuckAIWarnings),
              let observing = storageHandler as? DuckAiNativeEntriesObserving else { return nil }

        return observing.reservedEntryUpdatesPublisher
            .filter { $0 == .usageLimits }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// There is no API for the hand-off: web reads this entry on its next hydration and turns it into
    /// the bypass header itself. A fire tab carries an isolated handler, so a write can't leak.
    @discardableResult
    func write(_ entries: [DuckAiNativeStorageEntry]) -> Bool {
        guard featureFlagger.isFeatureOn(.utiDuckAIWarnings), let storageHandler else { return false }

        var didWriteAll = true
        for entry in entries {
            do {
                try storageHandler.putEntry(key: entry.key, value: entry.value)
                Logger.duckAIUsageWarnings.debug("[UsageWarnings] wrote entry '\(entry.key, privacy: .public)'")
            } catch {
                didWriteAll = false
                Logger.duckAIUsageWarnings.error("""
                    [UsageWarnings] failed to write entry '\(entry.key, privacy: .public)': \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
        return didWriteAll
    }

    private func makeLimitsProvider() -> DuckAiUsageSnapshotProviding? {
#if DEBUG || ALPHA
        // Wrapped rather than replaced, so "no storage bridge" still reads as inactive here exactly
        // as it does in Release.
        return storageProvider.map { DebugOverridableUsageLimitsProvider(wrapped: $0) }
#else
        return storageProvider
#endif
    }
}

#if DEBUG || ALPHA
/// Lets the debug menu drive the real decision path from a hand-seeded snapshot.
private struct DebugOverridableUsageLimitsProvider: DuckAiUsageSnapshotProviding {

    let wrapped: DuckAiUsageSnapshotProviding

    func currentSnapshot() -> DuckAiUsageSnapshot {
        if let override = MainActor.assumeIsolated({ DuckAiUsageLimitsStore.debugOverride }) {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] using debug override snapshot")
            return override
        }
        return wrapped.currentSnapshot()
    }
}
#endif

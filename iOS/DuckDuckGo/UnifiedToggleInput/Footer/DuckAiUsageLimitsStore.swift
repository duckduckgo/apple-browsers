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
import Core
import FeatureFlags_iOS
import Foundation
import os.log
import PrivacyConfig

/// Owns the app-side flag gating so the shared decision logic stays flag-agnostic, and builds the
/// view model that drives the footer. Mirrors macOS's file of the same name.
struct DuckAiUsageLimitsStore {

#if DEBUG || ALPHA
    @MainActor static var debugOverride: DuckAiUsageLimits?
#endif

    private let storageProvider: DuckAiUsageLimitsProviding?
    private let featureFlagger: FeatureFlagger
    private let dismissalStore: DuckAiUsageWarningDismissalStoring

    init(storageHandler: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         dismissalStore: DuckAiUsageWarningDismissalStoring = DuckAiUsageWarningDismissalStore(),
         dateProvider: @escaping () -> Date = Date.init) {
        self.storageProvider = storageHandler.map {
            DuckAiUsageLimitsProvider(storage: $0,
                                      pixelFiring: DuckAiNativeStoragePixelAdapter(),
                                      dateProvider: dateProvider)
        }
        self.featureFlagger = featureFlagger
        self.dismissalStore = dismissalStore
    }

    /// `nil` means inactive (flag off, or no storage bridge), which differs from having nothing to show.
    func makeWarningViewModel(tierProvider: @escaping () -> AIChatUserTier,
                              modelSuggester: DuckAiModelSuggesting,
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
            limitsProvider: limitsProvider,
            tierProvider: tierProvider,
            isInternalUser: { [featureFlagger] in featureFlagger.internalUserDecider.isInternalUser },
            dismissalStore: dismissalStore,
            modelSuggester: modelSuggester,
            isTrialEligible: isTrialEligible,
            isFireMode: isFireMode
        )
    }

    private func makeLimitsProvider() -> DuckAiUsageLimitsProviding? {
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
/// Lets the AI Chat debug menu drive the real decision path from a hand-seeded snapshot.
private struct DebugOverridableUsageLimitsProvider: DuckAiUsageLimitsProviding {

    let wrapped: DuckAiUsageLimitsProviding

    func currentUsageLimits() -> DuckAiUsageLimits {
        if let override = MainActor.assumeIsolated({ DuckAiUsageLimitsStore.debugOverride }) {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] using debug override snapshot")
            return override
        }
        return wrapped.currentUsageLimits()
    }
}
#endif

//
//  DuckAiUsageLimitsStore.swift
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
import AppKit
import FeatureFlags_macOS
import PrivacyConfig

/// Owns the app-side flag gating so the shared logic stays flag-agnostic and call sites don't repeat it.
/// Mirrors `CustomizeResponsesStore`: cheap to build, one per surface with a burner-aware handler.
final class DuckAiUsageLimitsStore {

    private let storageHandler: DuckAiNativeStorageHandling?
    private let featureFlagger: FeatureFlagger

    init(storageHandler: DuckAiNativeStorageHandling?,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.storageHandler = storageHandler
        self.featureFlagger = featureFlagger
    }

    /// `nil` means inactive (flag off, or no storage bridge), which differs from having nothing to show.
    func makeWarningViewModel(tierProvider: @escaping () -> AIChatUserTier,
                              modelSuggester: DuckAiModelSuggesting,
                              isTrialEligible: @escaping () -> Bool,
                              isFireMode: @escaping () -> Bool) -> DuckAiUsageWarningViewModel? {
        DuckAiUsageWarningViewModelFactory.make(
            isFeatureEnabled: featureFlagger.isFeatureOn(.aiChatUsageWarnings),
            storage: storageHandler,
            dismissalStore: DuckAiUsageWarningDismissalStore(),
            tierProvider: tierProvider,
            isInternalUser: { [featureFlagger] in featureFlagger.internalUserDecider.isInternalUser },
            modelSuggester: modelSuggester,
            isTrialEligible: isTrialEligible,
            isFireMode: isFireMode,
            pixelFiring: DuckAiNativeStoragePixelAdapter()
        )
    }
}

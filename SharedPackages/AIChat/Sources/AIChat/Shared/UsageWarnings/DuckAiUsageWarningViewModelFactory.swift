//
//  DuckAiUsageWarningViewModelFactory.swift
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

/// Takes an already-evaluated flag value, which keeps the platform-specific `FeatureFlag` enums in
/// their own app targets.
public enum DuckAiUsageWarningViewModelFactory {

    /// `nil` when the feature is inactive: flag off, or no storage bridge on this surface. No tier
    /// input — which message a user qualifies for is web's decision now.
    public static func make(isFeatureEnabled: Bool,
                            storage: DuckAiNativeStorageHandling?,
                            dismissalStore: DuckAiUsageWarningDismissalStoring,
                            modelSuggester: DuckAiModelSuggesting = NullDuckAiModelSuggester(),
                            isTrialEligible: @escaping () -> Bool = { false },
                            isFireMode: @escaping () -> Bool = { false },
                            storagePixelFiring: DuckAiNativeStoragePixelFiring = NullDuckAiNativeStoragePixelFiring()
    ) -> DuckAiUsageWarningViewModel? {
        guard isFeatureEnabled, let storage else { return nil }

        return DuckAiUsageWarningViewModel(
            snapshotProvider: DuckAiUsageSnapshotProvider(storage: storage, pixelFiring: storagePixelFiring),
            dismissalStore: dismissalStore,
            modelSuggester: modelSuggester,
            isTrialEligible: isTrialEligible,
            isFireMode: isFireMode
        )
    }
}

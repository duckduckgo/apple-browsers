//
//  OnboardingSharedPixelsStoring.swift
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

import Foundation
import Onboarding
import Persistence

enum OnboardingSharedPixelsStorageKeys: String, StorageKeyDescribing {
    case onboardingSource = "com-duckduckgo-onboarding-shared-pixels-source"
    case onboardingFlow = "com-duckduckgo-onboarding-shared-pixels-flow"
    // The single variant shared by every fork, before each fork had its own key. Only read to migrate it.
    case legacyOnboardingVariant = "com-duckduckgo-onboarding-shared-pixels-variant"
    case onboardingSearchExperienceVariant = "com-duckduckgo-onboarding-shared-pixels-variant-search-experience"
    case onboardingDownloadReasonVariant = "com-duckduckgo-onboarding-shared-pixels-variant-download-reason"
}

struct OnboardingSharedPixelsKeys: StoringKeys {
    let onboardingSource = StorageKey<OnboardingPixelParameter.Source>(OnboardingSharedPixelsStorageKeys.onboardingSource)
    let onboardingFlow = StorageKey<OnboardingPixelParameter.Flow>(OnboardingSharedPixelsStorageKeys.onboardingFlow)
    let legacyOnboardingVariant = StorageKey<String>(OnboardingSharedPixelsStorageKeys.legacyOnboardingVariant)
    let onboardingSearchExperienceVariant = StorageKey<OnboardingPixelParameter.SearchExperienceVariant>(OnboardingSharedPixelsStorageKeys.onboardingSearchExperienceVariant)
    let onboardingDownloadReasonVariant = StorageKey<OnboardingPixelParameter.DownloadReasonVariant>(OnboardingSharedPixelsStorageKeys.onboardingDownloadReasonVariant)
}

enum OnboardingSharedPixelsVariantMigration {

    /// Moves the single variant stored before each fork had its own key into its fork's key, then clears it.
    /// The stored value tells the forks apart (`search_plus_duckai-*` or `download_reason_*`).
    static func migrateLegacyVariantIfNeeded(in storage: any KeyedStoring<OnboardingSharedPixelsKeys>) {
        guard let legacyVariant = storage.legacyOnboardingVariant else { return }

        if let variant = OnboardingPixelParameter.SearchExperienceVariant(rawValue: legacyVariant), storage.onboardingSearchExperienceVariant == nil {
            storage.onboardingSearchExperienceVariant = variant
        } else if let variant = OnboardingPixelParameter.DownloadReasonVariant(rawValue: legacyVariant), storage.onboardingDownloadReasonVariant == nil {
            storage.onboardingDownloadReasonVariant = variant
        }
        storage.legacyOnboardingVariant = nil
    }

}

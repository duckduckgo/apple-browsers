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
    case onboardingVariant = "com-duckduckgo-onboarding-shared-pixels-variant"
}

struct OnboardingSharedPixelsKeys: StoringKeys {
    let onboardingSource = StorageKey<OnboardingPixelParameter.Source>(OnboardingSharedPixelsStorageKeys.onboardingSource)
    let onboardingFlow = StorageKey<OnboardingPixelParameter.Flow>(OnboardingSharedPixelsStorageKeys.onboardingFlow)
    let onboardingVariant = StorageKey<OnboardingPixelParameter.Variant>(OnboardingSharedPixelsStorageKeys.onboardingVariant)
}

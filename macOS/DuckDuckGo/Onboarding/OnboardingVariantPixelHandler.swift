//
//  OnboardingVariantPixelHandler.swift
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

struct OnboardingPixelSettings: StoringKeys {
    let searchExperienceVariant = StorageKey<OnboardingPixelParameter.SearchExperienceVariant>(.onboardingSearchExperienceVariant)
}

/// Adds the search or chat choice to every onboarding shared pixel sent after it.
/// The choice is recorded from the step's own click pixel, and the first one is kept.
final class OnboardingVariantPixelHandler: OnboardingSharedPixelHandling {
    private let handler: OnboardingSharedPixelHandling
    private let settings: any KeyedStoring<OnboardingPixelSettings>

    init(handler: OnboardingSharedPixelHandling,
         settings: any KeyedStoring<OnboardingPixelSettings> = UserDefaults.standard.keyedStoring()) {
        self.handler = handler
        self.settings = settings
    }

    func fire(_ event: OnboardingSharedPixelEvent,
              source: OnboardingPixelParameter.Source?,
              flow: OnboardingPixelParameter.Flow?,
              variants: OnboardingPixelParameter.Variants) {
        var variants = variants
        variants.searchExperience = variants.searchExperience ?? settings.searchExperienceVariant
        handler.fire(event, source: source, flow: flow, variants: variants)

        if case .searchChatToggle(.clicked(let value)) = event, settings.searchExperienceVariant == nil {
            settings.searchExperienceVariant = OnboardingPixelParameter.SearchExperienceVariant(value)
        }
    }
}

private extension OnboardingPixelParameter.SearchExperienceVariant {
    init(_ value: OnboardingSharedPixelEvent.SuggestionOrCustomToggleEvent.Value) {
        switch value {
        case .suggestedChat, .customChat: self = .duckAIChat
        case .suggestedSearch, .customSearch: self = .duckAISearch
        }
    }
}

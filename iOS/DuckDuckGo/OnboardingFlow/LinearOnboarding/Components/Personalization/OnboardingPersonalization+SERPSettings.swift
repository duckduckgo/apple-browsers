//
//  OnboardingPersonalization+SERPSettings.swift
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


// MARK: OnboardingPersonalization + SERP

/// Store adapter backing the SERP-blob toggles used across two onboarding steps.
///
/// Maps onboarding toggles onto the native SERP settings (persisted in the shared SERP blob):
/// - **Safe search** (Search step): `true` → `.moderate` (the app default, shown selected when the step
///   first loads), `false` → `.off`. A pre-existing `.strict` reads as enabled.
/// - **Search Assist** (No AI step): `true` → `.sometimes` (app default), `false` → `.never`.
/// - **AI-generated images** (No AI step): store-truth passthrough to `hideAIGeneratedImages`. The screen
///   presents the inverse ("show AI-generated images"), so the view model performs the visual inversion.
///
/// - See: [Search: Setup step](https://app.asana.com/1/137249556945/task/1216445221863465?focus=true)
/// - See: [No AI: Setup step 1](https://app.asana.com/1/137249556945/task/1216445221863467?focus=true)
extension SERPSettingsProvider: OnboardingSERPPersonalizationStore {

    public var isSafeSearchEnabled: Bool {
        get {
            self.safeSearch != .off
        }
        set {
            self.safeSearch = newValue ? .moderate : .off
        }
    }
    
    public var isSearchAssistEnabled: Bool {
        get {
            self.searchAssistFrequency != .never
        }
        set {
            self.searchAssistFrequency = newValue ? .sometimes : .never
        }
    }

    public var areAIGeneratedImagesHidden: Bool {
        get {
            self.hideAIGeneratedImages
        }
        set {
            self.hideAIGeneratedImages = newValue
        }
    }

}

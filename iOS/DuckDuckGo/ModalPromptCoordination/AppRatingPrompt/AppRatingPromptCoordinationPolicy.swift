//
//  AppRatingPromptCoordinationPolicy.swift
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

import Core
import FeatureFlags_iOS
import Foundation
import PrivacyConfig

/// Governs how the App Store rating prompt takes part in the Promo Queue. Not to be confused with
/// `AppRatingPrompt`, which owns the separate policy for when the prompt is due.
protocol AppRatingPromptCoordinationPolicying {
    /// Whether the prompt is coordinated. When `false` it keeps its existing search-time behaviour.
    var isCoordinationEnabled: Bool { get }

    /// How many foregrounds may take the promo slot without a search following before the prompt
    /// stops taking it. Zero or less removes the cap.
    var maxUnredeemedSlots: Int { get }
}

struct AppRatingPromptCoordinationPolicy: AppRatingPromptCoordinationPolicying {

    private enum Constants {
        static let defaultMaxUnredeemedSlots = 3
        static let maxUnredeemedSlotsKey = "maxUnredeemedSlots"
    }

    let isCoordinationEnabled: Bool

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    init(promoCoordinationMode: PromoCoordinationMode,
         featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging) {
        // Coordination needs both the queue itself and the prompt's own flag.
        self.isCoordinationEnabled = promoCoordinationMode == .coordinated
            && featureFlagger.isFeatureOn(for: FeatureFlag.appRatingPromptCoordination)
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    /// Read from the `appRatingPromptCoordination` subfeature settings, falling back to the default
    /// when absent or malformed.
    var maxUnredeemedSlots: Int {
        guard let json = privacyConfigurationManager.privacyConfig.settings(for: iOSBrowserConfigSubfeature.appRatingPromptCoordination),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dict[Constants.maxUnredeemedSlotsKey] as? NSNumber else {
            return Constants.defaultMaxUnredeemedSlots
        }
        return value.intValue
    }
}

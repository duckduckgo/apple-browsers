//
//  AppRatingCoordinationCapability.swift
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

/// Protocol for resolving whether the App Store rating prompt participates in the Promo Queue.
protocol AppRatingCoordinationCapable {
    /// Whether the prompt is coordinated. When `false` it keeps its existing search-time behaviour.
    var isCoordinationEnabled: Bool { get }
}

enum AppRatingCoordinationCapability {
    static func create(
        promoCoordinationMode: PromoCoordinationMode,
        featureFlagger: FeatureFlagger
    ) -> AppRatingCoordinationCapable {
        AppRatingCoordinationDefaultCapability(
            promoCoordinationMode: promoCoordinationMode,
            featureFlagger: featureFlagger
        )
    }
}

struct AppRatingCoordinationDefaultCapability: AppRatingCoordinationCapable {
    private let promoCoordinationMode: PromoCoordinationMode
    private let featureFlagger: FeatureFlagger

    init(promoCoordinationMode: PromoCoordinationMode, featureFlagger: FeatureFlagger) {
        self.promoCoordinationMode = promoCoordinationMode
        self.featureFlagger = featureFlagger
    }

    var isCoordinationEnabled: Bool {
        promoCoordinationMode == .coordinated
            && featureFlagger.isFeatureOn(for: FeatureFlag.appRatingPromptCoordination)
    }
}

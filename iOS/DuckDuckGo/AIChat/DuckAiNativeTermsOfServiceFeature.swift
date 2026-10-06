//
//  DuckAiNativeTermsOfServiceFeature.swift
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

import FeatureFlags_iOS
import PrivacyConfig

protocol DuckAiNativeTermsOfServiceFeatureProviding {
    var isAvailable: Bool { get }
}

/// Every native input shows the disclaimer: the UTI on iPhone, and the address bar and the contextual
/// sheet's input on iPad.
struct DuckAiNativeTermsOfServiceFeature: DuckAiNativeTermsOfServiceFeatureProviding {

    private let featureFlagger: any FeatureFlagger

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var isAvailable: Bool {
        featureFlagger.isFeatureOn(.duckAINativeTermsOfService)
    }
}

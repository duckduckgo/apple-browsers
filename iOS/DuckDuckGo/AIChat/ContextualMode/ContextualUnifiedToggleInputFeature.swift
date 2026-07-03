//
//  ContextualUnifiedToggleInputFeature.swift
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
import Core
import PrivacyConfig

protocol ContextualUnifiedToggleInputFeatureProviding {
    /// True when the presubmission contextual sheet should show the UTI in place of the basic native input.
    var isAvailable: Bool { get }
}

/// Gates the presubmission contextual UTI: the contextual flag AND-gated on top of `UnifiedToggleInputFeature` availability (iPhone-only + grant-gated).
struct ContextualUnifiedToggleInputFeature: ContextualUnifiedToggleInputFeatureProviding {

    private let unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger,
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature()) {
        self.featureFlagger = featureFlagger
        self.unifiedToggleInputFeature = unifiedToggleInputFeature
    }

    var isAvailable: Bool {
        unifiedToggleInputFeature.isAvailable && featureFlagger.isFeatureOn(.aiChatContextualUnifiedToggleInput)
    }
}

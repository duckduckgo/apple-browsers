//
//  ExperimentalAIChatManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import PrivacyConfig

struct ExperimentalAIChatManager {
    private let featureFlagger: FeatureFlagger
    private let aiChatContextualModeFeature: AIChatContextualModeFeatureProviding

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         aiChatContextualModeFeature: AIChatContextualModeFeatureProviding = AIChatContextualModeFeature()) {
        self.featureFlagger = featureFlagger
        self.aiChatContextualModeFeature = aiChatContextualModeFeature
    }

    var isStandaloneMigrationSupported: Bool {
        featureFlagger.isFeatureOn(.standaloneMigration)
    }

    var isContextualDuckAIModeEnabled: Bool {
        aiChatContextualModeFeature.isAvailable
    }
}

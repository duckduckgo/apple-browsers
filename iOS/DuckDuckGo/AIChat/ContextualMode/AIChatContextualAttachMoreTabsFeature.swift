//
//  AIChatContextualAttachMoreTabsFeature.swift
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

import AIChat
import FeatureFlags_iOS
import PrivacyConfig

enum AIChatContextualAttachMoreTabsState: Equatable {
    case unavailable
    case available(maximumTabAttachmentCount: Int)
}

protocol AIChatContextualAttachMoreTabsFeatureProviding {
    var state: AIChatContextualAttachMoreTabsState { get }
}

struct AIChatContextualAttachMoreTabsFeature: AIChatContextualAttachMoreTabsFeatureProviding {
    private let featureFlagger: any FeatureFlagger
    private let aiChatSettings: AIChatSettingsProvider

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings()) {
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
    }

    var state: AIChatContextualAttachMoreTabsState {
        guard featureFlagger.isFeatureOn(.aiChatContextualAttachMoreTabs) else {
            return .unavailable
        }

        return .available(maximumTabAttachmentCount: aiChatSettings.aiChatAttachMoreTabsLimit)
    }
}

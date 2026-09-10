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
import Common
import FeatureFlags_iOS
import PrivacyConfig

enum AIChatContextualAttachMoreTabsState: Equatable {
    case unavailable
    case available(maximumTabAttachmentCount: Int)
}

protocol AIChatContextualAttachMoreTabsFeatureProviding {
    var state: AIChatContextualAttachMoreTabsState { get }
}

extension AIChatContextualAttachMoreTabsFeatureProviding {
    func makeRequest(using provider: () -> MultiTabAttachmentRequest?) -> MultiTabAttachmentRequest? {
        guard case .available = state, let request = provider() else { return nil }

        return MultiTabAttachmentRequest(contexts: {
            guard case .available = self.state else { return [] }
            let contexts = await request.contexts()
            guard case .available = self.state else { return [] }
            return contexts
        }, didConsume: {
            guard case .available = self.state else { return }
            request.didConsume()
        })
    }
}

struct AIChatContextualAttachMoreTabsFeature: AIChatContextualAttachMoreTabsFeatureProviding {
    private let featureFlagger: any FeatureFlagger
    private let aiChatSettings: AIChatSettingsProvider
    private let devicePlatform: DevicePlatformProviding.Type

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
        self.devicePlatform = devicePlatform
    }

    var state: AIChatContextualAttachMoreTabsState {
        guard devicePlatform.isIphone,
              featureFlagger.isFeatureOn(.aiChatContextualAttachMoreTabs) else {
            return .unavailable
        }

        return .available(maximumTabAttachmentCount: aiChatSettings.aiChatAttachMoreTabsLimit)
    }
}

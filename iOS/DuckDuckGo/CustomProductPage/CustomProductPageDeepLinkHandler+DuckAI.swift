//
//  CustomProductPageDeepLinkHandler+DuckAI.swift
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
import AIChat
import Core
import PrivacyConfig

protocol AIChatDeepLinkHandling {
    func handleDeepLink(_ url: URL, on presenter: AIChatDeepLinkPresenting, voiceMode: Bool)
}

extension AIChatDeepLinkHandling {
    func handleDeepLink(_ url: URL, on presenter: AIChatDeepLinkPresenting) {
        handleDeepLink(url, on: presenter, voiceMode: false)
    }
}

extension AIChatDeepLinkHandler: AIChatDeepLinkHandling {}

/// Wrapper for AI Chat deep link handler
struct DuckAIDestinationHandler: CustomProductPageDestinationHandling {
    private let aiChatDeepLinkHandler: AIChatDeepLinkHandling
    private let pixelFiring: DailyPixelFiring.Type
    private let featureFlagger: FeatureFlagger

    init(
        aiChatDeepLinkHandler: AIChatDeepLinkHandling = AIChatDeepLinkHandler(),
        pixelFiring: DailyPixelFiring.Type = DailyPixel.self,
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger
    ) {
        self.aiChatDeepLinkHandler = aiChatDeepLinkHandler
        self.pixelFiring = pixelFiring
        self.featureFlagger = featureFlagger
    }

    func handle(url: URL, on presenter: AppStoreCustomProductPagePresenter) {
        guard featureFlagger.isFeatureOn(.customProductPageDuckAiChat) else { return }
        
        pixelFiring.fireDailyAndCount(.customProductPageDuckAIOpenedAIChat, error: nil, withAdditionalParameters: [:])
        aiChatDeepLinkHandler.handleDeepLink(url, on: presenter)
    }
}

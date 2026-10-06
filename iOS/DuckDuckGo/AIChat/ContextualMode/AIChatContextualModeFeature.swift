//
//  AIChatContextualModeFeature.swift
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

import AIChat
import Common
import FoundationExtensions
import Foundation
import PrivacyConfig
import FeatureFlags_iOS

/// Provides access to contextual Duck AI chat mode availability.
protocol AIChatContextualModeFeatureProviding {
    /// Whether Duck AI contextual chat mode is available on this device.
    ///
    /// Returns `true` only when all conditions are met:
    /// - The `contextualDuckAIMode` sub-feature flag is enabled
    /// - The AI Chat URL domain is `duck.ai`
    /// - On iPhone: the `pageContextFeature` flag is enabled
    /// - On iPad: always enabled
    var isAvailable: Bool { get }
}

/// Determines availability of Duck AI's contextual chat mode feature.
struct AIChatContextualModeFeature: AIChatContextualModeFeatureProviding {

    private let featureFlagger: any FeatureFlagger
    private let devicePlatform: DevicePlatformProviding.Type
    private let aiChatURLProvider: () -> URL
    private let debugSettings: AIChatDebugSettingsHandling

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self,
         aiChatURLProvider: @escaping () -> URL = { [settings = AIChatSettings()] in settings.aiChatURL },
         debugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings()) {
        self.featureFlagger = featureFlagger
        self.devicePlatform = devicePlatform
        self.aiChatURLProvider = aiChatURLProvider
        self.debugSettings = debugSettings
    }

    /// Whether Duck AI contextual chat mode is available.
    var isAvailable: Bool {
        let url = aiChatURLProvider()
        // Accept the debug custom URL too, so contextual mode can be tested against a dev
        // duck.ai instance whose host isn't literally `duck.ai`. No-op in production (custom
        // URL unset → matchesCustomURL is false), mirroring the webview's supported-URL check.
        return featureFlagger.isFeatureOn(.contextualDuckAIMode)
            && isPageContextEnabled
            && (url.isStandaloneDuckAIURL || debugSettings.matchesCustomURL(url))
    }

    private var isPageContextEnabled: Bool {
        if devicePlatform.isIphone {
            return featureFlagger.isFeatureOn(.pageContextFeature)
        }
        return true
    }
}

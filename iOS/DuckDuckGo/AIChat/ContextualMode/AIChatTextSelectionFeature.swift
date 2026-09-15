//
//  AIChatTextSelectionFeature.swift
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
import Foundation
import PrivacyConfig
import FeatureFlags_iOS

/// Availability of the items offered on text selected in the browser.
protocol AIChatTextSelectionFeatureProviding {
    /// Whether the feature is on at all, gating the machinery both items share.
    var isEnabled: Bool { get }
    /// Whether **Ask Duck.ai** is offered.
    var isAskAvailable: Bool { get }
    /// Whether **Search with DuckDuckGo** is offered.
    var isSearchAvailable: Bool { get }
}

/// Computed on each read rather than snapshotted at launch, so switching Duck.ai off in Settings removes
/// the Ask item immediately.
struct AIChatTextSelectionFeature: AIChatTextSelectionFeatureProviding {

    private let featureFlagger: any FeatureFlagger
    private let aiChatSettings: AIChatSettingsProvider
    private let unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding
    private let devicePlatform: DevicePlatformProviding.Type

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         aiChatSettings: AIChatSettingsProvider = AIChatSettings(),
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature(),
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.featureFlagger = featureFlagger
        self.aiChatSettings = aiChatSettings
        self.unifiedToggleInputFeature = unifiedToggleInputFeature
        self.devicePlatform = devicePlatform
    }

    /// The feature's kill switch and platform scope, shared by both items.
    var isEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatTextActions) && devicePlatform.isIphone
    }

    /// Additionally gated on Duck.ai being enabled at all: a user who has turned AI features off must see
    /// nothing AI-related. Deliberately not the browsing-menu shortcut setting, which only hides one entry
    /// point.
    ///
    /// Also requires everything the unified input's attachment strip needs, since that is where an
    /// attached selection appears — without it a selection would attach invisibly and still be submitted.
    var isAskAvailable: Bool {
        isEnabled
            && aiChatSettings.isAIChatEnabled
            && featureFlagger.isFeatureOn(.aiChatContextualUnifiedToggleInput)
            && unifiedToggleInputFeature.isAvailable
    }

    /// Not an AI action, so deliberately independent of the Duck.ai setting and of the unified input —
    /// searching a selection still works for someone who has Duck.ai switched off.
    var isSearchAvailable: Bool {
        isEnabled
    }
}

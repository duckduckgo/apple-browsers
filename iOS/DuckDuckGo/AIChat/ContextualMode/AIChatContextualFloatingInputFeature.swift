//
//  AIChatContextualFloatingInputFeature.swift
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

import Common
import Foundation
import PrivacyConfig

/// Provides access to the floating contextual input availability.
protocol AIChatContextualFloatingInputFeatureProviding {
    /// Whether "Ask About Page" opens the floating input instead of the contextual sheet.
    var isAvailable: Bool { get }
}

/// Determines availability of the address-bar Duck.ai menu and the floating contextual input.
struct AIChatContextualFloatingInputFeature: AIChatContextualFloatingInputFeatureProviding {

    private let featureFlagger: any FeatureFlagger
    private let devicePlatform: DevicePlatformProviding.Type
    private let unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self,
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature()) {
        self.featureFlagger = featureFlagger
        self.devicePlatform = devicePlatform
        self.unifiedToggleInputFeature = unifiedToggleInputFeature
    }

    /// `isIphone` is checked explicitly even though `unifiedToggleInputFeature` implies it, so the
    /// iPad-always-gets-the-sheet rule survives any change to the UTI's own gating.
    var isAvailable: Bool {
        devicePlatform.isIphone
            && featureFlagger.isFeatureOn(.aiChatContextualFloatingInput)
            && unifiedToggleInputFeature.isAvailable
    }
}

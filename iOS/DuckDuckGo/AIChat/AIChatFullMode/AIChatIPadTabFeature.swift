//
//  AIChatIPadTabFeature.swift
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
import PrivacyConfig
import Common

/// Provides access to Duck AI iPad tab mode availability.
protocol AIChatIPadTabFeatureProviding {
    /// Whether Duck AI should display in a tab on iPad.
    ///
    /// Returns `true` only when both conditions are met:
    /// - The `iPadDuckaiOnTab` feature flag is enabled
    /// - The device is NOT an iPhone (i.e. iPad or other large-screen devices)
    var isAvailable: Bool { get }
}

/// Determines availability of Duck AI's iPad tab mode feature.
struct AIChatIPadTabFeature: AIChatIPadTabFeatureProviding {

    private let featureFlagger: any FeatureFlagger
    private let devicePlatform: DevicePlatformProviding.Type

    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.featureFlagger = featureFlagger
        self.devicePlatform = devicePlatform
    }

    var isAvailable: Bool {
        featureFlagger.isFeatureOn(.iPadDuckaiOnTab) && !devicePlatform.isIphone
    }
}

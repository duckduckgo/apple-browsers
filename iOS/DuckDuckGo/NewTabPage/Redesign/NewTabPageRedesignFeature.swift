//
//  NewTabPageRedesignFeature.swift
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
import FeatureFlags_iOS
import PrivacyConfig

protocol NewTabPageRedesignFeatureProviding {

    /// Whether the redesigned New Tab Page can be shown on this device.
    var isAvailable: Bool { get }
}

struct NewTabPageRedesignFeature: NewTabPageRedesignFeatureProviding {

    private let featureFlagger: FeatureFlagger
    private let devicePlatform: DevicePlatformProviding.Type

    init(featureFlagger: FeatureFlagger,
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.featureFlagger = featureFlagger
        self.devicePlatform = devicePlatform
    }

    var isAvailable: Bool {
        // The device check comes first, and must stay first: reading the flag on a device that can
        // never show the redesign would enrol it in the experiment cohort and dilute the results.
        guard devicePlatform.isIphone else { return false }

        return featureFlagger.isFeatureOn(.newTabPageRedesign)
    }
}

//
//  AdBlockingAvailability.swift
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
import BrowserServicesKit
import DuckPlayer
import PrivacyConfig
import WebExtensions

final class AdBlockingAvailability: AdBlockingAvailabilityProviding {

    private let featureFlagger: FeatureFlagger
    private let isEnabledByUserProvider: () -> Bool

    init(featureFlagger: FeatureFlagger, isEnabledByUserProvider: @escaping () -> Bool) {
        self.featureFlagger = featureFlagger
        self.isEnabledByUserProvider = isEnabledByUserProvider
    }

    var isFeatureAvailable: Bool { featureFlagger.isFeatureOn(.adBlockingExtension) }
    var isEnabledByUser: Bool { isEnabledByUserProvider() }

    func shouldShowAnimation(for url: URL) -> Bool {
        isEnabled && url.isPlayableYoutubeVideoContent
    }
}

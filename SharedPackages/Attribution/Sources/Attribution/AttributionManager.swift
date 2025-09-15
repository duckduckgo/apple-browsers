//
//  AttributionManager.swift
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
//

import Foundation
import PixelKit
import Combine
import BrowserServicesKit

/// https://app.asana.com/1/137249556945/project/1205842942115003/task/1210884473312053?focus=true
public final class AttributionManager {

    private let pixelKit: PixelKit
    private let userDefaults: UserDefaults
    private let originProvider: (any AttributionOriginProvider)?
    private let featureFlagger: FeatureFlagger
    private var cancellables = Set<AnyCancellable>()

    var isEnabled: Bool {
        featureFlagger.isFeatureOn(for: AttributionFeatureFlags.attributionEnabled)
    }

    public init(pixelKit: PixelKit, userDefaults: UserDefaults, featureFlagger: FeatureFlagger, originProvider: (any AttributionOriginProvider)?) {
        self.pixelKit = pixelKit
        self.userDefaults = userDefaults
        self.originProvider = originProvider
        self.featureFlagger = featureFlagger

        registerNotifications()
    }

    // MARK: - Data storage

    struct StorageKey {
        /// Array of app start timestamps
        var firstStart = "startTimeStamps"

    }

    // MARK: - Triggers

    func appDidStart() {
        guard isEnabled else { return }

        
    }
}

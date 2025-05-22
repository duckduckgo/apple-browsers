//
//  MaliciousSiteProtectionPreferences.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Combine
import BrowserServicesKit

protocol MaliciousSiteProtectionPreferencesPersistor {
    var isEnabled: Bool { get set }
}

struct MaliciousSiteProtectionPreferencesUserDefaultsPersistor: MaliciousSiteProtectionPreferencesPersistor {

    @UserDefaultsWrapper(key: .maliciousSiteDetectionEnabled, defaultValue: true)
    var isEnabled: Bool
}

final class MaliciousSiteProtectionPreferences: ObservableObject, PreferencesTabOpening {

    static let shared = MaliciousSiteProtectionPreferences()
    private let featureFlagger: FeatureFlagger

    @Published
    var isEnabled: Bool {
        didSet {
            persistor.isEnabled = isEnabled
        }
    }

    var isFeatureOn: Bool {
        featureFlagger.isFeatureOn(.maliciousSiteProtection)
    }

    init(persistor: MaliciousSiteProtectionPreferencesPersistor = MaliciousSiteProtectionPreferencesUserDefaultsPersistor(),
         featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger
    ) {
        self.persistor = persistor
        self.isEnabled = persistor.isEnabled
        self.featureFlagger = featureFlagger
    }

    private var persistor: MaliciousSiteProtectionPreferencesPersistor
}

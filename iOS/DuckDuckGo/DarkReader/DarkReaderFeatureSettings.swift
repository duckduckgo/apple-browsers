//
//  DarkReaderFeatureSettings.swift
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
import Persistence
import PrivacyConfig

protocol DarkReaderFeatureSettings {

    var isFeatureEnabled: Bool { get }
    var isDarkModeEnabled: Bool { get }
    func setDarkModeEnabled(_ enabled: Bool)
}

enum DarkReaderStorageKeys: String, StorageKeyDescribing {
    case adaptiveDarkModeEnabled
}

struct DarkReaderKeys: StoringKeys {
    let adaptiveDarkModeEnabled = StorageKey<Bool>(DarkReaderStorageKeys.adaptiveDarkModeEnabled)
}

final class AppDarkReaderFeatureSettings: DarkReaderFeatureSettings {

    private let featureFlagger: FeatureFlagger
    private let storage: any KeyedStoring<DarkReaderKeys>

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         storage: (any KeyedStoring<DarkReaderKeys>)? = nil) {
        self.featureFlagger = featureFlagger
        self.storage = if let storage { storage } else { UserDefaults.app.keyedStoring() }
    }

    var isFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.forceDarkModeOnWebsites)
    }

    var isDarkModeEnabled: Bool {
        isFeatureEnabled && storage.adaptiveDarkModeEnabled ?? false
    }

    func setDarkModeEnabled(_ enabled: Bool) {
        storage.adaptiveDarkModeEnabled = enabled
    }
}

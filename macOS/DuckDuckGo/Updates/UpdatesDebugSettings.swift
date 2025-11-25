//
//  UpdatesDebugSettings.swift
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
import Common
import BrowserServicesKit
import Persistence

/// Debug settings for testing update functionality
/// Only available to internal users
protocol UpdatesDebugSettingsPersistor {
    var forceUpdateAvailable: Bool { get set }

    func reset()
}

final class UpdatesDebugSettingsUserDefaultsPersistor: UpdatesDebugSettingsPersistor {

    enum Key: String {
        case forceUpdateAvailable = "updates.debug.force-update-available"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var forceUpdateAvailable: Bool {
        get { (keyValueStore.object(forKey: Key.forceUpdateAvailable.rawValue) as? Bool) ?? false }
        set { keyValueStore.set(newValue, forKey: Key.forceUpdateAvailable.rawValue) }
    }

    func reset() {
        forceUpdateAvailable = false
    }
}

final class UpdatesDebugSettings {
    private var persistor: UpdatesDebugSettingsPersistor

    init(persistor: UpdatesDebugSettingsPersistor = UpdatesDebugSettingsUserDefaultsPersistor()) {
        self.persistor = persistor
    }

    var forceUpdateAvailable: Bool {
        get { persistor.forceUpdateAvailable }
        set { persistor.forceUpdateAvailable = newValue }
    }

    func reset() {
        persistor.reset()
    }
}

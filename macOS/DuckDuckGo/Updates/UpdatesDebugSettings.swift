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
public protocol UpdatesDebugSettingsPersistor {
    var forceUpdateAvailable: Bool { get set }

    func reset()
}

public final class UpdatesDebugSettingsUserDefaultsPersistor: UpdatesDebugSettingsPersistor {

    public enum Key: String {
        case forceUpdateAvailable = "updates.debug.force-update-available"
    }

    private let keyValueStore: KeyValueStoring

    public init(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    public var forceUpdateAvailable: Bool {
        get { (keyValueStore.object(forKey: Key.forceUpdateAvailable.rawValue) as? Bool) ?? false }
        set { keyValueStore.set(newValue, forKey: Key.forceUpdateAvailable.rawValue) }
    }

    public func reset() {
        forceUpdateAvailable = false
    }
}

public final class UpdatesDebugSettings {
    private var persistor: UpdatesDebugSettingsPersistor

    public init(persistor: UpdatesDebugSettingsPersistor = UpdatesDebugSettingsUserDefaultsPersistor()) {
        self.persistor = persistor
    }

    public var forceUpdateAvailable: Bool {
        get { persistor.forceUpdateAvailable }
        set { persistor.forceUpdateAvailable = newValue }
    }

    public func reset() {
        persistor.reset()
    }
}

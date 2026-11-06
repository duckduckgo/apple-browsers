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

import BrowserServicesKit
import Common
import FoundationExtensions
import Foundation
import Persistence

/// Debug settings for testing update functionality
/// Only available to internal users
public protocol UpdatesDebugSettingsPersistor {
    var forceUpdateAvailable: Bool { get set }
    var forcedUpdatePromptStage: UpdatePromptStage? { get set }

    func reset()
}

public final class UpdatesDebugSettingsUserDefaultsPersistor: UpdatesDebugSettingsPersistor {

    public enum Key: String {
        case forceUpdateAvailable = "updates.debug.force-update-available"
        case forcedUpdatePromptStage = "updates.debug.forced-update-prompt-stage"
    }

    private let keyValueStore: KeyValueStoring

    public init(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    public var forceUpdateAvailable: Bool {
        get { (keyValueStore.object(forKey: Key.forceUpdateAvailable.rawValue) as? Bool) ?? false }
        set { keyValueStore.set(newValue, forKey: Key.forceUpdateAvailable.rawValue) }
    }

    public var forcedUpdatePromptStage: UpdatePromptStage? {
        get { (keyValueStore.object(forKey: Key.forcedUpdatePromptStage.rawValue) as? Int).flatMap(UpdatePromptStage.init(rawValue:)) }
        set { keyValueStore.set(newValue?.rawValue, forKey: Key.forcedUpdatePromptStage.rawValue) }
    }

    public func reset() {
        forceUpdateAvailable = false
        forcedUpdatePromptStage = nil
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

    /// Overrides the update prompt stage while an update is available.
    public var forcedUpdatePromptStage: UpdatePromptStage? {
        get { persistor.forcedUpdatePromptStage }
        set { persistor.forcedUpdatePromptStage = newValue }
    }

    public func reset() {
        persistor.reset()
    }
}

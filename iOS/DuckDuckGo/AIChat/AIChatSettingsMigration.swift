//
//  AIChatSettingsMigration.swift
//  DuckDuckGo
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

import Foundation
import Persistence
import Core

struct AIChatSettingsMigration {

    typealias Keys = LegacyAiChatUserDefaultsKeys

    /// Migrate the settings from user defaults to the store created by the store factory, if any settings exist, and only create target store if we need it.
    static func migrate(from userDefaults: UserDefaults, to storeFactory: () -> KeyValueStoring) {

        let settings = [
            Keys.isAIChatEnabledKey: userDefaults.value(forKey: Keys.isAIChatEnabledKey),
            Keys.showAIChatBrowsingMenuKey: userDefaults.value(forKey: Keys.showAIChatBrowsingMenuKey),
            Keys.showAIChatAddressBarKey: userDefaults.value(forKey: Keys.showAIChatAddressBarKey),
            Keys.showAIChatVoiceSearchKey: userDefaults.value(forKey: Keys.showAIChatVoiceSearchKey),
            Keys.showAIChatTabSwitcherKey: userDefaults.value(forKey: Keys.showAIChatTabSwitcherKey),
            Keys.showAIChatExperimentalSearchInputKey: userDefaults.value(forKey: Keys.showAIChatExperimentalSearchInputKey),
        ].compactMapValues {
            $0
        }

        guard settings.count > 0 else { return }

        let store = storeFactory()
        if settings.first(where: { store.object(forKey: $0.key) != nil }) != nil {
            assertionFailure("Secondary migration of AIChatSettings has ocurred")
        }

        // Write to the new store
        settings.forEach {
            store.set($0.value, forKey: $0.key)
        }

        // We're now safe to delete. If this fails the above will get duplicated, but this can't be done atomically.
        settings.forEach {
            userDefaults.removeObject(forKey: $0.key)
        }
    }

}

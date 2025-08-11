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

    typealias Keys = AIChatSettings.StoreKeys

    static func migrate(from userDefaults: UserDefaults, to store: KeyValueStoring) {

        let settings = [
            Keys.isAIChatEnabled: userDefaults.value(forKey: Keys.isAIChatEnabled),
            Keys.showAIChatBrowsingMenu: userDefaults.value(forKey: Keys.showAIChatBrowsingMenu),
            Keys.showAIChatAddressBar: userDefaults.value(forKey: Keys.showAIChatAddressBar),
            Keys.showAIChatVoiceSearch: userDefaults.value(forKey: Keys.showAIChatVoiceSearch),
            Keys.showAIChatTabSwitcher: userDefaults.value(forKey: Keys.showAIChatTabSwitcher),
            Keys.showAIChatExperimentalSearchInput: userDefaults.value(forKey: Keys.showAIChatExperimentalSearchInput),
        ].compactMapValues {
            $0
        }

        if settings.count > 0 {
            // Write to the new store

        }

        // We're now safe to delete. If this fails the above will get duplicated, but this can't be done atomically.
        settings.forEach {
            userDefaults.removeObject(forKey: $0.key)
        }
    }

}

private extension UserDefaults {

    typealias Keys = AIChatSettings.StoreKeys

    static let isAIChatEnabledDefaultValue = true
    static let showAIChatBrowsingMenuDefaultValue = true
    static let showAIChatAddressBarDefaultValue = true
    static let showAIChatVoiceSearchDefaultValue = true
    static let showAIChatTabSwitcherDefaultValue = true
    static let showAIChatExperimentalSearchInputDefaultValue = false

    @objc dynamic var isAIChatEnabled: Bool {
        get {
            value(forKey: Keys.isAIChatEnabled) as? Bool ?? Self.isAIChatEnabledDefaultValue
        }

        set {
            guard newValue != isAIChatEnabled else { return }
            set(newValue, forKey: Keys.isAIChatEnabled)
        }
    }

    @objc dynamic var showAIChatBrowsingMenu: Bool {
        get {
            value(forKey: Keys.showAIChatBrowsingMenu) as? Bool ?? Self.showAIChatBrowsingMenuDefaultValue
        }

        set {
            guard newValue != showAIChatBrowsingMenu else { return }
            set(newValue, forKey: Keys.showAIChatBrowsingMenu)
        }
    }

    @objc dynamic var showAIChatVoiceSearch: Bool {
        get {
            value(forKey: Keys.showAIChatVoiceSearch) as? Bool ?? Self.showAIChatVoiceSearchDefaultValue
        }

        set {
            guard newValue != showAIChatVoiceSearch else { return }
            set(newValue, forKey: Keys.showAIChatVoiceSearch)
        }
    }

    @objc dynamic var showAIChatAddressBar: Bool {
        get {
            value(forKey: Keys.showAIChatAddressBar) as? Bool ?? Self.showAIChatAddressBarDefaultValue
        }

        set {
            guard newValue != showAIChatAddressBar else { return }
            set(newValue, forKey: Keys.showAIChatAddressBar)
        }
    }

    @objc dynamic var showAIChatExperimentalSearchInput: Bool {
        get {
            value(forKey: Keys.showAIChatExperimentalSearchInput) as? Bool ?? Self.showAIChatExperimentalSearchInputDefaultValue
        }

        set {
            guard newValue != showAIChatExperimentalSearchInput else { return }
            set(newValue, forKey: Keys.showAIChatExperimentalSearchInput)
        }
    }

    @objc dynamic var showAIChatTabSwitcher: Bool {
        get {
            value(forKey: Keys.showAIChatTabSwitcher) as? Bool ?? Self.showAIChatTabSwitcherDefaultValue
        }

        set {
            guard newValue != showAIChatTabSwitcher else { return }
            set(newValue, forKey: Keys.showAIChatTabSwitcher)
        }
    }
}

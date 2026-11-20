//
//  IOSLaunchSettings+DuckAI.swift
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

#if DEBUG || ALPHA

import AIChat
import Foundation
import LaunchProfile

/// Duck.ai settings, saved under the keys `AIChatSettings` reads. They persist like a change in Settings.
/// `AIChatSettings`'s own setters send pixels and need the app's services, so they can't run this early.
extension IOSLaunchSettings {

    private typealias Keys = LegacyAiChatUserDefaultsKeys

    private static let toggles: [(key: String, summary: String, storageKey: String)] = [
        ("duckAI.enabled", "Turns Duck.ai on or off everywhere.", Keys.isAIChatEnabledKey),
        ("duckAI.addressBar", "Shows Duck.ai in the address bar.", Keys.showAIChatAddressBarKey),
        ("duckAI.searchInput", "Uses the search and Duck.ai toggle in the address bar.", Keys.showAIChatExperimentalSearchInputKey),
        ("duckAI.browsingMenu", "Shows Duck.ai in the browsing menu.", Keys.showAIChatBrowsingMenuKey),
        ("duckAI.voiceSearch", "Shows Duck.ai in voice search.", Keys.showAIChatVoiceSearchKey),
        ("duckAI.tabSwitcher", "Shows Duck.ai in the tab switcher.", Keys.showAIChatTabSwitcherKey),
    ]

    static func duckAI(_ store: UserDefaults) -> [LaunchSetting] {
        toggles.map { toggle in
            LaunchSetting(toggle.key, summary: toggle.summary) { (isOn: Bool) in
                store.set(isOn, forKey: toggle.storageKey)
            }
        } + [defaultOmnibarMode(store)]
    }

    static func defaultOmnibarMode(_ store: UserDefaults) -> LaunchSetting {
        .choice("duckAI.defaultOmnibarMode",
                summary: "Mode the address bar starts in. Read only while the aiChatOmnibarDefaultPosition flag is on.",
                options: DefaultOmnibarMode.allCases,
                name: \.rawValue) { store.set($0.rawValue, forKey: Keys.defaultOmnibarModeKey) }
    }
}

#endif

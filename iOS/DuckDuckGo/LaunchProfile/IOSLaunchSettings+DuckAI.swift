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
import LaunchProfile

/// Duck.ai settings, written through `AIChatUserSettingsStore` like a change in Settings. They persist.
extension IOSLaunchSettings {

    private static let toggles: [(key: String, summary: String, toggle: AIChatUserSettingsStore.Toggle)] = [
        ("duckAI.enabled", "Turns Duck.ai on or off everywhere.", .duckAI),
        ("duckAI.addressBar", "Shows Duck.ai in the address bar.", .addressBar),
        ("duckAI.searchInput", "Uses the search and Duck.ai toggle in the address bar.", .searchInput),
        ("duckAI.browsingMenu", "Shows Duck.ai in the browsing menu.", .browsingMenu),
        ("duckAI.voiceSearch", "Shows Duck.ai in voice search.", .voiceSearch),
        ("duckAI.tabSwitcher", "Shows Duck.ai in the tab switcher.", .tabSwitcher),
    ]

    static func duckAI(_ store: AIChatUserSettingsStore) -> [LaunchSetting] {
        toggles.map { toggle in
            LaunchSetting(toggle.key, summary: toggle.summary) { (isOn: Bool) in
                store.set(toggle.toggle, isOn: isOn)
            }
        } + [defaultOmnibarMode(store), pageSummariesModel(store)]
    }

    static func defaultOmnibarMode(_ store: AIChatUserSettingsStore) -> LaunchSetting {
        .choice("duckAI.defaultOmnibarMode",
                summary: "Mode the address bar starts in. Read only while the aiChatOmnibarDefaultPosition flag is on.",
                options: DefaultOmnibarMode.allCases,
                name: \.rawValue) { store.setDefaultOmnibarMode($0) }
    }

    static func pageSummariesModel(_ store: AIChatUserSettingsStore) -> LaunchSetting {
        .choice("duckAI.pageSummariesModel",
                summary: "Model that summarizes pages.",
                options: AIChatPageSummariesModel.allCases,
                name: { String(describing: $0) }) { store.setPageSummariesModel($0) }
    }
}

#endif

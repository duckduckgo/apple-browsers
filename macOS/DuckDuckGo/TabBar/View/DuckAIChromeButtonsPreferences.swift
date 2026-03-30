//
//  DuckAIChromeButtonsPreferences.swift
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

import Persistence
import Foundation

struct DuckAIChromeButtonsUserDefaultsPersistor {

    enum Key: String {
        case isDuckAIButtonHidden = "duck-ai-chrome.title-button.hidden"
        case isSidebarButtonHidden = "duck-ai-chrome.sidebar-button.hidden"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var isDuckAIButtonHidden: Bool {
        get { boolValue(for: .isDuckAIButtonHidden) }
        set { set(newValue, for: .isDuckAIButtonHidden) }
    }

    var isSidebarButtonHidden: Bool {
        get { boolValue(for: .isSidebarButtonHidden) }
        set { set(newValue, for: .isSidebarButtonHidden) }
    }

    private func boolValue(for key: Key) -> Bool {
        keyValueStore.object(forKey: key.rawValue) as? Bool ?? false
    }

    private func set(_ value: Bool, for key: Key) {
        keyValueStore.set(value, forKey: key.rawValue)
    }

}

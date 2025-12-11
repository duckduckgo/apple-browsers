//
//  TabSwitcherSettings.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

protocol TabSwitcherSettings: AnyObject {

    var isGridViewEnabled: Bool { get set }
    var hasSeenNewLayout: Bool { get set }
    var showTrackerCountInTabSwitcher: Bool { get set }

}

final class DefaultTabSwitcherSettings: TabSwitcherSettings {

    enum Key: String {
        case gridViewEnabled = "com.duckduckgo.ios.tabs.grid"
        case gridViewSeen = "com.duckduckgo.ios.tabs.seen"
        case showTrackerCount = "com.duckduckgo.ios.tabswitcher.showTrackerCount"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults.app) {
        self.keyValueStore = keyValueStore
    }

    var isGridViewEnabled: Bool {
        get { keyValueStore.object(forKey: Key.gridViewEnabled.rawValue) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Key.gridViewEnabled.rawValue) }
    }

    var hasSeenNewLayout: Bool {
        get { keyValueStore.object(forKey: Key.gridViewSeen.rawValue) as? Bool ?? false }
        set { keyValueStore.set(newValue, forKey: Key.gridViewSeen.rawValue) }
    }

    var showTrackerCountInTabSwitcher: Bool {
        get { keyValueStore.object(forKey: Key.showTrackerCount.rawValue) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Key.showTrackerCount.rawValue) }
    }

}

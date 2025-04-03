//
//  TabsPreferences.swift
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

protocol TabsPreferencesPersistor {
    var switchToNewTabWhenOpened: Bool { get set }
    var preferNewTabsToWindows: Bool { get set }
    var newTabPosition: NewTabPosition { get set }
    var sharedPinnedTabs: Bool { get set }
}

struct TabsPreferencesUserDefaultsPersistor: TabsPreferencesPersistor {
    @UserDefaultsWrapper(key: .preferNewTabsToWindows, defaultValue: true)
    var preferNewTabsToWindows: Bool

    @UserDefaultsWrapper(key: .switchToNewTabWhenOpened, defaultValue: false)
    var switchToNewTabWhenOpened: Bool

    @UserDefaultsWrapper(key: .newTabPosition, defaultValue: .atEnd)
    var newTabPosition: NewTabPosition

    @UserDefaultsWrapper(key: .sharedPinnedTabs, defaultValue: true)
    var sharedPinnedTabs: Bool
}

final class TabsPreferences: ObservableObject, PreferencesTabOpening {

    static let shared = TabsPreferences()

    @Published var preferNewTabsToWindows: Bool {
        didSet {
            persistor.preferNewTabsToWindows = preferNewTabsToWindows
        }
    }

    @Published var switchToNewTabWhenOpened: Bool {
        didSet {
            persistor.switchToNewTabWhenOpened = switchToNewTabWhenOpened
        }
    }

    @Published var newTabPosition: NewTabPosition {
        didSet {
            persistor.newTabPosition = newTabPosition
        }
    }

    @Published var pinnedTabsMode: PinnedTabsMode {
        didSet {
            persistor.sharedPinnedTabs = pinnedTabsMode == .shared
        }
    }

    init(persistor: TabsPreferencesPersistor = TabsPreferencesUserDefaultsPersistor()) {
        self.persistor = persistor
        preferNewTabsToWindows = persistor.preferNewTabsToWindows
        switchToNewTabWhenOpened = persistor.switchToNewTabWhenOpened
        newTabPosition = persistor.newTabPosition
        pinnedTabsMode = persistor.sharedPinnedTabs ? .shared : .separate
    }

    private var persistor: TabsPreferencesPersistor

    // MARK: - Pinned Tabs Setting Migration

    @UserDefaultsWrapper(key: .pinnedTabsMigrated, defaultValue: false)
    var pinnedTabsMigrated: Bool

    func migratePinnedTabsSettingIfNecessary(_ collection: TabCollection?) {
        guard !pinnedTabsMigrated else { return }
        pinnedTabsMigrated = true

        // Set the shared pinned tabs setting only in case shared pinned tabs are restored
        if let collection, !collection.tabs.isEmpty {
            pinnedTabsMode = .shared
        } else {
            pinnedTabsMode = .separate
        }
    }
}

enum NewTabPosition: String, CaseIterable {
    case atEnd
    case nextToCurrent
}

enum PinnedTabsMode: String, CaseIterable {
    case shared
    case separate
}

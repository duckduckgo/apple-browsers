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
import Persistence

protocol TabsPreferencesPersistor {
    var switchToNewTabWhenOpened: Bool { get set }
    var preferNewTabsToWindows: Bool { get set }
    var newTabPosition: NewTabPosition { get set }
    var sharedPinnedTabs: Bool { get set }
    var warnBeforeQuitting: Bool { get set }
    var warnBeforeClosingPinnedTabs: Bool { get set }
}

struct TabsPreferencesUserDefaultsPersistor: TabsPreferencesPersistor {

    var preferNewTabsToWindows: Bool {
        get {
            (try? keyValueStore.object(forKey: UserDefaultsWrapper<Any>.Key.preferNewTabsToWindows.rawValue) as? Bool) ?? true
        }
        set {
            try? keyValueStore.set(newValue, forKey: UserDefaultsWrapper<Any>.Key.preferNewTabsToWindows.rawValue)
        }
    }

    var switchToNewTabWhenOpened: Bool {
        get {
            (try? keyValueStore.object(forKey: UserDefaultsWrapper<Any>.Key.switchToNewTabWhenOpened.rawValue) as? Bool) ?? false
        }
        set {
            try? keyValueStore.set(newValue, forKey: UserDefaultsWrapper<Any>.Key.switchToNewTabWhenOpened.rawValue)
        }
    }

    var newTabPosition: NewTabPosition {
        get {
            guard let rawValue = try? keyValueStore.object(forKey: UserDefaultsWrapper<Any>.Key.newTabPosition.rawValue) as? String else {
                return .atEnd
            }
            return NewTabPosition(rawValue: rawValue) ?? .atEnd
        }
        set {
            try? keyValueStore.set(newValue.rawValue, forKey: UserDefaultsWrapper<Any>.Key.newTabPosition.rawValue)
        }
    }

    var sharedPinnedTabs: Bool {
        get {
            (try? keyValueStore.object(forKey: UserDefaultsWrapper<Any>.Key.sharedPinnedTabs.rawValue) as? Bool) ?? true
        }
        set {
            try? keyValueStore.set(newValue, forKey: UserDefaultsWrapper<Any>.Key.sharedPinnedTabs.rawValue)
        }
    }

    var warnBeforeQuitting: Bool {
        get {
            (try? keyValueStore.object(forKey: UserDefaultsWrapper<Any>.Key.warnBeforeQuitting.rawValue) as? Bool) ?? true
        }
        set {
            try? keyValueStore.set(newValue, forKey: UserDefaultsWrapper<Any>.Key.warnBeforeQuitting.rawValue)
        }
    }

    var warnBeforeClosingPinnedTabs: Bool {
        get {
            (try? keyValueStore.object(forKey: UserDefaultsWrapper<Any>.Key.warnBeforeClosingPinnedTabs.rawValue) as? Bool) ?? true
        }
        set {
            try? keyValueStore.set(newValue, forKey: UserDefaultsWrapper<Any>.Key.warnBeforeClosingPinnedTabs.rawValue)
        }
    }

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    private let keyValueStore: ThrowingKeyValueStoring
}

final class TabsPreferences: ObservableObject, PreferencesTabOpening {

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

    @Published var warnBeforeQuitting: Bool {
        didSet {
            persistor.warnBeforeQuitting = warnBeforeQuitting
        }
    }

    @Published var warnBeforeClosingPinnedTabs: Bool {
        didSet {
            persistor.warnBeforeClosingPinnedTabs = warnBeforeClosingPinnedTabs
        }
    }

    init(
        persistor: TabsPreferencesPersistor,
        windowControllersManager: WindowControllersManagerProtocol
    ) {
        self.persistor = persistor
        self.windowControllersManager = windowControllersManager
        preferNewTabsToWindows = persistor.preferNewTabsToWindows
        switchToNewTabWhenOpened = persistor.switchToNewTabWhenOpened
        newTabPosition = persistor.newTabPosition
        pinnedTabsMode = persistor.sharedPinnedTabs ? .shared : .separate
        warnBeforeQuitting = persistor.warnBeforeQuitting
        warnBeforeClosingPinnedTabs = persistor.warnBeforeClosingPinnedTabs
    }

    let windowControllersManager: WindowControllersManagerProtocol
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

#if DEBUG
final class MockTabsPreferencesPersistor: TabsPreferencesPersistor {
    var preferNewTabsToWindows: Bool = false
    var switchToNewTabWhenOpened: Bool = false
    var newTabPosition: NewTabPosition = .atEnd
    var sharedPinnedTabs: Bool = false
    var warnBeforeQuitting: Bool = true
    var warnBeforeClosingPinnedTabs: Bool = true
}
#endif

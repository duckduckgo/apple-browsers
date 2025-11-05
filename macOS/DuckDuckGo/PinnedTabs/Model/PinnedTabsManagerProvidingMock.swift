//
//  PinnedTabsManagerProvidingMock.swift
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
#if DEBUG
import Combine

final class PinnedTabsManagerProvidingMock: PinnedTabsManagerProviding {
    var pinnedTabsMode: PinnedTabsMode = .shared
    var arePinnedTabsEmpty: Bool = true
    var currentPinnedTabManagers: [PinnedTabsManager] = []
    var areDifferentPinnedTabsPresent: Bool = false

    private var settingChangedSubject = PassthroughSubject<Void, Never>()
    var settingChangedPublisher: AnyPublisher<Void, Never> {
        settingChangedSubject.eraseToAnyPublisher()
    }

    private var _newPinnedTabsManager: PinnedTabsManager?
    var newPinnedTabsManager: PinnedTabsManager {
        get {
            if let newPinnedTabsManager = _newPinnedTabsManager {
                return newPinnedTabsManager
            }
            assert(_newPinnedTabsManager == nil && _pinnedTabsManager == nil, """
            It seems you‘re setting incorrect Pinned Tabs Manager not actually used in the test.
            You should either set both `newPinnedTabsManager` and `pinnedTabsManager` - if they‘re both actually used,
            or leave both unset - to use the default (empty) values for them.
            """)
            _newPinnedTabsManager = PinnedTabsManager()
            _pinnedTabsManager = PinnedTabsManager()
            return _newPinnedTabsManager!
        }
        set {
            assert(_newPinnedTabsManager == nil, "newPinnedTabManager is already set")
            _newPinnedTabsManager = newValue
        }
    }
    func getNewPinnedTabsManager(shouldMigrate: Bool, tabCollectionViewModel: TabCollectionViewModel, forceActive: Bool? = nil) -> PinnedTabsManager {
        return newPinnedTabsManager
    }

    private var _pinnedTabsManager: PinnedTabsManager?
    var pinnedTabsManager: PinnedTabsManager {
        get {
            if let pinnedTabsManager = _pinnedTabsManager {
                return pinnedTabsManager
            }
            assert(_newPinnedTabsManager == nil && _pinnedTabsManager == nil, """
            It seems you‘re setting incorrect Pinned Tabs Manager not actually used in the test.
            You should either set both `newPinnedTabsManager` and `pinnedTabsManager` - if they‘re both actually used,
            or leave both unset - to use the default (empty) values for them.
            """)
            _newPinnedTabsManager = PinnedTabsManager()
            _pinnedTabsManager = PinnedTabsManager()
            return _pinnedTabsManager!
        }
        set {
            assert(_pinnedTabsManager == nil, "pinnedTabManager is already set")
            _pinnedTabsManager = newValue
        }
    }
    func pinnedTabsManager(for tab: Tab) -> PinnedTabsManager? {
        return pinnedTabsManager
    }

    func cacheClosedWindowPinnedTabsIfNeeded(pinnedTabsManager: PinnedTabsManager?) {}

    func triggerSettingChange() {
        settingChangedSubject.send(())
    }
}
#endif

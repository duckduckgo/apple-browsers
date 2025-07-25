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

@testable import DuckDuckGo_Privacy_Browser
import Combine

class PinnedTabsManagerProvidingMock: PinnedTabsManagerProviding {
    var pinnedTabsMode: PinnedTabsMode = .shared
    var arePinnedTabsEmpty: Bool = true
    var currentPinnedTabManagers: [PinnedTabsManager] = []
    var areDifferentPinnedTabsPresent: Bool = false

    private var settingChangedSubject = PassthroughSubject<Void, Never>()
    var settingChangedPublisher: AnyPublisher<Void, Never> {
        settingChangedSubject.eraseToAnyPublisher()
    }

    var newPinnedTabsManager = PinnedTabsManager()
    func getNewPinnedTabsManager(shouldMigrate: Bool, tabCollectionViewModel: TabCollectionViewModel, forceActive: Bool? = nil) -> PinnedTabsManager {
        return newPinnedTabsManager
    }

    var pinnedTabsManager = PinnedTabsManager()
    func pinnedTabsManager(for tab: Tab) -> PinnedTabsManager? {
        return pinnedTabsManager
    }

    func cacheClosedWindowPinnedTabsIfNeeded(pinnedTabsManager: PinnedTabsManager?) {}

    func triggerSettingChange() {
        settingChangedSubject.send(())
    }
}

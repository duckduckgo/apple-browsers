//
//  PinnedTabsManagerProvider.swift
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

protocol PinnedTabsManagerProviding {

    var arePerWindowPinnedTabsEnabled: Bool { get }
    func pinnedTabsManager() -> PinnedTabsManager
    func pinnedTabsManager(for tab: Tab) -> PinnedTabsManager?

}

class PinnedTabsManagerProvider: @preconcurrency PinnedTabsManagerProviding {

    var arePerWindowPinnedTabsEnabled: Bool {
        return true
    }

    func pinnedTabsManager() -> PinnedTabsManager {
        if arePerWindowPinnedTabsEnabled {
            return PinnedTabsManager()
        } else {
            return Application.appDelegate.pinnedTabsManager
        }
    }

    @MainActor
    func pinnedTabsManager(for tab: Tab) -> PinnedTabsManager? {
        if arePerWindowPinnedTabsEnabled {
            let tabCollectionViewModel = WindowControllersManager.shared.allTabCollectionViewModels.first { tabCollectionViewModel in
                tabCollectionViewModel.tabCollection.tabs.contains(tab)
            }
            return tabCollectionViewModel?.pinnedTabsManager
        } else {
            return Application.appDelegate.pinnedTabsManager
        }
    }

}

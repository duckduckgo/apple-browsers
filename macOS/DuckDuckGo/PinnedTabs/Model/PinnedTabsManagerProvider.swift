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

import Combine

protocol PinnedTabsManagerProviding {

    var arePerWindowPinnedTabsEnabled: Bool { get }
    var arePinnedTabsEmpty: Bool { get }
    var currentPinnedTabManagers: [PinnedTabsManager] { get }

    func getNewPinnedTabsManager(shouldMigrate: Bool,
                                 tabCollectionViewModel: TabCollectionViewModel) -> PinnedTabsManager
    func pinnedTabsManager(for tab: Tab) -> PinnedTabsManager?

    func cacheClosedWindowPinnedTabsIfNeeded(pinnedTabsManager: PinnedTabsManager?)

    var settingChangedPublisher: AnyPublisher<Void, Never> { get }

}

class PinnedTabsManagerProvider: @preconcurrency PinnedTabsManagerProviding {

    private let tabsPreferences: TabsPreferences

    var closedWindowPinnedTabCollectionCache: TabCollection?
    var settingChangedPublisher: AnyPublisher<Void, Never>

    init(tabsPreferences: TabsPreferences = TabsPreferences.shared) {
        self.tabsPreferences = tabsPreferences

        settingChangedPublisher = tabsPreferences.$sharedPinnedTabs
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    @MainActor
    private var windowControllerManager: WindowControllersManagerProtocol {
        return WindowControllersManager.shared
    }

    @MainActor
    private var allPerWindowPinnedTabsManagers: [PinnedTabsManager] {
        return windowControllerManager.allTabCollectionViewModels
            .compactMap { $0.pinnedTabsManager }
            .filter { $0 !== Application.appDelegate.pinnedTabsManager }
    }

    var arePerWindowPinnedTabsEnabled: Bool {
        return !tabsPreferences.sharedPinnedTabs
    }

    @MainActor
    var arePinnedTabsEmpty: Bool {
        if arePerWindowPinnedTabsEnabled {
            return allPerWindowPinnedTabsManagers.contains(where: \.tabCollection.tabs.isEmpty)
        } else {
            return Application.appDelegate.pinnedTabsManager.tabCollection.tabs.isEmpty
        }
    }

    @MainActor
    var currentPinnedTabManagers: [PinnedTabsManager] {
        if arePerWindowPinnedTabsEnabled {
            return allPerWindowPinnedTabsManagers
        } else {
            return [Application.appDelegate.pinnedTabsManager]
        }
    }

    @MainActor
    func getNewPinnedTabsManager(shouldMigrate: Bool = false,
                                 tabCollectionViewModel: TabCollectionViewModel) -> PinnedTabsManager {
        if arePerWindowPinnedTabsEnabled {
            let isFirstWindow = windowControllerManager.mainWindowControllers.isEmpty
            let isActiveWindow = windowControllerManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel === tabCollectionViewModel

            let newPinnedTabsManager = PinnedTabsManager()

            if isFirstWindow && !shouldMigrate, let closedWindowPinnedTabCollectionCache {
                newPinnedTabsManager.setUp(with: closedWindowPinnedTabCollectionCache)
                self.closedWindowPinnedTabCollectionCache = nil
            }

            if shouldMigrate && isActiveWindow {
                for currentlyPinnedTab in Application.appDelegate.pinnedTabsManager.tabCollection.tabs {
                    // Duplicate tabs and add to new pinned tabs manager
                    guard let url = currentlyPinnedTab.url else {
                        continue
                    }
                    let newTab = Tab(content: .url(url, source: .ui))
                    newPinnedTabsManager.pin(newTab)
                }

                // Clear pinned tabs
                Application.appDelegate.pinnedTabsManager.tabCollection.removeAll()
            }
            return newPinnedTabsManager
        } else {
            if shouldMigrate {
                // Collect tabs from per-window pinned tabs managers
                var tabs = [Tab]()
                for perWindowPinnedTabManager in allPerWindowPinnedTabsManagers {
                    for pinnedTab in perWindowPinnedTabManager.tabCollection.tabs {
                        if !tabs.contains(where: { $0.content == pinnedTab.content }) {
                            tabs.append(pinnedTab)
                        }
                    }
                }

                // Remove from original place
                for perWindowPinnedTabManager in allPerWindowPinnedTabsManagers {
                    perWindowPinnedTabManager.tabCollection.removeAll()
                }

                // Add to the shared pinned tabs manager
                for tab in tabs {
                    Application.appDelegate.pinnedTabsManager.pin(tab)
                }
            }
            return Application.appDelegate.pinnedTabsManager
        }
    }

    @MainActor
    func pinnedTabsManager(for tab: Tab) -> PinnedTabsManager? {
        if arePerWindowPinnedTabsEnabled {
            let tabCollectionViewModel = windowControllerManager.allTabCollectionViewModels.first { tabCollectionViewModel in
                tabCollectionViewModel.tabs.contains(tab) || tabCollectionViewModel.pinnedTabs.contains(tab)
            }
            return tabCollectionViewModel?.pinnedTabsManager
        } else {
            return Application.appDelegate.pinnedTabsManager
        }
    }

    @MainActor
    func cacheClosedWindowPinnedTabsIfNeeded(pinnedTabsManager: PinnedTabsManager?) {
        guard let pinnedTabsManager, arePerWindowPinnedTabsEnabled else { return }
        let isLastWindow = windowControllerManager.mainWindowControllers.count == 1
        guard isLastWindow else { return }

        closedWindowPinnedTabCollectionCache = pinnedTabsManager.tabCollection.duplicate()
    }

}

fileprivate extension TabCollection {

    @MainActor
    func duplicate() -> TabCollection {
        let duplicatedCollection = TabCollection()

        for tab in self.tabs {
            guard let url = tab.url else {
                continue
            }
            let newTab = Tab(content: .url(url, source: .ui))
            duplicatedCollection.append(tab: newTab)
        }

        return duplicatedCollection
    }
}

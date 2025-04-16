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

    /// Pinned tabs mode currently set in Settings
    var pinnedTabsMode: PinnedTabsMode { get }

    /// True if there are no pinned tabs in the whole application
    var arePinnedTabsEmpty: Bool { get }

    /// Returns all currently used pinned tabs managers
    var currentPinnedTabManagers: [PinnedTabsManager] { get }

    /// True if per-window pinned tabs are enabled and there are different sets of pinnned tabs present in current windows
    var areDifferentPinnedTabsPresent: Bool { get }

    /// Returns a current PinnedTabsManager for a specific tab
    func pinnedTabsManager(for tab: Tab) -> PinnedTabsManager?

    /// Returns a PinnedTabsManager for each window depending on the current setting
    /// It also encapsulates a logic to migrate, in case the setting have been switched and windows are asking for a new PinnedTabsManager
    func getNewPinnedTabsManager(shouldMigrate: Bool,
                                 tabCollectionViewModel: TabCollectionViewModel) -> PinnedTabsManager

    /// Caches a set of pinned tabs
    /// Used to restore a set of pinned tabs of the last closed window when per-window pinned tabs are used
    func cacheClosedWindowPinnedTabsIfNeeded(pinnedTabsManager: PinnedTabsManager?)

    /// Publishes an event when the pinned tabs setting is switched
    var settingChangedPublisher: AnyPublisher<Void, Never> { get }

}

/// Encapsulates logic to manage per-window pinned tabs or shared pinned tabs
final class PinnedTabsManagerProvider: @preconcurrency PinnedTabsManagerProviding {

    private let tabsPreferences: TabsPreferences
    private var closedWindowPinnedTabCache: TabCollection?

    var settingChangedPublisher: AnyPublisher<Void, Never>

    init(tabsPreferences: TabsPreferences = TabsPreferences.shared) {
        self.tabsPreferences = tabsPreferences
        self.settingChangedPublisher = tabsPreferences.$pinnedTabsMode
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .eraseToAnyPublisher()
    }

    private var sharedPinnedTabsManager: PinnedTabsManager {
        Application.appDelegate.pinnedTabsManager
    }

    @MainActor
    private var windowControllerManager: WindowControllersManagerProtocol {
        WindowControllersManager.shared
    }

    @MainActor
    private var perWindowPinnedTabsManagers: [PinnedTabsManager] {
        windowControllerManager.allTabCollectionViewModels
            .compactMap { $0.pinnedTabsManager }
            .filter { $0 !== sharedPinnedTabsManager }
    }

    var pinnedTabsMode: PinnedTabsMode {
        tabsPreferences.pinnedTabsMode
    }

    @MainActor
    var arePinnedTabsEmpty: Bool {
        if pinnedTabsMode == .separate {
            return perWindowPinnedTabsManagers.allSatisfy { $0.tabCollection.tabs.isEmpty }
        }
        return sharedPinnedTabsManager.tabCollection.tabs.isEmpty
    }

    @MainActor
    var currentPinnedTabManagers: [PinnedTabsManager] {
        switch pinnedTabsMode {
        case .separate:
            return perWindowPinnedTabsManagers
        case .shared:
            return [sharedPinnedTabsManager]
        }
    }

    @MainActor
    var areDifferentPinnedTabsPresent: Bool {
        pinnedTabsMode == .separate && perWindowPinnedTabsManagers.filter { !$0.tabCollection.tabs.isEmpty }.count >= 2
    }

    @MainActor
    func pinnedTabsManager(for tab: Tab) -> PinnedTabsManager? {
        switch pinnedTabsMode {
        case .separate:
            return windowControllerManager.allTabCollectionViewModels.first(where: { $0.tabs.contains(tab) || $0.pinnedTabs.contains(tab) })?.pinnedTabsManager
        case .shared:
            return sharedPinnedTabsManager
        }
    }

    // MARK: Providing PinnedTabsManagers

    @MainActor
    func getNewPinnedTabsManager(shouldMigrate: Bool = false, tabCollectionViewModel: TabCollectionViewModel) -> PinnedTabsManager {
        switch pinnedTabsMode {
        case .separate:
            return getNewPerWindowPinnedTabsManager(shouldMigrate: shouldMigrate,
                                                    tabCollectionViewModel: tabCollectionViewModel)
        case .shared:
            return getSharedPinnedTabManager(shouldMigrate: shouldMigrate)
        }
    }

    @MainActor
    private func getNewPerWindowPinnedTabsManager(shouldMigrate: Bool, tabCollectionViewModel: TabCollectionViewModel) -> PinnedTabsManager {
        let newPinnedTabsManager = PinnedTabsManager()
        let isFirstWindow = windowControllerManager.mainWindowControllers.isEmpty
        let isActiveWindow = windowControllerManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel === tabCollectionViewModel

        if isFirstWindow, !shouldMigrate, let cachedTabs = closedWindowPinnedTabCache {
            newPinnedTabsManager.setUp(with: cachedTabs)
            closedWindowPinnedTabCache = nil
        }

        if shouldMigrate, isActiveWindow {
            migrateShared(to: newPinnedTabsManager)
        }

        return newPinnedTabsManager
    }

    @MainActor
    private func migrateShared(to newPinnedTabsManager: PinnedTabsManager) {
        for tab in sharedPinnedTabsManager.tabCollection.tabs {
            guard let url = tab.url else { continue }
            let newTab = Tab(content: .url(url, source: .ui))
            newPinnedTabsManager.pin(newTab, firePixel: false)
        }
        sharedPinnedTabsManager.tabCollection.removeAll()
    }

    @MainActor
    private func getSharedPinnedTabManager(shouldMigrate: Bool) -> PinnedTabsManager {
        if shouldMigrate {
            migrateAllPerWindowPinnedTabsToShared()
        }
        return sharedPinnedTabsManager
    }

    @MainActor
    private func migrateAllPerWindowPinnedTabsToShared() {
        let allTabs = perWindowPinnedTabsManagers.flatMap { $0.tabCollection.tabs }
        perWindowPinnedTabsManagers.forEach { $0.tabCollection.removeAll() }
        allTabs.forEach { sharedPinnedTabsManager.pin($0, firePixel: false) }
    }

    // MARK: Cache

    @MainActor
    func cacheClosedWindowPinnedTabsIfNeeded(pinnedTabsManager: PinnedTabsManager?) {
        guard let pinnedTabsManager,
              pinnedTabsMode == .separate,
                windowControllerManager.mainWindowControllers.count == 1 else { return }
        closedWindowPinnedTabCache = pinnedTabsManager.tabCollection.duplicate()
    }
}

fileprivate extension TabCollection {
    @MainActor
    func duplicate() -> TabCollection {
        let duplicatedCollection = TabCollection()
        for tab in tabs {
            if let url = tab.url {
                duplicatedCollection.append(tab: Tab(content: .url(url, source: .ui)))
            }
        }
        return duplicatedCollection
    }
}

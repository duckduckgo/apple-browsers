//
//  PinnedTabsManagerProviderTests.swift
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

import XCTest
import Combine
@testable import DuckDuckGo_Privacy_Browser

class MockTabsPreferencesPersistor: TabsPreferencesPersistor {
    var preferNewTabsToWindows: Bool = false
    var switchToNewTabWhenOpened: Bool = false
    var newTabPosition: NewTabPosition = .atEnd
    var sharedPinnedTabs: Bool = false
}

final class PinnedTabsManagerProviderTests: XCTestCase {

    private var provider: PinnedTabsManagerProvider!
    private var tabsPreferences: TabsPreferences!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        tabsPreferences = TabsPreferences(persistor: MockTabsPreferencesPersistor())
        provider = PinnedTabsManagerProvider(tabsPreferences: tabsPreferences)
    }

    @MainActor
    override func tearDown() {
        provider = nil
        tabsPreferences = nil
        cancellables.removeAll()

        WindowControllersManager.shared.mainWindowControllers.forEach { $0.close() }
        super.tearDown()
    }

    func test_providerReturnsSameModeAsTabsPreferences() {
        XCTAssertTrue(provider.pinnedTabsMode == tabsPreferences.pinnedTabsMode)
    }

    func test_WhenSettingChanged_ThenPublisherEmitsValue() {
        let expectation = expectation(description: "Publisher emits value")
        provider.settingChangedPublisher
            .sink { _ in
            expectation.fulfill()
        }.store(in: &cancellables)

        tabsPreferences.pinnedTabsMode = .separate

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func test_WhenNoTabsExist_ThenArePinnedTabsEmptyReturnsTrueForShared() {
        tabsPreferences.pinnedTabsMode = .shared
        XCTAssertTrue(provider.arePinnedTabsEmpty)
    }

    @MainActor
    func test_WhenNoTabsExist_ThenArePinnedTabsEmptyReturnsTrueForSeparate() {
        tabsPreferences.pinnedTabsMode = .separate
        XCTAssertTrue(provider.arePinnedTabsEmpty)
    }

    @MainActor
    func test_WhenTabsExistAndPinnedTabsModeIsSeparate_ThenArePinnedTabsEmptyReturnsFalse() {
        tabsPreferences.pinnedTabsMode = .separate
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: provider)
        _ = WindowsManager.openNewWindow(with: tabCollectionViewModel)
        tabCollectionViewModel.pinnedTabsManager!.pin(Tab(content: .none))

        XCTAssertFalse(provider.arePinnedTabsEmpty)
    }

    @MainActor
    func test_WhenTabsExistAndPinnedTabsModeIsShared_ThenArePinnedTabsEmptyReturnsFalse() {
        tabsPreferences.pinnedTabsMode = .shared
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: provider)
        _ = WindowsManager.openNewWindow(with: tabCollectionViewModel)
        tabCollectionViewModel.pinnedTabsManager!.pin(Tab(content: .none))

        XCTAssertFalse(provider.arePinnedTabsEmpty)
    }

    @MainActor
    func test_WhenGettingNewPinnedTabsManagerInSharedModeWithoutMigration_ThenReturnsSharedManager() {
        tabsPreferences.pinnedTabsMode = .shared
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: provider)

        let manager = provider.getNewPinnedTabsManager(shouldMigrate: false, tabCollectionViewModel: tabCollectionViewModel)

        XCTAssertNotNil(manager)
        XCTAssert(manager === Application.appDelegate.pinnedTabsManager)
    }

    @MainActor
    func test_WhenGettingNewPinnedTabsManagerInSeparateModeWithoutMigration_ThenReturnsNewInstance() {
        tabsPreferences.pinnedTabsMode = .separate
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: provider)

        let manager = provider.getNewPinnedTabsManager(shouldMigrate: false, tabCollectionViewModel: tabCollectionViewModel)

        XCTAssertNotNil(manager)
        XCTAssert(manager !== Application.appDelegate.pinnedTabsManager)
        XCTAssertFalse(provider.currentPinnedTabManagers.contains { $0 === manager })
    }

    @MainActor
    func test_WhenMigratingFromSharedToPerWindow_ThenTabsAreMigratedToFirstNewPerWindowManager() async {
        // Start in shared mode and add a tab to shared pinned tabs manager
        tabsPreferences.pinnedTabsMode = .shared

        let sharedManager = Application.appDelegate.pinnedTabsManager
        let sharedTab = Tab(content: .url(URL(string: "https://duckduckgo.com")!, source: .ui))
        sharedManager.pin(sharedTab)

        // Switch mode and get new pinned tab managers
        tabsPreferences.pinnedTabsMode = .separate

        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: provider)
        let window = WindowsManager.openNewWindow(with: tabCollectionViewModel)
        window?.makeKeyAndOrderFront(nil)

        try? await Task.sleep(interval: 1)

        let newManager = provider.getNewPinnedTabsManager(shouldMigrate: true, tabCollectionViewModel: tabCollectionViewModel)

        let secondNewManager = provider.getNewPinnedTabsManager(shouldMigrate: true, tabCollectionViewModel: TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: provider))

        XCTAssert(newManager.tabCollection.tabs.contains(where: { $0.url == sharedTab.url }))
        XCTAssert(secondNewManager.tabCollection.tabs.isEmpty)
        XCTAssert(sharedManager.tabCollection.tabs.isEmpty)
    }

    @MainActor
    func test_WhenMigratingFromPerWindowToShared_ThenTabsAreMigratedToSharedManager() async {
        // Start in separate mode and create two windows with pinned tabs
        tabsPreferences.pinnedTabsMode = .separate

        let firstTabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: provider)
        let firstWindow = WindowsManager.openNewWindow(with: firstTabCollectionViewModel)
        firstWindow?.makeKeyAndOrderFront(nil)

        let tab1 = Tab(content: .url(URL(string: "https://first.com")!, source: .ui))
        firstTabCollectionViewModel.pinnedTabsManager!.pin(tab1)

        let secondTabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: provider)
        let secondWindow = WindowsManager.openNewWindow(with: secondTabCollectionViewModel)
        secondWindow?.makeKeyAndOrderFront(nil)

        let tab2 = Tab(content: .url(URL(string: "https://second.com")!, source: .ui))
        secondTabCollectionViewModel.pinnedTabsManager!.pin(tab2)

        try? await Task.sleep(interval: 1)

        // Switch to shared mode and trigger migration
        tabsPreferences.pinnedTabsMode = .shared

        let sharedManager = provider.getNewPinnedTabsManager(shouldMigrate: true, tabCollectionViewModel: firstTabCollectionViewModel)

        let urls = sharedManager.tabCollection.tabs.compactMap { $0.url?.absoluteString }

        XCTAssertTrue(urls.contains("https://first.com"))
        XCTAssertTrue(urls.contains("https://second.com"))

        // Ensure both per-window managers are empty
        XCTAssertTrue(firstTabCollectionViewModel.pinnedTabsManager!.tabCollection.tabs.isEmpty)
        XCTAssertTrue(secondTabCollectionViewModel.pinnedTabsManager!.tabCollection.tabs.isEmpty)
    }

}

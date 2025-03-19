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

final class PinnedTabsManagerProviderTests: XCTestCase {

    private var provider: PinnedTabsManagerProvider!
    private var tabsPreferences: TabsPreferences!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        tabsPreferences = TabsPreferences(persistor: MockTabsPreferencesPersistor())
        provider = PinnedTabsManagerProvider(tabsPreferences: tabsPreferences)
    }

    override func tearDown() {
        provider = nil
        tabsPreferences = nil
        cancellables.removeAll()
        super.tearDown()
    }

    func test_WhenPerWindowPinnedTabsEnabled_ThenReturnsTrue() {
        tabsPreferences.pinnedTabsMode = .separate
        XCTAssertTrue(provider.arePerWindowPinnedTabsEnabled)
    }

    func test_WhenSharedModeEnabled_ThenReturnsFalse() {
        tabsPreferences.pinnedTabsMode = .shared
        XCTAssertFalse(provider.arePerWindowPinnedTabsEnabled)
    }

    func test_WhenSettingChanged_ThenPublisherEmitsValue() {
        let expectation = expectation(description: "Publisher emits value")
        provider.settingChangedPublisher
            .dropFirst()
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
        tabCollectionViewModel.pinnedTabsManager!.pin(Tab())

        XCTAssertFalse(provider.arePinnedTabsEmpty)
    }

    @MainActor
    func test_WhenTabsExistAndPinnedTabsModeIsShared_ThenArePinnedTabsEmptyReturnsFalse() {
        tabsPreferences.pinnedTabsMode = .shared
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: provider)
        _ = WindowsManager.openNewWindow(with: tabCollectionViewModel)
        tabCollectionViewModel.pinnedTabsManager!.pin(Tab())

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

}

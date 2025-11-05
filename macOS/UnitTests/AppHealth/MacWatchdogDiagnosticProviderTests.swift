//
//  MacWatchdogDiagnosticProviderTests.swift
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
import AppKit
import BrowserServicesKit
import Common

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class MacWatchdogDiagnosticProviderTests: XCTestCase {

    var diagnosticProvider: MacWatchdogDiagnosticProvider!
    var mockWindowControllersManager: WindowControllersManagerMock!

    override func setUp() {
        super.setUp()
        mockWindowControllersManager = WindowControllersManagerMock(selectedWindow: 0)
        diagnosticProvider = MacWatchdogDiagnosticProvider(windowControllersManager: mockWindowControllersManager)
    }

    override func tearDown() {
        diagnosticProvider = nil
        mockWindowControllersManager = nil
        super.tearDown()
    }

    // MARK: - Tab count tests

    func testTabCountCalculation() async {
        // Given
        let event = Watchdog.Event.uiHangRecovered(durationSeconds: 3)

        let tabCollectionViewModel1 = createTabCollectionViewModel(with: ["tab1", "tab2"])
        let tabCollectionViewModel2 = createTabCollectionViewModel(with: ["tab3", "tab4", "tab5"])
        let tabCollectionViewModel3 = createTabCollectionViewModel(with: ["tab6"])

        mockWindowControllersManager.customAllTabCollectionViewModels = [
            tabCollectionViewModel1,
            tabCollectionViewModel2,
            tabCollectionViewModel3
        ]

        // When
        let diagnostics = await diagnosticProvider.collectDiagnostics(for: event)

        // Then
        XCTAssertEqual(diagnostics.openBrowserTabCount, 6)
    }

    func testTabCountCalculation_EmptyCollections() async {
        // Given
        let event = Watchdog.Event.uiHangRecovered(durationSeconds: 2)

        let tabCollectionViewModel1 = createEmptyTabCollectionViewModel()
        let tabCollectionViewModel2 = createEmptyTabCollectionViewModel()

        mockWindowControllersManager.customAllTabCollectionViewModels = [
            tabCollectionViewModel1,
            tabCollectionViewModel2
        ]

        // When
        let diagnostics = await diagnosticProvider.collectDiagnostics(for: event)

        // Then
        XCTAssertEqual(diagnostics.openBrowserTabCount, 0)
    }

    // MARK: - Nil window manager test

    func testNilWindowManager_ReturnsNilCounts() async {
        // Given
        let event = Watchdog.Event.uiHangRecovered(durationSeconds: 4)
        diagnosticProvider = MacWatchdogDiagnosticProvider(windowControllersManager: nil)

        // When
        let diagnostics = await diagnosticProvider.collectDiagnostics(for: event)

        // Then
        // Window manager dependent values will be nil
        XCTAssertNil(diagnostics.openBrowserWindowCount)
        XCTAssertNil(diagnostics.openBrowserTabCount)
    }

    // MARK: - Helper Methods

    /// Creates a TabCollectionViewModel with the specified tab UUIDs, removing any automatically added tabs first
    private func createTabCollectionViewModel(with tabUUIDs: [String]) -> TabCollectionViewModel {
        let emptyPinnedTabsManager = PinnedTabsManager(tabCollection: TabCollection())
        let pinnedTabsProvider = PinnedTabsManagerProvidingMock()
        pinnedTabsProvider.pinnedTabsManager = emptyPinnedTabsManager
        pinnedTabsProvider.newPinnedTabsManager = emptyPinnedTabsManager

        let persistor = MockTabsPreferencesPersistor()
        let tabCollectionViewModel = TabCollectionViewModel(
            tabCollection: TabCollection(),
            pinnedTabsManagerProvider: pinnedTabsProvider,
            tabsPreferences: TabsPreferences(persistor: persistor)
        )

        // Remove any automatically added tabs
        while !tabCollectionViewModel.tabCollection.tabs.isEmpty {
            tabCollectionViewModel.remove(at: .unpinned(0))
        }

        // Add our test tabs
        for uuid in tabUUIDs {
            let tab = Tab(uuid: uuid, content: .url(URL.duckDuckGo, source: .ui))
            tabCollectionViewModel.append(tab: tab)
        }

        return tabCollectionViewModel
    }

    /// Creates a TabCollectionViewModel with no tabs (empty collection)
    private func createEmptyTabCollectionViewModel() -> TabCollectionViewModel {
        return createTabCollectionViewModel(with: [])
    }
}

//
//  VerticalTabsViewModelTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class VerticalTabsViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
    }

    func testListsTheTabsAndTheSelectedTab() {
        let tabCollectionViewModel = tabCollectionViewModel(tabCount: 3, selectedIndex: 1)

        let model = verticalTabsViewModel(for: tabCollectionViewModel)

        XCTAssertEqual(model.tabs.map(\.id), tabIDs(of: tabCollectionViewModel))
        XCTAssertEqual(model.selectedTabID, tabIDs(of: tabCollectionViewModel)[1])
    }

    func testWhenTabIsClosedThenItLeavesTheList() {
        let tabCollectionViewModel = tabCollectionViewModel(tabCount: 3, selectedIndex: 0)
        let model = verticalTabsViewModel(for: tabCollectionViewModel)
        let closedTabID = model.tabs[1].id
        let tabsUpdated = expectTabsUpdate(of: model)

        model.close(closedTabID)

        wait(for: [tabsUpdated], timeout: 1)
        XCTAssertEqual(model.tabs.map(\.id), tabIDs(of: tabCollectionViewModel))
        XCTAssertFalse(model.tabs.map(\.id).contains(closedTabID))
    }

    func testWhenTabMovesToAnotherPlaceThenTheListFollows() {
        let tabCollectionViewModel = tabCollectionViewModel(tabCount: 3, selectedIndex: 0)
        let model = verticalTabsViewModel(for: tabCollectionViewModel)
        let originalIDs = model.tabs.map(\.id)
        let tabsUpdated = expectTabsUpdate(of: model)

        model.moveTab(originalIDs[0], to: 2)

        wait(for: [tabsUpdated], timeout: 1)
        XCTAssertEqual(tabIDs(of: tabCollectionViewModel), [originalIDs[1], originalIDs[2], originalIDs[0]])
        XCTAssertEqual(model.tabs.map(\.id), [originalIDs[1], originalIDs[2], originalIDs[0]])
    }

    private func tabCollectionViewModel(tabCount: Int, selectedIndex: Int) -> TabCollectionViewModel {
        let tabs = (0..<tabCount).map { _ in Tab(content: .newtab) }
        return TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs),
                                      selectionIndex: .unpinned(selectedIndex),
                                      pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
    }

    private func verticalTabsViewModel(for tabCollectionViewModel: TabCollectionViewModel) -> VerticalTabsViewModel {
        VerticalTabsViewModel(tabCollectionViewModel: tabCollectionViewModel, aiChatCoordinator: nil)
    }

    private func tabIDs(of tabCollectionViewModel: TabCollectionViewModel) -> [TabIdentifier] {
        tabCollectionViewModel.tabCollection.tabs.map(\.uuid)
    }

    private func expectTabsUpdate(of model: VerticalTabsViewModel) -> XCTestExpectation {
        let expectation = expectation(description: "Tabs updated")
        model.$tabs
            .dropFirst()
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        return expectation
    }
}

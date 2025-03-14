//
//  TabCollectionViewModelTests+CloseTabLogic.swift
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
@testable import DuckDuckGo_Privacy_Browser

// MARK: - Tests for TabCollectionViewModel selected tab after closing logic

extension TabCollectionViewModelTests {

    @MainActor
    func testFindNextTabWithSameParent() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let parentTab = tabCollectionViewModel.tabCollection.tabs[0]
        let childTab1 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab1, selected: false)
        let childTab2 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab2, selected: true)
        let childTab3 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab3, selected: false)

        tabCollectionViewModel.remove(at: .unpinned(2))

        /// We have Parent + Child1 + Child 2 (selected) + Child 3. Then, we remove Child 2.
        /// So the next tab should be selected, not the parent nor the previous tab.
        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab, childTab3)
    }

    @MainActor
    func testFindPreviousTabWithSameParent() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let parentTab = tabCollectionViewModel.tabCollection.tabs[0]
        let childTab1 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab1, selected: false)
        let childTab2 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab2, selected: true)
        let normalTab = Tab()
        tabCollectionViewModel.append(tab: normalTab, selected: false)

        tabCollectionViewModel.remove(at: .unpinned(2))

        /// We have Parent + Child1 + Child 2 (selected) + Non Child. Then, we remove Child 2.
        /// So the previous tab should be selected, not the parent nor the non child tab.
        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab, childTab1)
    }

    @MainActor
    func testFindParentTab_whenNoChildParentIsClose() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let parentTab = tabCollectionViewModel.tabCollection.tabs[0]
        let normalTab = Tab()
        tabCollectionViewModel.append(tab: normalTab, selected: false)
        let childTab1 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab1, selected: true)

        tabCollectionViewModel.remove(at: .unpinned(2))

        /// We have Parent + Non Child + Child 1. Then, we remove Child1.
        /// So the parent tab should be selected.
        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab, parentTab)
    }

    @MainActor
    func testFindNextTabWithRemovedTabAsParent() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let parentTab = tabCollectionViewModel.tabCollection.tabs[0]
        let normalTab = Tab()
        tabCollectionViewModel.append(tab: normalTab, selected: false)
        let childTab1 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab1, selected: true)

        tabCollectionViewModel.remove(at: .unpinned(0))

        /// We have Parent + Non Child + Child 1. Then, we remove Parent.
        /// So the next child tab should be selected.
        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab, childTab1)
    }

    @MainActor
    func testFindPreviousTabWithRemovedTabAsParent() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let parentTab = tabCollectionViewModel.tabCollection.tabs[0]
        let childTab1 = Tab(parentTab: parentTab)
        tabCollectionViewModel.append(tab: childTab1, selected: true)
        let normalTab = Tab()
        tabCollectionViewModel.append(tab: normalTab, selected: false)

        /// We move the parent to the last position
        tabCollectionViewModel.moveTab(at: 0, to: 2)

        tabCollectionViewModel.remove(at: .unpinned(2))

        /// We have Child 1 + Non Child + Parent . Then, we remove Parent.
        /// So the previous child tab should be selected.
        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab, childTab1)
    }

    @MainActor
    func testFindNextTabWhenNoParentOrChildIsInvoled_shouldReturnToPreviouslyClosedTab() {
        let tabCollectionViewModel = TabCollectionViewModel.aTabCollectionViewModel()
        let firstTab = tabCollectionViewModel.tabCollection.tabs[0]

        for _ in 1..<100 {
            tabCollectionViewModel.append(tab: Tab(), selected: false)
        }

        let lastTab = Tab()
        tabCollectionViewModel.append(tab: lastTab, selected: true)

        tabCollectionViewModel.remove(at: .unpinned(100))

        /// We have a tab and we open 99 tabs more without selecting them.
        /// So the previous child tab should be selected.
        XCTAssertEqual(tabCollectionViewModel.selectedTabViewModel?.tab, firstTab)
    }
}

fileprivate extension TabCollectionViewModel {

    static func aTabCollectionViewModel() -> TabCollectionViewModel {
        let tabCollection = TabCollection()
        return TabCollectionViewModel(tabCollection: tabCollection, pinnedTabsManager: nil)
    }
}

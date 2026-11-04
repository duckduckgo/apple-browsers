//
//  TabDragAndDropManagerTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class TabDragAndDropManagerTests: XCTestCase {

    @MainActor
    func testWhenDroppingOntoPinnedSectionOfWindowWithoutUnpinnedTabs_ThenTabIsInsertedAtFirstUnpinnedPosition() {
        let source = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
        source.appendNewTab(with: .url(.duckDuckGo, source: .link))
        let draggedTab = source.tabCollection.tabs[1]

        let destination = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
        destination.appendPinnedTab()
        destination.remove(at: .unpinned(0))
        XCTAssertTrue(destination.tabCollection.tabs.isEmpty)

        let manager = TabDragAndDropManager()
        manager.setSource(tabCollectionViewModel: source, index: .unpinned(1))
        manager.setDestination(tabCollectionViewModel: destination, index: .pinned(1))

        XCTAssertTrue(manager.performDragAndDropIfNeeded())

        XCTAssertEqual(source.tabCollection.tabs.count, 1)
        XCTAssertEqual(destination.pinnedTabsCollection?.tabs.count, 1)
        XCTAssertEqual(destination.tabCollection.tabs.map(\.uuid), [draggedTab.uuid])
    }

    @MainActor
    func testWhenDroppingOntoPinnedSectionOfWindowWithUnpinnedTabs_ThenTabIsInsertedAtFirstUnpinnedPosition() {
        let source = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
        source.appendNewTab(with: .url(.duckDuckGo, source: .link))
        let draggedTab = source.tabCollection.tabs[1]

        let destination = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
        destination.appendPinnedTab()
        destination.appendNewTab(with: .url(.aboutDuckDuckGo, source: .link))
        let existingTabIDs = destination.tabCollection.tabs.map(\.uuid)

        let manager = TabDragAndDropManager()
        manager.setSource(tabCollectionViewModel: source, index: .unpinned(1))
        manager.setDestination(tabCollectionViewModel: destination, index: .pinned(1))

        XCTAssertTrue(manager.performDragAndDropIfNeeded())

        XCTAssertEqual(destination.pinnedTabsCollection?.tabs.count, 1)
        XCTAssertEqual(destination.tabCollection.tabs.map(\.uuid), [draggedTab.uuid] + existingTabIDs)
    }
}

private extension TabCollectionViewModel {

    func appendPinnedTab() {
        let tab = Tab(content: .url("https://duck.com".url!, source: .link), shouldLoadInBackground: false)
        pinnedTabsManager?.tabCollection.append(tab: tab)
    }
}

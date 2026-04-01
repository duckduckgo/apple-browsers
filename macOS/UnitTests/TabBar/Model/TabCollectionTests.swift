//
//  TabCollectionTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import History
@testable import DuckDuckGo_Privacy_Browser

final class TabCollectionTests: XCTestCase {

    override func setUp() {
        customAssert = { _, _, _, _ in }
        customAssertionFailure = { _, _, _ in }
    }

    override func tearDown() {
        customAssert = nil
        customAssertionFailure = nil
    }

    // MARK: - Append

    @MainActor
    func testWhenTabIsAppendedThenItsIndexIsLast() {
        autoreleasepool {
            let tabCollection = TabCollection()

            let tab1 = Tab()
            tabCollection.append(tab: tab1)
            XCTAssertEqual(tabCollection.tabs[tabCollection.tabs.count - 1].tab, tab1)

            let tab2 = Tab()
            tabCollection.append(tab: tab2)
            XCTAssertEqual(tabCollection.tabs[tabCollection.tabs.count - 1].tab, tab2)
        }
    }

    // MARK: - Insert

    @MainActor
    func testWhenInsertIsCalledWithIndexOutOfBoundsThenItemIsNotInserted() {
        autoreleasepool {
            let tabCollection = TabCollection()
            let tab = Tab()

            tabCollection.insert(tab, at: -1)
            XCTAssertEqual(tabCollection.tabs.count, 0)
            XCTAssertFalse(tabCollection.contains(tab: tab))
        }
    }

    @MainActor
    func testWhenTabIsInsertedAtIndexThenItemsWithEqualOrHigherIndexesAreMoved() {
        autoreleasepool {
            let tabCollection = TabCollection()

            let tab1 = Tab()
            tabCollection.insert(tab1, at: 0)
            XCTAssertEqual(tabCollection.tabs[0].tab, tab1)

            let tab2 = Tab()
            tabCollection.insert(tab2, at: 0)
            XCTAssertEqual(tabCollection.tabs[0].tab, tab2)
            XCTAssertEqual(tabCollection.tabs[1].tab, tab1)
        }

    }

    // MARK: - Remove

    @MainActor
    func testWhenRemoveIsCalledWithIndexOutOfBoundsThenNoItemIsRemoved() {
        autoreleasepool {
            let tabCollection = TabCollection()

            let tab = Tab()
            tabCollection.append(tab: tab)
            XCTAssertEqual(tabCollection.tabs.count, 1)
            XCTAssert(tabCollection.contains(tab: tab))

            XCTAssertFalse(tabCollection.removeTab(at: 1))
            XCTAssertEqual(tabCollection.tabs.count, 1)
            XCTAssert(tabCollection.contains(tab: tab))
        }
    }

    @MainActor
    func testWhenTabIsRemovedAtIndexThenItemsWithHigherIndexesAreMoved() {
        autoreleasepool {
            let tabCollection = TabCollection()

            let tab1 = Tab()
            tabCollection.append(tab: tab1)
            let tab2 = Tab()
            tabCollection.append(tab: tab2)
            let tab3 = Tab()
            tabCollection.append(tab: tab3)

            XCTAssert(tabCollection.removeTab(at: 0))

            XCTAssertEqual(tabCollection.tabs[0].tab, tab2)
            XCTAssertEqual(tabCollection.tabs[1].tab, tab3)
        }
    }

    @MainActor
    func testWhenTabIsRemoved_ThenItsLocalHistoryIsKeptInTabCollection() {
        autoreleasepool {
            let tabCollection = TabCollection()
            let historyExtensionMock = HistoryTabExtensionMock()
            let extensionBuilder = TestTabExtensionsBuilder(load: [HistoryTabExtensionMock.self]) { builder in { _, _ in
                builder.override {
                    historyExtensionMock
                }
            }}

            let tab1 = Tab()
            tabCollection.append(tab: tab1)
            let tab2 = Tab(content: .newtab, extensionsBuilder: extensionBuilder)
            tabCollection.append(tab: tab2)

            let visit = Visit(date: Date())
            historyExtensionMock.localHistory.append(visit)

            tabCollection.removeAll()
            XCTAssert(tabCollection.localHistoryOfRemovedTabs.contains(visit))
        }
    }

    // MARK: - Move

    @MainActor
    func testWhenMoveIsCalledWithIndexesOutOfBoundsThenNoItemIsMoved() {
        autoreleasepool {
            let tabCollection = TabCollection()

            let tab1 = Tab()
            tabCollection.append(tab: tab1)
            let tab2 = Tab()
            tabCollection.append(tab: tab2)

            tabCollection.moveTab(at: 0, to: 3)
            tabCollection.moveTab(at: 0, to: -1)
            tabCollection.moveTab(at: 3, to: 0)
            tabCollection.moveTab(at: -1, to: 0)
            XCTAssertEqual(tabCollection.tabs[0].tab, tab1)
            XCTAssertEqual(tabCollection.tabs[1].tab, tab2)
        }
    }

    @MainActor
    func testWhenMoveIsCalledWithSameIndexesThenNoItemIsMoved() {
        autoreleasepool {
            let tabCollection = TabCollection()

            let tab1 = Tab()
            tabCollection.append(tab: tab1)
            let tab2 = Tab()
            tabCollection.append(tab: tab2)

            tabCollection.moveTab(at: 0, to: 0)
            tabCollection.moveTab(at: 1, to: 1)
            XCTAssertEqual(tabCollection.tabs[0].tab, tab1)
            XCTAssertEqual(tabCollection.tabs[1].tab, tab2)
        }
    }

    @MainActor
    func testWhenTabIsMovedThenOtherItemsAreReorganizedProperly() {
        autoreleasepool {
            let tabCollection = TabCollection()

            let tab1 = Tab()
            tabCollection.append(tab: tab1)
            let tab2 = Tab()
            tabCollection.append(tab: tab2)
            let tab3 = Tab()
            tabCollection.append(tab: tab3)

            tabCollection.moveTab(at: 0, to: 1)
            XCTAssertEqual(tabCollection.tabs[0].tab, tab2)
            XCTAssertEqual(tabCollection.tabs[1].tab, tab1)
            XCTAssertEqual(tabCollection.tabs[2].tab, tab3)

            tabCollection.moveTab(at: 0, to: 2)
            XCTAssertEqual(tabCollection.tabs[0].tab, tab1)
            XCTAssertEqual(tabCollection.tabs[1].tab, tab3)
            XCTAssertEqual(tabCollection.tabs[2].tab, tab2)
        }
    }

    // MARK: - PopUp

    @MainActor
    func testPopupTabCollectionAllowsOnlyOneTab_Append() {
        let popup = TabCollection(isPopup: true)
        popup.append(tab: Tab())
        XCTAssertEqual(popup.tabs.count, 1)
        // Attempt to append another tab should be ignored
        popup.append(tab: Tab())
        XCTAssertEqual(popup.tabs.count, 1)
    }

    @MainActor
    func testPopupTabCollectionAllowsOnlyOneTab_Insert() {
        let popup = TabCollection(isPopup: true)
        XCTAssertTrue(popup.insert(Tab(), at: 0))
        XCTAssertEqual(popup.tabs.count, 1)
        // Attempt to insert second tab should be ignored and return false
        XCTAssertFalse(popup.insert(Tab(content: .newtab), at: 1))
        XCTAssertEqual(popup.tabs.count, 1)
    }

    // MARK: - Suspended Tabs

    @MainActor
    func testLoadedTabsFiltersSuspendedTabs() {
        let loadedTab = Tab()
        let suspended = SuspendedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
        let tabCollection = TabCollection(tabs: [.loaded(loadedTab), .suspended(suspended)])

        XCTAssertEqual(tabCollection.tabs.count, 2)
        XCTAssertEqual(tabCollection.loadedTabs.count, 1)
        XCTAssertTrue(tabCollection.loadedTabs[0] === loadedTab)
    }

    @MainActor
    func testLocalHistoryDomainsIncludesSuspendedTabVisitedDomains() {
        let suspended = SuspendedTab(
            content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration),
            visitedDomainURLs: [URL(string: "https://example.com")!, URL(string: "https://test.org")!]
        )
        let tabCollection = TabCollection(tabs: [.suspended(suspended)])

        let domains = tabCollection.localHistoryDomains
        XCTAssertTrue(domains.contains("example.com"))
        XCTAssertTrue(domains.contains("test.org"))
    }

    @MainActor
    func testRemoveSuspendedTab() {
        let loadedTab = Tab()
        let suspended = SuspendedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
        let tabCollection = TabCollection(tabs: [.loaded(loadedTab), .suspended(suspended)])

        XCTAssertTrue(tabCollection.removeTab(at: 1))
        XCTAssertEqual(tabCollection.tabs.count, 1)
        XCTAssertTrue(tabCollection.tabs[0].tab === loadedTab)
    }

    @MainActor
    func testContainsAndFirstIndexWithMixedTabs() {
        let tab1 = Tab()
        let tab2 = Tab()
        let suspended = SuspendedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
        let tabCollection = TabCollection(tabs: [.loaded(tab1), .suspended(suspended), .loaded(tab2)])

        XCTAssertTrue(tabCollection.contains(tab: tab1))
        XCTAssertTrue(tabCollection.contains(tab: tab2))
        XCTAssertEqual(tabCollection.firstIndex(of: tab1), 0)
        XCTAssertEqual(tabCollection.firstIndex(of: tab2), 2)
        XCTAssertTrue(tabCollection.contains(uuid: suspended.uuid))
    }

}

private extension Tab {
    @MainActor
    convenience override init() {
        self.init(content: .none)
    }

    @MainActor
     convenience init(url: URL) {
         self.init(content: .url(url, credential: nil, source: .userEntered(url.absoluteString, downloadRequested: false)))
     }
}

class HistoryTabExtensionMock: TabExtension, HistoryExtensionProtocol {

    var localHistory: [Visit] = []
    func getPublicProtocol() -> HistoryExtensionProtocol { self }

    func clearNavigationHistory(keepingCurrent: Bool) {}
}

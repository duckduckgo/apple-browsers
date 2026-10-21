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
            XCTAssertEqual(tabCollection.tabs[tabCollection.tabs.count - 1], .loaded(tab1))

            let tab2 = Tab()
            tabCollection.append(tab: tab2)
            XCTAssertEqual(tabCollection.tabs[tabCollection.tabs.count - 1], .loaded(tab2))
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
            XCTAssertEqual(tabCollection.tabs[0], .loaded(tab1))

            let tab2 = Tab()
            tabCollection.insert(tab2, at: 0)
            XCTAssertEqual(tabCollection.tabs[0], .loaded(tab2))
            XCTAssertEqual(tabCollection.tabs[1], .loaded(tab1))
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

            XCTAssertEqual(tabCollection.tabs[0], .loaded(tab2))
            XCTAssertEqual(tabCollection.tabs[1], .loaded(tab3))
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
            XCTAssertEqual(tabCollection.tabs[0], .loaded(tab1))
            XCTAssertEqual(tabCollection.tabs[1], .loaded(tab2))
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
            XCTAssertEqual(tabCollection.tabs[0], .loaded(tab1))
            XCTAssertEqual(tabCollection.tabs[1], .loaded(tab2))
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
            XCTAssertEqual(tabCollection.tabs[0], .loaded(tab2))
            XCTAssertEqual(tabCollection.tabs[1], .loaded(tab1))
            XCTAssertEqual(tabCollection.tabs[2], .loaded(tab3))

            tabCollection.moveTab(at: 0, to: 2)
            XCTAssertEqual(tabCollection.tabs[0], .loaded(tab1))
            XCTAssertEqual(tabCollection.tabs[1], .loaded(tab3))
            XCTAssertEqual(tabCollection.tabs[2], .loaded(tab2))
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

    // MARK: - Unloaded Tabs

    @MainActor
    func testLoadedTabsFiltersUnloadedTabs() {
        let loadedTab = Tab()
        let unloaded = UnloadedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
        let tabCollection = TabCollection(tabs: [.loaded(loadedTab), .unloaded(unloaded)])

        XCTAssertEqual(tabCollection.tabs.count, 2)
        XCTAssertEqual(tabCollection.loadedTabs.count, 1)
        XCTAssertTrue(tabCollection.loadedTabs[0] === loadedTab)
    }

    @MainActor
    func testLocalHistoryDomainsIncludesUnloadedTabVisitedDomains() {
        let unloaded = UnloadedTab(
            content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration),
            localHistoryIDs: [URL(string: "https://example.com")!, URL(string: "https://test.org")!]
        )
        let tabCollection = TabCollection(tabs: [.unloaded(unloaded)])

        let domains = tabCollection.localHistoryDomains
        XCTAssertTrue(domains.contains("example.com"))
        XCTAssertTrue(domains.contains("test.org"))
    }

    @MainActor
    func testLocalHistoryDomainsEmptyForUnloadedTabWithoutVisitedDomains() {
        let unloaded = UnloadedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
        let tabCollection = TabCollection(tabs: [.unloaded(unloaded)])

        XCTAssertTrue(tabCollection.localHistoryDomains.isEmpty)
    }

    @MainActor
    func testRemoveUnloadedTab() {
        let loadedTab = Tab()
        let unloaded = UnloadedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
        let tabCollection = TabCollection(tabs: [.loaded(loadedTab), .unloaded(unloaded)])

        XCTAssertTrue(tabCollection.removeTab(at: 1))
        XCTAssertEqual(tabCollection.tabs.count, 1)
        XCTAssertEqual(tabCollection.tabs[0], .loaded(loadedTab))
    }

    @MainActor
    func testContainsAndFirstIndexWithMixedTabs() {
        let tab1 = Tab()
        let tab2 = Tab()
        let unloaded = UnloadedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
        let tabCollection = TabCollection(tabs: [.loaded(tab1), .unloaded(unloaded), .loaded(tab2)])

        XCTAssertTrue(tabCollection.contains(tab: tab1))
        XCTAssertTrue(tabCollection.contains(tab: tab2))
        XCTAssertEqual(tabCollection.firstIndex(of: tab1), 0)
        XCTAssertEqual(tabCollection.firstIndex(of: tab2), 2)
        XCTAssertTrue(tabCollection.contains(uuid: unloaded.uuid))
    }

    // MARK: - Clear Navigation History

    @MainActor
    func testClearNavigationHistoryOnUnloadedTabClearsVisitedDomainURLs() {
        let urls = [URL(string: "https://example.com")!, URL(string: "https://test.org")!]
        let unloaded = UnloadedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration),
                                   localHistoryIDs: urls)

        unloaded.clearNavigationHistory(keepingCurrent: false)

        XCTAssertNil(unloaded.localHistoryIDs)
    }

    @MainActor
    func testClearNavigationHistoryKeepingCurrentPreservesCurrentDomain() {
        let duckDuckGoURL = URL.duckDuckGo
        let otherURL = URL(string: "https://example.com")!
        let unloaded = UnloadedTab(content: .url(duckDuckGoURL, credential: nil, source: .pendingStateRestoration),
                                   localHistoryIDs: [duckDuckGoURL, otherURL])

        unloaded.clearNavigationHistory(keepingCurrent: true)

        XCTAssertEqual(unloaded.localHistoryIDs?.count, 1)
        XCTAssertEqual(unloaded.localHistoryIDs?.first?.host, duckDuckGoURL.host)
    }

    @MainActor
    func testRemovedUnloadedTabDomainsCapturedInRemovedTabDomains() {
        let urls = [URL(string: "https://example.com")!, URL(string: "https://test.org")!]
        let unloaded = UnloadedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration),
                                   localHistoryIDs: urls)
        let tabCollection = TabCollection(tabs: [AnyTab.unloaded(unloaded)])

        tabCollection.removeTab(at: 0)

        XCTAssertTrue(tabCollection.removedTabDomains.contains("example.com"))
        XCTAssertTrue(tabCollection.removedTabDomains.contains("test.org"))
    }

    @MainActor
    func testMaterializationDoesNotLeakHistoryIntoRemovedTabDomains() {
        let urls = [URL(string: "https://example.com")!, URL(string: "https://test.org")!]
        let unloaded = UnloadedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration),
                                   localHistoryIDs: urls)
        let tabCollection = TabCollection(tabs: [AnyTab.unloaded(unloaded)])

        let loadedTab = Tab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
        tabCollection.replaceTab(at: 0, with: .loaded(loadedTab), keepHistory: false)

        XCTAssertTrue(tabCollection.removedTabDomains.isEmpty)
    }

    @MainActor
    func testClearNavigationHistoryOnAnyTabClearsUnloadedTab() {
        let urls = [URL(string: "https://example.com")!]
        let unloaded = UnloadedTab(content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration),
                                   localHistoryIDs: urls)
        let anyTab = AnyTab.unloaded(unloaded)

        anyTab.clearNavigationHistory(keepingCurrent: false)

        XCTAssertNil(unloaded.localHistoryIDs)
    }

    // MARK: - AnyTab Identity vs UUID Equality

    @MainActor
    func testAnyTabIdentityEquality() {
        let tab = Tab()
        let wrapped1 = AnyTab.loaded(tab)
        let wrapped2 = AnyTab.loaded(tab)

        // Same instance → equal
        XCTAssertEqual(wrapped1, wrapped2)

        // Different instance, same content → not equal (identity-based)
        let otherTab = Tab()
        XCTAssertNotEqual(AnyTab.loaded(tab), AnyTab.loaded(otherTab))

        // Suspended vs loaded with same UUID → not equal
        let unloaded = UnloadedTab(uuid: tab.uuid, content: tab.content)
        XCTAssertNotEqual(AnyTab.loaded(tab), AnyTab.unloaded(unloaded))
    }

    @MainActor
    func testContainsUUIDMatchesSuspendedAndLoadedTabs() {
        let tab = Tab()
        let unloaded = UnloadedTab(uuid: "specific-uuid", content: .url(.duckDuckGo, credential: nil, source: .pendingStateRestoration))
        let tabCollection = TabCollection(tabs: [.loaded(tab), .unloaded(unloaded)])

        // UUID lookup finds both types
        XCTAssertTrue(tabCollection.contains(uuid: tab.uuid))
        XCTAssertTrue(tabCollection.contains(uuid: "specific-uuid"))

        // Identity lookup only finds loaded tabs
        XCTAssertTrue(tabCollection.contains(tab: tab))
        XCTAssertNil(tabCollection.firstIndex(of: Tab())) // different instance, not found
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
    var restoredURLs: [URL]?
    func getPublicProtocol() -> HistoryExtensionProtocol { self }

    func clearNavigationHistory(keepingCurrent: Bool) {}
    func restoreLocalHistoryIDs(_ urls: [URL]) {
        restoredURLs = urls
    }
}

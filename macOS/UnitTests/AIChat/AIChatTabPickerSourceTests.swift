//
//  AIChatTabPickerSourceTests.swift
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

@MainActor
final class AIChatTabPickerSourceTests: XCTestCase {

    private func regularCollection(urls: [String]) -> TabCollectionViewModel {
        let tabs = urls.map { Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui)) }
        return TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs))
    }

    private func burnerCollection() -> TabCollectionViewModel {
        TabCollectionViewModel(tabCollection: TabCollection(), burnerMode: BurnerMode(isBurner: true))
    }

    /// A regular collection whose first tab is a loaded (selected) page and whose second tab is a
    /// suspended/unloaded tab with the given id + url.
    private func collectionWithSuspendedTab(id: String, url: String) -> TabCollectionViewModel {
        let loaded = Tab(content: .url(URL(string: "https://selected.example")!, credential: nil, source: .ui))
        let suspended = UnloadedTab(uuid: id, content: .url(URL(string: url)!, credential: nil, source: .ui), isSuspended: true)
        return TabCollectionViewModel(tabCollection: TabCollection(tabs: [.loaded(loaded), .unloaded(suspended)]))
    }

    // MARK: - materializeAttachableTab (wake suspended tabs)

    func testMaterializeWakesSuspendedTabWithoutChangingSelection() {
        let collection = collectionWithSuspendedTab(id: "suspended-1", url: "https://apple.com")
        let selectionBefore = collection.selectionIndex
        let wcm = WindowControllersManagerMock()
        wcm.customAllTabCollectionViewModels = [collection]

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-1", forOrigin: collection, in: wcm)

        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.wasMaterialized == true)
        XCTAssertEqual(resolved?.tab.uuid, "suspended-1")
        // The slot is now loaded...
        if case .loaded(let tab) = collection.tabCollection.tabs[1] {
            XCTAssertEqual(tab.uuid, "suspended-1")
        } else {
            XCTFail("Expected the suspended tab to be materialized to .loaded")
        }
        // ...and the user's selection did not change (no focus steal).
        XCTAssertEqual(collection.selectionIndex, selectionBefore)
    }

    func testMaterializeReturnsAlreadyLoadedTabWithoutMaterializing() {
        let collection = regularCollection(urls: ["https://apple.com"])
        let id = collection.tabCollection.tabs[0].uuid
        let wcm = WindowControllersManagerMock()
        wcm.customAllTabCollectionViewModels = [collection]

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: id, forOrigin: collection, in: wcm)

        XCTAssertEqual(resolved?.tab.uuid, id)
        XCTAssertFalse(resolved?.wasMaterialized ?? true)
    }

    func testMaterializeFindsSuspendedTabInAnotherRegularWindow() {
        let origin = regularCollection(urls: ["https://origin.example"])
        let other = collectionWithSuspendedTab(id: "suspended-2", url: "https://apple.com")
        let wcm = WindowControllersManagerMock()
        wcm.customAllTabCollectionViewModels = [origin, other]

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-2", forOrigin: origin, in: wcm)

        XCTAssertEqual(resolved?.tab.uuid, "suspended-2")
        XCTAssertTrue(resolved?.wasMaterialized == true)
    }

    func testMaterializeDoesNotResolveRegularTabFromFireWindowOrigin() {
        let regular = collectionWithSuspendedTab(id: "suspended-3", url: "https://apple.com")
        let burner = burnerCollection()
        let wcm = WindowControllersManagerMock()
        wcm.customAllTabCollectionViewModels = [regular, burner]

        // Origin is the Fire Window → it must not reach into the regular window's tabs.
        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-3", forOrigin: burner, in: wcm)

        XCTAssertNil(resolved)
    }

    // MARK: - Scope

    func testRegularOriginSourcesAllRegularWindowsAndExcludesBurner() {
        let regular1 = regularCollection(urls: [])
        let regular2 = regularCollection(urls: [])
        let burner = burnerCollection()
        let wcm = WindowControllersManagerMock()
        wcm.customAllTabCollectionViewModels = [regular1, regular2, burner]

        let collections = AIChatTabPickerSource.tabCollections(forOrigin: regular1, in: wcm)

        XCTAssertTrue(collections.contains { $0 === regular1 })
        XCTAssertTrue(collections.contains { $0 === regular2 })
        XCTAssertFalse(collections.contains { $0 === burner })
    }

    func testFireWindowOriginSourcesOnlyThatFireWindow() {
        let regular = regularCollection(urls: [])
        let burner = burnerCollection()
        let otherBurner = burnerCollection()
        let wcm = WindowControllersManagerMock()
        wcm.customAllTabCollectionViewModels = [regular, burner, otherBurner]

        let collections = AIChatTabPickerSource.tabCollections(forOrigin: burner, in: wcm)

        XCTAssertEqual(collections.count, 1)
        XCTAssertTrue(collections.first === burner)
    }

    // MARK: - Aggregation

    func testAttachableTabsAggregatesAcrossRegularWindowsExcludingBurner() {
        let regular1 = regularCollection(urls: ["https://example.com"])
        let regular2 = regularCollection(urls: ["https://apple.com"])
        let burner = burnerCollection()
        let wcm = WindowControllersManagerMock()
        wcm.customAllTabCollectionViewModels = [regular1, regular2, burner]

        let tabs = AIChatTabPickerSource.attachableTabs(forOrigin: regular1, in: wcm)
        let urls = tabs.compactMap { tab -> String? in
            guard case .url(let url, _, _) = tab.content else { return nil }
            return url.absoluteString
        }

        XCTAssertTrue(urls.contains("https://example.com"))
        XCTAssertTrue(urls.contains("https://apple.com"))
    }

    func testAttachableTabsDeduplicatesByUUID() {
        let regular = regularCollection(urls: ["https://example.com"])
        let wcm = WindowControllersManagerMock()
        // Same collection referenced twice (mirrors shared pinned tabs appearing per window).
        wcm.customAllTabCollectionViewModels = [regular, regular]

        let tabs = AIChatTabPickerSource.attachableTabs(forOrigin: regular, in: wcm)
        let ids = tabs.map { $0.uuid }

        XCTAssertEqual(ids.count, Set(ids).count, "Tabs should be deduplicated by uuid")
    }

    func testFireWindowOriginDoesNotLeakOtherWindowsTabs() {
        let regular = regularCollection(urls: ["https://example.com"])
        let burner = burnerCollection()
        let wcm = WindowControllersManagerMock()
        wcm.customAllTabCollectionViewModels = [regular, burner]

        let tabs = AIChatTabPickerSource.attachableTabs(forOrigin: burner, in: wcm)
        let urls = tabs.compactMap { tab -> String? in
            guard case .url(let url, _, _) = tab.content else { return nil }
            return url.absoluteString
        }

        XCTAssertFalse(urls.contains("https://example.com"), "A Fire Window must not surface regular-window tabs")
    }
}

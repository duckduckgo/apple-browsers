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

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-1", forOrigin: collection)

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

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: id, forOrigin: collection)

        XCTAssertEqual(resolved?.tab.uuid, id)
        XCTAssertFalse(resolved?.wasMaterialized ?? true)
    }

    func testMaterializeDoesNotResolveTabFromAnotherRegularWindow() {
        let origin = regularCollection(urls: ["https://origin.example"])
        let other = collectionWithSuspendedTab(id: "suspended-2", url: "https://apple.com")

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-2", forOrigin: origin)

        XCTAssertNil(resolved, "A tab that lives in another window must not be resolvable")
        // The other window's suspended tab was left untouched.
        if case .loaded = other.tabCollection.tabs[1] {
            XCTFail("The other window's suspended tab must not have been materialized")
        }
    }

    // MARK: - needsLoad (page not in the web view yet)

    func testNeedsLoadIsTrueForJustMaterializedSuspendedTab() {
        let collection = collectionWithSuspendedTab(id: "suspended-4", url: "https://apple.com")

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-4", forOrigin: collection)

        XCTAssertTrue(resolved?.wasMaterialized == true)
        XCTAssertTrue(resolved?.needsLoad == true)
    }

    /// The pinned-tab-at-launch shape: already `.loaded` so there's nothing to materialize, but the web
    /// view is still empty. This is the case a `wasMaterialized`-only check skips.
    func testNeedsLoadIsTrueForRestoredTabThatWasAlreadyLoadedButNeverNavigated() {
        let restored = Tab(content: .url(URL(string: "https://pinned.example")!, credential: nil, source: .pendingStateRestoration),
                           interactionStateData: Data())
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: [restored]))

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: restored.uuid, forOrigin: collection)

        XCTAssertNotNil(resolved)
        XCTAssertFalse(resolved?.wasMaterialized ?? true, "Nothing to materialize — the tab is already .loaded")
        XCTAssertTrue(resolved?.needsLoad == true, "…but its web view has no page, so a load must still be kicked")
    }

    func testMaterializeDoesNotResolveRegularTabFromFireWindowOrigin() {
        let regular = collectionWithSuspendedTab(id: "suspended-3", url: "https://apple.com")
        let burner = burnerCollection()

        // Origin is the Fire Window → it must not reach into the regular window's tabs.
        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-3", forOrigin: burner)

        XCTAssertNil(resolved)
        if case .loaded = regular.tabCollection.tabs[1] {
            XCTFail("The regular window's suspended tab must not have been materialized")
        }
    }

    // MARK: - Scope (origin window only)

    func testAttachableTabsOffersOnlyTheOriginWindowsTabs() {
        let origin = regularCollection(urls: ["https://example.com", "https://wikipedia.org"])
        let other = regularCollection(urls: ["https://apple.com"])

        let urls = attachableURLs(forOrigin: origin)

        XCTAssertEqual(urls, ["https://example.com", "https://wikipedia.org"])
        XCTAssertEqual(attachableURLs(forOrigin: other), ["https://apple.com"],
                       "Each window's picker sees that window's tabs and nothing else")
    }

    func testFireWindowOriginOffersOnlyItsOwnTabs() {
        let regular = regularCollection(urls: ["https://example.com"])
        let burner = TabCollectionViewModel(
            tabCollection: TabCollection(tabs: [Tab(content: .url(URL(string: "https://fire.example")!, credential: nil, source: .ui))]),
            burnerMode: BurnerMode(isBurner: true)
        )

        let urls = attachableURLs(forOrigin: burner)

        XCTAssertEqual(urls, ["https://fire.example"])
        XCTAssertFalse(urls.contains("https://example.com"), "A Fire Window must not surface regular-window tabs")
        XCTAssertEqual(attachableURLs(forOrigin: regular), ["https://example.com"])
    }

    // MARK: - Filtering

    func testAttachableTabsExcludesNonURLAndDuckAITabs() {
        let page = Tab(content: .url(URL(string: "https://example.com")!, credential: nil, source: .ui))
        let newTab = Tab(content: .newtab)
        let serp = Tab(content: .url(URL(string: "https://duckduckgo.com/?q=test&ia=web")!, credential: nil, source: .ui))
        let duckAI = Tab(content: .url(URL(string: "https://duckduckgo.com/?ia=chat")!, credential: nil, source: .ui))
        let origin = TabCollectionViewModel(tabCollection: TabCollection(tabs: [page, newTab, serp, duckAI]))

        XCTAssertEqual(attachableURLs(forOrigin: origin), ["https://example.com"])
    }

    private func attachableURLs(forOrigin origin: TabCollectionViewModel) -> [String] {
        AIChatTabPickerSource.attachableTabs(forOrigin: origin).compactMap { tab in
            guard case .url(let url, _, _) = tab.content else { return nil }
            return url.absoluteString
        }
    }
}

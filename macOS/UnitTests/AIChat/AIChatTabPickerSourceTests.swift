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

    private func manager(with collections: [TabCollectionViewModel]) -> WindowControllersManagerMock {
        let mock = WindowControllersManagerMock()
        mock.customAllTabCollectionViewModels = collections
        return mock
    }

    /// `pinnedTabsManagerProvider: nil` throughout: the convenience initialiser reaches for the
    /// app-wide provider, whose pinned tabs are shared by every collection and listed first.
    private func collection(_ tabs: [AnyTab], burnerMode: BurnerMode = .regular) -> TabCollectionViewModel {
        TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs),
                               pinnedTabsManagerProvider: nil,
                               burnerMode: burnerMode)
    }

    private func regularCollection(urls: [String]) -> TabCollectionViewModel {
        collection(urls.map { .loaded(Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui))) })
    }

    private func burnerCollection() -> TabCollectionViewModel {
        collection([], burnerMode: BurnerMode(isBurner: true))
    }

    /// A regular collection whose first tab is a loaded (selected) page and whose second tab is a
    /// suspended/unloaded tab with the given id + url.
    private func collectionWithSuspendedTab(id: String, url: String) -> TabCollectionViewModel {
        let loaded = Tab(content: .url(URL(string: "https://selected.example")!, credential: nil, source: .ui))
        let suspended = UnloadedTab(uuid: id, content: .url(URL(string: url)!, credential: nil, source: .ui), isSuspended: true)
        return collection([.loaded(loaded), .unloaded(suspended)])
    }

    // MARK: - materializeAttachableTab (wake suspended tabs)

    func testMaterializeWakesSuspendedTabWithoutChangingSelection() {
        let collection = collectionWithSuspendedTab(id: "suspended-1", url: "https://apple.com")
        let selectionBefore = collection.selectionIndex

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-1", forOrigin: collection, in: manager(with: [collection]))

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

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: id, forOrigin: collection, in: manager(with: [collection]))

        XCTAssertEqual(resolved?.tab.uuid, id)
        XCTAssertFalse(resolved?.wasMaterialized ?? true)
    }

    func testMaterializeFindsSuspendedTabInAnotherRegularWindow() {
        let origin = regularCollection(urls: ["https://origin.example"])
        let other = collectionWithSuspendedTab(id: "suspended-2", url: "https://apple.com")

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-2",
                                                                     forOrigin: origin,
                                                                     in: manager(with: [origin, other]))

        XCTAssertEqual(resolved?.tab.uuid, "suspended-2")
        XCTAssertTrue(resolved?.wasMaterialized == true)
    }

    // MARK: - needsLoad (page not in the web view yet)

    func testNeedsLoadIsTrueForJustMaterializedSuspendedTab() {
        let collection = collectionWithSuspendedTab(id: "suspended-4", url: "https://apple.com")

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-4", forOrigin: collection, in: manager(with: [collection]))

        XCTAssertTrue(resolved?.wasMaterialized == true)
        XCTAssertTrue(resolved?.needsLoad == true)
    }

    /// The pinned-tab-at-launch shape: already `.loaded` so there's nothing to materialize, but the web
    /// view is still empty. This is the case a `wasMaterialized`-only check skips.
    func testNeedsLoadIsTrueForRestoredTabThatWasAlreadyLoadedButNeverNavigated() {
        let restored = Tab(content: .url(URL(string: "https://pinned.example")!, credential: nil, source: .pendingStateRestoration),
                           interactionStateData: Data())
        let origin = collection([.loaded(restored)])

        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: restored.uuid, forOrigin: origin, in: manager(with: [origin]))

        XCTAssertNotNil(resolved)
        XCTAssertFalse(resolved?.wasMaterialized ?? true, "Nothing to materialize — the tab is already .loaded")
        XCTAssertTrue(resolved?.needsLoad == true, "…but its web view has no page, so a load must still be kicked")
    }

    func testMaterializeDoesNotResolveRegularTabFromFireWindowOrigin() {
        let regular = collectionWithSuspendedTab(id: "suspended-3", url: "https://apple.com")
        let burner = burnerCollection()

        // Origin is the Fire Window → it must not reach into the regular window's tabs.
        let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: "suspended-3",
                                                                     forOrigin: burner,
                                                                     in: manager(with: [regular, burner]))

        XCTAssertNil(resolved)
        if case .loaded = regular.tabCollection.tabs[1] {
            XCTFail("The regular window's suspended tab must not have been materialized")
        }
    }

    // MARK: - Scope (every regular window, Fire Windows isolated)

    func testAttachableTabsOffersEveryRegularWindowStartingWithTheOrigin() {
        let origin = regularCollection(urls: ["https://example.com", "https://wikipedia.org"])
        let other = regularCollection(urls: ["https://apple.com"])
        let manager = manager(with: [other, origin])

        XCTAssertEqual(attachableURLs(forOrigin: origin, in: manager),
                       ["https://example.com", "https://wikipedia.org", "https://apple.com"],
                       "The origin window's tabs come first, then the rest")
        XCTAssertEqual(attachableURLs(forOrigin: other, in: manager),
                       ["https://apple.com", "https://example.com", "https://wikipedia.org"])
    }

    func testAttachableTabsDeduplicatesTabsSharedBetweenWindows() {
        let origin = regularCollection(urls: ["https://example.com"])

        // The same collection twice mirrors a pinned collection shared by every window.
        let urls = attachableURLs(forOrigin: origin, in: manager(with: [origin, origin]))

        XCTAssertEqual(urls, ["https://example.com"])
    }

    func testFireWindowOriginOffersOnlyItsOwnTabsAndIsNeverOfferedToOthers() {
        let regular = regularCollection(urls: ["https://example.com"])
        // One BurnerMode value for both: each carries its own data store, and a collection whose tab
        // has a different mode trips the burner-tab-management fatalError.
        let burnerMode = BurnerMode(isBurner: true)
        let fireTab = Tab(content: .url(URL(string: "https://fire.example")!, credential: nil, source: .ui),
                          burnerMode: burnerMode)
        let burner = collection([.loaded(fireTab)], burnerMode: burnerMode)

        let manager = manager(with: [regular, burner])
        let urls = attachableURLs(forOrigin: burner, in: manager)

        XCTAssertEqual(urls, ["https://fire.example"])
        XCTAssertFalse(urls.contains("https://example.com"), "A Fire Window must not surface regular-window tabs")
        XCTAssertEqual(attachableURLs(forOrigin: regular, in: manager), ["https://example.com"],
                       "…and its tabs are not offered to regular windows either")
    }

    // MARK: - Filtering

    /// A SERP carries page content worth attaching, so only the homepage, Duck.ai and non-URL tabs go.
    func testAttachableTabsExcludesNonURLHomepageAndDuckAITabs() {
        let page = Tab(content: .url(URL(string: "https://example.com")!, credential: nil, source: .ui))
        let newTab = Tab(content: .newtab)
        let homepage = Tab(content: .url(URL(string: "https://duckduckgo.com/")!, credential: nil, source: .ui))
        let duckAI = Tab(content: .url(URL(string: "https://duckduckgo.com/?ia=chat")!, credential: nil, source: .ui))
        let serp = Tab(content: .url(URL(string: "https://duckduckgo.com/?q=test")!, credential: nil, source: .ui))
        let origin = collection([page, newTab, homepage, duckAI, serp].map { AnyTab.loaded($0) })

        XCTAssertEqual(attachableURLs(forOrigin: origin, in: manager(with: [origin])),
                       ["https://example.com", "https://duckduckgo.com/?q=test"])
    }

    private func attachableURLs(forOrigin origin: TabCollectionViewModel,
                                in windowControllersManager: WindowControllersManagerProtocol) -> [String] {
        AIChatTabPickerSource.attachableTabs(forOrigin: origin, in: windowControllersManager).compactMap { tab in
            guard case .url(let url, _, _) = tab.content else { return nil }
            return url.absoluteString
        }
    }
}

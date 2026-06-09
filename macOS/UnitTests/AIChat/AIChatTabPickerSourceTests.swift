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

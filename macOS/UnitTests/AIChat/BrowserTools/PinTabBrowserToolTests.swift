//
//  PinTabBrowserToolTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class PinTabBrowserToolTests: XCTestCase {

    func testWhenNoTabIdsAreGivenThenTheOwnerTabIsPinned() async {
        let collection = collection(urls: ["https://a.example", "https://b.example"])
        let owner = collection.tabCollection.tabs[1]
        let (tool, context) = make(collection: collection, ownerTabID: owner.uuid)

        let omitted = await tool.execute(arguments: [:], context: context)

        XCTAssertEqual(omitted, .success(pinned(owner.uuid)))
        XCTAssertEqual(collection.pinnedTabsCollection?.tabs.map(\.uuid), [owner.uuid])
    }

    func testWhenTabIdsAreGivenThenThoseTabsArePinnedAndTheSelectionStays() async {
        let collection = collection(urls: ["https://a.example", "https://b.example", "https://c.example"])
        let ids = collection.tabCollection.tabs.map(\.uuid)
        collection.select(at: .unpinned(0))
        let (tool, context) = make(collection: collection, ownerTabID: ids[0])

        let result = await tool.execute(arguments: ["tabIds": [.string(ids[2]), .string(ids[1]), .string(ids[2])]], context: context)

        XCTAssertEqual(result, .success(pinned(ids[2], ids[1])))
        XCTAssertEqual(collection.pinnedTabsCollection?.tabs.map(\.uuid), [ids[2], ids[1]])
        XCTAssertEqual(collection.selectedTabViewModel?.tab.uuid, ids[0])
    }

    func testWhenATabIsAlreadyPinnedThenItIsReportedAsPinned() async {
        let collection = collection(urls: ["https://a.example", "https://b.example"])
        let ids = collection.tabCollection.tabs.map(\.uuid)
        collection.pinTab(at: 0)
        let (tool, context) = make(collection: collection, ownerTabID: ids[1])

        let result = await tool.execute(arguments: ["tabIds": [.string(ids[0]), .string(ids[1])]], context: context)

        XCTAssertEqual(result, .success(pinned(ids[0], ids[1])))
        XCTAssertEqual(collection.pinnedTabsCollection?.tabs.map(\.uuid), ids)
    }

    func testWhenAnyTabIdIsUnknownThenNothingIsPinned() async {
        let collection = collection(urls: ["https://a.example"])
        let id = collection.tabCollection.tabs[0].uuid
        let (tool, context) = make(collection: collection, ownerTabID: id)

        let result = await tool.execute(arguments: ["tabIds": [.string(id), "missing"]], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertEqual(collection.pinnedTabsCollection?.tabs.count, 0)
    }

    func testWhenATabCannotBePinnedThenOnlyThatTabReportsNotPinned() async {
        let collection = collection([
            Tab(content: .url(URL(fileURLWithPath: "/tmp/notes.txt"), credential: nil, source: .ui)),
            Tab(content: .url(URL(string: "https://a.example")!, credential: nil, source: .ui))
        ])
        let ids = collection.tabCollection.tabs.map(\.uuid)
        let (tool, context) = make(collection: collection, ownerTabID: ids[0])

        let result = await tool.execute(arguments: ["tabIds": [.string(ids[0]), .string(ids[1])]], context: context)

        XCTAssertEqual(result, .success(["tabs": [["tabId": .string(ids[0]), "pinned": false],
                                                  ["tabId": .string(ids[1]), "pinned": true]]]))
        XCTAssertEqual(collection.pinnedTabsCollection?.tabs.map(\.uuid), [ids[1]])
    }

    func testWhenATabIsNotListedThenNothingIsPinned() async {
        let collection = collection([
            Tab(content: .url(URL(string: "https://a.example")!, credential: nil, source: .ui)),
            Tab(content: .newtab)
        ])
        let ids = collection.tabCollection.tabs.map(\.uuid)
        let (tool, context) = make(collection: collection, ownerTabID: ids[0])

        let result = await tool.execute(arguments: ["tabIds": [.string(ids[0]), .string(ids[1])]], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertEqual(collection.pinnedTabsCollection?.tabs.count, 0)
    }

    func testWhenTabIdsAreMalformedThenArgumentsAreInvalid() async {
        let collection = collection(urls: ["https://a.example"])
        let (tool, context) = make(collection: collection, ownerTabID: collection.tabCollection.tabs[0].uuid)
        let tooMany = JSONValue.array(Array(repeating: "id", count: PinTabBrowserTool.maxTabIDs + 1))

        for tabIDs: JSONValue in [[], .null, "id", [1], [" "], tooMany] {
            let result = await tool.execute(arguments: ["tabIds": tabIDs], context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(tabIDs)")
        }
        XCTAssertEqual(collection.pinnedTabsCollection?.tabs.count, 0)
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let collection = collection(urls: ["https://a.example"])
        let tool = PinTabBrowserTool(windowControllersManager: manager(with: [collection]))
        let context = BrowserToolCallContext(ownerTabID: collection.tabCollection.tabs[0].uuid,
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: true)

        let result = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertEqual(collection.pinnedTabsCollection?.tabs.count, 0)
    }

    private func pinned(_ tabIDs: String...) -> JSONValue {
        ["tabs": .array(tabIDs.map { ["tabId": .string($0), "pinned": true] })]
    }

    private func make(collection: TabCollectionViewModel, ownerTabID: String) -> (PinTabBrowserTool, BrowserToolCallContext) {
        let tool = PinTabBrowserTool(windowControllersManager: manager(with: [collection]))
        let context = BrowserToolCallContext(ownerTabID: ownerTabID,
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: false)
        return (tool, context)
    }

    private func manager(with collections: [TabCollectionViewModel]) -> WindowControllersManagerMock {
        let mock = WindowControllersManagerMock()
        mock.customAllTabCollectionViewModels = collections
        return mock
    }

    private func collection(_ tabs: [Tab]) -> TabCollectionViewModel {
        TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs),
                               pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock())
    }

    private func collection(urls: [String]) -> TabCollectionViewModel {
        collection(urls.map { Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui)) })
    }
}

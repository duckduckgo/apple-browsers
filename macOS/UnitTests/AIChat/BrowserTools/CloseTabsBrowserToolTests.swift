//
//  CloseTabsBrowserToolTests.swift
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
final class CloseTabsBrowserToolTests: XCTestCase {

    func testWhenTheChatsOwnTabIsNamedThenNothingCloses() async {
        let collection = collection(urls: ["https://a.example", "https://b.example"])
        let ids = collection.tabCollection.tabs.map(\.uuid)
        let (tool, context) = make(collection: collection, ownerTabID: ids[0])

        let result = await tool.execute(arguments: ["tabIds": [.string(ids[1]), .string(ids[0])]], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertEqual(collection.tabCollection.tabs.map(\.uuid), ids)
    }

    func testWhenTheOwnerTabIsNotAWebPageThenItIsNotClosed() async {
        for content: Tab.TabContent in [.settings(pane: nil), .url(URL(string: "https://duck.ai/chat")!, credential: nil, source: .ui)] {
            let owner = Tab(content: content)
            let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: [owner]), pinnedTabsManagerProvider: nil)
            let (tool, context) = make(collection: collection, ownerTabID: owner.uuid)

            let result = await tool.execute(arguments: ["tabIds": [.string(owner.uuid)]], context: context)

            XCTAssertEqual(result, .failure(.notFound), "\(content)")
            XCTAssertEqual(collection.tabCollection.tabs.count, 1)
        }
    }

    func testWhenTabIdsAreGivenThenThoseTabsCloseInOrder() async {
        let collection = collection(urls: ["https://a.example", "https://b.example", "https://c.example"])
        let ids = collection.tabCollection.tabs.map(\.uuid)
        let (tool, context) = make(collection: collection, ownerTabID: ids[0])

        let result = await tool.execute(arguments: ["tabIds": [.string(ids[2]), .string(ids[1]), .string(ids[2])]], context: context)

        XCTAssertEqual(result, .success(closed([ids[2]: true, ids[1]: true])))
        XCTAssertEqual(collection.tabCollection.tabs.map(\.uuid), [ids[0]])
    }

    func testWhenAnyTabIdIsUnknownThenNothingCloses() async {
        let collection = collection(urls: ["https://a.example", "https://b.example"])
        let ids = collection.tabCollection.tabs.map(\.uuid)
        let (tool, context) = make(collection: collection, ownerTabID: ids[0])

        let result = await tool.execute(arguments: ["tabIds": [.string(ids[1]), "missing"]], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertEqual(collection.tabCollection.tabs.count, 2)
    }

    func testWhenATabIsPinnedThenItIsReportedAsNotClosed() async {
        let collection = collection(urls: ["https://a.example", "https://b.example"], pinnable: true)
        let ids = collection.tabCollection.tabs.map(\.uuid)
        collection.pinTab(at: 1)
        let (tool, context) = make(collection: collection, ownerTabID: ids[0])

        let result = await tool.execute(arguments: ["tabIds": [.string(ids[1])]], context: context)

        XCTAssertEqual(result, .success(closed([ids[1]: false])))
        XCTAssertEqual(collection.pinnedTabsCollection?.tabs.map(\.uuid), [ids[1]])
    }

    func testWhenNoTabIdExistsThenItIsNotFound() async {
        let collection = collection(urls: ["https://a.example"])
        let (tool, context) = make(collection: collection, ownerTabID: collection.tabCollection.tabs[0].uuid)

        let result = await tool.execute(arguments: ["tabIds": ["missing", "gone"]], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertEqual(collection.tabCollection.tabs.count, 1)
    }

    func testWhenTabIdsAreMissingOrMalformedThenArgumentsAreInvalid() async {
        let collection = collection(urls: ["https://a.example"])
        let (tool, context) = make(collection: collection, ownerTabID: collection.tabCollection.tabs[0].uuid)
        let tooMany = JSONValue.array(Array(repeating: "id", count: CloseTabsBrowserTool.maxTabIDs + 1))

        for arguments: JSONValue? in [nil, [:], ["tabIds": .null]] {
            let result = await tool.execute(arguments: arguments, context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(String(describing: arguments))")
        }
        for tabIDs: JSONValue in [[], "id", [1], [" "], tooMany] {
            let result = await tool.execute(arguments: ["tabIds": tabIDs], context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(tabIDs)")
        }
        XCTAssertEqual(collection.tabCollection.tabs.count, 1)
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let collection = collection(urls: ["https://a.example"])
        let tool = CloseTabsBrowserTool(windowControllersManager: manager(with: [collection]))
        let context = BrowserToolCallContext(ownerTabID: collection.tabCollection.tabs[0].uuid,
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: true)

        let result = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertEqual(collection.tabCollection.tabs.count, 1)
    }

    func testWhenDescribedThenItAsksForPermission() {
        let tool = CloseTabsBrowserTool(windowControllersManager: WindowControllersManagerMock())

        XCTAssertEqual(tool.name, "closeTabs")
        XCTAssertEqual(tool.permissionMode, .ask)
    }

    private func closed(_ states: KeyValuePairs<String, Bool>) -> JSONValue {
        ["tabs": .array(states.map { ["tabId": .string($0.key), "closed": .bool($0.value)] })]
    }

    private func make(collection: TabCollectionViewModel, ownerTabID: String) -> (CloseTabsBrowserTool, BrowserToolCallContext) {
        let tool = CloseTabsBrowserTool(windowControllersManager: manager(with: [collection]))
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

    private func collection(urls: [String], pinnable: Bool = false) -> TabCollectionViewModel {
        TabCollectionViewModel(tabCollection: TabCollection(tabs: urls.map { Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui)) }),
                               pinnedTabsManagerProvider: pinnable ? PinnedTabsManagerProvidingMock() : nil)
    }
}

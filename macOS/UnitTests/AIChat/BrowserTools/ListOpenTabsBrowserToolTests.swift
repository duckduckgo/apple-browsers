//
//  ListOpenTabsBrowserToolTests.swift
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
final class ListOpenTabsBrowserToolTests: XCTestCase {

    func testWhenCalledThenItListsTheWindowsPagesWithTheOwnerMarkedCurrent() async throws {
        let collection = regularCollection(urls: ["https://apple.com", "https://example.com/page"])
        let owner = collection.tabCollection.tabs[0]
        let (tool, context) = make(collection: collection, ownerTabID: owner.uuid)

        let result = await tool.execute(arguments: nil, context: context)

        let tabs = try XCTUnwrap(tabsPayload(from: result))
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(tabs[0]["tabId"], .string(owner.uuid))
        XCTAssertEqual(tabs[0]["url"], "https://apple.com")
        XCTAssertEqual(tabs[0]["title"], "apple.com")
        XCTAssertEqual(tabs[0]["isCurrentTab"], true)
        XCTAssertEqual(tabs[0]["isAttachable"], true)
        XCTAssertEqual(tabs[1]["url"], "https://example.com/page")
        XCTAssertEqual(tabs[1]["isCurrentTab"], false)
    }

    func testWhenAWindowHasDuckAIAndNonPageTabsThenOnlyPagesAreListed() async throws {
        let collection = collection([
            .loaded(Tab(content: .url(URL(string: "https://duck.ai/?q=hello")!, credential: nil, source: .ui))),
            .loaded(Tab(content: .newtab)),
            .loaded(Tab(content: .url(URL(string: "https://example.com")!, credential: nil, source: .ui)))
        ])
        let (tool, context) = make(collection: collection, ownerTabID: "owner")

        let result = await tool.execute(arguments: nil, context: context)

        let tabs = try XCTUnwrap(tabsPayload(from: result))
        XCTAssertEqual(tabs.map { $0["url"] }, ["https://example.com"])
    }

    /// Listed, because it is a page the user has open — but not attachable, matching the tab picker.
    func testWhenATabIsTheDuckDuckGoHomepageThenItIsListedAsNotAttachable() async throws {
        let collection = regularCollection(urls: ["https://duckduckgo.com/"])
        let (tool, context) = make(collection: collection, ownerTabID: "owner")

        let result = await tool.execute(arguments: nil, context: context)

        let tabs = try XCTUnwrap(tabsPayload(from: result))
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs[0]["isAttachable"], false)
    }

    func testWhenLimitIsGivenThenOnlyThatManyTabsAreReturnedInOrder() async throws {
        let collection = regularCollection(urls: ["https://a.example", "https://b.example", "https://c.example"])
        let (tool, context) = make(collection: collection, ownerTabID: "owner")

        let result = await tool.execute(arguments: ["limit": 2], context: context)

        let tabs = try XCTUnwrap(tabsPayload(from: result))
        XCTAssertEqual(tabs.map { $0["url"] }, ["https://a.example", "https://b.example"])
    }

    func testWhenLimitIsOutOfRangeThenArgumentsAreInvalid() async {
        let (tool, context) = make(collection: regularCollection(urls: ["https://a.example"]), ownerTabID: "owner")

        let tooSmall = await tool.execute(arguments: ["limit": 0], context: context)
        let tooLarge = await tool.execute(arguments: ["limit": 51], context: context)

        XCTAssertEqual(tooSmall, .failure(.invalidArguments))
        XCTAssertEqual(tooLarge, .failure(.invalidArguments))
    }

    func testWhenLimitIsNotAnIntegerThenArgumentsAreInvalid() async {
        let (tool, context) = make(collection: regularCollection(urls: ["https://a.example"]), ownerTabID: "owner")

        let string = await tool.execute(arguments: ["limit": "5"], context: context)
        let fraction = await tool.execute(arguments: ["limit": 2.5], context: context)

        XCTAssertEqual(string, .failure(.invalidArguments))
        XCTAssertEqual(fraction, .failure(.invalidArguments))
    }

    func testWhenTheWindowTokenDoesNotResolveThenCallIsUnavailable() async {
        let collection = regularCollection(urls: ["https://a.example"])
        let tool = ListOpenTabsBrowserTool(windowControllersManager: manager(with: [collection]))
        let context = BrowserToolCallContext(ownerTabID: "owner",
                                             ownerWindowToken: "not-a-window",
                                             isBurner: false,
                                             supportsElicitationForm: true)

        let result = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    /// The invoker refuses Fire first; the tool refuses again so a direct call cannot bypass it.
    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let collection = collection([], burnerMode: BurnerMode(isBurner: true))
        let tool = ListOpenTabsBrowserTool(windowControllersManager: manager(with: [collection]))
        let context = BrowserToolCallContext(ownerTabID: "owner",
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: true,
                                             supportsElicitationForm: true)

        let result = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenDescribedThenItAsksForPermissionWithTheWindowsCopy() {
        let tool = ListOpenTabsBrowserTool(windowControllersManager: WindowControllersManagerMock())

        XCTAssertEqual(tool.name, "listOpenTabs")
        XCTAssertEqual(tool.permissionMode, .ask)
        XCTAssertEqual(tool.permissionReason, "Duck.ai wants to see your open tabs.")
    }

    // MARK: -

    private func make(collection: TabCollectionViewModel, ownerTabID: String) -> (ListOpenTabsBrowserTool, BrowserToolCallContext) {
        let tool = ListOpenTabsBrowserTool(windowControllersManager: manager(with: [collection]))
        let context = BrowserToolCallContext(ownerTabID: ownerTabID,
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: false,
                                             supportsElicitationForm: true)
        return (tool, context)
    }

    private func tabsPayload(from result: BrowserToolResult) -> [JSONValue]? {
        guard case .success(let payload) = result else { return nil }
        return payload["tabs"]?.arrayValue
    }

    private func manager(with collections: [TabCollectionViewModel]) -> WindowControllersManagerMock {
        let mock = WindowControllersManagerMock()
        mock.customAllTabCollectionViewModels = collections
        return mock
    }

    /// `pinnedTabsManagerProvider: nil` so the app-wide pinned tabs do not leak into the fixture.
    private func collection(_ tabs: [AnyTab], burnerMode: BurnerMode = .regular) -> TabCollectionViewModel {
        TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs),
                               pinnedTabsManagerProvider: nil,
                               burnerMode: burnerMode)
    }

    private func regularCollection(urls: [String]) -> TabCollectionViewModel {
        collection(urls.map { .loaded(Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui))) })
    }
}

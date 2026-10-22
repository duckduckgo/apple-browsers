//
//  CloseTabBrowserToolTests.swift
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
final class CloseTabBrowserToolTests: XCTestCase {

    private var openedTabs: BrowserToolOpenedTabs!
    private var collection: TabCollectionViewModel!
    private var tabs: [Tab]!
    private var tool: CloseTabBrowserTool!
    private var context: BrowserToolCallContext!

    /// Tab 0 is the chat, tab 1 the user's own, tab 2 one this chat opened.
    override func setUp() {
        super.setUp()
        openedTabs = BrowserToolOpenedTabs()
        tabs = ["https://duck.ai/", "https://user.example", "https://shop.example"].map {
            Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui))
        }
        collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs.map { .loaded($0) }),
                                            pinnedTabsManagerProvider: nil,
                                            burnerMode: .regular)
        let manager = WindowControllersManagerMock()
        manager.customAllTabCollectionViewModels = [collection]
        tool = CloseTabBrowserTool(windowControllersManager: manager, openedTabs: openedTabs)
        context = BrowserToolCallContext(ownerTabID: tabs[0].uuid,
                                         ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                         isBurner: false,
                                         supportsElicitationForm: true)
        openedTabs.add(tabs[2].uuid, ownerTabID: tabs[0].uuid)
    }

    override func tearDown() {
        openedTabs = nil
        collection = nil
        tabs = nil
        tool = nil
        context = nil
        super.tearDown()
    }

    func testWhenTheChatOpenedTheTabThenItIsClosedAndForgotten() async {
        let result = await tool.execute(arguments: ["tabId": .string(tabs[2].uuid)], context: context)

        XCTAssertEqual(result, .success(["tabId": .string(tabs[2].uuid), "closed": true]))
        XCTAssertNil(collection.indexInAllTabs(where: { $0.uuid == self.tabs[2].uuid }))
        XCTAssertFalse(openedTabs.contains(tabs[2].uuid))
    }

    /// The model must never be able to close the user's own tabs.
    func testWhenTheTabIsTheUsersOwnThenItIsNotFoundAndStaysOpen() async {
        let result = await tool.execute(arguments: ["tabId": .string(tabs[1].uuid)], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertNotNil(collection.indexInAllTabs(where: { $0.uuid == self.tabs[1].uuid }))
    }

    func testWhenTheTabIsTheChatItselfThenItIsNotFound() async {
        let result = await tool.execute(arguments: ["tabId": .string(tabs[0].uuid)], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertEqual(collection.allTabsCount, 3)
    }

    func testWhenAnotherChatOpenedTheTabThenItIsNotFoundAndStaysOpen() async {
        let otherChat = BrowserToolCallContext(ownerTabID: "other-chat",
                                               ownerWindowToken: context.ownerWindowToken,
                                               isBurner: false,
                                               supportsElicitationForm: true)

        let result = await tool.execute(arguments: ["tabId": .string(tabs[2].uuid)], context: otherChat)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertTrue(openedTabs.contains(tabs[2].uuid, ownerTabID: tabs[0].uuid))
        XCTAssertEqual(collection.allTabsCount, 3)
    }

    func testWhenTheTabIsAlreadyGoneThenItIsNotFoundAndForgotten() async {
        openedTabs.add("gone", ownerTabID: tabs[0].uuid)

        let result = await tool.execute(arguments: ["tabId": "gone"], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertFalse(openedTabs.contains("gone"))
    }

    func testWhenTabIdIsMissingOrNotAStringThenArgumentsAreInvalid() async {
        let missing = await tool.execute(arguments: [:], context: context)
        let blank = await tool.execute(arguments: ["tabId": "  "], context: context)
        let number = await tool.execute(arguments: ["tabId": 3], context: context)
        let none = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(missing, .failure(.invalidArguments))
        XCTAssertEqual(blank, .failure(.invalidArguments))
        XCTAssertEqual(number, .failure(.invalidArguments))
        XCTAssertEqual(none, .failure(.invalidArguments))
        XCTAssertEqual(collection.allTabsCount, 3)
    }

    func testWhenTheWindowIsAFireWindowThenTheCallIsUnavailable() async {
        let fireContext = BrowserToolCallContext(ownerTabID: context.ownerTabID,
                                                 ownerWindowToken: context.ownerWindowToken,
                                                 isBurner: true,
                                                 supportsElicitationForm: true)

        let result = await tool.execute(arguments: ["tabId": .string(tabs[2].uuid)], context: fireContext)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertEqual(collection.allTabsCount, 3)
    }

    func testWhenDescribedThenItIsAutoMode() {
        XCTAssertEqual(tool.name, "closeTab")
        XCTAssertEqual(tool.permissionMode, .auto)
    }
}

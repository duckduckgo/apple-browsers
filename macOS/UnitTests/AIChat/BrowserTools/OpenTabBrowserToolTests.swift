//
//  OpenTabBrowserToolTests.swift
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
final class OpenTabBrowserToolTests: XCTestCase {

    func testWhenAWebURLIsGivenThenItOpensInTheBackgroundOfTheChatsWindow() async throws {
        let collection = collection(urls: ["https://a.example"])
        let current = collection.tabCollection.tabs[0].uuid
        collection.select(at: .unpinned(0))
        let (tool, context) = make(collection: collection)

        let result = await tool.execute(arguments: ["url": "https://duckduckgo.com/about"], context: context)

        let opened = try XCTUnwrap(collection.tabCollection.tabs.last)
        XCTAssertEqual(result, .success(["tabId": .string(opened.uuid)]))
        XCTAssertEqual(collection.tabCollection.tabs.count, 2)
        XCTAssertEqual(opened.content.urlForWebView, URL(string: "https://duckduckgo.com/about"))
        XCTAssertEqual(collection.selectedTabViewModel?.tab.uuid, current)
    }

    /// With no regular window to fall back on, a detached chat opens in its host tab's window.
    func testWhenDetachedWithoutAnyMainWindowThenItOpensInTheChatsWindow() async {
        let collection = collection(urls: ["https://a.example"])
        let (tool, context) = make(collection: collection, isDetached: true)

        let result = await tool.execute(arguments: ["url": "https://duckduckgo.com"], context: context)

        guard case .success = result else { return XCTFail("\(result)") }
        XCTAssertEqual(collection.tabCollection.tabs.count, 2)
    }

    func testWhenTheURLIsNotAWebPageThenArgumentsAreInvalid() async {
        let collection = collection(urls: ["https://a.example"])
        let (tool, context) = make(collection: collection)
        let tooLong = JSONValue.string("https://a.example/" + String(repeating: "a", count: BrowserToolOutputLimits.url))

        for url: JSONValue in ["", "duckduckgo.com", "javascript:alert(1)", "file:///etc/hosts", "duck://settings",
                               "data:text/html,hi", "https://", 1, tooLong] {
            let result = await tool.execute(arguments: ["url": url], context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(url)")
        }
        let missing = await tool.execute(arguments: [:], context: context)
        XCTAssertEqual(missing, .failure(.invalidArguments))
        XCTAssertEqual(collection.tabCollection.tabs.count, 1)
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let collection = collection(urls: ["https://a.example"])
        let tool = OpenTabBrowserTool(windowControllersManager: manager(with: [collection]))
        let context = BrowserToolCallContext(ownerTabID: "owner",
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: true)

        let result = await tool.execute(arguments: ["url": "https://duckduckgo.com"], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertEqual(collection.tabCollection.tabs.count, 1)
    }

    func testWhenTheWindowTokenDoesNotResolveThenCallIsUnavailable() async {
        let tool = OpenTabBrowserTool(windowControllersManager: manager(with: [collection(urls: [])]))
        let context = BrowserToolCallContext(ownerTabID: "owner", ownerWindowToken: "not-a-window", isBurner: false)

        let result = await tool.execute(arguments: ["url": "https://duckduckgo.com"], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    // MARK: -

    private func make(collection: TabCollectionViewModel, isDetached: Bool = false) -> (OpenTabBrowserTool, BrowserToolCallContext) {
        let tool = OpenTabBrowserTool(windowControllersManager: manager(with: [collection]))
        let context = BrowserToolCallContext(ownerTabID: "owner",
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: false,
                                             isDetached: isDetached)
        return (tool, context)
    }

    private func manager(with collections: [TabCollectionViewModel]) -> WindowControllersManagerMock {
        let mock = WindowControllersManagerMock()
        mock.customAllTabCollectionViewModels = collections
        return mock
    }

    private func collection(urls: [String]) -> TabCollectionViewModel {
        TabCollectionViewModel(tabCollection: TabCollection(tabs: urls.map { Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui)) }),
                               pinnedTabsManagerProvider: nil)
    }
}

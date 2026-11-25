//
//  SwitchToTabBrowserToolTests.swift
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
final class SwitchToTabBrowserToolTests: XCTestCase {

    func testWhenTheTabIsAWebPageThenItIsSelected() async {
        let (tool, context, collection) = make()
        let target = collection.tabCollection.tabs[1].uuid

        let result = await tool.execute(arguments: ["tabId": .string(target)], context: context)

        guard case .success(let value) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(value["tabId"], .string(target))
        XCTAssertEqual(collection.selectedTabViewModel?.tab.uuid, target)
    }

    func testWhenTheTabIsNotAWebPageThenItIsNotFound() async {
        let (tool, context, collection) = make()

        for target in collection.tabCollection.tabs[2...].map(\.uuid) {
            let result = await tool.execute(arguments: ["tabId": .string(target)], context: context)

            XCTAssertEqual(result, .failure(.notFound))
            XCTAssertEqual(collection.selectedTabViewModel?.tab.uuid, collection.tabCollection.tabs[0].uuid)
        }
    }

    private func make() -> (SwitchToTabBrowserTool, BrowserToolCallContext, TabCollectionViewModel) {
        let tabs = [
            Tab(content: .url(URL(string: "https://a.example")!, credential: nil, source: .ui)),
            Tab(content: .url(URL(string: "https://b.example")!, credential: nil, source: .ui)),
            Tab(content: .settings(pane: nil)),
            Tab(content: .url(URL(string: "https://duck.ai/chat")!, credential: nil, source: .ui))
        ]
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs), pinnedTabsManagerProvider: nil)
        collection.select(at: .unpinned(0))
        let manager = WindowControllersManagerMock()
        manager.customAllTabCollectionViewModels = [collection]
        let context = BrowserToolCallContext(ownerTabID: tabs[0].uuid,
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: false)
        return (SwitchToTabBrowserTool(windowControllersManager: manager), context, collection)
    }
}

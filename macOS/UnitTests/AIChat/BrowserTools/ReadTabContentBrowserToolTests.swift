//
//  ReadTabContentBrowserToolTests.swift
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
final class ReadTabContentBrowserToolTests: XCTestCase {

    private var reader: StubPageContentReader!

    override func setUp() {
        super.setUp()
        reader = StubPageContentReader()
    }

    override func tearDown() {
        reader = nil
        super.tearDown()
    }

    func testWhenTabIdIsOmittedThenTheOwnerTabIsRead() async throws {
        let (tool, context, _) = make()
        reader.pageContext = AIChatPageContextData(title: "Owner", favicon: [], url: "https://a.example", content: "body", truncated: false, fullContentLength: 4)

        let result = await tool.execute(arguments: nil, context: context)

        guard case .success(let payload) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(reader.requestedTabID, context.ownerTabID)
        XCTAssertEqual(payload["tabId"], .string(context.ownerTabID))
        XCTAssertEqual(payload["title"], "Owner")
        XCTAssertEqual(payload["content"], "body")
        XCTAssertEqual(payload["truncated"], false)
        XCTAssertEqual(payload["fullContentLength"], 4)
    }

    func testWhenTabIdNamesAnotherTabInTheWindowThenThatTabIsRead() async {
        let (tool, context, other) = make()

        _ = await tool.execute(arguments: ["tabId": .string(other.uuid)], context: context)

        XCTAssertEqual(reader.requestedTabID, other.uuid)
    }

    func testWhenTabIdIsNotInTheOwnerWindowThenCallIsNotFound() async {
        let (tool, context, _) = make()

        let result = await tool.execute(arguments: ["tabId": "elsewhere"], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertNil(reader.requestedTabID)
    }

    func testWhenArgumentsAreMalformedThenTheyAreInvalid() async {
        let (tool, context, _) = make()

        let notObject = await tool.execute(arguments: "x", context: context)
        let badTabID = await tool.execute(arguments: ["tabId": 5], context: context)

        XCTAssertEqual(notObject, .failure(.invalidArguments))
        XCTAssertEqual(badTabID, .failure(.invalidArguments))
    }

    func testWhenNoPageContextCanBeReadThenCallIsUnavailable() async {
        let (tool, context, _) = make()
        reader.pageContext = nil

        let result = await tool.execute(arguments: [:], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let (tool, ownerContext, _) = make()
        let context = BrowserToolCallContext(ownerTabID: ownerContext.ownerTabID,
                                             ownerWindowToken: ownerContext.ownerWindowToken,
                                             isBurner: true,
                                             supportsElicitationForm: true)

        let result = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertNil(reader.requestedTabID)
    }

    func testWhenDescribedThenItAsksWithTheWindowsCopy() {
        let (tool, _, _) = make()

        XCTAssertEqual(tool.name, "readTabContent")
        XCTAssertEqual(tool.permissionMode, .ask)
        XCTAssertEqual(tool.permissionReason, "Duck.ai wants to read this tab's content.")
    }

    // MARK: -

    private func make() -> (ReadTabContentBrowserTool, BrowserToolCallContext, Tab) {
        let owner = Tab(content: .url(URL(string: "https://a.example")!, credential: nil, source: .ui))
        let other = Tab(content: .url(URL(string: "https://b.example")!, credential: nil, source: .ui))
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: [.loaded(owner), .loaded(other)]),
                                                pinnedTabsManagerProvider: nil,
                                                burnerMode: .regular)
        let manager = WindowControllersManagerMock()
        manager.customAllTabCollectionViewModels = [collection]
        reader.pageContext = AIChatPageContextData(title: "t", favicon: [], url: "https://a.example", content: "c", truncated: false, fullContentLength: 1)
        let tool = ReadTabContentBrowserTool(windowControllersManager: manager, reader: reader)
        let context = BrowserToolCallContext(ownerTabID: owner.uuid,
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: false,
                                             supportsElicitationForm: true)
        return (tool, context, other)
    }
}

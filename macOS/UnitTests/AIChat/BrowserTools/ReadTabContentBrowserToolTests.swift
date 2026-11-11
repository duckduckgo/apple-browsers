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

    func testWhenContentExceedsTheClientToolLimitThenOnlyTheClientResultIsCut() async throws {
        let (tool, context, _) = make()
        let content = String(repeating: "a", count: BrowserToolOutputLimits.content + 10)
        reader.pageContext = AIChatPageContextData(title: "t", favicon: [AIChatPageContextData.PageContextFavicon(href: "https://a.example/f.ico", rel: "icon")],
                                                   url: "https://a.example", content: content, truncated: false,
                                                   fullContentLength: content.count, attachable: false)

        let result = await tool.execute(arguments: nil, context: context)
        guard case .success(let pagePayload) = result else { return XCTFail("expected success, got \(result)") }
        let clientResult = tool.clientToolResult(from: pagePayload)

        XCTAssertEqual(pagePayload["content"]?.stringValue, content)
        XCTAssertNotNil(pagePayload["favicon"])
        guard case .success(let payload) = clientResult else { return XCTFail("expected success, got \(clientResult)") }
        XCTAssertEqual(payload.objectValue?.keys.sorted(),
                       ["attachable", "attached", "content", "fullContentLength", "tabId", "title", "truncated", "url"])
        XCTAssertEqual(payload["content"]?.stringValue?.count, BrowserToolOutputLimits.content)
        XCTAssertEqual(payload["truncated"], true)
        XCTAssertEqual(payload["fullContentLength"], .int(content.count))
        XCTAssertEqual(payload["attachable"], false)
        XCTAssertEqual(payload["attached"], false)
    }

    func testWhenThePageIsADocumentThenTheClientResultIsUnavailable() async throws {
        let (tool, context, _) = make()
        reader.pageContext = .document(title: "t", url: "https://a.example/doc.pdf", mimeType: AIChatPageContextData.pdfMIMEType, data: "JVBERi0=")

        let result = await tool.execute(arguments: nil, context: context)
        guard case .success(let pagePayload) = result else { return XCTFail("expected success, got \(result)") }

        XCTAssertEqual(tool.clientToolResult(from: pagePayload), .failure(.unavailable))
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
                                             isBurner: true)

        let result = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertNil(reader.requestedTabID)
    }

    func testWhenDescribedThenItAsksWithTheWindowsCopy() {
        let (tool, _, _) = make()

        XCTAssertEqual(tool.name, "readTabContent")
        XCTAssertEqual(tool.permissionMode, .ask)
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
                                             isBurner: false)
        return (tool, context, other)
    }
}

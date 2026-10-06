//
//  FindInPageBrowserToolTests.swift
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
final class FindInPageBrowserToolTests: XCTestCase {

    private var reader: StubPageContentReader!

    override func setUp() {
        super.setUp()
        reader = StubPageContentReader()
    }

    override func tearDown() {
        reader = nil
        super.tearDown()
    }

    // MARK: - Text search

    func testWhenQueryOccursThenEveryNonOverlappingHitIsCountedAndSnippetsAreCapped() {
        let content = "aaa aaa aaa aaa"

        let found = FindInPageBrowserTool.search(content: content, query: "aa", caseSensitive: false, maxMatches: 2)

        XCTAssertEqual(found.matchCount, 4)
        XCTAssertEqual(found.matches.map(\.matchIndex), [0, 1])
    }

    func testWhenCaseSensitiveThenCaseMustMatch() {
        let content = "Games and games"

        let sensitive = FindInPageBrowserTool.search(content: content, query: "games", caseSensitive: true, maxMatches: 10)
        let insensitive = FindInPageBrowserTool.search(content: content, query: "games", caseSensitive: false, maxMatches: 10)

        XCTAssertEqual(sensitive.matchCount, 1)
        XCTAssertEqual(insensitive.matchCount, 2)
    }

    /// Forty characters either side, clipped to the text, whitespace collapsed.
    func testWhenSnippetIsBuiltThenItIsClippedToTheRadiusAndTheTextBounds() {
        let padding = String(repeating: "x", count: 60)
        let content = "start \n\n  \(padding) needle \(padding) end"

        let found = FindInPageBrowserTool.search(content: content, query: "needle", caseSensitive: false, maxMatches: 1)

        // Forty characters each side: the separating space plus 39 of the padding.
        let snippet = found.matches[0].snippet
        XCTAssertEqual(snippet, String(repeating: "x", count: 39) + " needle " + String(repeating: "x", count: 39))

        let short = FindInPageBrowserTool.search(content: "a  b\tneedle", query: "needle", caseSensitive: false, maxMatches: 1)
        XCTAssertEqual(short.matches[0].snippet, "a b needle")
    }

    func testWhenContentOrQueryIsEmptyThenNothingIsFound() {
        XCTAssertEqual(FindInPageBrowserTool.search(content: "", query: "a", caseSensitive: false, maxMatches: 5).matchCount, 0)
        XCTAssertEqual(FindInPageBrowserTool.search(content: "abc", query: "", caseSensitive: false, maxMatches: 5).matchCount, 0)
    }

    // MARK: - Arguments

    func testWhenQueryIsMissingOrBlankThenArgumentsAreInvalid() async {
        let (tool, context) = make()

        let missing = await tool.execute(arguments: [:], context: context)
        let blank = await tool.execute(arguments: ["query": "  "], context: context)
        let none = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(missing, .failure(.invalidArguments))
        XCTAssertEqual(blank, .failure(.invalidArguments))
        XCTAssertEqual(none, .failure(.invalidArguments))
    }

    func testWhenOptionsHaveTheWrongTypeOrRangeThenArgumentsAreInvalid() async {
        let (tool, context) = make()

        let caseSensitive = await tool.execute(arguments: ["query": "a", "caseSensitive": "yes"], context: context)
        let tooMany = await tool.execute(arguments: ["query": "a", "maxMatches": 51], context: context)
        let tooFew = await tool.execute(arguments: ["query": "a", "maxMatches": 0], context: context)
        let badTab = await tool.execute(arguments: ["query": "a", "tabId": 7], context: context)

        XCTAssertEqual(caseSensitive, .failure(.invalidArguments))
        XCTAssertEqual(tooMany, .failure(.invalidArguments))
        XCTAssertEqual(tooFew, .failure(.invalidArguments))
        XCTAssertEqual(badTab, .failure(.invalidArguments))
    }

    // MARK: - Targeting and result

    func testWhenTabIdIsNotInTheOwnerWindowThenCallIsNotFound() async {
        let (tool, context) = make()

        let result = await tool.execute(arguments: ["query": "a", "tabId": "elsewhere"], context: context)

        XCTAssertEqual(result, .failure(.notFound))
    }

    func testWhenNoPageContextCanBeReadThenCallIsUnavailable() async {
        let (tool, context) = make()
        reader.pageContext = nil

        let result = await tool.execute(arguments: ["query": "a"], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    /// Indexes come from extracted text, never the DOM, so the FE is told to highlight by quotes.
    func testWhenMatchesAreFoundThenTheReplyCarriesSnippetsAndMarksIndexesUnreliable() async throws {
        let (tool, context) = make()
        reader.pageContext = AIChatPageContextData(title: "Wiki", favicon: [], url: "https://a.example/p",
                                                   content: "video games are games", truncated: true, fullContentLength: 999)

        let result = await tool.execute(arguments: ["query": "GAMES", "maxMatches": 1], context: context)

        guard case .success(let payload) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(payload["tabId"], .string(context.ownerTabID))
        XCTAssertEqual(payload["title"], "Wiki")
        XCTAssertEqual(payload["url"], "https://a.example/p")
        XCTAssertEqual(payload["query"], "GAMES")
        XCTAssertEqual(payload["matchCount"], 2)
        XCTAssertEqual(payload["matches"]?.arrayValue?.count, 1)
        XCTAssertEqual(payload["matches"]?.arrayValue?.first?["matchIndex"], 0)
        XCTAssertEqual(payload["truncated"], true)
        XCTAssertEqual(payload["contentTruncated"], true)
        XCTAssertEqual(payload["matchIndexesReliable"], false)
        XCTAssertEqual(reader.requestedTabID, context.ownerTabID)
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let (tool, ownerContext) = make()
        let context = BrowserToolCallContext(ownerTabID: ownerContext.ownerTabID,
                                             ownerWindowToken: ownerContext.ownerWindowToken,
                                             isBurner: true,
                                             supportsElicitationForm: true)

        let result = await tool.execute(arguments: ["query": "a"], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    // MARK: -

    private func make() -> (FindInPageBrowserTool, BrowserToolCallContext) {
        let tab = Tab(content: .url(URL(string: "https://a.example/p")!, credential: nil, source: .ui))
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: [.loaded(tab)]),
                                                pinnedTabsManagerProvider: nil,
                                                burnerMode: .regular)
        let manager = WindowControllersManagerMock()
        manager.customAllTabCollectionViewModels = [collection]
        reader.pageContext = AIChatPageContextData(title: "t", favicon: [], url: "https://a.example/p", content: "a", truncated: false, fullContentLength: 1)
        let tool = FindInPageBrowserTool(windowControllersManager: manager, reader: reader)
        let context = BrowserToolCallContext(ownerTabID: tab.uuid,
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: false,
                                             supportsElicitationForm: true)
        return (tool, context)
    }
}

final class StubPageContentReader: BrowserToolPageContentReading {
    var pageContext: AIChatPageContextData?
    private(set) var requestedTabID: TabIdentifier?

    func pageContext(forTabID tabID: TabIdentifier, in collection: TabCollectionViewModel) async -> AIChatPageContextData? {
        requestedTabID = tabID
        return pageContext
    }
}

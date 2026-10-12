//
//  HighlightInPageBrowserToolTests.swift
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
final class HighlightInPageBrowserToolTests: XCTestCase {

    private var highlighter: StubHighlighter!

    override func setUp() {
        super.setUp()
        highlighter = StubHighlighter()
    }

    override func tearDown() {
        highlighter = nil
        super.tearDown()
    }

    // MARK: - Arguments

    /// macOS never issues reliable match indexes, so receiving them means the flag was ignored.
    func testWhenMatchIndexesAreGivenThenArgumentsAreInvalid() async {
        let (tool, context, _) = make(urls: ["https://a.example"])

        let result = await tool.execute(arguments: ["query": "x", "matchIndexes": [0]], context: context)

        XCTAssertEqual(result, .failure(.invalidArguments))
        XCTAssertTrue(highlighter.requests.isEmpty)
    }

    func testWhenQuotesAreMissingEmptyOrBlankThenArgumentsAreInvalid() async {
        let (tool, context, _) = make(urls: ["https://a.example"])

        let missing = await tool.execute(arguments: [:], context: context)
        let empty = await tool.execute(arguments: ["quotes": []], context: context)
        let blank = await tool.execute(arguments: ["quotes": ["games", "  "]], context: context)
        let notArray = await tool.execute(arguments: ["quotes": "games"], context: context)

        XCTAssertEqual(missing, .failure(.invalidArguments))
        XCTAssertEqual(empty, .failure(.invalidArguments))
        XCTAssertEqual(blank, .failure(.invalidArguments))
        XCTAssertEqual(notArray, .failure(.invalidArguments))
    }

    func testWhenArgumentsAreNotAnObjectThenTheyAreInvalid() async {
        let (tool, context, _) = make(urls: ["https://a.example"])

        let result = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(result, .failure(.invalidArguments))
    }

    // MARK: - Targeting

    func testWhenTabIdIsNotInTheOwnerWindowThenCallIsNotFound() async {
        let (tool, context, _) = make(urls: ["https://a.example"])

        let result = await tool.execute(arguments: ["quotes": ["x"], "tabId": "elsewhere"], context: context)

        XCTAssertEqual(result, .failure(.notFound))
    }

    func testWhenTargetIsADuckAITabThenCallIsUnavailable() async {
        let (tool, context, _) = make(urls: ["https://duck.ai/?q=hi"])

        let result = await tool.execute(arguments: ["quotes": ["x"]], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenCalledInAFireWindowThenCallIsUnavailable() async {
        let (tool, ownerContext, _) = make(urls: ["https://a.example"])
        let context = BrowserToolCallContext(ownerTabID: ownerContext.ownerTabID,
                                             ownerWindowToken: ownerContext.ownerWindowToken,
                                             isBurner: true,
                                             supportsElicitationForm: true)

        let result = await tool.execute(arguments: ["quotes": ["x"]], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertTrue(highlighter.requests.isEmpty)
    }

    // MARK: - Painting

    /// The overlay is shared with Cmd+F; a search the user is in the middle of is not ours to take.
    func testWhenTheFindBarIsOpenThenCallIsUnavailable() async {
        let (tool, context, _) = make(urls: ["https://a.example"])
        highlighter.findBarVisible = true

        let result = await tool.execute(arguments: ["quotes": ["x"]], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertTrue(highlighter.requests.isEmpty)
    }

    func testWhenAQuoteMatchesThenEveryOccurrenceCountIsReported() async throws {
        let (tool, context, tab) = make(urls: ["https://a.example/page"])
        highlighter.outcomes = ["games": .painted(count: 3)]

        let result = await tool.execute(arguments: ["quotes": ["games"]], context: context)

        guard case .success(let payload) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(payload["tabId"], .string(tab.uuid))
        XCTAssertEqual(payload["url"], "https://a.example/page")
        XCTAssertEqual(payload["highlightedCount"], 3)
        XCTAssertEqual(payload["truncated"], false)
        XCTAssertEqual(highlighter.requests, ["games"])
    }

    /// WebKit finds one string, so the first quote with a hit is painted and the rest are truncated.
    func testWhenSeveralQuotesAreGivenThenTheFirstMatchingOneIsPaintedAndTheRestAreTruncated() async throws {
        let (tool, context, _) = make(urls: ["https://a.example"])
        highlighter.outcomes = ["nope": .notFound, "games": .painted(count: 2), "later": .painted(count: 9)]

        let result = await tool.execute(arguments: ["quotes": ["nope", "games", "later"]], context: context)

        guard case .success(let payload) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(payload["highlightedCount"], 2)
        XCTAssertEqual(payload["truncated"], true)
        XCTAssertEqual(highlighter.requests, ["nope", "games"])
    }

    func testWhenNoQuoteMatchesThenZeroIsReportedWithoutTruncation() async throws {
        let (tool, context, _) = make(urls: ["https://a.example"])
        highlighter.outcomes = ["a": .notFound, "b": .notFound]

        let result = await tool.execute(arguments: ["quotes": ["a", "b"]], context: context)

        guard case .success(let payload) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(payload["highlightedCount"], 0)
        XCTAssertEqual(payload["truncated"], false)
    }

    /// The public find API reports found-or-not with no total: at least one, and say so.
    func testWhenTheCountIsUnknownThenOneIsReportedAsTruncated() async throws {
        let (tool, context, _) = make(urls: ["https://a.example"])
        highlighter.outcomes = ["games": .painted(count: nil)]

        let result = await tool.execute(arguments: ["quotes": ["games"]], context: context)

        guard case .success(let payload) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(payload["highlightedCount"], 1)
        XCTAssertEqual(payload["truncated"], true)
    }

    func testWhenFindIsCancelledThenCallIsUnavailable() async {
        let (tool, context, _) = make(urls: ["https://a.example"])
        highlighter.outcomes = ["games": .cancelled]

        let result = await tool.execute(arguments: ["quotes": ["games"]], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenDescribedThenItIsAutoModeAndNotReadOnly() {
        let (tool, _, _) = make(urls: ["https://a.example"])

        XCTAssertEqual(tool.name, "highlightInPage")
        XCTAssertEqual(tool.permissionMode, .auto)
        XCTAssertEqual(tool.annotations?.readOnlyHint, false)
    }

    // MARK: -

    private func make(urls: [String]) -> (HighlightInPageBrowserTool, BrowserToolCallContext, Tab) {
        let tabs = urls.map { Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui)) }
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs.map { .loaded($0) }),
                                                pinnedTabsManagerProvider: nil,
                                                burnerMode: .regular)
        let manager = WindowControllersManagerMock()
        manager.customAllTabCollectionViewModels = [collection]
        let tool = HighlightInPageBrowserTool(windowControllersManager: manager, highlighter: highlighter)
        let context = BrowserToolCallContext(ownerTabID: tabs[0].uuid,
                                             ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                             isBurner: false,
                                             supportsElicitationForm: true)
        return (tool, context, tabs[0])
    }
}

private final class StubHighlighter: BrowserToolPageHighlighting {
    var findBarVisible = false
    var outcomes: [String: BrowserToolHighlightOutcome] = [:]
    private(set) var requests: [String] = []

    func isFindBarVisible(in tab: Tab) -> Bool { findBarVisible }

    func highlight(_ quote: String, in tab: Tab) async -> BrowserToolHighlightOutcome {
        requests.append(quote)
        return outcomes[quote] ?? .notFound
    }
}

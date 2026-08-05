//
//  AIChatSelectionContextTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo
@testable import AIChat

final class AIChatSelectionContextBuilderTests: XCTestCase {

    private let url = URL(string: "https://example.com/article")!

    // MARK: - makeSelection

    func testShortSelectionIsNotTruncated() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "hello world", url: url)

        XCTAssertEqual(selection.content, "hello world")
        XCTAssertFalse(selection.truncated)
        XCTAssertEqual(selection.fullContentLength, 11)
    }

    func testSelectionAtTheCapIsNotTruncated() {
        let text = String(repeating: "a", count: AIChatSelectionContextBuilder.maxSelectionContextLength)
        let selection = AIChatSelectionContextBuilder.makeSelection(text: text, url: url)

        XCTAssertFalse(selection.truncated)
        XCTAssertEqual(selection.content.count, AIChatSelectionContextBuilder.maxSelectionContextLength)
    }

    func testSelectionOverTheCapIsTruncatedForContentOnly() {
        let overflow = 500
        let text = String(repeating: "a", count: AIChatSelectionContextBuilder.maxSelectionContextLength + overflow)
        let selection = AIChatSelectionContextBuilder.makeSelection(text: text, url: url)

        XCTAssertTrue(selection.truncated)
        XCTAssertEqual(selection.content.count, AIChatSelectionContextBuilder.maxSelectionContextLength)
        // The point of the pair: `content` is capped but the length describes what the user selected.
        XCTAssertEqual(selection.fullContentLength, AIChatSelectionContextBuilder.maxSelectionContextLength + overflow)
    }

    /// The frontend can't recount words from a truncated `content`, so native has to report the real
    /// figure — which is only possible because the selection reaches here uncapped.
    func testWordCountIsMeasuredOnTheUntruncatedSelection() {
        let word = "word "
        let repeats = 4000
        let text = String(repeating: word, count: repeats)
        XCTAssertGreaterThan(text.count, AIChatSelectionContextBuilder.maxSelectionContextLength)

        let selection = AIChatSelectionContextBuilder.makeSelection(text: text, url: url)

        XCTAssertTrue(selection.truncated)
        XCTAssertEqual(selection.wordCount, repeats)
    }

    func testWordCountIgnoresRunsOfWhitespace() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "one   two\n\nthree\tfour", url: url)
        XCTAssertEqual(selection.wordCount, 4)
    }

    func testSelectionCarriesURLAndGenericTitle() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url)

        XCTAssertEqual(selection.url, url.absoluteString)
        XCTAssertEqual(selection.title, UserText.aiChatTextSelectionTitle)
    }

    func testSelectionWithoutURLGetsEmptyURLString() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "text", url: nil)
        XCTAssertEqual(selection.url, "")
    }

    func testFaviconIsWrappedWhenProvided() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url, faviconBase64: "data:image/png;base64,AAAA")

        XCTAssertEqual(selection.favicon.count, 1)
        XCTAssertEqual(selection.favicon.first?.href, "data:image/png;base64,AAAA")
        XCTAssertEqual(selection.favicon.first?.rel, "icon")
    }

    func testFaviconIsEmptyWhenAbsent() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url)
        XCTAssertTrue(selection.favicon.isEmpty)
    }

    func testEachSelectionGetsAUniqueIdentifier() {
        let first = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url)
        let second = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url)

        XCTAssertNotEqual(first.id, second.id)
    }

    // MARK: - displayTitle

    func testDisplayTitleQuotesTheSnippet() {
        XCTAssertEqual(AIChatSelectionContextBuilder.displayTitle(for: "hello"), "“hello”")
    }

    func testDisplayTitleCollapsesWhitespaceSoChipsStaySingleLine() {
        XCTAssertEqual(AIChatSelectionContextBuilder.displayTitle(for: "first line\n\n  second   line"), "“first line second line”")
    }

    func testLongDisplayTitleIsTruncatedWithAnEllipsis() {
        let content = String(repeating: "a", count: AIChatSelectionContextBuilder.maxDisplayTitleLength + 50)
        let title = AIChatSelectionContextBuilder.displayTitle(for: content)

        XCTAssertTrue(title.hasSuffix("…”"))
        // Quotes plus the ellipsis sit outside the bounded snippet.
        XCTAssertEqual(title.count, AIChatSelectionContextBuilder.maxDisplayTitleLength + 3)
    }

    func testDisplayTitleAtTheLimitIsNotTruncated() {
        let content = String(repeating: "a", count: AIChatSelectionContextBuilder.maxDisplayTitleLength)
        let title = AIChatSelectionContextBuilder.displayTitle(for: content)

        XCTAssertFalse(title.contains("…"))
    }
}

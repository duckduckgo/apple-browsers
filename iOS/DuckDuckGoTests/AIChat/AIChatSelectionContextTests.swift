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
        XCTAssertEqual(selection.fullContentLength, AIChatSelectionContextBuilder.maxSelectionContextLength + overflow)
    }

    /// Can't be recomputed from a truncated `content`, so it is measured before truncation.
    func testWordCountIsMeasuredOnTheUntruncatedSelection() {
        let repeats = 4000
        let text = String(repeating: "word ", count: repeats)
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

    /// Chips are reconciled and removed by id, so identical text must not collide.
    func testEachSelectionGetsAUniqueIdentifier() {
        let first = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url)
        let second = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url)

        XCTAssertNotEqual(first.id, second.id)
    }

    // MARK: - displayTitle

    func testDisplayTitleLeadsWithTheWordCountThenASnippet() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "a dog barked", url: url)

        let title = AIChatSelectionContextBuilder.displayTitle(for: selection)

        XCTAssertEqual(title, "\(UserText.aiChatTextSelectionWordCount(3)) · a dog barked")
    }

    func testDisplayTitleUsesTheSingularWordFormForAOneWordSelection() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "barked", url: url)

        XCTAssertEqual(AIChatSelectionContextBuilder.displayTitle(for: selection), "1 word · barked")
    }

    func testDisplayTitleUsesThePluralWordFormBeyondOneWord() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "a dog barked", url: url)

        XCTAssertEqual(AIChatSelectionContextBuilder.displayTitle(for: selection), "3 words · a dog barked")
    }

    func testDisplayTitleCollapsesWhitespaceSoChipsStaySingleLine() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "first line\n\n  second   line", url: url)

        XCTAssertTrue(AIChatSelectionContextBuilder.displayTitle(for: selection).hasSuffix("first line second line"))
    }

    /// The count describes the whole selection even when the snippet and payload were cut.
    func testDisplayTitleWordCountDescribesTheUntruncatedSelection() {
        let text = String(repeating: "word ", count: 4000)
        let selection = AIChatSelectionContextBuilder.makeSelection(text: text, url: url)

        XCTAssertTrue(AIChatSelectionContextBuilder.displayTitle(for: selection)
            .hasPrefix(UserText.aiChatTextSelectionWordCount(4000)))
    }

    func testLongDisplayTitleIsTruncatedWithAnEllipsis() {
        let content = String(repeating: "a", count: AIChatSelectionContextBuilder.maxDisplayTitleLength + 50)
        let selection = AIChatSelectionContextBuilder.makeSelection(text: content, url: url)

        XCTAssertTrue(AIChatSelectionContextBuilder.displayTitle(for: selection).hasSuffix("…"))
    }

    func testDisplayTitleAtTheLimitIsNotTruncated() {
        let content = String(repeating: "a", count: AIChatSelectionContextBuilder.maxDisplayTitleLength)
        let selection = AIChatSelectionContextBuilder.makeSelection(text: content, url: url)

        XCTAssertFalse(AIChatSelectionContextBuilder.displayTitle(for: selection).contains("…"))
    }
}

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

final class AIChatTextSelectionActionTests: XCTestCase {

    /// Only ask attaches. Summarize carries its text inside the tool payload, so attaching as well
    /// would send the model the text twice and leave a chip behind for a question already asked.
    func testOnlyAskAttachesTheSelection() {
        XCTAssertTrue(AIChatTextSelectionAction.ask.attachesSelection)
        XCTAssertFalse(AIChatTextSelectionAction.summarize.attachesSelection)
        XCTAssertFalse(AIChatTextSelectionAction.translate.attachesSelection)
    }

    func testOnlySummarizeAndTranslateSubmitImmediately() {
        XCTAssertFalse(AIChatTextSelectionAction.ask.autoSubmits)
        XCTAssertTrue(AIChatTextSelectionAction.summarize.autoSubmits)
        XCTAssertTrue(AIChatTextSelectionAction.translate.autoSubmits)
    }

    /// The two are exact opposites today; if that ever stops being true, `attachesSelection` needs its
    /// own switch rather than being derived from `autoSubmits`.
    func testAttachingAndAutoSubmittingAreMutuallyExclusive() {
        for action in AIChatTextSelectionAction.allCases {
            XCTAssertNotEqual(action.attachesSelection, action.autoSubmits, "\(action)")
        }
    }
}

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

    // MARK: - makePageContextData (interim delivery)

    func testPageContextDataCarriesTheSelectionsContentAndLengths() {
        let text = String(repeating: "b", count: AIChatSelectionContextBuilder.maxSelectionContextLength + 100)
        let selection = AIChatSelectionContextBuilder.makeSelection(text: text, url: url)

        let pageContext = AIChatSelectionContextBuilder.makePageContextData(from: selection)

        XCTAssertEqual(pageContext.content, selection.content)
        XCTAssertEqual(pageContext.truncated, selection.truncated)
        XCTAssertEqual(pageContext.fullContentLength, selection.fullContentLength)
        XCTAssertEqual(pageContext.url, selection.url)
        XCTAssertEqual(pageContext.title, selection.title)
    }

    /// Without a `tabId` the frontend reads a selection sent beside the page as a rival "current page"
    /// entry and discards one of the two. The selection's own id is the discriminator.
    func testPageContextDataBorrowsTheSelectionIdAsTabId() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url)

        let pageContext = AIChatSelectionContextBuilder.makePageContextData(from: selection)

        XCTAssertEqual(pageContext.tabId, selection.id)
    }

    func testPageContextDataIsMarkedAttached() {
        let pageContext = AIChatSelectionContextBuilder.makePageContextData(
            from: AIChatSelectionContextBuilder.makeSelection(text: "text", url: url)
        )

        XCTAssertEqual(pageContext.attached, true)
        XCTAssertEqual(pageContext.attachable, true)
    }

    func testPageContextDataKeepsTheFavicon() {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url, faviconBase64: "data:image/png;base64,AAAA")

        let pageContext = AIChatSelectionContextBuilder.makePageContextData(from: selection)

        XCTAssertEqual(pageContext.favicon.first?.href, "data:image/png;base64,AAAA")
    }

    func testDistinctSelectionsProduceDistinctTabIds() {
        let first = AIChatSelectionContextBuilder.makeSelection(text: "one", url: url)
        let second = AIChatSelectionContextBuilder.makeSelection(text: "two", url: url)

        let firstContext = AIChatSelectionContextBuilder.makePageContextData(from: first)
        let secondContext = AIChatSelectionContextBuilder.makePageContextData(from: second)

        XCTAssertNotEqual(firstContext.tabId, secondContext.tabId)
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

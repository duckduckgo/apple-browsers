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

import UserScript
import WebKit
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

    // MARK: - Delivery on the prompt's `selections` key

    /// The key is omitted entirely when nothing is attached.
    func testPromptOmitsSelectionsKeyWhenNoneAttached() throws {
        let prompt = AIChatNativePrompt.queryPrompt("hello", autoSubmit: true)

        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(prompt), encoding: .utf8))

        XCTAssertFalse(json.contains("selections"))
    }

    func testPromptCarriesAttachedSelectionsIntact() throws {
        let text = String(repeating: "b", count: AIChatSelectionContextBuilder.maxSelectionContextLength + 100)
        let selection = AIChatSelectionContextBuilder.makeSelection(text: text, url: url)
        let prompt = AIChatNativePrompt.queryPrompt("hello", autoSubmit: true, selections: [selection])

        let decoded = try JSONDecoder().decode(AIChatNativePrompt.self, from: try JSONEncoder().encode(prompt))

        XCTAssertEqual(decoded.selections, [selection])
        XCTAssertEqual(decoded.selections?.first?.wordCount, selection.wordCount)
        XCTAssertEqual(decoded.selections?.first?.truncated, true)
    }

    /// Selections must not displace page context.
    func testPromptCarriesPageContextAndSelectionsTogether() throws {
        let selection = AIChatSelectionContextBuilder.makeSelection(text: "text", url: url)
        let page = AIChatPageContextData(title: "Page", favicon: [], url: url.absoluteString, content: "body",
                                         truncated: false, fullContentLength: 4, attachable: true, attached: true)
        let prompt = AIChatNativePrompt.queryPrompt("hello", autoSubmit: true,
                                                    pageContext: .single(page), selections: [selection])

        let decoded = try JSONDecoder().decode(AIChatNativePrompt.self, from: try JSONEncoder().encode(prompt))

        XCTAssertEqual(decoded.selections, [selection])
        XCTAssertNotNil(decoded.pageContext)
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

/// Consumption clears the chips and the session's selections, so it has to happen exactly when they
/// reach the frontend — never on a submit that carried none, and never on one that was dropped before
/// it got there, or the user's text is destroyed unsent.
final class AIChatUserScriptSelectionDeliveryTests: XCTestCase {

    private let url = URL(string: "https://example.com/article")!

    /// Weak on the user script, so the fixture has to hold them.
    private var webView: WKWebView!
    private var broker: UserScriptMessageBroker!

    override func setUp() {
        super.setUp()
        webView = WKWebView()
        broker = UserScriptMessageBroker(context: "aiChat")
    }

    override func tearDown() {
        webView = nil
        broker = nil
        super.tearDown()
    }

    /// A script whose bridge can actually dispatch.
    private func makeConnectedUserScript() -> AIChatUserScript {
        let userScript = makeTestUserScript()
        userScript.webView = webView
        userScript.broker = broker
        return userScript
    }

    private func attach(_ userScript: AIChatUserScript, consumed: @escaping () -> Void) {
        userScript.setAttachedSelectionsProvider { [AIChatSelectionContextBuilder.makeSelection(text: "selected", url: self.url)] }
        userScript.setAttachedSelectionsConsumedHandler(consumed)
    }

    func testSubmittingWithAttachedSelectionsConsumesThem() {
        let userScript = makeConnectedUserScript()
        var didConsume = false
        attach(userScript) { didConsume = true }

        userScript.submitPrompt("hello", pageContext: nil, modelId: nil)

        XCTAssertTrue(didConsume)
    }

    func testMultiModalSubmitAlsoConsumesAttachedSelections() {
        let userScript = makeConnectedUserScript()
        var didConsume = false
        attach(userScript) { didConsume = true }

        userScript.submitPrompt("hello", images: nil, files: nil, modelId: nil, tools: nil, reasoningEffort: nil)

        XCTAssertTrue(didConsume)
    }

    func testSubmittingWithNothingAttachedDoesNotConsume() {
        let userScript = makeConnectedUserScript()
        var didConsume = false
        userScript.setAttachedSelectionsProvider { [] }
        userScript.setAttachedSelectionsConsumedHandler { didConsume = true }

        userScript.submitPrompt("hello", pageContext: nil, modelId: nil)

        XCTAssertFalse(didConsume)
    }

    /// Consuming a dropped push would clear the chips for a prompt that was never sent.
    func testSubmittingWithoutABridgeDoesNotConsume() {
        let userScript = makeTestUserScript()
        var didConsume = false
        attach(userScript) { didConsume = true }

        userScript.submitPrompt("hello", pageContext: nil, modelId: nil)

        XCTAssertFalse(didConsume)
    }

    func testMultiModalSubmitWithoutABridgeDoesNotConsume() {
        let userScript = makeTestUserScript()
        var didConsume = false
        attach(userScript) { didConsume = true }

        userScript.submitPrompt("hello", images: nil, files: nil, modelId: nil, tools: nil, reasoningEffort: nil)

        XCTAssertFalse(didConsume)
    }
}

//
//  QuerySubmittedTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import UIKit
import Suggestions
import Bookmarks
import AIChat

@testable import DuckDuckGo

class QuerySubmittedTests: XCTestCase {
    let mock = MockOmniBarDelegate()
    let sut = DefaultOmniBarViewController(
        dependencies: MockOmnibarDependency(
            voiceSearchHelper: MockVoiceSearchHelper(
                isSpeechRecognizerAvailable: true,
                voiceSearchEnabled: true)
        ),
        isFloatingUIEnabled: false
    )

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: termsSuiteName)?.removePersistentDomain(forName: termsSuiteName)
        sut.omniDelegate = mock
    }

    override func tearDown() {
        UserDefaults(suiteName: termsSuiteName)?.removePersistentDomain(forName: termsSuiteName)
        mock.clear()
        super.tearDown()
    }

    func testValidAddressSubmissions() {
        let validQueries = [
            ("www.test.com", "http://www.test.com"),
            ("http://example.com/path?query=123", "http://example.com/path?query=123"),
            (" www.test.com ", "http://www.test.com")
        ]

        for (query, expected) in validQueries {
            assertQuerySubmission(query: query, expected: expected)
        }
    }

    func testInvalidAddressSubmissions() {
        let invalidQueries = [
            "16385-12228.75",
            "invalid-url",
            "http://[::1]:80",
            "12345"
        ]

        for query in invalidQueries {
            assertQuerySubmission(query: query, expected: query)
        }
    }

    func testSuggestionSelectionCallsDelegate() {
        mock.suggestion = .website(url: URL(string: "www.testing.com")!)

        sut.onQuerySubmitted()

        XCTAssertTrue(mock.wasOnOmniSuggestionSelectedCalled)
        XCTAssertFalse(mock.wasOnOmniQuerySubmittedCalled)
    }

    func testEmptyQueryDoesNotCallDelegate() {
        sut.barView.textField.text = ""
        sut.onQuerySubmitted()

        XCTAssertFalse(mock.wasOnOmniQuerySubmittedCalled)
        XCTAssertFalse(mock.wasOnOmniSuggestionSelectedCalled)
    }

    func testBlankQueryDoesNotCallDelegate() {
        sut.barView.textField.text = "   "
        sut.onQuerySubmitted()

        XCTAssertFalse(mock.wasOnOmniQuerySubmittedCalled)
        XCTAssertFalse(mock.wasOnOmniSuggestionSelectedCalled)
    }

    func testWhenSubmittingValidURLInIPadDuckAIModeThenSubmitsAsQuery() {
        sut.loadViewIfNeeded()
        sut.setSelectedTextEntryMode(TextEntryMode.aiChat)

        let textView = UITextView()
        textView.text = "https://example.com/path"

        let shouldChange = sut.textView(textView,
                                        shouldChangeTextIn: NSRange(location: textView.text.count, length: 0),
                                        replacementText: "\n")

        XCTAssertFalse(shouldChange)
        XCTAssertTrue(mock.wasOnOmniQuerySubmittedCalled)
        XCTAssertEqual(mock.query, "https://example.com/path")
        XCTAssertFalse(mock.wasOnPromptSubmittedCalled)
    }

    func testWhenSubmittingTextInIPadDuckAIModeThenSubmitsAsPrompt() {
        sut.loadViewIfNeeded()
        sut.setSelectedTextEntryMode(TextEntryMode.aiChat)

        let textView = UITextView()
        textView.text = "best places to visit in japan"

        let shouldChange = sut.textView(textView,
                                        shouldChangeTextIn: NSRange(location: textView.text.count, length: 0),
                                        replacementText: "\n")

        XCTAssertFalse(shouldChange)
        XCTAssertTrue(mock.wasOnPromptSubmittedCalled)
        XCTAssertEqual(mock.promptQuery, "best places to visit in japan")
        XCTAssertFalse(mock.wasOnOmniQuerySubmittedCalled)
    }

    // MARK: - Clear button visibility (iPad duck.ai expanded panel)

    func testWhenSearchAreaExpandedAndDuckAIFieldEmptyThenClearButtonIsHidden() throws {
        sut.loadViewIfNeeded()
        let expandable = try XCTUnwrap(sut.expandableBarView, "iPad omni bar should expose an expandable bar view")

        // Set the text after expanding: expansion transfers the (empty) search field text into the
        // aiChatTextView, so seeding it beforehand would be overwritten.
        expandable.setSearchAreaExpanded(true, animated: false)
        expandable.aiChatTextView.text = ""
        XCTAssertTrue(expandable.isSearchAreaExpanded, "Precondition: the duck.ai panel must be expanded")

        // A text-editing state reports showClear == true; before the fix the clear button followed
        // the state machine and lingered over the empty duck.ai field (the reported bug).
        let textEditingState = LargeOmniBarState.BrowsingTextEditingState(dependencies: MockOmnibarDependency(), isLoading: false)
        XCTAssertTrue(textEditingState.showClear)
        XCTAssertTrue(sut.shouldHideClearButton(for: textEditingState))
    }

    func testWhenSearchAreaExpandedAndDuckAIFieldHasTextThenClearButtonIsVisible() throws {
        sut.loadViewIfNeeded()
        let expandable = try XCTUnwrap(sut.expandableBarView)

        // Set the text after expanding: expansion transfers the (empty) search field text into the
        // aiChatTextView, so seeding it beforehand would be overwritten.
        expandable.setSearchAreaExpanded(true, animated: false)
        expandable.aiChatTextView.text = "best places to visit in japan"
        XCTAssertTrue(expandable.isSearchAreaExpanded, "Precondition: the duck.ai panel must be expanded")

        let textEditingState = LargeOmniBarState.BrowsingTextEditingState(dependencies: MockOmnibarDependency(), isLoading: false)
        XCTAssertFalse(sut.shouldHideClearButton(for: textEditingState))
    }

    func testWhenSearchAreaNotExpandedThenClearButtonFollowsStateShowClear() throws {
        sut.loadViewIfNeeded()
        let expandable = try XCTUnwrap(sut.expandableBarView)

        // Not expanded: the search text field governs, so the state machine's showClear is
        // authoritative regardless of the (unused) aiChatTextView content.
        expandable.aiChatTextView.text = "stale text"
        expandable.setSearchAreaExpanded(false, animated: false)

        let dependencies = MockOmnibarDependency()
        XCTAssertFalse(sut.shouldHideClearButton(for: LargeOmniBarState.BrowsingTextEditingState(dependencies: dependencies, isLoading: false)))
        XCTAssertTrue(sut.shouldHideClearButton(for: LargeOmniBarState.BrowsingEmptyEditingState(dependencies: dependencies, isLoading: false)))
    }

    // MARK: - Layout (iPad duck.ai expanded panel)

    func testWhenIPadDuckAIPanelIsExpandedThenTheTextStopsAboveTheButtonRow() throws {
        let omniBarView = try expandDuckAIPanel(of: sut)
        omniBarView.layoutIfNeeded()

        let textFrame = omniBarView.aiChatTextView.convert(omniBarView.aiChatTextView.bounds, to: omniBarView)
        let sendFrame = omniBarView.aiChatSendButton.convert(omniBarView.aiChatSendButton.bounds, to: omniBarView)
        XCTAssertGreaterThan(textFrame.height, 0)
        XCTAssertLessThanOrEqual(textFrame.maxY, sendFrame.minY)
    }

    // MARK: - Terms of Service disclaimer (iPad duck.ai expanded panel)

    func testWhenTheTermsDisclaimerIsShownInIPadDuckAIModeThenReturnAddsANewLine() throws {
        let sut = makeSUTShowingTermsOfService()
        let omniBarView = try expandDuckAIPanel(of: sut)
        omniBarView.aiChatTextView.text = "best places to visit in japan"

        let shouldChange = sut.textView(omniBarView.aiChatTextView,
                                        shouldChangeTextIn: NSRange(location: omniBarView.aiChatTextView.text.count, length: 0),
                                        replacementText: "\n")

        XCTAssertTrue(shouldChange)
        XCTAssertFalse(mock.wasOnPromptSubmittedCalled)
        XCTAssertEqual(omniBarView.aiChatTextView.keyboardType, .default, "The web-search keyboard would draw Return as Go")
    }

    func testWhenTheTermsDisclaimerIsShownInIPadDuckAIModeThenSendReadsAsk() throws {
        let sut = makeSUTShowingTermsOfService()
        let omniBarView = try expandDuckAIPanel(of: sut)

        // Typing refreshes the button this way; `textViewDidChange` itself would collapse the panel
        // here, since a windowless text view can't hold focus.
        omniBarView.aiChatTextView.text = "best places to visit in japan"
        omniBarView.updateAIChatSendButton(hasText: true)
        omniBarView.layoutIfNeeded()

        let sendButton = omniBarView.aiChatSendButton
        XCTAssertEqual(sendButton.title(for: .normal), UserText.duckAIAskButtonTitle)
        XCTAssertNil(sendButton.image(for: .normal))
        XCTAssertEqual(sendButton.accessibilityLabel, UserText.duckAIAskButtonTitle)
        let titleWidth = try XCTUnwrap(sendButton.titleLabel).intrinsicContentSize.width
        XCTAssertGreaterThan(sendButton.bounds.width, titleWidth)
    }

    func testWhenTheTermsDisclaimerNamesCreateInIPadDuckAIModeThenSendReadsCreate() throws {
        let sut = makeSUTShowingTermsOfService()
        let omniBarView = try expandDuckAIPanel(of: sut)

        omniBarView.termsOfServiceSendButton = .create
        omniBarView.updateAIChatSendButton(hasText: true)

        XCTAssertEqual(omniBarView.aiChatSendButton.title(for: .normal), UserText.duckAICreateButtonTitle)
        XCTAssertEqual(omniBarView.aiChatSendButton.accessibilityLabel, UserText.duckAICreateButtonTitle)
        XCTAssertEqual(omniBarView.aiChatTextView.keyboardType, .default, "Return still adds a new line")
    }

    func testWhenTheTermsDisclaimerIsShownInIPadDuckAIModeThenAnEmptyPromptKeepsTheVoiceButton() throws {
        let sut = makeSUTShowingTermsOfService()
        let omniBarView = try expandDuckAIPanel(of: sut)

        XCTAssertNil(omniBarView.aiChatSendButton.title(for: .normal))
        XCTAssertNotNil(omniBarView.aiChatSendButton.image(for: .normal))
    }

    func testWhenTermsAreAlreadyAcceptedThenIPadDuckAIReturnSubmitsAndSendKeepsItsArrow() throws {
        termsStore.recordWebReport()
        let sut = makeSUTShowingTermsOfService()
        let omniBarView = try expandDuckAIPanel(of: sut)
        omniBarView.aiChatTextView.text = "best places to visit in japan"
        omniBarView.updateAIChatSendButton(hasText: true)

        XCTAssertNil(omniBarView.aiChatSendButton.title(for: .normal))

        let shouldChange = sut.textView(omniBarView.aiChatTextView,
                                        shouldChangeTextIn: NSRange(location: omniBarView.aiChatTextView.text.count, length: 0),
                                        replacementText: "\n")

        XCTAssertFalse(shouldChange)
        XCTAssertTrue(mock.wasOnPromptSubmittedCalled)
        XCTAssertEqual(omniBarView.aiChatTextView.keyboardType, .webSearch)
    }

    // MARK: - Helper Methods

    private var termsSuiteName: String { String(describing: type(of: self)) + ".terms" }

    private var termsStore: DuckAiTermsOfServiceStore {
        DuckAiTermsOfServiceStore(keyValueStore: UserDefaults(suiteName: termsSuiteName)!)
    }

    private func makeSUTShowingTermsOfService() -> DefaultOmniBarViewController {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.duckAINativeTermsOfService])
        let sut = DefaultOmniBarViewController(dependencies: MockOmnibarDependency(featureFlagger: featureFlagger),
                                               isFloatingUIEnabled: false,
                                               termsOfServiceStore: termsStore)
        sut.omniDelegate = mock
        return sut
    }

    private func expandDuckAIPanel(of sut: DefaultOmniBarViewController) throws -> DefaultOmniBarView {
        sut.loadViewIfNeeded()
        sut.setSelectedTextEntryMode(TextEntryMode.aiChat)
        let omniBarView = try XCTUnwrap(sut.barView as? DefaultOmniBarView)
        omniBarView.frame = CGRect(x: 0, y: 0, width: 1024, height: DefaultOmniBarView.expectedHeight)
        omniBarView.setSearchAreaExpanded(true, animated: false)
        return omniBarView
    }

    private func assertQuerySubmission(query: String, expected: String) {
        sut.barView.textField.text = query
        sut.onQuerySubmitted()

        XCTAssertEqual(mock.query, expected)
        XCTAssertFalse(mock.wasOnOmniSuggestionSelectedCalled)
    }
}

final class MockOmniBarDelegate: OmniBarDelegate {

    var query: String = ""
    var promptQuery: String = ""
    var suggestion: Suggestion?
    var wasOnOmniQuerySubmittedCalled = false
    var wasOnPromptSubmittedCalled = false
    var wasOnOmniSuggestionSelectedCalled = false

    func onOmniQuerySubmitted(_ query: String) {
        wasOnOmniQuerySubmittedCalled = true
        self.query = query
    }

    func onOmniSuggestionSelected(_ suggestion: Suggestion) {
        wasOnOmniSuggestionSelectedCalled = true
    }

    func clear() {
        query = ""
        promptQuery = ""
        suggestion = nil
        wasOnOmniQuerySubmittedCalled = false
        wasOnPromptSubmittedCalled = false
        wasOnOmniSuggestionSelectedCalled = false
    }

    func selectedSuggestion() -> Suggestion? {
        return suggestion
    }

    func isSuggestionTrayVisible() -> Bool {
        false
    }

    // MARK: - Unused methods
    func onSelectFavorite(_ favorite: BookmarkEntity) {

    }

    func didRequestCurrentURL() -> URL? {
        return nil
    }

    func onPromptSubmitted(_ query: String, tools: [AIChatRAGTool]?) {
        wasOnPromptSubmittedCalled = true
        promptQuery = query
    }

    func onAbortPressed() {
    }

    func onEditingEnd() -> OmniBarEditingEndResult {
        return .dismissed
    }

    func onClearTextPressed() {
    }

    func onEnterPressed() {
    }

    func onVoiceSearchPressed() {
    }

    func onTextFieldWillBeginEditing(_ omniBar: DuckDuckGo.OmniBarView, tapped: Bool) {
    }

    func onTextFieldDidBeginEditing(_ omniBar: DuckDuckGo.OmniBarView) -> Bool {
        return false
    }
    
    func onBackPressed() {
    }

    func onForwardPressed() {
    }

    func onDidBeginEditing() { }

    func onDidEndEditing() { }

    func onCustomizableButtonPressed() { }

    func onEditFavorite(_ favorite: Bookmarks.BookmarkEntity) {}

    func isCurrentTabFireTab() -> Bool { false }

}

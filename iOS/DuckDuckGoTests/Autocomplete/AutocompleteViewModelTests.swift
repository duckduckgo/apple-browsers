//
//  AutocompleteViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Suggestions

final class AutocompleteViewModelTests: XCTestCase {

    private func makeViewModel(showMessage: Bool = true, showAskAIChat: Bool = false) -> (AutocompleteViewModel, MockAutocompleteViewModelDelegate) {
        let vm = AutocompleteViewModel(isAddressBarAtBottom: false, showMessage: showMessage, showAskAIChat: showAskAIChat)
        let delegate = MockAutocompleteViewModelDelegate()
        vm.delegate = delegate
        return (vm, delegate)
    }

    func testNextSelection_WhenNoSelection_SetsFirstFromAll() {
        let (vm, _) = makeViewModel()
        let first = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "first"))
        let second = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "second"))
        let third = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "third"))

        vm.topHits = [first]
        vm.ddgSuggestions = [second]
        vm.localResults = [third]

        vm.nextSelection()

        XCTAssertEqual(vm.selection, first)
    }

    func testNextSelection_Advances() {
        let (vm, _) = makeViewModel()
        let first = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "first"))
        let second = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "second"))
        vm.topHits = [first]
        vm.ddgSuggestions = [second]

        vm.selection = first
        vm.nextSelection()

        XCTAssertEqual(vm.selection, second)
    }

    func testPreviousSelection_GoesBack() {
        let (vm, _) = makeViewModel()
        let first = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "first"))
        let second = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "second"))
        vm.topHits = [first]
        vm.ddgSuggestions = [second]

        vm.selection = second
        vm.previousSelection()

        XCTAssertEqual(vm.selection, first)
    }

    func testSelectionDidSet_NotifiesDelegateWithQuery() {
        let (vm, delegate) = makeViewModel()
        vm.query = "duck"
        let model = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "s"))

        vm.selection = model

        XCTAssertNotNil(delegate.highlighted)
        XCTAssertEqual(delegate.highlighted?.query, "duck")
    }

    func testOnSuggestionSelected_NotifiesDelegate() {
        let (vm, delegate) = makeViewModel()
        let model = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "pick"))

        vm.onSuggestionSelected(model)

        XCTAssertEqual(delegate.selected.count, 1)
    }

    func testOnTapAhead_NotifiesDelegate() {
        let (vm, delegate) = makeViewModel()
        let model = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "ahead"))

        vm.onTapAhead(model)

        XCTAssertEqual(delegate.tapAhead, model.suggestion)
    }

    func testOnDismissMessage_HidesAndNotifiesDelegate() {
        let (vm, delegate) = makeViewModel(showMessage: true)

        vm.onDismissMessage()

        XCTAssertFalse(vm.isMessageVisible)
        XCTAssertEqual(delegate.dismissedCount, 1)
    }

    func testOnShownToUser_NotifiesDelegate() {
        let (vm, delegate) = makeViewModel()
        vm.onShownToUser()
        XCTAssertEqual(delegate.shownCount, 1)
    }

    func testDeleteSuggestion_NotifiesDelegate() {
        let (vm, delegate) = makeViewModel()
        let model = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "delete"))

        vm.deleteSuggestion(model)

        XCTAssertEqual(delegate.deleted, model.suggestion)
    }

    func testUpdateSuggestions_PopulatesArrays() {
        let (vm, _) = makeViewModel()
        let result = SuggestionResult(
            topHits: [.phrase(phrase: "one")],
            duckduckgoSuggestions: [.phrase(phrase: "two")],
            localSuggestions: [.phrase(phrase: "three")]
        )

        vm.updateSuggestions(result)

        XCTAssertEqual(vm.topHits.count, 1)
        XCTAssertEqual(vm.ddgSuggestions.count, 1)
        XCTAssertEqual(vm.localResults.count, 1)
        XCTAssertTrue(vm.aiChatSuggestions.isEmpty)
    }

    func testUpdateSuggestions_WhenAllEmpty_InsertsQueryAsTopHitWithoutTapAhead() {
        let (vm, _) = makeViewModel()
        vm.query = "duck"
        let result = SuggestionResult(topHits: [], duckduckgoSuggestions: [], localSuggestions: [])

        vm.updateSuggestions(result)

        XCTAssertEqual(vm.topHits.count, 1)
        XCTAssertFalse(vm.topHits[0].canShowTapAhead)
        if case .phrase(let phrase) = vm.topHits[0].suggestion {
            XCTAssertEqual(phrase, "duck")
        } else {
            XCTFail("Expected phrase suggestion")
        }
    }

    func testUpdateSuggestions_WhenShowAskAIChatTrue_AddsSupplementarySuggestion() {
        let (vm, _) = makeViewModel(showMessage: true, showAskAIChat: true)
        vm.query = "ask this"
        let result = SuggestionResult(topHits: [], duckduckgoSuggestions: [], localSuggestions: [])

        vm.updateSuggestions(result)

        XCTAssertEqual(vm.aiChatSuggestions.count, 1)
        if case .askAIChat(let value) = vm.aiChatSuggestions[0].suggestion {
            XCTAssertEqual(value, "ask this")
        } else {
            XCTFail("Expected askAIChat suggestion")
        }
    }

    func testNextSelection_IncludesAiChatSuggestions() {
        let (vm, _) = makeViewModel(showMessage: true, showAskAIChat: true)
        vm.query = "test query"
        let first = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "first"))
        let aiChat = AutocompleteViewModel.SuggestionModel(suggestion: .askAIChat(value: "test query"))
        
        vm.topHits = [first]
        vm.aiChatSuggestions = [aiChat]
        
        vm.selection = first
        vm.nextSelection()
        
        XCTAssertEqual(vm.selection, aiChat)
    }

    func testPreviousSelection_IncludesAiChatSuggestions() {
        let (vm, _) = makeViewModel(showMessage: true, showAskAIChat: true)
        vm.query = "test query"
        let first = AutocompleteViewModel.SuggestionModel(suggestion: .phrase(phrase: "first"))
        let aiChat = AutocompleteViewModel.SuggestionModel(suggestion: .askAIChat(value: "test query"))
        
        vm.topHits = [first]
        vm.aiChatSuggestions = [aiChat]
        
        vm.selection = aiChat
        vm.previousSelection()
        
        XCTAssertEqual(vm.selection, first)
    }

    func testNextSelection_WhenNoSelection_SelectsFirstFromAllIncludingAiChat() {
        let (vm, _) = makeViewModel(showMessage: true, showAskAIChat: true)
        vm.query = "test query"
        let aiChat = AutocompleteViewModel.SuggestionModel(suggestion: .askAIChat(value: "test query"))
        vm.aiChatSuggestions = [aiChat]
        
        vm.nextSelection()
        
        XCTAssertEqual(vm.selection, aiChat)
    }
}

private final class MockAutocompleteViewModelDelegate: NSObject, AutocompleteViewModelDelegate {

    var selected: [Suggestion] = []
    var highlighted: (suggestion: Suggestion, query: String)?
    var tapAhead: Suggestion?
    var dismissedCount: Int = 0
    var shownCount: Int = 0
    var deleted: Suggestion?

    func onSuggestionSelected(_ suggestion: Suggestion) {
        selected.append(suggestion)
    }

    func onSuggestionHighlighted(_ suggestion: Suggestion, forQuery query: String) {
        highlighted = (suggestion, query)
    }

    func onTapAhead(_ suggestion: Suggestion) {
        tapAhead = suggestion
    }

    func onMessageDismissed() {
        dismissedCount += 1
    }

    func onMessageShown() {
        shownCount += 1
    }

    func deleteSuggestion(_ suggestion: Suggestion) {
        deleted = suggestion
    }
}

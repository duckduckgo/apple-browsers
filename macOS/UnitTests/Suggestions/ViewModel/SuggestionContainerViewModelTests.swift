//
//  SuggestionContainerViewModelTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Combine
import PrivacyConfig
import SharedTestUtilities
import Suggestions
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class SuggestionContainerViewModelTests: XCTestCase {

    var suggestionLoadingMock: SuggestionLoadingMock!
    var historyProviderMock: HistoryProviderMock!
    var bookmarkProviderMock: SuggestionsBookmarkProvider!
    var searchPreferencesPersistorMock: MockSearchPreferencesPersistor!
    var suggestionContainer: SuggestionContainer!
    var suggestionContainerViewModel: SuggestionContainerViewModel!
    var featureFlagger: MockFeatureFlagger!

    var cancellables = Set<AnyCancellable>()

    @MainActor
    override func setUp() {
        searchPreferencesPersistorMock = MockSearchPreferencesPersistor()
        searchPreferencesPersistorMock.showAutocompleteSuggestions = true
        suggestionLoadingMock = SuggestionLoadingMock()
        historyProviderMock = HistoryProviderMock()
        bookmarkProviderMock = SuggestionsBookmarkProvider(bookmarkManager: MockBookmarkManager())
        featureFlagger = MockFeatureFlagger()
        suggestionContainer = SuggestionContainer(openTabsProvider: { [] },
                                                  suggestionLoading: suggestionLoadingMock,
                                                  historyProvider: historyProviderMock,
                                                  bookmarkProvider: bookmarkProviderMock,
                                                  featureFlagger: featureFlagger,
                                                  burnerMode: .regular,
                                                  isUrlIgnored: { _ in false })
        suggestionContainerViewModel = SuggestionContainerViewModel(
            suggestionContainer: suggestionContainer,
            searchPreferences: SearchPreferences(
                persistor: searchPreferencesPersistorMock,
                windowControllersManager: WindowControllersManagerMock()
            )
        )
    }

    override func tearDown() {
        suggestionLoadingMock = nil
        historyProviderMock = nil
        suggestionContainer = nil
        suggestionContainerViewModel = nil
        searchPreferencesPersistorMock = nil
        featureFlagger = nil
        cancellables.removeAll()
    }

    private func waitForMainQueueToFlush(for timeout: TimeInterval) {
        let e = expectation(description: "Main Queue flushed")
        DispatchQueue.main.async {
            e.fulfill()
        }
        wait(for: [e], timeout: timeout)
    }

    // MARK: - Tests

    @MainActor
    func testWhenSelectionIndexIsNilThenSelectedSuggestionViewModelIsNil() {
        let suggestionContainer = SuggestionContainer(
            historyProvider: HistoryProviderMock(),
            bookmarkProvider: SuggestionsBookmarkProvider(bookmarkManager: MockBookmarkManager()),
            featureFlagger: featureFlagger,
            burnerMode: .regular,
            isUrlIgnored: { _ in false }
        )
        let suggestionContainerViewModel = SuggestionContainerViewModel(
            suggestionContainer: suggestionContainer,
            searchPreferences: SearchPreferences(
                persistor: searchPreferencesPersistorMock,
                windowControllersManager: WindowControllersManagerMock()
            )
        )

        XCTAssertNil(suggestionContainerViewModel.selectionIndex)
        XCTAssertNil(suggestionContainerViewModel.selectedSuggestionViewModel)
    }

    @MainActor
    func testWhenSuggestionIsSelectedThenSelectedSuggestionViewModelMatchesSuggestion() {
        suggestionContainer.getSuggestions(for: "Test")
        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil )

        let index = 0

        let selectedSuggestionViewModelExpectation = expectation(description: "Selected suggestion view model expectation")
        suggestionContainerViewModel.$selectedSuggestionViewModel
            .dropFirst()
            .sink { [unowned self] selectedSuggestionViewModel in
                XCTAssertNotNil(selectedSuggestionViewModel)
                XCTAssertEqual(suggestionContainerViewModel.suggestionContainer.result?.all[index], selectedSuggestionViewModel?.suggestion)
                selectedSuggestionViewModelExpectation.fulfill()
            }
            .store(in: &cancellables)

        suggestionContainerViewModel.select(at: index)
        waitForExpectations(timeout: 0, handler: nil)
    }

    @MainActor
    func testWhenSelectCalledWithIndexOutOfBoundsThenSelectedSuggestionViewModelIsNil() {
        let suggestionContainer = SuggestionContainer(
            historyProvider: HistoryProviderMock(),
            bookmarkProvider: SuggestionsBookmarkProvider(bookmarkManager: MockBookmarkManager()),
            featureFlagger: featureFlagger,
            burnerMode: .regular,
            isUrlIgnored: { _ in false }
        )
        let suggestionListViewModel = SuggestionContainerViewModel(
            suggestionContainer: suggestionContainer,
            searchPreferences: SearchPreferences(persistor: MockSearchPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock())
        )

        suggestionListViewModel.select(at: 0)

        let selectedSuggestionViewModelExpectation = expectation(description: "Selected suggestion view model expectation")

        suggestionListViewModel.$selectedSuggestionViewModel
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .sink { selectedSuggestionViewModel in
                XCTAssertNil(suggestionListViewModel.selectionIndex)
                XCTAssertNil(selectedSuggestionViewModel)
                selectedSuggestionViewModelExpectation.fulfill()
            }
            .store(in: &cancellables)
        waitForExpectations(timeout: 1, handler: nil)
    }

    @MainActor
    func testWhenClearSelectionIsCalledThenNoSuggestonIsSeleted() {
        suggestionContainer.getSuggestions(for: "Test")
        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil )

        suggestionContainerViewModel.select(at: 0)

        suggestionContainerViewModel.clearSelection()

        let selectedSuggestionViewModelExpectation2 = expectation(description: "Selected suggestion view model expectation")

        suggestionContainerViewModel.$selectedSuggestionViewModel
            .debounce(for: 0.1, scheduler: RunLoop.main)
            .sink { [unowned self] _ in
                XCTAssertNil(suggestionContainerViewModel.selectionIndex)
                XCTAssertNil(suggestionContainerViewModel.selectedSuggestionViewModel)
                selectedSuggestionViewModelExpectation2.fulfill()
            }
            .store(in: &cancellables)
        waitForExpectations(timeout: 1, handler: nil)
    }

    @MainActor
    func testSelectNextIfPossible() {
        suggestionContainer.getSuggestions(for: "Test")
        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil )

        suggestionContainerViewModel.selectNextIfPossible()
        XCTAssertEqual(suggestionContainerViewModel.selectionIndex, 0)

        suggestionContainerViewModel.selectNextIfPossible()
        XCTAssertEqual(suggestionContainerViewModel.selectionIndex, 1)

        let lastIndex = suggestionContainerViewModel.numberOfSuggestions - 1
        suggestionContainerViewModel.select(at: lastIndex)
        XCTAssertEqual(suggestionContainerViewModel.selectionIndex, lastIndex)

        suggestionContainerViewModel.selectNextIfPossible()
        XCTAssertNil(suggestionContainerViewModel.selectionIndex)
    }

    @MainActor
    func testSelectPreviousIfPossible() {
        suggestionContainer.getSuggestions(for: "Test")
        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil )

        suggestionContainerViewModel.selectPreviousIfPossible()
        XCTAssertEqual(suggestionContainerViewModel.selectionIndex, suggestionContainerViewModel.numberOfSuggestions - 1)

        suggestionContainerViewModel.selectPreviousIfPossible()
        XCTAssertEqual(suggestionContainerViewModel.selectionIndex, suggestionContainerViewModel.numberOfSuggestions - 2)

        let firstIndex = 0
        suggestionContainerViewModel.select(at: firstIndex)
        XCTAssertEqual(suggestionContainerViewModel.selectionIndex, firstIndex)

        suggestionContainerViewModel.selectPreviousIfPossible()
        XCTAssertNil(suggestionContainerViewModel.selectionIndex)
    }

    @MainActor
    func testWhenUserAppendsText_suggestionsLoadingInitiatedAndTopHitIsSelected() {
        XCTAssertFalse(suggestionLoadingMock.getSuggestionsCalled)
        suggestionContainerViewModel.setUserStringValue("duck", userAppendedStringToTheEnd: true)
        XCTAssertTrue(suggestionLoadingMock.getSuggestionsCalled)

        let selectedSuggestionViewModelExpectation = expectation(description: "Selected suggestion view model")
        suggestionContainerViewModel.$selectedSuggestionViewModel
            .dropFirst()
            .sink { selectedSuggestionViewModel in
                XCTAssertNotNil(selectedSuggestionViewModel)
                XCTAssertEqual(selectedSuggestionViewModel?.suggestion, SuggestionResult.aSuggestionResult.topHits.first)
                selectedSuggestionViewModelExpectation.fulfill()
            }
            .store(in: &cancellables)

        XCTAssertNotNil(suggestionLoadingMock.completion)
        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil)

        wait(for: [selectedSuggestionViewModelExpectation], timeout: 0)
    }

    @MainActor
    func testWhenUserAppendsSpace_suggestionsLoadingInitiatedWithoutTopSuggestionSelection() {
        suggestionContainerViewModel.setUserStringValue("duck ", userAppendedStringToTheEnd: true)
        XCTAssertTrue(suggestionLoadingMock.getSuggestionsCalled)

        suggestionContainerViewModel.$selectedSuggestionViewModel
            .dropFirst()
            .sink { _ in
                XCTFail("Unexpected suggestion view model selection")
            }
            .store(in: &cancellables)

        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil)

        waitForMainQueueToFlush(for: 1)
    }

    @MainActor
    func testWhenUserInsertsTextInTheMiddle_suggestionsLoadingInitiatedWithoutTopSuggestionSelection() {
        suggestionContainerViewModel.setUserStringValue("duck", userAppendedStringToTheEnd: false)
        XCTAssertTrue(suggestionLoadingMock.getSuggestionsCalled)

        suggestionContainerViewModel.$selectedSuggestionViewModel
            .dropFirst()
            .sink { _ in
                XCTFail("Unexpected suggestion view model selection")
            }
            .store(in: &cancellables)

        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil)

        waitForMainQueueToFlush(for: 1)
    }

    @MainActor
    func testWhenNoTopHitsLoaded_topSuggestionIsNotSelected() {
        suggestionContainerViewModel.setUserStringValue("duck", userAppendedStringToTheEnd: true)
        XCTAssertTrue(suggestionLoadingMock.getSuggestionsCalled)

        suggestionContainerViewModel.$selectedSuggestionViewModel
            .dropFirst()
            .sink { _ in
                XCTFail("Unexpected suggestion view model selection")
            }
            .store(in: &cancellables)

        suggestionLoadingMock.completion?(SuggestionResult.noTopHitsResult, nil)

        waitForMainQueueToFlush(for: 1)
    }

    @MainActor
    func testWhenSuggestionsLoadedAfterUserModifiesText_oldSuggestionsAreNotSelected() {
        suggestionContainerViewModel.setUserStringValue("duc", userAppendedStringToTheEnd: true)
        XCTAssertTrue(suggestionLoadingMock.getSuggestionsCalled)
        suggestionLoadingMock.getSuggestionsCalled = false

        suggestionContainerViewModel.setUserStringValue("duce", userAppendedStringToTheEnd: true)
        XCTAssertTrue(suggestionLoadingMock.getSuggestionsCalled)

        suggestionContainerViewModel.$selectedSuggestionViewModel
            .dropFirst()
            .sink { _ in
                XCTFail("Unexpected suggestion view model selection")
            }
            .store(in: &cancellables)

        suggestionLoadingMock.completion?(SuggestionResult.noTopHitsResult, nil)

        waitForMainQueueToFlush(for: 1)
    }

    @MainActor
    func testWhenOldSuggestionsLoadedAfterUserContinuesTypingText_topHitSuggestionsIsSelectedWithCorrectUserEnteredText() {
        suggestionContainerViewModel.setUserStringValue("duc", userAppendedStringToTheEnd: true)
        XCTAssertTrue(suggestionLoadingMock.getSuggestionsCalled)
        suggestionLoadingMock.getSuggestionsCalled = false

        suggestionContainerViewModel.setUserStringValue("duck", userAppendedStringToTheEnd: true)
        XCTAssertTrue(suggestionLoadingMock.getSuggestionsCalled)

        let selectedSuggestionViewModelExpectation = expectation(description: "Selected suggestion view model")
        suggestionContainerViewModel.$selectedSuggestionViewModel
            .dropFirst()
            .sink { selectedSuggestionViewModel in
                XCTAssertNotNil(selectedSuggestionViewModel)
                XCTAssertEqual(selectedSuggestionViewModel?.suggestion, SuggestionResult.aSuggestionResult.topHits.first)
                XCTAssertEqual(selectedSuggestionViewModel?.userStringValue, "duck")
                selectedSuggestionViewModelExpectation.fulfill()
            }
            .store(in: &cancellables)

        XCTAssertNotNil(suggestionLoadingMock.completion)
        suggestionLoadingMock.completion?(SuggestionResult.aSuggestionResult, nil)

        wait(for: [selectedSuggestionViewModelExpectation], timeout: 0)
    }

    @MainActor
    func testWhenUserClearsText_suggestionsLoadingIsCancelled() {
        suggestionContainerViewModel.setUserStringValue("duck", userAppendedStringToTheEnd: true)
        XCTAssertTrue(suggestionLoadingMock.getSuggestionsCalled)
        suggestionLoadingMock.getSuggestionsCalled = false

        suggestionContainerViewModel.setUserStringValue("", userAppendedStringToTheEnd: true)
        XCTAssertFalse(suggestionLoadingMock.getSuggestionsCalled)

        suggestionContainerViewModel.$selectedSuggestionViewModel
            .dropFirst()
            .sink { _ in
                XCTFail("Unexpected suggestion view model selection")
            }
            .store(in: &cancellables)

        suggestionLoadingMock.completion?(SuggestionResult.noTopHitsResult, nil)

        waitForMainQueueToFlush(for: 1)
    }

    @MainActor
    func testWhenSuggestionLoadingDataSourceOpenTabsRequested_ThenOpenTabsProviderIsCalled() {
        // Setup open tabs with matching URLs and titles
        let openTabs = [
            OpenTab(tabId: "1", title: "DuckDuckGo", url: URL(string: "http://duckduckgo.com")!),
            OpenTab(tabId: "2", title: "Duck Tales", url: URL(string: "http://ducktales.com")!),
        ]

        // Mock the open tabs provider to return the defined open tabs
        suggestionContainer = SuggestionContainer(openTabsProvider: { openTabs },
                                                  suggestionLoading: suggestionLoadingMock,
                                                  historyProvider: historyProviderMock,
                                                  bookmarkProvider: bookmarkProviderMock,
                                                  featureFlagger: featureFlagger,
                                                  burnerMode: .regular,
                                                  isUrlIgnored: { _ in false })
        suggestionContainerViewModel = SuggestionContainerViewModel(
            suggestionContainer: suggestionContainer,
            searchPreferences: SearchPreferences(persistor: MockSearchPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock())
        )

        suggestionContainer.getSuggestions(for: "Duck")

        let openTabsResult = suggestionLoadingMock.dataSource!.openTabs(for: suggestionLoadingMock) as! [OpenTab]
        XCTAssertEqual(openTabsResult, openTabs)
    }

    // MARK: - AI Chat Footer Cell Tests

    @MainActor
    func testWhenAIFeaturesEnabled_ThenAIChatCellAppearsInFooter() {
        // Cluster removed: the AI chat cell only ever appears in the footer, never at the top
        let aiChatStorage = MockAIChatPreferencesStorage()
        aiChatStorage.isAIFeaturesEnabled = true

        suggestionContainerViewModel = SuggestionContainerViewModel(
            isHomePage: false,
            isBurner: false,
            suggestionContainer: suggestionContainer,
            searchPreferences: SearchPreferences(
                persistor: searchPreferencesPersistorMock,
                windowControllersManager: WindowControllersManagerMock()
            ),
            themeManager: MockThemeManager(),
            featureFlagger: featureFlagger,
            aiChatPreferencesStorage: aiChatStorage
        )

        suggestionContainerViewModel.setUserStringValue("test query", userAppendedStringToTheEnd: false)
        suggestionLoadingMock.completion?(SuggestionResult.noTopHitsResult, nil)

        // AI chat cell should appear at the bottom (footer), not at the top
        XCTAssertNotEqual(suggestionContainerViewModel.rowContent(at: 0), .aiChatCell, "AI chat cell should not appear at top")
        let lastRowIndex = suggestionContainerViewModel.numberOfRows - 1
        XCTAssertEqual(suggestionContainerViewModel.rowContent(at: lastRowIndex), .aiChatCell, "AI chat cell should appear in footer")
    }

    @MainActor
    func testWhenAIFeaturesDisabled_ThenListShowsOnlySuggestions() {
        // Setup with AI features disabled
        let aiChatStorage = MockAIChatPreferencesStorage()
        aiChatStorage.isAIFeaturesEnabled = false

        suggestionContainerViewModel = SuggestionContainerViewModel(
            isHomePage: false,
            isBurner: false,
            suggestionContainer: suggestionContainer,
            searchPreferences: SearchPreferences(
                persistor: searchPreferencesPersistorMock,
                windowControllersManager: WindowControllersManagerMock()
            ),
            themeManager: MockThemeManager(),
            featureFlagger: featureFlagger,
            aiChatPreferencesStorage: aiChatStorage
        )

        suggestionContainerViewModel.setUserStringValue("test query", userAppendedStringToTheEnd: false)
        suggestionLoadingMock.completion?(SuggestionResult.noTopHitsResult, nil)

        // No AI chat cell should appear when AI features are disabled
        XCTAssertEqual(suggestionContainerViewModel.numberOfFooterRows, 0, "Footer should have no rows when AI features disabled")

        // First row should be a suggestion
        XCTAssertEqual(suggestionContainerViewModel.rowContent(at: 0), .suggestion(index: 0))
    }

    @MainActor
    func testWhenAIFeaturesDisabledAfterInit_ThenAIChatCellFooterIsHidden() {
        // AI features enabled: AI chat always appears in the footer
        let aiChatStorage = MockAIChatPreferencesStorage()
        aiChatStorage.isAIFeaturesEnabled = true

        suggestionContainerViewModel = SuggestionContainerViewModel(
            isHomePage: false,
            isBurner: false,
            suggestionContainer: suggestionContainer,
            searchPreferences: SearchPreferences(
                persistor: searchPreferencesPersistorMock,
                windowControllersManager: WindowControllersManagerMock()
            ),
            themeManager: MockThemeManager(),
            featureFlagger: featureFlagger,
            aiChatPreferencesStorage: aiChatStorage
        )

        suggestionContainerViewModel.setUserStringValue("test query", userAppendedStringToTheEnd: false)
        suggestionLoadingMock.completion?(SuggestionResult.noTopHitsResult, nil)

        // AI chat cell should initially appear in the footer
        let lastRowIndex = suggestionContainerViewModel.numberOfRows - 1
        XCTAssertEqual(suggestionContainerViewModel.rowContent(at: lastRowIndex), .aiChatCell, "AI chat cell should appear in footer")

        // Disable AI features after init
        aiChatStorage.isAIFeaturesEnabled = false

        // Footer should no longer contain AI chat cell
        XCTAssertEqual(suggestionContainerViewModel.numberOfFooterRows, 0, "Footer should have no rows when AI features disabled")
    }

}

extension SuggestionContainerViewModel {

    convenience init(suggestionContainer: SuggestionContainer, searchPreferences: SearchPreferences) {
        self.init(isHomePage: false, isBurner: false, suggestionContainer: suggestionContainer, searchPreferences: searchPreferences, themeManager: MockThemeManager(), featureFlagger: MockFeatureFlagger())
    }

}

extension SuggestionResult {

    static var aSuggestionResult: SuggestionResult {
        let topHits = [
            Suggestion.bookmark(title: "DuckDuckGo", url: URL.duckDuckGo, isFavorite: true, score: 0),
            Suggestion.website(url: URL.duckDuckGoAutocomplete)
        ]
        return SuggestionResult(topHits: topHits,
                                duckduckgoSuggestions: [],
                                localSuggestions: [])
    }

    static var noTopHitsResult: SuggestionResult {
        let suggestions = [
            Suggestion.website(url: URL.duckDuckGo),
            Suggestion.website(url: URL.duckDuckGoAutocomplete)
        ]
        return SuggestionResult(topHits: [],
                                duckduckgoSuggestions: suggestions,
                                localSuggestions: [])
    }

}

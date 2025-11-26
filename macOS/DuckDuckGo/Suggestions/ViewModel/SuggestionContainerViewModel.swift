//
//  SuggestionContainerViewModel.swift
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

import BrowserServicesKit
import Combine
import Common
import Foundation
import os.log
import Suggestions

/// Represents the type of content to display in a suggestion row
enum SuggestionRowContent {
    /// The search cell row (shown when AI chat toggle is enabled)
    case searchCell
    /// A suggestion item at the given index
    case suggestion(index: Int)
}

final class SuggestionContainerViewModel {

    var isHomePage: Bool
    let isBurner: Bool
    let suggestionContainer: SuggestionContainer
    private let searchPreferences: SearchPreferences
    private let themeManager: ThemeManaging
    private let featureFlagger: FeatureFlagger
    private var suggestionResultCancellable: AnyCancellable?

    init(isHomePage: Bool,
         isBurner: Bool,
         suggestionContainer: SuggestionContainer,
         searchPreferences: SearchPreferences,
         themeManager: ThemeManaging,
         featureFlagger: FeatureFlagger) {
        self.isHomePage = isHomePage
        self.isBurner = isBurner
        self.suggestionContainer = suggestionContainer
        self.searchPreferences = searchPreferences
        self.themeManager = themeManager
        self.featureFlagger = featureFlagger
        subscribeToSuggestionResult()
    }

    // MARK: - Row-based API (for TableView)

    /// The number of extra rows added before the suggestion results (e.g., search cell)
    private var numberOfPrefixRows: Int {
        shouldShowSearchCell ? 1 : 0
    }

    /// Total number of rows to display in the table view (includes prefix rows like search cell)
    var numberOfRows: Int {
        numberOfSuggestions + numberOfPrefixRows
    }

    /// Returns the content type for a given table row
    func rowContent(at row: Int) -> SuggestionRowContent? {
        guard row >= 0, row < numberOfRows else { return nil }

        if shouldShowSearchCell && row == 0 {
            return .searchCell
        }

        let suggestionIndex = row - numberOfPrefixRows
        guard suggestionIndex >= 0, suggestionIndex < numberOfSuggestions else { return nil }
        return .suggestion(index: suggestionIndex)
    }

    /// Converts a table view row to a suggestion selection index (returns nil for non-suggestion rows)
    func selectionIndex(forRow row: Int) -> Int? {
        guard row >= numberOfPrefixRows else { return nil }
        let index = row - numberOfPrefixRows
        guard index >= 0, index < numberOfSuggestions else { return nil }
        return index
    }

    /// Converts a suggestion selection index to a table view row
    func tableRow(forSelectionIndex index: Int?) -> Int? {
        guard let index, index >= 0, index < numberOfSuggestions else { return nil }
        return index + numberOfPrefixRows
    }

    /// Returns whether the given row is a non-suggestion prefix row (like search cell)
    func isPrefixRow(_ row: Int) -> Bool {
        row >= 0 && row < numberOfPrefixRows
    }

    /// Returns the default row to select when no suggestion is selected (search cell if shown, otherwise nil)
    var defaultSelectedRow: Int? {
        shouldShowSearchCell ? 0 : nil
    }

    // MARK: - Suggestion Data

    var numberOfSuggestions: Int {
        suggestionContainer.result?.count ?? 0
    }

    /// Returns whether the search cell should be shown in the suggestions list
    var shouldShowSearchCell: Bool {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarToggle) else { return false }
        guard let userStringValue, !userStringValue.isEmpty else { return false }
        return true
    }

    @Published private(set) var selectionIndex: Int? {
        didSet { updateSelectedSuggestionViewModel() }
    }

    @Published private(set) var selectedSuggestionViewModel: SuggestionViewModel?

    private(set) var userStringValue: String?

    var isTopSuggestionSelectionExpected = false

    private enum IgnoreTopSuggestionError: Error {
        case emptyResult
        case topSuggestionSelectionNotExpected
        case cantBeAutocompleted
        case noUserStringValue
        case noSuggestionViewModel
        case notEqual(lhs: String, rhs: String)
    }
    private func validateShouldSelectTopSuggestion(from result: SuggestionResult?) throws {
        assert(suggestionContainer.result == result)
        guard let result, !result.isEmpty else { throw IgnoreTopSuggestionError.emptyResult }
        guard self.isTopSuggestionSelectionExpected else { throw IgnoreTopSuggestionError.topSuggestionSelectionNotExpected }
        guard result.canBeAutocompleted else {
            throw IgnoreTopSuggestionError.cantBeAutocompleted
        }
        guard let userStringValue else { throw IgnoreTopSuggestionError.noUserStringValue }
        guard let firstSuggestion = self.suggestionViewModel(at: 0) else { throw IgnoreTopSuggestionError.noSuggestionViewModel }
        guard firstSuggestion.autocompletionString.lowercased().hasPrefix(userStringValue.lowercased()) else {
            throw IgnoreTopSuggestionError.notEqual(lhs: firstSuggestion.autocompletionString, rhs: userStringValue)
        }
    }

    private func subscribeToSuggestionResult() {
        suggestionResultCancellable = suggestionContainer.$result
            .sink { [weak self] result in
                guard let self else { return }
                do {
                    try validateShouldSelectTopSuggestion(from: result)
                } catch {
                    Logger.general.debug("SuggestionContainerViewModel: ignoring top suggestion from \( result.map(String.init(describing:)) ?? "<nil>"): \(error)")
                    return
                }

                self.select(at: 0)
            }
    }

    @MainActor
    func setUserStringValue(_ userStringValue: String, userAppendedStringToTheEnd: Bool) {
        guard searchPreferences.showAutocompleteSuggestions else { return }

        let oldValue = self.userStringValue
        self.userStringValue = userStringValue

        guard !userStringValue.isEmpty else {
            suggestionContainer.stopGettingSuggestions()
            return
        }
        guard userStringValue.lowercased() != oldValue?.lowercased() else { return }

        self.isTopSuggestionSelectionExpected = userAppendedStringToTheEnd && !userStringValue.contains(" ")

        suggestionContainer.getSuggestions(for: userStringValue)
    }

    func clearUserStringValue() {
        self.userStringValue = nil
        suggestionContainer.stopGettingSuggestions()
    }

    private func updateSelectedSuggestionViewModel() {
        if let selectionIndex {
            selectedSuggestionViewModel = suggestionViewModel(at: selectionIndex)
        } else {
            selectedSuggestionViewModel = nil
        }
    }

    func suggestionViewModel(at index: Int) -> SuggestionViewModel? {
        let items = suggestionContainer.result?.all ?? []

        guard index < items.count else {
            Logger.general.error("SuggestionContainerViewModel: Absolute index is out of bounds")
            return nil
        }

        return SuggestionViewModel(isHomePage: isHomePage, suggestion: items[index], userStringValue: userStringValue ?? "", themeManager: themeManager, featureFlagger: featureFlagger)
    }

    func select(at index: Int) {
        guard index >= 0, index < numberOfSuggestions else {
            Logger.general.error("SuggestionContainerViewModel: Index out of bounds")
            selectionIndex = nil
            return
        }

        if suggestionViewModel(at: index) != self.selectedSuggestionViewModel {
            selectionIndex = index
        }
    }

    func clearSelection() {
        if selectionIndex != nil {
            selectionIndex = nil
        }
    }

    func selectNextIfPossible() {
        // When no item is selected, start selection from the top of the list
        guard let selectionIndex = selectionIndex else {
            select(at: 0)
            return
        }

        // At the end of the list, cancel the selection
        if selectionIndex == numberOfSuggestions - 1 {
            clearSelection()
            return
        }

        let newIndex = min(numberOfSuggestions - 1, selectionIndex + 1)
        select(at: newIndex)
    }

    func selectPreviousIfPossible() {
        // When no item is selected, start selection from the bottom of the list
        guard let selectionIndex = selectionIndex else {
            select(at: numberOfSuggestions - 1)
            return
        }

        // If the first item is selected, cancel the selection
        if selectionIndex == 0 {
            clearSelection()
            return
        }

        let newIndex = max(0, selectionIndex - 1)
        select(at: newIndex)
    }

    func removeSuggestionFromResult(suggestion: Suggestion) {
        let topHits = suggestionContainer.result?.topHits.filter({
            !($0 == suggestion && $0.isHistoryEntry)
        }) ?? []
        let duckduckgoSuggestions = suggestionContainer.result?.duckduckgoSuggestions ?? []
        let localSuggestions = suggestionContainer.result?.localSuggestions.filter({
            !($0 == suggestion && $0.isHistoryEntry)
        }) ?? []
        let result = SuggestionResult(topHits: topHits,
                                      duckduckgoSuggestions: duckduckgoSuggestions,
                                      localSuggestions: localSuggestions)

        suggestionContainer.result = result
    }

}

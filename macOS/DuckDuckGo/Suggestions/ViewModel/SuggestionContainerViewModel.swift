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

import AIChat
import Combine
import Common
import FoundationExtensions
import Foundation
import os.log
import PrivacyConfig
import Suggestions

/// Represents the sections in the suggestion list
enum SuggestionListSection: Int, CaseIterable {
    case header = 0
    case suggestions = 1
    case footer = 2
}

/// Represents the type of content to display in a suggestion row
enum SuggestionRowContent: Equatable {
    /// The AI chat cell row (shown when the AI chat toggle and AI features are enabled)
    case aiChatCell
    /// A divider row between sections
    case sectionDivider
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
    private let aiChatPreferencesStorage: AIChatPreferencesStorage
    private var suggestionResultCancellable: AnyCancellable?
    private var cachedRowContents: [SuggestionRowContent]?

    init(isHomePage: Bool,
         isBurner: Bool,
         suggestionContainer: SuggestionContainer,
         searchPreferences: SearchPreferences,
         themeManager: ThemeManaging,
         featureFlagger: FeatureFlagger,
         aiChatPreferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage()) {
        self.isHomePage = isHomePage
        self.isBurner = isBurner
        self.suggestionContainer = suggestionContainer
        self.searchPreferences = searchPreferences
        self.themeManager = themeManager
        self.featureFlagger = featureFlagger
        self.aiChatPreferencesStorage = aiChatPreferencesStorage
        subscribeToSuggestionResult()
    }

    // MARK: - Section-based API (for TableView)

    /// Whether to show the AI chat cell in the footer section.
    /// Shown when the AI chat toggle is enabled, AI features are enabled, and the user has typed input.
    private var shouldShowAIChatCellInFooter: Bool {
        shouldShowAIChatCellBase
    }

    private func invalidateRowContentsCache() {
        cachedRowContents = nil
    }

    var numberOfFooterRows: Int {
        shouldShowAIChatCellInFooter ? 1 : 0
    }

    private var shouldShowFooterDivider: Bool {
        numberOfFooterRows > 0 && numberOfSuggestions > 0
    }

    var numberOfRows: Int {
        numberOfSuggestions
        + (shouldShowFooterDivider ? 1 : 0)
        + numberOfFooterRows
    }

    /// Returns the type of content to display for the given row index.
    func rowContent(at row: Int) -> SuggestionRowContent? {
        let contents = cachedRowContents ?? {
            let built = buildRowContents()
            cachedRowContents = built
            return built
        }()
        guard row >= 0, row < contents.count else { return nil }
        return contents[row]
    }

    private func buildRowContents() -> [SuggestionRowContent] {
        var contents: [SuggestionRowContent] = []

        for index in 0..<numberOfSuggestions {
            contents.append(.suggestion(index: index))
        }

        if shouldShowFooterDivider { contents.append(.sectionDivider) }
        if shouldShowAIChatCellInFooter { contents.append(.aiChatCell) }

        return contents
    }

    func selectionIndex(forRow row: Int) -> Int? {
        guard row >= 0, row < numberOfSuggestions else { return nil }
        return row
    }

    func tableRow(forSelectionIndex index: Int?) -> Int? {
        guard let index, index >= 0, index < numberOfSuggestions else { return nil }
        return index
    }

    func isDividerRow(_ row: Int) -> Bool {
        guard let content = rowContent(at: row) else { return false }
        return content == .sectionDivider
    }

    func isSelectableRow(_ row: Int) -> Bool {
        guard let content = rowContent(at: row) else { return false }
        return content != .sectionDivider
    }

    // MARK: - Suggestion Data

    var numberOfSuggestions: Int {
        suggestionContainer.result?.count ?? 0
    }

    private var shouldShowAIChatCellBase: Bool {
        guard aiChatPreferencesStorage.isAIFeaturesEnabled else { return false }
        guard let userStringValue, !userStringValue.isEmpty else { return false }
        return true
    }

    // MARK: - Row Selection

    @Published private(set) var selectedRowIndex: Int?

    var selectedRowContent: SuggestionRowContent? {
        guard let selectedRowIndex else { return nil }
        return rowContent(at: selectedRowIndex)
    }

    func selectRow(at rowIndex: Int) {
        guard rowIndex >= 0, rowIndex < numberOfRows else {
            Logger.general.error("SuggestionContainerViewModel: Row index out of bounds")
            if selectedRowIndex != nil {
                selectedRowIndex = nil
                selectionIndex = nil
            }
            return
        }

        guard selectedRowIndex != rowIndex else { return }

        selectedRowIndex = rowIndex
        selectionIndex = selectionIndex(forRow: rowIndex)
    }

    func clearRowSelection() {
        guard selectedRowIndex != nil || selectionIndex != nil else { return }
        selectedRowIndex = nil
        selectionIndex = nil
    }

    // MARK: - Suggestion Selection (legacy, for backward compatibility)

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
                self.invalidateRowContentsCache()
                do {
                    try validateShouldSelectTopSuggestion(from: result)
                } catch {
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
        invalidateRowContentsCache()

        guard !userStringValue.isEmpty else {
            suggestionContainer.stopGettingSuggestions()
            return
        }
        guard userStringValue.lowercased() != oldValue?.lowercased() else { return }

        self.isTopSuggestionSelectionExpected = userAppendedStringToTheEnd && !userStringValue.contains(" ")

        suggestionContainer.getSuggestions(for: userStringValue)
    }

    @MainActor
    func prewarmRemoteSuggestionsConnection() {
        guard searchPreferences.showAutocompleteSuggestions else { return }
        suggestionContainer.prewarmRemoteSuggestionsConnection()
    }

    func clearUserStringValue() {
        self.userStringValue = nil
        invalidateRowContentsCache()
        suggestionContainer.stopGettingSuggestions()
    }

    private func updateSelectedSuggestionViewModel() {
        if let selectionIndex {
            selectedSuggestionViewModel = suggestionViewModel(at: selectionIndex)
        } else if selectedRowContent == .aiChatCell, let userStringValue, !userStringValue.isEmpty {
            // Synthesize an .askAIChat view model so the address bar renders the
            // " – Duck.ai" context clue when the synthetic Ask-privately row is selected.
            selectedSuggestionViewModel = SuggestionViewModel(
                isHomePage: isHomePage,
                suggestion: .askAIChat(value: userStringValue),
                userStringValue: userStringValue,
                themeManager: themeManager,
                featureFlagger: featureFlagger
            )
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

    /// Selects a suggestion by its index (for backward compatibility)
    func select(at index: Int) {
        guard index >= 0, index < numberOfSuggestions else {
            Logger.general.error("SuggestionContainerViewModel: Index out of bounds")
            selectionIndex = nil
            selectedRowIndex = nil
            return
        }

        if suggestionViewModel(at: index) != self.selectedSuggestionViewModel {
            selectionIndex = index
            // Update row index to match
            selectedRowIndex = tableRow(forSelectionIndex: index)
        }
    }

    func clearSelection() {
        clearRowSelection()
    }

    func selectNextIfPossible() {
        // When no item is selected, start selection from the first selectable row
        guard let currentRowIndex = selectedRowIndex else {
            if let firstSelectable = firstSelectableRow() {
                selectRow(at: firstSelectable)
            }
            return
        }

        // Find next selectable row (skip divider)
        var nextRow = currentRowIndex + 1
        while nextRow < numberOfRows {
            if isSelectableRow(nextRow) {
                selectRow(at: nextRow)
                return
            }
            nextRow += 1
        }

        clearRowSelection()
    }

    func selectPreviousIfPossible() {
        guard let currentRowIndex = selectedRowIndex else {
            if let lastSelectable = lastSelectableRow() {
                selectRow(at: lastSelectable)
            }
            return
        }

        var prevRow = currentRowIndex - 1
        while prevRow >= 0 {
            if isSelectableRow(prevRow) {
                selectRow(at: prevRow)
                return
            }
            prevRow -= 1
        }

        clearRowSelection()
    }

    private func firstSelectableRow() -> Int? {
        for row in 0..<numberOfRows where isSelectableRow(row) {
            return row
        }
        return nil
    }

    private func lastSelectableRow() -> Int? {
        for row in stride(from: numberOfRows - 1, through: 0, by: -1) where isSelectableRow(row) {
            return row
        }
        return nil
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

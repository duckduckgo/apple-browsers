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
    /// The search cell row (shown when AI chat toggle is enabled)
    case searchCell
    /// The AI chat cell row (shown when AI chat toggle and AI features are enabled)
    case aiChatCell
    /// The visit cell row (shown when user types a URL-like string)
    case visitCell
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
    private let isAIFeaturesEnabled: Bool
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
        self.isAIFeaturesEnabled = aiChatPreferencesStorage.isAIFeaturesEnabled
        subscribeToSuggestionResult()
    }

    // MARK: - Section-based API (for TableView)

    /// Indicates whether the top suggestion has been auto-selected (e.g., user typed "apple" and there's a matching bookmark).
    /// When true, the header section is hidden and the AI chat cell moves to the footer.
    @Published private(set) var hasAutoSelectedSuggestion = false

    /// Whether the user input looks like a URL (e.g., "apple.com").
    /// When true, the visit cell is shown first and the search cell is hidden.
    private var userInputIsURL: Bool {
        guard let userStringValue, !userStringValue.isEmpty else { return false }
        guard let url = URL(trimmedAddressBarString: userStringValue) else { return false }
        return url.isValid
    }

    /// The URL parsed from user input, used for the visit cell display.
    var parsedURLFromUserInput: URL? {
        guard let userStringValue, !userStringValue.isEmpty else { return nil }
        guard let url = URL(trimmedAddressBarString: userStringValue), url.isValid else { return nil }
        return url
    }

    /// The host to display in the visit cell suffix (e.g., "apple.com").
    var visitCellHost: String? {
        parsedURLFromUserInput?.root?.toString(decodePunycode: true, dropScheme: true, dropTrailingSlash: true)
    }

    /// Whether to show header cells (search and AI chat at the top).
    /// Header is hidden when a suggestion is auto-selected OR when user input is a URL.
    private var shouldShowHeaderSection: Bool {
        !hasAutoSelectedSuggestion && !userInputIsURL
    }

    /// Whether to show the AI chat cell in the footer section.
    /// Footer AI chat is shown when:
    /// - aiChatOmnibarCluster is OFF: always show at bottom (never at top)
    /// - aiChatOmnibarCluster is ON: show when a suggestion is auto-selected OR when user input is a URL
    private var shouldShowAIChatCellInFooter: Bool {
        guard shouldShowAIChatCellBase else { return false }
        if !featureFlagger.isFeatureOn(.aiChatOmnibarCluster) {
            return true
        }
        return hasAutoSelectedSuggestion || userInputIsURL
    }

    /// Whether to show the visit cell in the header (when user types a URL-like string).
    private var shouldShowVisitCell: Bool {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarToggle) && featureFlagger.isFeatureOn(.aiChatOmnibarCluster) else { return false }
        return userInputIsURL
    }

    private func invalidateRowContentsCache() {
        cachedRowContents = nil
    }

    var numberOfHeaderRows: Int {
        var count = 0
        if shouldShowVisitCell { count += 1 }
        guard shouldShowHeaderSection else { return count }
        if shouldShowSearchCell { count += 1 }
        if shouldShowAIChatCell { count += 1 }
        return count
    }

    var numberOfFooterRows: Int {
        shouldShowAIChatCellInFooter ? 1 : 0
    }

    private var shouldShowHeaderDivider: Bool {
        guard !shouldShowVisitCell else { return false }
        return numberOfHeaderRows > 0 && numberOfSuggestions > 0
    }

    private var shouldShowFooterDivider: Bool {
        numberOfFooterRows > 0 && numberOfSuggestions > 0
    }

    var numberOfRows: Int {
        numberOfHeaderRows
        + (shouldShowHeaderDivider ? 1 : 0)
        + numberOfSuggestions
        + (shouldShowFooterDivider ? 1 : 0)
        + numberOfFooterRows
    }

    /// Returns the row index where the suggestions section starts
    private var suggestionsSectionStartRow: Int {
        numberOfHeaderRows + (shouldShowHeaderDivider ? 1 : 0)
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

        if shouldShowVisitCell { contents.append(.visitCell) }
        if shouldShowSearchCell { contents.append(.searchCell) }
        if shouldShowAIChatCell { contents.append(.aiChatCell) }

        if shouldShowHeaderDivider { contents.append(.sectionDivider) }

        for index in 0..<numberOfSuggestions {
            contents.append(.suggestion(index: index))
        }

        if shouldShowFooterDivider { contents.append(.sectionDivider) }
        if shouldShowAIChatCellInFooter { contents.append(.aiChatCell) }

        return contents
    }

    func selectionIndex(forRow row: Int) -> Int? {
        guard row >= suggestionsSectionStartRow else { return nil }
        let index = row - suggestionsSectionStartRow
        guard index >= 0, index < numberOfSuggestions else { return nil }
        return index
    }

    func tableRow(forSelectionIndex index: Int?) -> Int? {
        guard let index, index >= 0, index < numberOfSuggestions else { return nil }
        return index + suggestionsSectionStartRow
    }

    func isDividerRow(_ row: Int) -> Bool {
        guard let content = rowContent(at: row) else { return false }
        return content == .sectionDivider
    }

    func isSelectableRow(_ row: Int) -> Bool {
        guard let content = rowContent(at: row) else { return false }
        return content != .sectionDivider
    }

    /// Returns the default row to select when no suggestion is selected.
    /// - When visit cell is shown: returns 0 (visit cell is first and should be selected)
    /// - When auto-selection is active: returns nil (the auto-selected suggestion handles selection)
    /// - When no auto-selection: returns the search cell row (0) if shown, otherwise nil
    var defaultSelectedRow: Int? {
        if shouldShowVisitCell {
            return 0
        }
        if hasAutoSelectedSuggestion {
            return nil
        }
        return shouldShowSearchCell ? 0 : nil
    }

    // MARK: - Suggestion Data

    var numberOfSuggestions: Int {
        suggestionContainer.result?.count ?? 0
    }

    private var shouldShowSearchCellBase: Bool {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarToggle) && featureFlagger.isFeatureOn(.aiChatOmnibarCluster) else { return false }
        guard let userStringValue, !userStringValue.isEmpty else { return false }
        return true
    }

    private var shouldShowAIChatCellBase: Bool {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarToggle) else { return false }
        guard isAIFeaturesEnabled else { return false }
        guard let userStringValue, !userStringValue.isEmpty else { return false }
        return true
    }

    var shouldShowSearchCell: Bool {
        shouldShowHeaderSection && shouldShowSearchCellBase
    }

    var shouldShowAIChatCell: Bool {
        guard featureFlagger.isFeatureOn(.aiChatOmnibarCluster) else { return false }
        return shouldShowHeaderSection && shouldShowAIChatCellBase
    }

    // MARK: - Row Selection (includes prefix rows)

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
                    Logger.general.debug("SuggestionContainerViewModel: ignoring top suggestion from \( result.map(String.init(describing:)) ?? "<nil>"): \(error)")
                    self.hasAutoSelectedSuggestion = false
                    return
                }
                self.hasAutoSelectedSuggestion = true
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
            hasAutoSelectedSuggestion = false
            suggestionContainer.stopGettingSuggestions()
            return
        }
        guard userStringValue.lowercased() != oldValue?.lowercased() else { return }

        self.isTopSuggestionSelectionExpected = userAppendedStringToTheEnd && !userStringValue.contains(" ")

        if !isTopSuggestionSelectionExpected {
            hasAutoSelectedSuggestion = false
        }

        suggestionContainer.getSuggestions(for: userStringValue)
    }

    func clearUserStringValue() {
        self.userStringValue = nil
        hasAutoSelectedSuggestion = false
        invalidateRowContentsCache()
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

        wrapAroundOrClearSelection(using: firstSelectableRow)
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

        wrapAroundOrClearSelection(using: lastSelectableRow)
    }

    /// Wraps around to the given row when aiChatOmnibarToggle is on, otherwise clears selection
    private func wrapAroundOrClearSelection(using selectableRow: () -> Int?) {
        if featureFlagger.isFeatureOn(.aiChatOmnibarToggle), let row = selectableRow() {
            selectRow(at: row)
        } else {
            clearRowSelection()
        }
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

//
//  AIChatSuggestionsViewModel.swift
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

import Combine
import Foundation

/// View model that manages AI chat suggestions displayed in the omnibar.
/// Handles filtering based on user input and keyboard-based selection.
public final class AIChatSuggestionsViewModel: ObservableObject {

    // MARK: - Published Properties

    /// The currently filtered suggestions to display.
    /// Pinned chats appear first, followed by recent chats.
    @Published public private(set) var filteredSuggestions: [AIChatSuggestion] = []

    /// The index of the currently selected suggestion (for keyboard navigation).
    /// `nil` means no suggestion is selected.
    @Published public private(set) var selectedIndex: Int?

    /// Indicates whether keyboard navigation is currently active.
    /// Used to suppress mouse hover while navigating with keyboard.
    @Published public private(set) var isKeyboardNavigating: Bool = false

    // MARK: - Private Properties

    private var pinnedChats: [AIChatSuggestion] = []
    private var recentChats: [AIChatSuggestion] = []
    private var currentQuery: String = ""

    // MARK: - Computed Properties

    /// Returns true if there are any suggestions to display.
    public var hasSuggestions: Bool {
        !filteredSuggestions.isEmpty
    }

    /// Returns the currently selected suggestion, if any.
    public var selectedSuggestion: AIChatSuggestion? {
        guard let index = selectedIndex, filteredSuggestions.indices.contains(index) else {
            return nil
        }
        return filteredSuggestions[index]
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Data Management

    /// Updates the pinned chats list.
    /// - Parameter chats: The new list of pinned chats (max 5 recommended).
    public func setPinnedChats(_ chats: [AIChatSuggestion]) {
        pinnedChats = chats
        applyFilter()
    }

    /// Updates the recent chats list.
    /// - Parameter chats: The new list of recent chats (max 5 recommended).
    public func setRecentChats(_ chats: [AIChatSuggestion]) {
        recentChats = chats
        applyFilter()
    }

    /// Convenience method to set both pinned and recent chats at once.
    /// - Parameters:
    ///   - pinned: The list of pinned chats.
    ///   - recent: The list of recent chats.
    public func setChats(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
        pinnedChats = pinned
        recentChats = recent
        applyFilter()
    }

    // MARK: - Filtering

    /// Updates the filter query and refreshes the filtered suggestions.
    /// - Parameter query: The search query to filter suggestions by.
    public func updateQuery(_ query: String) {
        currentQuery = query
        applyFilter()
    }

    private func applyFilter() {
        let filteredPinned = pinnedChats.filter { $0.matches(query: currentQuery) }
        let filteredRecent = recentChats.filter { $0.matches(query: currentQuery) }

        filteredSuggestions = filteredPinned + filteredRecent

        // Reset selection if it's now out of bounds
        if let index = selectedIndex, index >= filteredSuggestions.count {
            selectedIndex = filteredSuggestions.isEmpty ? nil : filteredSuggestions.count - 1
        }
    }

    // MARK: - Selection Management

    /// Moves selection to the next suggestion.
    /// - Returns: `true` if selection changed, `false` if already at the end or no suggestions.
    @discardableResult
    public func selectNext() -> Bool {
        guard hasSuggestions else { return false }

        isKeyboardNavigating = true

        if let currentIndex = selectedIndex {
            let nextIndex = currentIndex + 1
            if nextIndex < filteredSuggestions.count {
                selectedIndex = nextIndex
                return true
            }
            return false
        } else {
            // No selection, select first item
            selectedIndex = 0
            return true
        }
    }

    /// Moves selection to the previous suggestion.
    /// - Returns: `true` if selection changed, `false` if already at the beginning.
    @discardableResult
    public func selectPrevious() -> Bool {
        guard hasSuggestions else { return false }

        isKeyboardNavigating = true

        if let currentIndex = selectedIndex {
            if currentIndex > 0 {
                selectedIndex = currentIndex - 1
                return true
            } else {
                // At the first item, clear selection to return focus to text field
                selectedIndex = nil
                return true
            }
        }
        return false
    }

    /// Clears the current selection.
    /// - Parameter keepMouseSuppressed: If true, mouse hover remains suppressed until mouse moves.
    public func clearSelection(keepMouseSuppressed: Bool = false) {
        selectedIndex = nil
        if !keepMouseSuppressed {
            isKeyboardNavigating = false
        }
    }

    /// Selects a suggestion at the given index (from mouse interaction).
    /// - Parameter index: The index to select.
    public func select(at index: Int) {
        guard filteredSuggestions.indices.contains(index) else { return }
        isKeyboardNavigating = false
        selectedIndex = index
    }

    /// Called when mouse moves, to re-enable mouse hover selection.
    public func acknowledgeMouseMovement() {
        isKeyboardNavigating = false
    }

    /// Suppresses mouse hover selection until the mouse actually moves.
    /// Call this when the view becomes visible to prevent accidental selection.
    public func suppressMouseHoverUntilMouseMoves() {
        isKeyboardNavigating = true
    }

    // MARK: - Reset

    /// Resets the view model state, clearing query and selection.
    public func reset() {
        currentQuery = ""
        selectedIndex = nil
        isKeyboardNavigating = false
        applyFilter()
    }
}

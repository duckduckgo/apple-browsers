//
//  AIChatSuggestionsViewModel.swift
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

import Combine
import Foundation

/// View model that manages AI chat suggestions displayed in the omnibar.
/// Applies local filtering: merges pinned and recent, sorts by recency, limits to max count.
public final class AIChatSuggestionsViewModel: ObservableObject {

    // MARK: - Constants

    public static let defaultMaxSuggestions = 5

    // MARK: - Properties

    public let maxSuggestions: Int

    // MARK: - Published Properties

    /// The suggestions to display (merged, sorted by recency, limited to max count).
    @Published public private(set) var filteredSuggestions: [AIChatSuggestion] = []

    /// The index of the currently selected suggestion (for keyboard navigation).
    /// `nil` means no suggestion is selected.
    @Published public private(set) var selectedIndex: Int?

    /// Indicates whether keyboard navigation is currently active.
    /// Used to suppress mouse hover while navigating with keyboard.
    @Published public private(set) var isKeyboardNavigating: Bool = false

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

    /// Creates a new suggestions view model.
    /// - Parameter maxSuggestions: Maximum number of suggestions to display. Defaults to 5.
    public init(maxSuggestions: Int = defaultMaxSuggestions) {
        self.maxSuggestions = maxSuggestions
    }

    // MARK: - Data Management

    /// Sets the suggestions to display with local processing applied.
    /// Merges pinned and recent chats, sorts by recency, limits to max count.
    /// Note: One-week filter for empty queries is applied server-side in SuggestionsReader.
    /// - Parameters:
    ///   - pinned: The list of pinned chats.
    ///   - recent: The list of recent chats.
    public func setChats(pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
        // Merge pinned and recent chats
        var allChats = pinned + recent

        // Sort by recency (most recent first)
        allChats.sort { lhs, rhs in
            let lhsDate = lhs.timestamp ?? .distantPast
            let rhsDate = rhs.timestamp ?? .distantPast
            return lhsDate > rhsDate
        }

        // Limit to max suggestions
        filteredSuggestions = Array(allChats.prefix(maxSuggestions))

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
        } else {
            // No selection, select last item (bottom of list)
            selectedIndex = filteredSuggestions.count - 1
            return true
        }
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
    /// Does not clear the selection - that's handled by hover callbacks.
    public func acknowledgeMouseMovement() {
        guard isKeyboardNavigating else { return }
        isKeyboardNavigating = false
    }

    /// Suppresses mouse hover selection until the mouse actually moves.
    /// Call this when the view becomes visible to prevent accidental selection.
    public func suppressMouseHoverUntilMouseMoves() {
        isKeyboardNavigating = true
    }

    // MARK: - Reset

    /// Clears all chats and resets the view model completely.
    public func clearAllChats() {
        selectedIndex = nil
        isKeyboardNavigating = false
        filteredSuggestions = []
    }
}

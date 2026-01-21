//
//  AIChatSuggestionsViewModelTests.swift
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
@testable import AIChat

final class AIChatSuggestionsViewModelTests: XCTestCase {

    private var viewModel: AIChatSuggestionsViewModel!

    override func setUp() {
        super.setUp()
        viewModel = AIChatSuggestionsViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeSuggestion(id: String, title: String, isPinned: Bool = false) -> AIChatSuggestion {
        AIChatSuggestion(id: id, title: title, isPinned: isPinned, chatId: "chat-\(id)")
    }

    // MARK: - Initial State Tests

    func testInitialState_HasNoSuggestions() {
        XCTAssertTrue(viewModel.filteredSuggestions.isEmpty)
        XCTAssertFalse(viewModel.hasSuggestions)
        XCTAssertNil(viewModel.selectedIndex)
        XCTAssertNil(viewModel.selectedSuggestion)
        XCTAssertFalse(viewModel.isKeyboardNavigating)
    }

    // MARK: - Setting Chats Tests

    func testSetPinnedChats_UpdatesFilteredSuggestions() {
        // Given
        let pinnedChats = [
            makeSuggestion(id: "1", title: "Pinned 1", isPinned: true),
            makeSuggestion(id: "2", title: "Pinned 2", isPinned: true)
        ]

        // When
        viewModel.setPinnedChats(pinnedChats)

        // Then
        XCTAssertEqual(viewModel.filteredSuggestions.count, 2)
        XCTAssertTrue(viewModel.hasSuggestions)
    }

    func testSetRecentChats_UpdatesFilteredSuggestions() {
        // Given
        let recentChats = [
            makeSuggestion(id: "1", title: "Recent 1"),
            makeSuggestion(id: "2", title: "Recent 2"),
            makeSuggestion(id: "3", title: "Recent 3")
        ]

        // When
        viewModel.setRecentChats(recentChats)

        // Then
        XCTAssertEqual(viewModel.filteredSuggestions.count, 3)
    }

    func testSetChats_CombinesPinnedAndRecent() {
        // Given
        let pinnedChats = [makeSuggestion(id: "p1", title: "Pinned", isPinned: true)]
        let recentChats = [makeSuggestion(id: "r1", title: "Recent")]

        // When
        viewModel.setChats(pinned: pinnedChats, recent: recentChats)

        // Then
        XCTAssertEqual(viewModel.filteredSuggestions.count, 2)
        // Pinned should come first
        XCTAssertEqual(viewModel.filteredSuggestions[0].id, "p1")
        XCTAssertEqual(viewModel.filteredSuggestions[1].id, "r1")
    }

    // MARK: - Filtering Tests

    func testUpdateQuery_FiltersResults() {
        // Given
        viewModel.setChats(
            pinned: [makeSuggestion(id: "p1", title: "Swift programming", isPinned: true)],
            recent: [
                makeSuggestion(id: "r1", title: "Python basics"),
                makeSuggestion(id: "r2", title: "Swift UI tutorial")
            ]
        )

        // When
        viewModel.updateQuery("Swift")

        // Then
        XCTAssertEqual(viewModel.filteredSuggestions.count, 2)
        XCTAssertTrue(viewModel.filteredSuggestions.allSatisfy { $0.title.contains("Swift") })
    }

    func testUpdateQuery_WithEmptyQuery_ShowsAllResults() {
        // Given
        viewModel.setChats(
            pinned: [makeSuggestion(id: "p1", title: "Pinned", isPinned: true)],
            recent: [makeSuggestion(id: "r1", title: "Recent")]
        )
        viewModel.updateQuery("Pinned")
        XCTAssertEqual(viewModel.filteredSuggestions.count, 1)

        // When
        viewModel.updateQuery("")

        // Then
        XCTAssertEqual(viewModel.filteredSuggestions.count, 2)
    }

    func testUpdateQuery_WithNoMatches_ReturnsEmpty() {
        // Given
        viewModel.setChats(
            pinned: [makeSuggestion(id: "p1", title: "Pinned", isPinned: true)],
            recent: [makeSuggestion(id: "r1", title: "Recent")]
        )

        // When
        viewModel.updateQuery("xyz123nonexistent")

        // Then
        XCTAssertTrue(viewModel.filteredSuggestions.isEmpty)
        XCTAssertFalse(viewModel.hasSuggestions)
    }

    func testUpdateQuery_IsCaseInsensitive() {
        // Given
        viewModel.setRecentChats([makeSuggestion(id: "1", title: "Swift Programming")])

        // When/Then
        viewModel.updateQuery("swift")
        XCTAssertEqual(viewModel.filteredSuggestions.count, 1)

        viewModel.updateQuery("SWIFT")
        XCTAssertEqual(viewModel.filteredSuggestions.count, 1)

        viewModel.updateQuery("SwIfT")
        XCTAssertEqual(viewModel.filteredSuggestions.count, 1)
    }

    // MARK: - Selection Tests

    func testSelectNext_WithNoSelection_SelectsFirst() {
        // Given
        viewModel.setRecentChats([
            makeSuggestion(id: "1", title: "First"),
            makeSuggestion(id: "2", title: "Second")
        ])

        // When
        let result = viewModel.selectNext()

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertTrue(viewModel.isKeyboardNavigating)
    }

    func testSelectNext_WithSelection_MovesToNext() {
        // Given
        viewModel.setRecentChats([
            makeSuggestion(id: "1", title: "First"),
            makeSuggestion(id: "2", title: "Second"),
            makeSuggestion(id: "3", title: "Third")
        ])
        viewModel.selectNext() // Select first

        // When
        let result = viewModel.selectNext()

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.selectedIndex, 1)
    }

    func testSelectNext_AtLastItem_ReturnsFalse() {
        // Given
        viewModel.setRecentChats([
            makeSuggestion(id: "1", title: "First"),
            makeSuggestion(id: "2", title: "Second")
        ])
        viewModel.selectNext() // Select first (index 0)
        viewModel.selectNext() // Select second (index 1)

        // When
        let result = viewModel.selectNext()

        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(viewModel.selectedIndex, 1) // Still at last item
    }

    func testSelectNext_WithNoSuggestions_ReturnsFalse() {
        // When
        let result = viewModel.selectNext()

        // Then
        XCTAssertFalse(result)
        XCTAssertNil(viewModel.selectedIndex)
    }

    func testSelectPrevious_WithSelection_MovesToPrevious() {
        // Given
        viewModel.setRecentChats([
            makeSuggestion(id: "1", title: "First"),
            makeSuggestion(id: "2", title: "Second"),
            makeSuggestion(id: "3", title: "Third")
        ])
        viewModel.selectNext() // Select first (index 0)
        viewModel.selectNext() // Select second (index 1)

        // When
        let result = viewModel.selectPrevious()

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testSelectPrevious_AtFirstItem_ClearsSelection() {
        // Given
        viewModel.setRecentChats([
            makeSuggestion(id: "1", title: "First"),
            makeSuggestion(id: "2", title: "Second")
        ])
        viewModel.selectNext() // Select first (index 0)

        // When
        let result = viewModel.selectPrevious()

        // Then
        XCTAssertTrue(result)
        XCTAssertNil(viewModel.selectedIndex)
    }

    func testSelectPrevious_WithNoSelection_ReturnsFalse() {
        // Given
        viewModel.setRecentChats([makeSuggestion(id: "1", title: "First")])

        // When
        let result = viewModel.selectPrevious()

        // Then
        XCTAssertFalse(result)
    }

    func testSelectPrevious_WithNoSuggestions_ReturnsFalse() {
        // When
        let result = viewModel.selectPrevious()

        // Then
        XCTAssertFalse(result)
    }

    func testSelectAtIndex_WithValidIndex_SelectsItem() {
        // Given
        viewModel.setRecentChats([
            makeSuggestion(id: "1", title: "First"),
            makeSuggestion(id: "2", title: "Second"),
            makeSuggestion(id: "3", title: "Third")
        ])

        // When
        viewModel.select(at: 1)

        // Then
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertFalse(viewModel.isKeyboardNavigating) // Mouse selection disables keyboard navigating
    }

    func testSelectAtIndex_WithInvalidIndex_DoesNothing() {
        // Given
        viewModel.setRecentChats([makeSuggestion(id: "1", title: "First")])

        // When
        viewModel.select(at: 5)

        // Then
        XCTAssertNil(viewModel.selectedIndex)
    }

    func testSelectedSuggestion_ReturnsCorrectItem() {
        // Given
        let suggestions = [
            makeSuggestion(id: "1", title: "First"),
            makeSuggestion(id: "2", title: "Second")
        ]
        viewModel.setRecentChats(suggestions)
        viewModel.selectNext()
        viewModel.selectNext()

        // Then
        XCTAssertEqual(viewModel.selectedSuggestion?.id, "2")
    }

    // MARK: - Clear Selection Tests

    func testClearSelection_RemovesSelection() {
        // Given
        viewModel.setRecentChats([makeSuggestion(id: "1", title: "First")])
        viewModel.selectNext()
        XCTAssertNotNil(viewModel.selectedIndex)

        // When
        viewModel.clearSelection()

        // Then
        XCTAssertNil(viewModel.selectedIndex)
        XCTAssertFalse(viewModel.isKeyboardNavigating)
    }

    func testClearSelection_WithKeepMouseSuppressed_KeepsKeyboardNavigatingTrue() {
        // Given
        viewModel.setRecentChats([makeSuggestion(id: "1", title: "First")])
        viewModel.selectNext()
        XCTAssertTrue(viewModel.isKeyboardNavigating)

        // When
        viewModel.clearSelection(keepMouseSuppressed: true)

        // Then
        XCTAssertNil(viewModel.selectedIndex)
        XCTAssertTrue(viewModel.isKeyboardNavigating)
    }

    // MARK: - Mouse Movement Tests

    func testAcknowledgeMouseMovement_DisablesKeyboardNavigating() {
        // Given
        viewModel.setRecentChats([makeSuggestion(id: "1", title: "First")])
        viewModel.selectNext()
        XCTAssertTrue(viewModel.isKeyboardNavigating)

        // When
        viewModel.acknowledgeMouseMovement()

        // Then
        XCTAssertFalse(viewModel.isKeyboardNavigating)
        XCTAssertEqual(viewModel.selectedIndex, 0) // Selection preserved
    }

    func testAcknowledgeMouseMovement_WhenNotKeyboardNavigating_DoesNothing() {
        // Given
        viewModel.setRecentChats([makeSuggestion(id: "1", title: "First")])
        viewModel.select(at: 0) // Mouse selection
        XCTAssertFalse(viewModel.isKeyboardNavigating)

        // When
        viewModel.acknowledgeMouseMovement()

        // Then
        XCTAssertFalse(viewModel.isKeyboardNavigating)
    }

    func testSuppressMouseHoverUntilMouseMoves_EnablesKeyboardNavigating() {
        // Given
        XCTAssertFalse(viewModel.isKeyboardNavigating)

        // When
        viewModel.suppressMouseHoverUntilMouseMoves()

        // Then
        XCTAssertTrue(viewModel.isKeyboardNavigating)
    }

    // MARK: - Reset Tests

    func testReset_ClearsQueryAndSelection() {
        // Given
        viewModel.setRecentChats([
            makeSuggestion(id: "1", title: "Swift"),
            makeSuggestion(id: "2", title: "Python")
        ])
        viewModel.updateQuery("Swift")
        viewModel.selectNext()
        XCTAssertEqual(viewModel.filteredSuggestions.count, 1)
        XCTAssertNotNil(viewModel.selectedIndex)

        // When
        viewModel.reset()

        // Then
        XCTAssertEqual(viewModel.filteredSuggestions.count, 2) // All suggestions visible
        XCTAssertNil(viewModel.selectedIndex)
        XCTAssertFalse(viewModel.isKeyboardNavigating)
    }

    // MARK: - Clear All Chats Tests

    func testClearAllChats_RemovesAllData() {
        // Given
        viewModel.setChats(
            pinned: [makeSuggestion(id: "p1", title: "Pinned", isPinned: true)],
            recent: [makeSuggestion(id: "r1", title: "Recent")]
        )
        viewModel.selectNext()
        XCTAssertTrue(viewModel.hasSuggestions)

        // When
        viewModel.clearAllChats()

        // Then
        XCTAssertTrue(viewModel.filteredSuggestions.isEmpty)
        XCTAssertFalse(viewModel.hasSuggestions)
        XCTAssertNil(viewModel.selectedIndex)
        XCTAssertFalse(viewModel.isKeyboardNavigating)
    }

    // MARK: - Selection Adjustment on Filter Tests

    func testFilteringAdjustsSelectionWhenOutOfBounds() {
        // Given
        viewModel.setRecentChats([
            makeSuggestion(id: "1", title: "Apple"),
            makeSuggestion(id: "2", title: "Banana"),
            makeSuggestion(id: "3", title: "Cherry")
        ])
        viewModel.selectNext()
        viewModel.selectNext()
        viewModel.selectNext() // Select Cherry (index 2)
        XCTAssertEqual(viewModel.selectedIndex, 2)

        // When: Filter to only show Apple
        viewModel.updateQuery("Apple")

        // Then: Selection should adjust to last valid index
        XCTAssertEqual(viewModel.filteredSuggestions.count, 1)
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testFilteringClearsSelectionWhenNoResults() {
        // Given
        viewModel.setRecentChats([makeSuggestion(id: "1", title: "Apple")])
        viewModel.selectNext()
        XCTAssertEqual(viewModel.selectedIndex, 0)

        // When: Filter to show no results
        viewModel.updateQuery("xyz")

        // Then
        XCTAssertTrue(viewModel.filteredSuggestions.isEmpty)
        XCTAssertNil(viewModel.selectedIndex)
    }
}

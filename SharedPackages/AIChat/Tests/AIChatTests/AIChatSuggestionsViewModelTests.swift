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

    private func makeSuggestion(
        id: String,
        title: String,
        isPinned: Bool = false,
        timestamp: Date = Date()
    ) -> AIChatSuggestion {
        AIChatSuggestion(id: id, title: title, isPinned: isPinned, chatId: "chat-\(id)", timestamp: timestamp)
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

    func testSetChats_MergesAndSortsByRecency() {
        // Given - pinned is older, recent is newer
        let pinnedChats = [makeSuggestion(id: "p1", title: "Pinned", isPinned: true, timestamp: Date().addingTimeInterval(-3600))]
        let recentChats = [makeSuggestion(id: "r1", title: "Recent", timestamp: Date())]

        // When
        viewModel.setChats(pinned: pinnedChats, recent: recentChats)

        // Then - sorted by recency, most recent first
        XCTAssertEqual(viewModel.filteredSuggestions.count, 2)
        XCTAssertTrue(viewModel.hasSuggestions)
        XCTAssertEqual(viewModel.filteredSuggestions[0].id, "r1") // More recent
        XCTAssertEqual(viewModel.filteredSuggestions[1].id, "p1") // Older
    }

    func testSetChats_ReplacesExistingChats() {
        // Given
        viewModel.setChats(
            pinned: [makeSuggestion(id: "old", title: "Old", isPinned: true)],
            recent: []
        )
        XCTAssertEqual(viewModel.filteredSuggestions.count, 1)

        // When
        let now = Date()
        viewModel.setChats(
            pinned: [],
            recent: [
                makeSuggestion(id: "new1", title: "New 1", timestamp: now),
                makeSuggestion(id: "new2", title: "New 2", timestamp: now.addingTimeInterval(-60))
            ]
        )

        // Then - sorted by recency
        XCTAssertEqual(viewModel.filteredSuggestions.count, 2)
        XCTAssertEqual(viewModel.filteredSuggestions[0].id, "new1") // More recent
    }

    func testSetChats_LimitsToMaxSuggestions() {
        // Given - 7 suggestions, should be limited to 5
        let now = Date()
        let suggestions = (1...7).map { i in
            makeSuggestion(id: "\(i)", title: "Chat \(i)", timestamp: now.addingTimeInterval(Double(-i * 60)))
        }

        // When
        viewModel.setChats(pinned: [], recent: suggestions)

        // Then
        XCTAssertEqual(viewModel.filteredSuggestions.count, 5)
    }

    // MARK: - Selection Tests

    func testSelectNext_WithNoSelection_SelectsFirst() {
        // Given
        let now = Date()
        viewModel.setChats(pinned: [], recent: [
            makeSuggestion(id: "1", title: "First", timestamp: now),
            makeSuggestion(id: "2", title: "Second", timestamp: now.addingTimeInterval(-60))
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
        let now = Date()
        viewModel.setChats(pinned: [], recent: [
            makeSuggestion(id: "1", title: "First", timestamp: now),
            makeSuggestion(id: "2", title: "Second", timestamp: now.addingTimeInterval(-60)),
            makeSuggestion(id: "3", title: "Third", timestamp: now.addingTimeInterval(-120))
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
        let now = Date()
        viewModel.setChats(pinned: [], recent: [
            makeSuggestion(id: "1", title: "First", timestamp: now),
            makeSuggestion(id: "2", title: "Second", timestamp: now.addingTimeInterval(-60))
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
        let now = Date()
        viewModel.setChats(pinned: [], recent: [
            makeSuggestion(id: "1", title: "First", timestamp: now),
            makeSuggestion(id: "2", title: "Second", timestamp: now.addingTimeInterval(-60)),
            makeSuggestion(id: "3", title: "Third", timestamp: now.addingTimeInterval(-120))
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
        let now = Date()
        viewModel.setChats(pinned: [], recent: [
            makeSuggestion(id: "1", title: "First", timestamp: now),
            makeSuggestion(id: "2", title: "Second", timestamp: now.addingTimeInterval(-60))
        ])
        viewModel.selectNext() // Select first (index 0)

        // When
        let result = viewModel.selectPrevious()

        // Then
        XCTAssertTrue(result)
        XCTAssertNil(viewModel.selectedIndex)
    }

    func testSelectPrevious_WithNoSelection_SelectsLastItem() {
        // Given
        let now = Date()
        viewModel.setChats(pinned: [], recent: [
            makeSuggestion(id: "1", title: "First", timestamp: now),
            makeSuggestion(id: "2", title: "Second", timestamp: now.addingTimeInterval(-60)),
            makeSuggestion(id: "3", title: "Third", timestamp: now.addingTimeInterval(-120))
        ])

        // When
        let result = viewModel.selectPrevious()

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.selectedIndex, 2) // Last item selected
        XCTAssertTrue(viewModel.isKeyboardNavigating)
    }

    func testSelectPrevious_WithNoSuggestions_ReturnsFalse() {
        // When
        let result = viewModel.selectPrevious()

        // Then
        XCTAssertFalse(result)
    }

    func testSelectAtIndex_WithValidIndex_SelectsItem() {
        // Given
        let now = Date()
        viewModel.setChats(pinned: [], recent: [
            makeSuggestion(id: "1", title: "First", timestamp: now),
            makeSuggestion(id: "2", title: "Second", timestamp: now.addingTimeInterval(-60)),
            makeSuggestion(id: "3", title: "Third", timestamp: now.addingTimeInterval(-120))
        ])

        // When
        viewModel.select(at: 1)

        // Then
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertFalse(viewModel.isKeyboardNavigating) // Mouse selection disables keyboard navigating
    }

    func testSelectAtIndex_WithInvalidIndex_DoesNothing() {
        // Given
        viewModel.setChats(pinned: [], recent: [makeSuggestion(id: "1", title: "First")])

        // When
        viewModel.select(at: 5)

        // Then
        XCTAssertNil(viewModel.selectedIndex)
    }

    func testSelectedSuggestion_ReturnsCorrectItem() {
        // Given
        let now = Date()
        let suggestions = [
            makeSuggestion(id: "1", title: "First", timestamp: now),
            makeSuggestion(id: "2", title: "Second", timestamp: now.addingTimeInterval(-60))
        ]
        viewModel.setChats(pinned: [], recent: suggestions)
        viewModel.selectNext()
        viewModel.selectNext()

        // Then
        XCTAssertEqual(viewModel.selectedSuggestion?.id, "2")
    }

    // MARK: - Clear Selection Tests

    func testClearSelection_RemovesSelection() {
        // Given
        viewModel.setChats(pinned: [], recent: [makeSuggestion(id: "1", title: "First")])
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
        viewModel.setChats(pinned: [], recent: [makeSuggestion(id: "1", title: "First")])
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
        viewModel.setChats(pinned: [], recent: [makeSuggestion(id: "1", title: "First")])
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
        viewModel.setChats(pinned: [], recent: [makeSuggestion(id: "1", title: "First")])
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

    // MARK: - Selection Adjustment Tests

    func testSetChats_AdjustsSelectionWhenOutOfBounds() {
        // Given
        let now = Date()
        viewModel.setChats(pinned: [], recent: [
            makeSuggestion(id: "1", title: "First", timestamp: now),
            makeSuggestion(id: "2", title: "Second", timestamp: now.addingTimeInterval(-60)),
            makeSuggestion(id: "3", title: "Third", timestamp: now.addingTimeInterval(-120))
        ])
        viewModel.selectNext()
        viewModel.selectNext()
        viewModel.selectNext() // Select Third (index 2)
        XCTAssertEqual(viewModel.selectedIndex, 2)

        // When: Set fewer chats
        viewModel.setChats(pinned: [], recent: [
            makeSuggestion(id: "1", title: "First")
        ])

        // Then: Selection should adjust to last valid index
        XCTAssertEqual(viewModel.filteredSuggestions.count, 1)
        XCTAssertEqual(viewModel.selectedIndex, 0)
    }

    func testSetChats_ClearsSelectionWhenEmpty() {
        // Given
        viewModel.setChats(pinned: [], recent: [makeSuggestion(id: "1", title: "First")])
        viewModel.selectNext()
        XCTAssertEqual(viewModel.selectedIndex, 0)

        // When: Set empty chats
        viewModel.setChats(pinned: [], recent: [])

        // Then
        XCTAssertTrue(viewModel.filteredSuggestions.isEmpty)
        XCTAssertNil(viewModel.selectedIndex)
    }
}

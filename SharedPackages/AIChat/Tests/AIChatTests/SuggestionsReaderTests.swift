//
//  SuggestionsReaderTests.swift
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

final class SuggestionsReaderTests: XCTestCase {

    // MARK: - Helper Methods

    private func makeSuggestion(
        id: String,
        title: String = "Test",
        isPinned: Bool = false,
        timestamp: Date? = nil
    ) -> AIChatSuggestion {
        AIChatSuggestion(id: id, title: title, isPinned: isPinned, chatId: "chat-\(id)", timestamp: timestamp)
    }

    // MARK: - mostRecentTimestamp Tests

    func testMostRecentTimestamp_WithEmptyArrays_ReturnsNil() {
        // Given
        let suggestions: (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) = (pinned: [], recent: [])

        // When
        let result = SuggestionsReader.mostRecentTimestamp(from: suggestions)

        // Then
        XCTAssertNil(result)
    }

    func testMostRecentTimestamp_WithNoTimestamps_ReturnsNil() {
        // Given
        let suggestions = (
            pinned: [makeSuggestion(id: "p1")],
            recent: [makeSuggestion(id: "r1")]
        )

        // When
        let result = SuggestionsReader.mostRecentTimestamp(from: suggestions)

        // Then
        XCTAssertNil(result)
    }

    func testMostRecentTimestamp_WithOnlyPinnedTimestamps_ReturnsMostRecent() {
        // Given
        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()

        let suggestions = (
            pinned: [
                makeSuggestion(id: "p1", timestamp: oldDate),
                makeSuggestion(id: "p2", timestamp: newDate)
            ],
            recent: [makeSuggestion(id: "r1")]
        )

        // When
        let result = SuggestionsReader.mostRecentTimestamp(from: suggestions)

        // Then
        XCTAssertEqual(result, newDate)
    }

    func testMostRecentTimestamp_WithOnlyRecentTimestamps_ReturnsMostRecent() {
        // Given
        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()

        let suggestions = (
            pinned: [makeSuggestion(id: "p1")],
            recent: [
                makeSuggestion(id: "r1", timestamp: newDate),
                makeSuggestion(id: "r2", timestamp: oldDate)
            ]
        )

        // When
        let result = SuggestionsReader.mostRecentTimestamp(from: suggestions)

        // Then
        XCTAssertEqual(result, newDate)
    }

    func testMostRecentTimestamp_WithMixedTimestamps_ReturnsMostRecentOverall() {
        // Given
        let oldestDate = Date().addingTimeInterval(-7200)
        let middleDate = Date().addingTimeInterval(-3600)
        let newestDate = Date()

        let suggestions = (
            pinned: [
                makeSuggestion(id: "p1", timestamp: middleDate),
                makeSuggestion(id: "p2", timestamp: oldestDate)
            ],
            recent: [
                makeSuggestion(id: "r1", timestamp: newestDate),
                makeSuggestion(id: "r2", timestamp: oldestDate)
            ]
        )

        // When
        let result = SuggestionsReader.mostRecentTimestamp(from: suggestions)

        // Then
        XCTAssertEqual(result, newestDate)
    }

    func testMostRecentTimestamp_WithPinnedMoreRecent_ReturnsPinnedDate() {
        // Given
        let pinnedDate = Date()
        let recentDate = Date().addingTimeInterval(-3600)

        let suggestions = (
            pinned: [makeSuggestion(id: "p1", timestamp: pinnedDate)],
            recent: [makeSuggestion(id: "r1", timestamp: recentDate)]
        )

        // When
        let result = SuggestionsReader.mostRecentTimestamp(from: suggestions)

        // Then
        XCTAssertEqual(result, pinnedDate)
    }

    // MARK: - findMostRecentResult Tests

    func testFindMostRecentResult_WithEmptyArray_ReturnsNil() {
        // Given
        let results: [(pinned: [AIChatSuggestion], recent: [AIChatSuggestion])] = []

        // When
        let result = SuggestionsReader.findMostRecentResult(from: results)

        // Then
        XCTAssertNil(result)
    }

    func testFindMostRecentResult_WithSingleResult_ReturnsThatResult() {
        // Given
        let singleResult = (
            pinned: [makeSuggestion(id: "p1", timestamp: Date())],
            recent: [makeSuggestion(id: "r1")]
        )
        let results = [singleResult]

        // When
        let result = SuggestionsReader.findMostRecentResult(from: results)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pinned.first?.id, "p1")
    }

    func testFindMostRecentResult_WithMultipleResults_ReturnsResultWithMostRecentTimestamp() {
        // Given
        let olderDate = Date().addingTimeInterval(-3600)
        let newerDate = Date()

        let olderResult = (
            pinned: [makeSuggestion(id: "old-p1", timestamp: olderDate)],
            recent: [makeSuggestion(id: "old-r1")]
        )

        let newerResult = (
            pinned: [makeSuggestion(id: "new-p1", timestamp: newerDate)],
            recent: [makeSuggestion(id: "new-r1")]
        )

        let results = [olderResult, newerResult]

        // When
        let result = SuggestionsReader.findMostRecentResult(from: results)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pinned.first?.id, "new-p1")
    }

    func testFindMostRecentResult_WithReversedOrder_StillReturnsResultWithMostRecentTimestamp() {
        // Given: Results in reverse order (newer first, then older)
        let olderDate = Date().addingTimeInterval(-3600)
        let newerDate = Date()

        let newerResult = (
            pinned: [makeSuggestion(id: "new-p1", timestamp: newerDate)],
            recent: [makeSuggestion(id: "new-r1")]
        )

        let olderResult = (
            pinned: [makeSuggestion(id: "old-p1", timestamp: olderDate)],
            recent: [makeSuggestion(id: "old-r1")]
        )

        let results = [newerResult, olderResult]

        // When
        let result = SuggestionsReader.findMostRecentResult(from: results)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pinned.first?.id, "new-p1")
    }

    func testFindMostRecentResult_WithNoTimestamps_ReturnsFirstResult() {
        // Given: No timestamps in any result
        let result1 = (
            pinned: [makeSuggestion(id: "first-p1")],
            recent: [makeSuggestion(id: "first-r1")]
        )

        let result2 = (
            pinned: [makeSuggestion(id: "second-p1")],
            recent: [makeSuggestion(id: "second-r1")]
        )

        let results = [result1, result2]

        // When
        let result = SuggestionsReader.findMostRecentResult(from: results)

        // Then: Should return first result when no timestamps
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pinned.first?.id, "first-p1")
    }

    func testFindMostRecentResult_WithMixedTimestampPresence_PrefersResultWithTimestamp() {
        // Given: One result has timestamps, one doesn't
        let dateWithTimestamp = Date()

        let resultWithTimestamp = (
            pinned: [makeSuggestion(id: "with-ts-p1", timestamp: dateWithTimestamp)],
            recent: [makeSuggestion(id: "with-ts-r1")]
        )

        let resultWithoutTimestamp = (
            pinned: [makeSuggestion(id: "no-ts-p1")],
            recent: [makeSuggestion(id: "no-ts-r1")]
        )

        let results = [resultWithoutTimestamp, resultWithTimestamp]

        // When
        let result = SuggestionsReader.findMostRecentResult(from: results)

        // Then: Should prefer result with timestamp
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pinned.first?.id, "with-ts-p1")
    }

    func testFindMostRecentResult_WithTimestampInRecentOnly_UsesRecentTimestamp() {
        // Given
        let newerDate = Date()
        let olderDate = Date().addingTimeInterval(-3600)

        let result1 = (
            pinned: [makeSuggestion(id: "r1-p1")],
            recent: [makeSuggestion(id: "r1-r1", timestamp: newerDate)]
        )

        let result2 = (
            pinned: [makeSuggestion(id: "r2-p1")],
            recent: [makeSuggestion(id: "r2-r1", timestamp: olderDate)]
        )

        let results = [result2, result1]

        // When
        let result = SuggestionsReader.findMostRecentResult(from: results)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.recent.first?.id, "r1-r1")
    }

    func testFindMostRecentResult_WithEmptySubarrays_HandlesGracefully() {
        // Given
        let date = Date()

        let emptyResult: (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) = (pinned: [], recent: [])

        let nonEmptyResult = (
            pinned: [makeSuggestion(id: "p1", timestamp: date)],
            recent: [] as [AIChatSuggestion]
        )

        let results = [emptyResult, nonEmptyResult]

        // When
        let result = SuggestionsReader.findMostRecentResult(from: results)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pinned.first?.id, "p1")
    }

    func testFindMostRecentResult_WithThreeResults_ReturnsCorrectOne() {
        // Given
        let oldestDate = Date().addingTimeInterval(-7200)
        let middleDate = Date().addingTimeInterval(-3600)
        let newestDate = Date()

        let oldestResult = (
            pinned: [makeSuggestion(id: "oldest-p1", timestamp: oldestDate)],
            recent: [makeSuggestion(id: "oldest-r1")]
        )

        let middleResult = (
            pinned: [makeSuggestion(id: "middle-p1", timestamp: middleDate)],
            recent: [makeSuggestion(id: "middle-r1")]
        )

        let newestResult = (
            pinned: [makeSuggestion(id: "newest-p1", timestamp: newestDate)],
            recent: [makeSuggestion(id: "newest-r1")]
        )

        // Test with different orderings
        let results1 = [oldestResult, middleResult, newestResult]
        let results2 = [newestResult, oldestResult, middleResult]
        let results3 = [middleResult, newestResult, oldestResult]

        // When/Then
        XCTAssertEqual(SuggestionsReader.findMostRecentResult(from: results1)?.pinned.first?.id, "newest-p1")
        XCTAssertEqual(SuggestionsReader.findMostRecentResult(from: results2)?.pinned.first?.id, "newest-p1")
        XCTAssertEqual(SuggestionsReader.findMostRecentResult(from: results3)?.pinned.first?.id, "newest-p1")
    }
}

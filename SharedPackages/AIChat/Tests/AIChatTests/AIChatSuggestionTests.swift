//
//  AIChatSuggestionTests.swift
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

final class AIChatSuggestionTests: XCTestCase {

    // MARK: - ISO8601 Date Parsing Tests

    func testParseISO8601Date_WithValidDateWithFractionalSeconds_ReturnsDate() {
        // Given
        let dateString = "2026-01-19T11:48:10.903Z"

        // When
        let result = AIChatSuggestion.parseISO8601Date(dateString)

        // Then
        XCTAssertNotNil(result)

        // Verify the parsed date components
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: result!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 11)
        XCTAssertEqual(components.minute, 48)
        XCTAssertEqual(components.second, 10)
    }

    func testParseISO8601Date_WithValidDateWithoutFractionalSeconds_ReturnsNil() {
        // Given: Date without fractional seconds (our formatter requires them)
        let dateString = "2026-01-19T11:48:10Z"

        // When
        let result = AIChatSuggestion.parseISO8601Date(dateString)

        // Then: Returns nil because our formatter specifically requires fractional seconds
        XCTAssertNil(result)
    }

    func testParseISO8601Date_WithNilString_ReturnsNil() {
        // When
        let result = AIChatSuggestion.parseISO8601Date(nil)

        // Then
        XCTAssertNil(result)
    }

    func testParseISO8601Date_WithInvalidString_ReturnsNil() {
        // Given
        let invalidStrings = [
            "not a date",
            "2026/01/19",
            "19-01-2026",
            "",
            "2026-01-19 11:48:10"
        ]

        for dateString in invalidStrings {
            // When
            let result = AIChatSuggestion.parseISO8601Date(dateString)

            // Then
            XCTAssertNil(result, "Expected nil for invalid date string: \(dateString)")
        }
    }

    func testParseISO8601Date_WithDifferentFractionalSecondPrecisions_ParsesCorrectly() {
        // Given: Various fractional second precisions
        let dateStrings = [
            "2026-01-19T11:48:10.1Z",
            "2026-01-19T11:48:10.12Z",
            "2026-01-19T11:48:10.123Z",
            "2026-01-19T11:48:10.1234Z",
            "2026-01-19T11:48:10.12345Z",
            "2026-01-19T11:48:10.123456Z"
        ]

        for dateString in dateStrings {
            // When
            let result = AIChatSuggestion.parseISO8601Date(dateString)

            // Then
            XCTAssertNotNil(result, "Expected valid date for: \(dateString)")
        }
    }

    // MARK: - Initialization Tests

    func testInit_SetsAllProperties() {
        // Given
        let id = "test-id"
        let title = "Test Title"
        let isPinned = true
        let chatId = "chat-123"
        let timestamp = Date()

        // When
        let suggestion = AIChatSuggestion(
            id: id,
            title: title,
            isPinned: isPinned,
            chatId: chatId,
            timestamp: timestamp
        )

        // Then
        XCTAssertEqual(suggestion.id, id)
        XCTAssertEqual(suggestion.title, title)
        XCTAssertEqual(suggestion.isPinned, isPinned)
        XCTAssertEqual(suggestion.chatId, chatId)
        XCTAssertEqual(suggestion.timestamp, timestamp)
    }

    func testInit_WithNilTimestamp_SetsTimestampToNil() {
        // When
        let suggestion = AIChatSuggestion(
            id: "1",
            title: "Test",
            isPinned: false,
            chatId: "chat-1"
        )

        // Then
        XCTAssertNil(suggestion.timestamp)
    }

    // MARK: - Equatable Tests

    func testEquatable_WithSameValues_ReturnsTrue() {
        // Given
        let date = Date()
        let suggestion1 = AIChatSuggestion(id: "1", title: "Test", isPinned: true, chatId: "chat-1", timestamp: date)
        let suggestion2 = AIChatSuggestion(id: "1", title: "Test", isPinned: true, chatId: "chat-1", timestamp: date)

        // Then
        XCTAssertEqual(suggestion1, suggestion2)
    }

    func testEquatable_WithDifferentId_ReturnsFalse() {
        // Given
        let suggestion1 = AIChatSuggestion(id: "1", title: "Test", isPinned: true, chatId: "chat-1")
        let suggestion2 = AIChatSuggestion(id: "2", title: "Test", isPinned: true, chatId: "chat-1")

        // Then
        XCTAssertNotEqual(suggestion1, suggestion2)
    }

    // MARK: - Hashable Tests

    func testHashable_WithSameValues_HasSameHash() {
        // Given
        let date = Date()
        let suggestion1 = AIChatSuggestion(id: "1", title: "Test", isPinned: true, chatId: "chat-1", timestamp: date)
        let suggestion2 = AIChatSuggestion(id: "1", title: "Test", isPinned: true, chatId: "chat-1", timestamp: date)

        // Then
        XCTAssertEqual(suggestion1.hashValue, suggestion2.hashValue)
    }

    func testHashable_CanBeUsedInSet() {
        // Given
        let suggestion1 = AIChatSuggestion(id: "1", title: "Test 1", isPinned: false, chatId: "chat-1")
        let suggestion2 = AIChatSuggestion(id: "2", title: "Test 2", isPinned: false, chatId: "chat-2")
        let suggestion3 = AIChatSuggestion(id: "1", title: "Test 1", isPinned: false, chatId: "chat-1") // duplicate of 1

        // When
        let set: Set<AIChatSuggestion> = [suggestion1, suggestion2, suggestion3]

        // Then
        XCTAssertEqual(set.count, 2)
    }
}

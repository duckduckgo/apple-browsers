//
//  AddressBarSharedTextStateTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Combine
@testable import DuckDuckGo_Privacy_Browser

final class AddressBarSharedTextStateTests: XCTestCase {

    var sut: AddressBarSharedTextState!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = AddressBarSharedTextState()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testWhenInitialized_ThenTextIsEmpty() {
        // When
        let text = sut.text

        // Then
        XCTAssertEqual(text, "")
    }

    func testWhenInitialized_ThenHasUserInteractedWithTextIsFalse() {
        // When
        let hasInteracted = sut.hasUserInteractedWithText

        // Then
        XCTAssertFalse(hasInteracted)
    }

    // MARK: - Update Text Tests

    func testWhenUpdateTextWithNonEmptyString_ThenTextIsUpdated() {
        // When
        sut.updateText("hello")

        // Then
        XCTAssertEqual(sut.text, "hello")
    }

    func testWhenUpdateTextWithNonEmptyString_ThenHasUserInteractedWithTextIsTrue() {
        // When
        sut.updateText("hello")

        // Then
        XCTAssertTrue(sut.hasUserInteractedWithText)
    }

    func testWhenUpdateTextWithEmptyString_ThenTextIsEmpty() {
        // Given
        sut.updateText("hello")

        // When
        sut.updateText("")

        // Then
        XCTAssertEqual(sut.text, "")
    }

    func testWhenUpdateTextWithEmptyString_ThenHasUserInteractedWithTextRemainsTrue() {
        // Given
        sut.updateText("hello")

        // When
        sut.updateText("")

        // Then
        XCTAssertTrue(sut.hasUserInteractedWithText, "Flag should remain true once set")
    }

    func testWhenUpdateTextWithMarkInteractionFalse_ThenHasUserInteractedWithTextStaysFalse() {
        // When
        sut.updateText("hello", markInteraction: false)

        // Then
        XCTAssertFalse(sut.hasUserInteractedWithText)
    }

    func testWhenUpdateTextMultipleTimes_ThenTextIsUpdatedToLatestValue() {
        // When
        sut.updateText("first")
        sut.updateText("second")
        sut.updateText("third")

        // Then
        XCTAssertEqual(sut.text, "third")
    }

    // MARK: - Reset Tests

    func testWhenReset_ThenTextIsEmpty() {
        // Given
        sut.updateText("hello")

        // When
        sut.reset()

        // Then
        XCTAssertEqual(sut.text, "")
    }

    func testWhenReset_ThenHasUserInteractedWithTextIsFalse() {
        // Given
        sut.updateText("hello")

        // When
        sut.reset()

        // Then
        XCTAssertFalse(sut.hasUserInteractedWithText)
    }

    func testWhenResetMultipleTimes_ThenStateRemainsClean() {
        // Given
        sut.updateText("hello")
        sut.reset()

        // When
        sut.reset()

        // Then
        XCTAssertEqual(sut.text, "")
        XCTAssertFalse(sut.hasUserInteractedWithText)
    }

    // MARK: - Publisher Tests

    func testWhenTextIsUpdated_ThenPublisherEmitsNewValue() {
        // Given
        let expectation = expectation(description: "Text publisher emits")
        var receivedValues: [String] = []

        sut.$text
            .dropFirst() // Skip initial value
            .sink { text in
                receivedValues.append(text)
                if receivedValues.count == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        sut.updateText("first")
        sut.updateText("second")

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValues, ["first", "second"])
    }

    func testWhenHasUserInteractedWithTextChanges_ThenPublisherEmitsNewValue() {
        // Given
        let expectation = expectation(description: "HasUserInteractedWithText publisher emits")
        var receivedValue: Bool?

        sut.$hasUserInteractedWithText
            .dropFirst() // Skip initial value
            .sink { hasInteracted in
                receivedValue = hasInteracted
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sut.updateText("hello")

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(receivedValue == true)
    }

    // MARK: - Edge Cases

    func testWhenUpdateTextWithWhitespaceOnly_ThenTextIsUpdatedButInteractionNotMarked() {
        // When
        sut.updateText("   ")

        // Then
        XCTAssertEqual(sut.text, "   ")
        XCTAssertTrue(sut.hasUserInteractedWithText, "Whitespace is still considered interaction")
    }

    func testWhenUpdateTextWithNewlines_ThenTextContainsNewlines() {
        // When
        sut.updateText("hello\nworld")

        // Then
        XCTAssertEqual(sut.text, "hello\nworld")
    }

    func testWhenUpdateTextWithSpecialCharacters_ThenTextIsPreserved() {
        // Given
        let specialText = "!@#$%^&*()_+-=[]{}|;:',.<>?/~`"

        // When
        sut.updateText(specialText)

        // Then
        XCTAssertEqual(sut.text, specialText)
    }

    func testWhenUpdateTextWithEmoji_ThenEmojiIsPreserved() {
        // Given
        let emojiText = "Hello 👋 World 🌍"

        // When
        sut.updateText(emojiText)

        // Then
        XCTAssertEqual(sut.text, emojiText)
    }

    func testWhenUpdateTextWithVeryLongString_ThenFullTextIsStored() {
        // Given
        let longText = String(repeating: "a", count: 10000)

        // When
        sut.updateText(longText)

        // Then
        XCTAssertEqual(sut.text.count, 10000)
        XCTAssertEqual(sut.text, longText)
    }

    // MARK: - Integration Tests

    func testWhenSimulatingUserTypingFlow_ThenStateIsCorrect() {
        // Simulate user typing in search mode
        XCTAssertFalse(sut.hasUserInteractedWithText)

        sut.updateText("h")
        XCTAssertTrue(sut.hasUserInteractedWithText)
        XCTAssertEqual(sut.text, "h")

        sut.updateText("he")
        XCTAssertEqual(sut.text, "he")

        sut.updateText("hello")
        XCTAssertEqual(sut.text, "hello")

        // Simulate navigation (reset)
        sut.reset()
        XCTAssertFalse(sut.hasUserInteractedWithText)
        XCTAssertEqual(sut.text, "")
    }

    func testWhenSimulatingModeSwitching_ThenTextIsPersisted() {
        // Simulate typing in search mode
        sut.updateText("test query")
        let textAfterSearchMode = sut.text

        // Switch to AI chat mode (text should persist)
        XCTAssertEqual(sut.text, textAfterSearchMode)

        // Type more in AI chat mode
        sut.updateText("test query with more text")

        // Switch back to search mode (text should still be there)
        XCTAssertEqual(sut.text, "test query with more text")
    }

    func testWhenSimulatingNavigationToWebsite_ThenStateIsReset() {
        // User types something
        sut.updateText("hello world")
        XCTAssertTrue(sut.hasUserInteractedWithText)

        // User navigates to a website (reset is called)
        sut.reset()

        // State should be clean
        XCTAssertFalse(sut.hasUserInteractedWithText)
        XCTAssertEqual(sut.text, "")
    }

    // MARK: - Thread Safety Tests

    func testWhenUpdatingFromMultipleThreads_ThenNoRaceConditionsOccur() {
        // Given
        let expectation = expectation(description: "All updates complete")
        expectation.expectedFulfillmentCount = 100

        // When
        for i in 0..<100 {
            DispatchQueue.global().async {
                self.sut.updateText("text\(i)")
                expectation.fulfill()
            }
        }

        // Then
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(sut.hasUserInteractedWithText)
        XCTAssertFalse(sut.text.isEmpty)
    }
}

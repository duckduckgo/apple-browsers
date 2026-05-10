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
import AIChat
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

    // MARK: - Duck.ai Mode Tests

    func testWhenInitialized_ThenIsInDuckAIModeIsFalse() {
        XCTAssertFalse(sut.isInDuckAIMode)
    }

    func testWhenSetDuckAIModeTrue_ThenIsInDuckAIModeIsTrue() {
        sut.setDuckAIMode(true)
        XCTAssertTrue(sut.isInDuckAIMode)
    }

    func testWhenSetDuckAIModeFalse_ThenIsInDuckAIModeIsFalse() {
        sut.setDuckAIMode(true)
        sut.setDuckAIMode(false)
        XCTAssertFalse(sut.isInDuckAIMode)
    }

    func testWhenResetCalled_ThenIsInDuckAIModeIsFalse() {
        sut.setDuckAIMode(true)
        sut.reset()
        XCTAssertFalse(sut.isInDuckAIMode)
    }

    func testWhenSetDuckAIModeToSameValue_ThenPublisherDoesNotEmitAgain() {
        sut.setDuckAIMode(true)
        let expectation = expectation(description: "Publisher does not emit for no-op assignment")
        expectation.isInverted = true

        sut.$isInDuckAIMode
            .dropFirst() // skip current value
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        sut.setDuckAIMode(true) // no-op

        wait(for: [expectation], timeout: 0.2)
    }

    func testWhenSetDuckAIModeChanges_ThenPublisherEmits() {
        let expectation = expectation(description: "Publisher emits on state change")
        var received: [Bool] = []

        sut.$isInDuckAIMode
            .dropFirst()
            .sink { value in
                received.append(value)
                if received.count == 2 { expectation.fulfill() }
            }
            .store(in: &cancellables)

        sut.setDuckAIMode(true)
        sut.setDuckAIMode(false)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received, [true, false])
    }

    func testWhenResetCalled_WithDuckAIModeAlreadyFalse_ThenPublisherDoesNotRedundantlyEmit() {
        let expectation = expectation(description: "Publisher does not emit for no-op reset")
        expectation.isInverted = true

        sut.$isInDuckAIMode
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        sut.reset() // isInDuckAIMode was already false

        wait(for: [expectation], timeout: 0.2)
    }

    func testWhenDuckAIModeEnabled_AndTextIsUpdated_ThenModeIsPreserved() {
        sut.setDuckAIMode(true)
        sut.updateText("prompt text")

        XCTAssertTrue(sut.isInDuckAIMode)
        XCTAssertEqual(sut.text, "prompt text")
    }

    // MARK: - AI Chat Tool Mode Tests

    func testWhenInitialized_ThenAIChatToolModeIsNil() {
        XCTAssertNil(sut.aiChatToolMode)
    }

    func testWhenSetAIChatToolModeToImageGeneration_ThenStored() {
        sut.setAIChatToolMode(.imageGeneration)
        XCTAssertEqual(sut.aiChatToolMode, .imageGeneration)
    }

    func testWhenSetAIChatToolModeToWebSearch_ThenStored() {
        sut.setAIChatToolMode(.webSearch)
        XCTAssertEqual(sut.aiChatToolMode, .webSearch)
    }

    func testWhenSetAIChatToolModeToNil_ThenCleared() {
        sut.setAIChatToolMode(.imageGeneration)
        sut.setAIChatToolMode(nil)
        XCTAssertNil(sut.aiChatToolMode)
    }

    func testWhenSetAIChatToolModeToSameValue_ThenPublisherDoesNotReemit() {
        sut.setAIChatToolMode(.imageGeneration)

        let expectation = expectation(description: "Publisher does not emit for no-op assignment")
        expectation.isInverted = true

        sut.$aiChatToolMode
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        sut.setAIChatToolMode(.imageGeneration) // no-op

        wait(for: [expectation], timeout: 0.2)
    }

    // MARK: - AI Chat Attachments Tests

    func testWhenInitialized_ThenAIChatAttachmentsIsEmpty() {
        XCTAssertTrue(sut.aiChatAttachments.isEmpty)
    }

    func testWhenSetAIChatAttachments_ThenStored() {
        let attachment = makeAttachment()
        sut.setAIChatAttachments([attachment])

        XCTAssertEqual(sut.aiChatAttachments.count, 1)
        XCTAssertEqual(sut.aiChatAttachments.first?.id, attachment.id)
    }

    func testWhenSetAIChatAttachmentsWithSameIds_ThenPublisherDoesNotReemit() {
        let attachment = makeAttachment()
        sut.setAIChatAttachments([attachment])

        let expectation = expectation(description: "Publisher does not emit when attachment ids are unchanged")
        expectation.isInverted = true

        sut.$aiChatAttachments
            .dropFirst()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)

        // Re-submit the SAME attachment instance — tab-switch restore path replays the current list; the
        // idempotency guard stops that from churning subscribers.
        sut.setAIChatAttachments([attachment])

        wait(for: [expectation], timeout: 0.2)
    }

    func testWhenSetAIChatAttachmentsWithDifferentIds_ThenPublisherReemits() {
        let first = makeAttachment()
        sut.setAIChatAttachments([first])

        let expectation = expectation(description: "Publisher emits when attachment list changes")
        var received: [[AIChatImageAttachment]] = []

        sut.$aiChatAttachments
            .dropFirst()
            .sink { attachments in
                received.append(attachments)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let second = makeAttachment()
        sut.setAIChatAttachments([first, second])

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received.first?.count, 2)
    }

    // MARK: - Selection Range Tests

    func testWhenInitialized_ThenSelectionRangeIsZero() {
        XCTAssertEqual(sut.selectionRange, NSRange(location: 0, length: 0))
    }

    func testWhenUpdateSelection_ThenStored() {
        sut.updateText("hello world")
        sut.updateSelection(NSRange(location: 6, length: 5))

        XCTAssertEqual(sut.selectionRange, NSRange(location: 6, length: 5))
    }

    func testWhenUpdateSelectionBeyondTextLength_ThenClampedToTextEnd() {
        sut.updateText("hi")
        sut.updateSelection(NSRange(location: 99, length: 0))

        XCTAssertEqual(sut.selectionRange, NSRange(location: 2, length: 0))
    }

    func testWhenUpdateSelectionUpperBoundBeyondTextLength_ThenLengthClamped() {
        sut.updateText("hello")
        sut.updateSelection(NSRange(location: 2, length: 10))

        XCTAssertEqual(sut.selectionRange, NSRange(location: 2, length: 3))
    }

    // MARK: - Reset with clearingDuckAIState Tests

    func testWhenResetWithClearingDuckAIStateTrue_ThenAllDuckAIFieldsCleared() {
        sut.updateText("prompt")
        sut.updateSelection(NSRange(location: 3, length: 0))
        sut.setDuckAIMode(true)
        sut.setAIChatToolMode(.imageGeneration)
        sut.setAIChatAttachments([makeAttachment()])

        sut.reset(clearingDuckAIState: true)

        XCTAssertEqual(sut.text, "")
        XCTAssertEqual(sut.selectionRange, NSRange(location: 0, length: 0))
        XCTAssertFalse(sut.hasUserInteractedWithText)
        XCTAssertFalse(sut.isInDuckAIMode)
        XCTAssertNil(sut.aiChatToolMode)
        XCTAssertTrue(sut.aiChatAttachments.isEmpty)
    }

    func testWhenResetWithClearingDuckAIStateFalse_ThenAllDuckAIStatePreserved() {
        // Tab-switch restore must not wipe ANY of the incoming tab's preserved duck.ai state — including
        // the prompt text and selection. The unfocused duck.ai bar (`applyDuckAIUnfocusedValue`) reads
        // from `text` to render the preserved prompt, so wiping it here would leave the bar showing the
        // empty placeholder on every tab-switch-back.
        sut.updateText("prompt")
        sut.updateSelection(NSRange(location: 3, length: 0))
        sut.setDuckAIMode(true)
        sut.setAIChatToolMode(.webSearch)
        let attachment = makeAttachment()
        sut.setAIChatAttachments([attachment])

        sut.reset(clearingDuckAIState: false)

        XCTAssertEqual(sut.text, "prompt", "Text should survive a tab-switch reset")
        XCTAssertEqual(sut.selectionRange, NSRange(location: 3, length: 0), "Selection should survive a tab-switch reset")
        XCTAssertTrue(sut.hasUserInteractedWithText, "User-interaction flag should survive a tab-switch reset")
        XCTAssertTrue(sut.isInDuckAIMode, "isInDuckAIMode should survive a tab-switch reset")
        XCTAssertEqual(sut.aiChatToolMode, .webSearch, "Tool mode should survive a tab-switch reset")
        XCTAssertEqual(sut.aiChatAttachments.count, 1, "Attachments should survive a tab-switch reset")
        XCTAssertEqual(sut.aiChatAttachments.first?.id, attachment.id)
    }

    func testWhenResetWithoutParameter_ThenBehavesAsClearingDuckAIStateTrue() {
        // Backwards-compat: existing call sites (e.g. in navigation path) use reset() without argument
        // and must continue to do a full clear.
        sut.setDuckAIMode(true)
        sut.setAIChatToolMode(.imageGeneration)

        sut.reset()

        XCTAssertFalse(sut.isInDuckAIMode)
        XCTAssertNil(sut.aiChatToolMode)
    }

    // MARK: - Helpers

    private func makeAttachment(id: UUID = UUID()) -> AIChatImageAttachment {
        AIChatImageAttachment(id: id, image: NSImage(), fileName: "\(id.uuidString).png", fileURL: nil, skipResize: true)
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

//
//  SwitchBarHandlerTests.swift
//  DuckDuckGoTests
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

import XCTest
@testable import Core
@testable import DuckDuckGo
import Combine
import PersistenceTestingUtils

final class SwitchBarHandlerTests: XCTestCase {

    private enum StorageKey {
        static let toggleState = "SwitchBarHandler.toggleState"
    }

    private var sut: SwitchBarHandler!
    private var mockVoiceSearchHelper: MockVoiceSearchHelper!
    private var mockStorage: MockKeyValueStore!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockVoiceSearchHelper = MockVoiceSearchHelper()
        mockStorage = MockKeyValueStore()
        cancellables = Set<AnyCancellable>()
        createSUT()
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        mockVoiceSearchHelper = nil
        mockStorage = nil
        super.tearDown()
    }

    private func createSUT() {
        sut = SwitchBarHandler(
            voiceSearchHelper: mockVoiceSearchHelper,
            storage: mockStorage
        )
    }

    // MARK: - Toggle State Persistence Tests
    /*
     Disable Toggle states while new approach is being evaluated
     https://app.asana.com/1/137249556945/project/72649045549333/task/1210814996510636?focus=true
     func testRestoreToggleState_WhenNoStoredValue_ShouldDefaultToSearch() {
     // Given: No stored value in storage
     mockStorage.clearAll()

     // When: Creating a new handler
     createSUT()

     // Then: Should default to search mode
     XCTAssertEqual(sut.currentToggleState, .search)
     }

     func testRestoreToggleState_WhenStoredValueIsSearch_ShouldRestoreSearch() {
     // Given: Stored value is "search"
     mockStorage.set(TextEntryMode.search.rawValue, forKey: StorageKey.toggleState)

     // When: Creating a new handler
     createSUT()

     // Then: Should restore search mode
     XCTAssertEqual(sut.currentToggleState, .search)
     }

     func testRestoreToggleState_WhenStoredValueIsAIChat_ShouldRestoreAIChat() {
     // Given: Stored value is "aiChat"
     mockStorage.set(TextEntryMode.aiChat.rawValue, forKey: StorageKey.toggleState)

     // When: Creating a new handler
     createSUT()

     // Then: Should restore aiChat mode
     XCTAssertEqual(sut.currentToggleState, .aiChat)
     }

     func testRestoreToggleState_WhenStoredValueIsInvalid_ShouldDefaultToSearch() {
     // Given: Stored value is invalid
     mockStorage.set("invalidValue", forKey: StorageKey.toggleState)

     // When: Creating a new handler
     createSUT()

     // Then: Should default to search mode
     XCTAssertEqual(sut.currentToggleState, .search)
     }

     func testRestoreToggleState_WhenStoredValueIsWrongType_ShouldDefaultToSearch() {
     // Given: Stored value is wrong type (number instead of string)
     mockStorage.set(123, forKey: StorageKey.toggleState)

     // When: Creating a new handler
     createSUT()

     // Then: Should default to search mode
     XCTAssertEqual(sut.currentToggleState, .search)
     }

     func testSaveToggleState_WhenSetToSearch_ShouldPersistSearchValue() {
     // Given: Handler is initialized
     createSUT()

     // When: Setting toggle state to search
     sut.setToggleState(.search)

     // Then: Should save "search" to storage
     XCTAssertEqual(mockStorage.object(forKey: StorageKey.toggleState) as? String, "search")
     }

     func testSaveToggleState_WhenSetToAIChat_ShouldPersistAIChatValue() {
     // Given: Handler is initialized
     createSUT()

     // When: Setting toggle state to aiChat
     sut.setToggleState(.aiChat)

     // Then: Should save "aiChat" to storage
     XCTAssertEqual(mockStorage.object(forKey: StorageKey.toggleState) as? String, "aiChat")
     }

     func testToggleStatePersistence_WhenMultipleChanges_ShouldPersistLatestValue() {
     // Given: Handler is initialized
     createSUT()

     // When: Making multiple changes
     sut.setToggleState(.search)
     sut.setToggleState(.aiChat)
     sut.setToggleState(.search)

     // Then: Should persist the latest value
     XCTAssertEqual(mockStorage.object(forKey: StorageKey.toggleState) as? String, "search")
     XCTAssertEqual(sut.currentToggleState, .search)
     }

     func testToggleStatePersistenceAcrossInstances_ShouldMaintainState() {
     // Given: First handler instance with aiChat mode
     sut.setToggleState(.aiChat)
     let firstInstanceState = sut.currentToggleState

     // When: Creating a new handler instance
     createSUT()

     // Then: New instance should restore the same state
     XCTAssertEqual(firstInstanceState, .aiChat)
     XCTAssertEqual(sut.currentToggleState, .aiChat)
     }

    // MARK: - Toggle State Publisher Tests

    func testToggleStatePublisher_WhenStateChanges_ShouldEmitNewValue() {
        // Given: Subscription to toggle state publisher
        var receivedStates: [TextEntryMode] = []
        sut.toggleStatePublisher
            .sink { receivedStates.append($0) }
            .store(in: &cancellables)

        // When: Changing toggle state
        sut.setToggleState(.aiChat)

        // Then: Should emit new state
        XCTAssertEqual(receivedStates.last, .aiChat)
    }

    func testToggleStatePublisher_InitialValue_ShouldBeCurrentState() {
        // Given: Handler with specific state
        mockStorage.set("aiChat", forKey: StorageKey.toggleState)
        createSUT()

        // When: Subscribing to toggle state publisher
        var receivedState: TextEntryMode?
        sut.toggleStatePublisher
            .sink { receivedState = $0 }
            .store(in: &cancellables)

        // Then: Should emit current state
        XCTAssertEqual(receivedState, .aiChat)
    }

    // MARK: - Text Functionality Tests

    func testUpdateCurrentText_ShouldUpdateCurrentText() {
        // Given: Handler is initialized
        createSUT()

        // When: Updating current text
        sut.updateCurrentText("test query")

        // Then: Should update current text
        XCTAssertEqual(sut.currentText, "test query")
    }

    func testCurrentTextPublisher_WhenTextChanges_ShouldEmitNewValue() {
        // Given: Subscription to current text publisher
        var receivedTexts: [String] = []
        sut.currentTextPublisher
            .sink { receivedTexts.append($0) }
            .store(in: &cancellables)

        // When: Updating text
        sut.updateCurrentText("new text")

        // Then: Should emit new text
        XCTAssertEqual(receivedTexts.last, "new text")
    }

    func testSubmitText_WithValidText_ShouldEmitSubmission() {
        // Given: Subscription to text submission publisher
        var submissions: [(text: String, mode: TextEntryMode)] = []
        sut.textSubmissionPublisher
            .sink { submissions.append($0) }
            .store(in: &cancellables)

        // When: Submitting text
        sut.submitText("test query")

        // Then: Should emit submission with current mode
        XCTAssertEqual(submissions.count, 1)
        XCTAssertEqual(submissions.first?.text, "test query")
        XCTAssertEqual(submissions.first?.mode, .search)
    }

    func testSubmitText_WithEmptyText_ShouldNotEmitSubmission() {
        // Given: Subscription to text submission publisher
        var submissions: [(text: String, mode: TextEntryMode)] = []
        sut.textSubmissionPublisher
            .sink { submissions.append($0) }
            .store(in: &cancellables)

        // When: Submitting empty text
        sut.submitText("")

        // Then: Should not emit submission
        XCTAssertEqual(submissions.count, 0)
    }

    func testSubmitText_WithWhitespaceOnlyText_ShouldNotEmitSubmission() {
        // Given: Subscription to text submission publisher
        var submissions: [(text: String, mode: TextEntryMode)] = []
        sut.textSubmissionPublisher
            .sink { submissions.append($0) }
            .store(in: &cancellables)

        // When: Submitting whitespace-only text
        sut.submitText("   \n\t  ")

        // Then: Should not emit submission
        XCTAssertEqual(submissions.count, 0)
    }

    func testClearText_ShouldResetCurrentText() {
        // Given: Handler with text
        sut.updateCurrentText("some text")

        // When: Clearing text
        sut.clearText()

        // Then: Should reset current text
        XCTAssertEqual(sut.currentText, "")
    }

    // MARK: - Voice Search Tests

    func testIsVoiceSearchEnabled_ShouldReturnHelperValue() {
        // Given: Voice search helper with specific enabled state
        mockVoiceSearchHelper.isVoiceSearchEnabled = true

        // When: Checking if voice search is enabled
        let isEnabled = sut.isVoiceSearchEnabled

        // Then: Should return helper's value
        XCTAssertTrue(isEnabled)
    }

    func testMicrophoneButtonTapped_ShouldEmitEvent() {
        // Given: Subscription to microphone button tapped publisher
        var tappedCount = 0
        sut.microphoneButtonTappedPublisher
            .sink { _ in tappedCount += 1 }
            .store(in: &cancellables)

        // When: Tapping microphone button
        sut.microphoneButtonTapped()

        // Then: Should emit event
        XCTAssertEqual(tappedCount, 1)
    }

    // MARK: - Force Web Search Tests

    func testToggleForceWebSearch_ShouldToggleValue() {
        // Given: Handler with initial force web search state
        let initialState = sut.forceWebSearch

        // When: Toggling force web search
        sut.toggleForceWebSearch()

        // Then: Should toggle the value
        XCTAssertEqual(sut.forceWebSearch, !initialState)
    }

    func testSetForceWebSearch_ShouldSetSpecificValue() {
        // Given: Handler is initialized
        createSUT()

        // When: Setting force web search to true
        sut.setForceWebSearch(true)

        // Then: Should set the value
        XCTAssertTrue(sut.forceWebSearch)

        // When: Setting force web search to false
        sut.setForceWebSearch(false)

        // Then: Should set the value
        XCTAssertFalse(sut.forceWebSearch)
    }

    // MARK: - Integration Tests

    func testEndToEndToggleStatePersistence_ShouldWorkCorrectly() {
        // Given: Fresh storage
        mockStorage.clearAll()

        // When: Creating handler, changing state, and recreating
        createSUT()
        XCTAssertEqual(sut.currentToggleState, .search) // Default

        sut.setToggleState(.aiChat)
        XCTAssertEqual(sut.currentToggleState, .aiChat)

        // Create new instance to test persistence
        createSUT()

        // Then: Should restore the saved state
        XCTAssertEqual(sut.currentToggleState, .aiChat)
    }

    func testTextSubmissionWithDifferentModes_ShouldEmitCorrectMode() {
        // Given: Subscription to text submission publisher
        var submissions: [(text: String, mode: TextEntryMode)] = []
        sut.textSubmissionPublisher
            .sink { submissions.append($0) }
            .store(in: &cancellables)

        // When: Submitting text in search mode
        sut.setToggleState(.search)
        sut.submitText("search query")

        // Then: Should emit with search mode
        XCTAssertEqual(submissions.last?.mode, .search)

        // When: Changing to AI chat mode and submitting
        sut.setToggleState(.aiChat)
        sut.submitText("ai chat query")

        // Then: Should emit with aiChat mode
        XCTAssertEqual(submissions.last?.mode, .aiChat)
    }
     */
}

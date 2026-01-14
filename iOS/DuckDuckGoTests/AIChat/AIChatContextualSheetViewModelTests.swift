//
//  AIChatContextualSheetViewModelTests.swift
//  DuckDuckGo
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
import Combine
@testable import DuckDuckGo

final class AIChatContextualSheetViewModelTests: XCTestCase {

    private var sut: AIChatContextualSheetViewModel!
    private var mockSettings: MockAIChatSettingsProvider!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockSettings = MockAIChatSettingsProvider()
        mockSettings.aiChatURL = URL(string: "https://duck.ai")!
        cancellables = []
    }

    override func tearDown() {
        sut = nil
        mockSettings = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialStateWithNoExistingChat() {
        // When
        sut = AIChatContextualSheetViewModel(settings: mockSettings)

        // Then
        XCTAssertFalse(sut.hasSubmittedPrompt)
        XCTAssertNil(sut.contextualChatURL)
        XCTAssertTrue(sut.isExpandEnabled)
        XCTAssertFalse(sut.isNewChatButtonVisible)
    }

    func testInitialStateWithExistingChat() {
        // When
        sut = AIChatContextualSheetViewModel(settings: mockSettings, hasExistingChat: true)

        // Then
        XCTAssertTrue(sut.hasSubmittedPrompt)
        XCTAssertTrue(sut.isNewChatButtonVisible)
    }

    // MARK: - expandURL Tests

    func testExpandURLReturnsBaseURLWhenNoContextualChatURL() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)

        // When
        let url = sut.expandURL()

        // Then
        XCTAssertEqual(url, mockSettings.aiChatURL)
    }

    func testExpandURLReturnsContextualChatURLWhenAvailable() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        let chatURL = URL(string: "https://duck.ai/chat/abc123")!
        sut.didUpdateContextualChatURL(chatURL)

        // When
        let url = sut.expandURL()

        // Then
        XCTAssertEqual(url, chatURL)
    }

    func testExpandURLPreservesChatURLAfterNewChat() {
        // Given - User had a chat, started new chat, then got a new chat URL
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        let originalChatURL = URL(string: "https://duck.ai/chat/original123")!
        sut.didSubmitPrompt()
        sut.didUpdateContextualChatURL(originalChatURL)

        // When - User starts new chat and types directly in web view (no didSubmitPrompt call)
        sut.didStartNewChat()
        let newChatURL = URL(string: "https://duck.ai/chat/new456")!
        sut.didUpdateContextualChatURL(newChatURL)

        // Then - expand should use the new chat URL, not the base URL
        XCTAssertEqual(sut.expandURL(), newChatURL)
    }

    // MARK: - didSubmitPrompt Tests

    func testDidSubmitPromptSetsHasSubmittedPromptAndShowsNewChatButton() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        XCTAssertFalse(sut.hasSubmittedPrompt)
        XCTAssertFalse(sut.isNewChatButtonVisible)

        // When
        sut.didSubmitPrompt()

        // Then
        XCTAssertTrue(sut.hasSubmittedPrompt)
        XCTAssertTrue(sut.isNewChatButtonVisible)
    }

    // MARK: - didUpdateContextualChatURL Tests

    func testDidUpdateContextualChatURLUpdatesURL() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        let chatURL = URL(string: "https://duck.ai/chat/abc123")!

        // When
        sut.didUpdateContextualChatURL(chatURL)

        // Then
        XCTAssertEqual(sut.contextualChatURL, chatURL)
    }

    func testDidUpdateContextualChatURLDoesNotResetHasSubmittedPromptWhenURLGoesNil() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        let chatURL = URL(string: "https://duck.ai/chat/abc123")!
        sut.didSubmitPrompt()
        sut.didUpdateContextualChatURL(chatURL)
        XCTAssertTrue(sut.hasSubmittedPrompt)

        // When - URL goes nil (e.g., during navigation)
        sut.didUpdateContextualChatURL(nil)

        // Then - hasSubmittedPrompt should NOT be reset (only explicit didStartNewChat resets it)
        XCTAssertTrue(sut.hasSubmittedPrompt)
        XCTAssertNil(sut.contextualChatURL)
    }

    // MARK: - didStartNewChat Tests

    func testDidStartNewChatResetsState() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        let chatURL = URL(string: "https://duck.ai/chat/abc123")!
        sut.didSubmitPrompt()
        sut.didUpdateContextualChatURL(chatURL)
        XCTAssertTrue(sut.hasSubmittedPrompt)
        XCTAssertNotNil(sut.contextualChatURL)

        // When
        sut.didStartNewChat()

        // Then
        XCTAssertFalse(sut.hasSubmittedPrompt)
        XCTAssertNil(sut.contextualChatURL)
        XCTAssertTrue(sut.isExpandEnabled)
    }

    // MARK: - isExpandEnabled Tests

    func testIsExpandEnabledIsTrueInitially() {
        // When
        sut = AIChatContextualSheetViewModel(settings: mockSettings)

        // Then
        XCTAssertTrue(sut.isExpandEnabled)
    }

    func testIsExpandEnabledBecomesFalseAfterPromptSubmissionWithoutChatURL() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)

        // When
        sut.didSubmitPrompt()

        // Then
        XCTAssertFalse(sut.isExpandEnabled)
    }

    func testIsExpandEnabledBecomesTrueWhenChatURLIsSet() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        sut.didSubmitPrompt()
        XCTAssertFalse(sut.isExpandEnabled)

        // When
        let chatURL = URL(string: "https://duck.ai/chat/abc123")!
        sut.didUpdateContextualChatURL(chatURL)

        // Then
        XCTAssertTrue(sut.isExpandEnabled)
    }

    func testIsExpandEnabledPublishesChanges() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        var receivedValues: [Bool] = []

        sut.$isExpandEnabled
            .sink { receivedValues.append($0) }
            .store(in: &cancellables)

        // When
        sut.didSubmitPrompt()
        let chatURL = URL(string: "https://duck.ai/chat/abc123")!
        sut.didUpdateContextualChatURL(chatURL)

        // Then
        XCTAssertEqual(receivedValues, [true, false, true])
    }

    // MARK: - createAttachActions Tests

    func testCreateAttachActionsReturnsOneAction() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        var actionCalled = false

        // When
        let actions = sut.createAttachActions {
            actionCalled = true
        }

        // Then
        XCTAssertEqual(actions.count, 1)
        XCTAssertNotNil(actions.first?.icon)

        // When handler is called
        actions.first?.handler()

        // Then
        XCTAssertTrue(actionCalled)
    }

    // MARK: - createContextChipView Tests

    func testCreateContextChipViewReturnsNilWhenNoPageContext() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        XCTAssertNil(sut.pageContext)

        // When
        let chipView = sut.createContextChipView { }

        // Then
        XCTAssertNil(chipView)
    }

    func testCreateContextChipViewReturnsConfiguredViewWhenPageContextIsSet() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings)
        sut.pageContext = AIChatContextualSheetViewModel.PageContext(
            title: "Test Page",
            favicon: nil
        )
        var removeCalled = false

        // When
        let chipView = sut.createContextChipView {
            removeCalled = true
        }

        // Then
        XCTAssertNotNil(chipView)

        // When onRemove is called
        chipView?.onRemove?()

        // Then
        XCTAssertTrue(removeCalled)
    }

    // MARK: - isAutomaticContextAttachmentEnabled Tests

    func testIsAutomaticContextAttachmentEnabledReflectsSettings() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sut = AIChatContextualSheetViewModel(settings: mockSettings)

        // Then
        XCTAssertTrue(sut.isAutomaticContextAttachmentEnabled)

        // When
        mockSettings.isAutomaticContextAttachmentEnabled = false

        // Then
        XCTAssertFalse(sut.isAutomaticContextAttachmentEnabled)
    }

    // MARK: - setInitialContextualChatURL Tests

    func testSetInitialContextualChatURLSetsURLAndUpdatesExpandState() {
        // Given
        sut = AIChatContextualSheetViewModel(settings: mockSettings, hasExistingChat: true)
        XCTAssertFalse(sut.isExpandEnabled) // hasSubmittedPrompt is true, no chat URL yet

        // When
        let chatURL = URL(string: "https://duck.ai/chat/abc123")!
        sut.setInitialContextualChatURL(chatURL)

        // Then
        XCTAssertEqual(sut.contextualChatURL, chatURL)
        XCTAssertTrue(sut.isExpandEnabled)
    }
}

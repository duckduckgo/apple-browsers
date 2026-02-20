//
//  AIChatContextualChatSessionStateTests.swift
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
@testable import AIChat

@MainActor
final class AIChatContextualChatSessionStateTests: XCTestCase {

    private var sessionState: AIChatContextualChatSessionState!
    private var mockSettings: MockAIChatSettingsProvider!
    private var mockPixelHandler: MockContextualModePixelHandler!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockSettings = MockAIChatSettingsProvider()
        mockPixelHandler = MockContextualModePixelHandler()
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler
        )
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sessionState = nil
        mockSettings = nil
        mockPixelHandler = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertEqual(sessionState.frontendState, .noChat)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.isShowingNativeInput)
        XCTAssertNil(sessionState.contextualChatURL)
        XCTAssertNil(sessionState.latestContext)
    }

    func testInitialViewState() {
        let viewState = sessionState.viewState
        XCTAssertTrue(viewState.isExpandButtonEnabled)
        XCTAssertFalse(viewState.shouldShowNewChatButton)
        XCTAssertEqual(viewState.chipState, .placeholder)
        if case .nativeInput = viewState.content {
            // Expected
        } else {
            XCTFail("Expected nativeInput content mode")
        }
    }

    // MARK: - Prompt Submission Tests

    func testHandlePromptSubmissionWithAttachedChip() {
        // Given
        let context = makeTestContext()
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(context)

        // When
        sessionState.handlePromptSubmission("Hello")

        // Then
        XCTAssertEqual(sessionState.frontendState, .chatWithInitialContext)
        XCTAssertFalse(sessionState.isShowingNativeInput)
        XCTAssertTrue(mockPixelHandler.promptSubmittedWithContextFired)
    }

    func testHandlePromptSubmissionWithPlaceholderChip() {
        // Given - chip stays as placeholder (no context attached)

        // When
        sessionState.handlePromptSubmission("Hello")

        // Then
        XCTAssertEqual(sessionState.frontendState, .chatWithoutInitialContext)
        XCTAssertFalse(sessionState.isShowingNativeInput)
        XCTAssertTrue(mockPixelHandler.promptSubmittedWithoutContextFired)
    }

    func testHandlePromptSubmissionWithURL() {
        // Given
        let url = URL(string: "https://duck.ai/chat/123")!

        // When
        sessionState.handlePromptSubmission("Hello", url: url)

        // Then
        XCTAssertEqual(sessionState.contextualChatURL, url)
    }

    func testHandlePromptSubmissionIgnoredInRestoredState() {
        // Given
        let url = URL(string: "https://duck.ai/chat/123")!
        sessionState.restoreChat(with: url)
        XCTAssertEqual(sessionState.frontendState, .restoredChat)

        // When
        sessionState.handlePromptSubmission("Hello")

        // Then - state unchanged
        XCTAssertEqual(sessionState.frontendState, .restoredChat)
    }

    // MARK: - Reset Tests

    func testResetToNoChat() {
        // Given
        sessionState.handlePromptSubmission("Hello")
        XCTAssertEqual(sessionState.frontendState, .chatWithoutInitialContext)

        // When
        sessionState.resetToNoChat()

        // Then
        XCTAssertEqual(sessionState.frontendState, .noChat)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertNil(sessionState.contextualChatURL)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.isShowingNativeInput)
    }

    func testResetToNoChatClearsManualAttachState() {
        // Given
        sessionState.beginManualAttach()

        // When
        sessionState.resetToNoChat()

        // Then
        XCTAssertTrue(mockPixelHandler.manualAttachEnded)
    }

    // MARK: - Chip Removal Tests

    func testHandleChipRemovalWhenAttached() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let context = makeTestContext()
        sessionState.updateContext(context)

        // When
        let result = sessionState.handleChipRemoval()

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(mockPixelHandler.pageContextRemovedNativeFired)
    }

    func testHandleChipRemovalWhenPlaceholder() {
        // Given - chip is placeholder by default

        // When
        let result = sessionState.handleChipRemoval()

        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testDowngradeToPlaceholder() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let context = makeTestContext()
        sessionState.updateContext(context)

        // When
        sessionState.downgradeToPlaceholder()

        // Then
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)
    }

    // MARK: - Context Update Tests

    func testUpdateContextWithAutoAttachEnabled() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let context = makeTestContext()

        // When
        sessionState.updateContext(context)

        // Then
        XCTAssertEqual(sessionState.latestContext?.title, context.title)
        if case .attached(let attachedContext) = sessionState.chipState {
            XCTAssertEqual(attachedContext.title, context.title)
        } else {
            XCTFail("Expected attached chip state")
        }
        XCTAssertTrue(mockPixelHandler.pageContextAutoAttachedFired)
    }

    func testUpdateContextWithAutoAttachDisabled() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = false
        let context = makeTestContext()

        // When
        sessionState.updateContext(context)

        // Then
        XCTAssertEqual(sessionState.latestContext?.title, context.title)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertFalse(mockPixelHandler.pageContextAutoAttachedFired)
    }

    func testUpdateContextWithNilClearsState() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext())

        // When
        sessionState.updateContext(nil)

        // Then
        XCTAssertNil(sessionState.latestContext)
        XCTAssertEqual(sessionState.chipState, .placeholder)
    }

    func testUpdateContextDoesNotAutoAttachWhenUserDowngraded() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let context1 = makeTestContext(title: "Page 1")
        sessionState.updateContext(context1)
        _ = sessionState.handleChipRemoval() // user downgraded
        mockPixelHandler.reset()

        // When
        let context2 = makeTestContext(title: "Page 2")
        sessionState.updateContext(context2)

        // Then
        XCTAssertEqual(sessionState.latestContext?.title, "Page 2")
        XCTAssertEqual(sessionState.chipState, .placeholder) // Still placeholder
        XCTAssertFalse(mockPixelHandler.pageContextAutoAttachedFired)
    }

    // MARK: - Manual Attach Tests

    func testBeginManualAttach() {
        // When
        sessionState.beginManualAttach()

        // Then
        XCTAssertTrue(mockPixelHandler.manualAttachBegan)
    }

    func testManualAttachFromNativeInput() {
        // Given
        sessionState.beginManualAttach(fromFrontend: false)
        let context = makeTestContext()

        // When
        sessionState.updateContext(context)

        // Then
        if case .attached = sessionState.chipState {
            // Expected
        } else {
            XCTFail("Expected attached chip state")
        }
        XCTAssertTrue(mockPixelHandler.pageContextManuallyAttachedNativeFired)
        XCTAssertTrue(mockPixelHandler.manualAttachEnded)
    }

    func testManualAttachFromFrontend() {
        // Given
        sessionState.handlePromptSubmission("Hello") // Start chat without context
        sessionState.beginManualAttach(fromFrontend: true)
        let context = makeTestContext()

        // When
        sessionState.updateContext(context)

        // Then
        XCTAssertTrue(mockPixelHandler.pageContextManuallyAttachedFrontendFired)
        XCTAssertTrue(mockPixelHandler.manualAttachEnded)
    }

    func testCancelManualAttach() {
        // Given
        sessionState.beginManualAttach()

        // When
        sessionState.cancelManualAttach()

        // Then
        XCTAssertTrue(mockPixelHandler.manualAttachEnded)
    }

    // MARK: - Navigation Tests

    func testNotifyPageChangedClearsUserDowngradeFlag() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext())
        _ = sessionState.handleChipRemoval()
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // When
        sessionState.notifyPageChanged()

        // Then
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testUpdateContextAfterNavigationFiresPixel() {
        // Given
        sessionState.notifyPageChanged()
        let context = makeTestContext()

        // When
        sessionState.updateContext(context)

        // Then
        XCTAssertTrue(mockPixelHandler.pageContextUpdatedOnNavigationFired)
    }

    // MARK: - Restore Chat Tests

    func testRestoreChat() {
        // Given
        let url = URL(string: "https://duck.ai/chat/123")!

        // When
        sessionState.restoreChat(with: url)

        // Then
        XCTAssertEqual(sessionState.frontendState, .restoredChat)
        XCTAssertEqual(sessionState.contextualChatURL, url)
        XCTAssertFalse(sessionState.isShowingNativeInput)
    }

    // MARK: - URL Update Tests

    func testUpdateContextualChatURL() {
        // Given
        let url = URL(string: "https://duck.ai/chat/456")!

        // When
        sessionState.updateContextualChatURL(url)

        // Then
        XCTAssertEqual(sessionState.contextualChatURL, url)
    }

    func testClearContextualChatURL() {
        // Given
        sessionState.updateContextualChatURL(URL(string: "https://duck.ai/chat/456")!)

        // When
        sessionState.updateContextualChatURL(nil)

        // Then
        XCTAssertNil(sessionState.contextualChatURL)
    }

    // MARK: - Auto-Attach Setting Refresh Tests

    func testRefreshAutoAttachSettingClearsUserDowngradeWhenEnabled() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext())
        _ = sessionState.handleChipRemoval()
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // Simulate setting being toggled off then on
        mockSettings.isAutomaticContextAttachmentEnabled = false
        sessionState.refreshAutoAttachSetting()
        mockSettings.isAutomaticContextAttachmentEnabled = true

        // When
        sessionState.refreshAutoAttachSetting()

        // Then
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    // MARK: - Derived Properties Tests

    func testHasActiveChat() {
        XCTAssertFalse(sessionState.hasActiveChat)

        sessionState.handlePromptSubmission("Hello")
        XCTAssertTrue(sessionState.hasActiveChat)

        sessionState.resetToNoChat()
        XCTAssertFalse(sessionState.hasActiveChat)
    }

    func testIsNewChatButtonVisible() {
        XCTAssertFalse(sessionState.isNewChatButtonVisible)

        sessionState.handlePromptSubmission("Hello")
        XCTAssertTrue(sessionState.isNewChatButtonVisible)
    }

    func testIsExpandEnabled() {
        // No chat, no URL - expand enabled
        XCTAssertTrue(sessionState.isExpandEnabled)

        // Chat started, no URL - expand disabled
        sessionState.handlePromptSubmission("Hello")
        XCTAssertFalse(sessionState.isExpandEnabled)

        // Chat started with URL - expand enabled
        sessionState.updateContextualChatURL(URL(string: "https://duck.ai/chat/123")!)
        XCTAssertTrue(sessionState.isExpandEnabled)
    }

    func testHasContext() {
        XCTAssertFalse(sessionState.hasContext)

        sessionState.updateContext(makeTestContext())
        XCTAssertTrue(sessionState.hasContext)

        sessionState.updateContext(nil)
        XCTAssertFalse(sessionState.hasContext)
    }

    // MARK: - View State Publisher Tests

    func testViewStatePublisherEmitsChanges() {
        // Given
        let expectation = expectation(description: "View state publishes changes")
        var receivedStates: [SheetViewState] = []

        sessionState.$viewState
            .sink { state in
                receivedStates.append(state)
                if receivedStates.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.handlePromptSubmission("Hello")
        sessionState.resetToNoChat()

        waitForExpectations(timeout: 1.0)

        // Then
        XCTAssertEqual(receivedStates.count, 3)
        // Initial state
        if case .nativeInput = receivedStates[0].content {} else { XCTFail("Expected nativeInput") }
        // After prompt submission
        if case .webView = receivedStates[1].content {} else { XCTFail("Expected webView") }
        // After reset
        if case .nativeInput = receivedStates[2].content {} else { XCTFail("Expected nativeInput") }
    }

    // MARK: - Effects Publisher Tests

    func testEffectsPublisherEmitsSubmitPrompt() {
        // Given
        let expectation = expectation(description: "Effects publishes submit prompt")
        var receivedEffect: SheetEffect?

        sessionState.effects
            .sink { effect in
                receivedEffect = effect
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sessionState.handlePromptSubmission("Hello world")

        waitForExpectations(timeout: 1.0)

        // Then
        if case .submitPrompt(let prompt, let context) = receivedEffect {
            XCTAssertEqual(prompt, "Hello world")
            XCTAssertNil(context)
        } else {
            XCTFail("Expected submitPrompt effect")
        }
    }

    func testEffectsPublisherEmitsSubmitPromptWithContext() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext())

        let expectation = expectation(description: "Effects publishes submit prompt with context")
        var receivedEffect: SheetEffect?

        sessionState.effects
            .sink { effect in
                receivedEffect = effect
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sessionState.handlePromptSubmission("Hello world")

        waitForExpectations(timeout: 1.0)

        // Then
        if case .submitPrompt(let prompt, let context) = receivedEffect {
            XCTAssertEqual(prompt, "Hello world")
            XCTAssertNotNil(context)
            XCTAssertEqual(context?.title, "Test Page")
        } else {
            XCTFail("Expected submitPrompt effect")
        }
    }

    func testEffectsPublisherEmitsClearPromptOnReset() {
        // Given
        sessionState.handlePromptSubmission("Hello")

        let expectation = expectation(description: "Effects publishes clear prompt")
        var receivedEffect: SheetEffect?

        sessionState.effects
            .sink { effect in
                receivedEffect = effect
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sessionState.resetToNoChat()

        waitForExpectations(timeout: 1.0)

        // Then
        if case .clearPrompt = receivedEffect {
            // Expected
        } else {
            XCTFail("Expected clearPrompt effect")
        }
    }

    func testEffectsPublisherEmitsPushContextToFrontend() {
        // Given
        sessionState.handlePromptSubmission("Hello") // Start chat without context
        sessionState.beginManualAttach(fromFrontend: true)

        let expectation = expectation(description: "Effects publishes push context")
        var receivedEffect: SheetEffect?

        sessionState.effects
            .sink { effect in
                if case .pushContextToFrontend = effect {
                    receivedEffect = effect
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.updateContext(makeTestContext())

        waitForExpectations(timeout: 1.0)

        // Then
        if case .pushContextToFrontend(let contextData) = receivedEffect {
            XCTAssertEqual(contextData.title, "Test Page")
        } else {
            XCTFail("Expected pushContextToFrontend effect")
        }
    }

    func testRequestWebViewReloadEmitsEffect() {
        // Given
        let expectation = expectation(description: "Effects publishes reload")
        var receivedEffect: SheetEffect?

        sessionState.effects
            .sink { effect in
                receivedEffect = effect
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        sessionState.requestWebViewReload()

        waitForExpectations(timeout: 1.0)

        // Then
        if case .reloadWebView = receivedEffect {
            // Expected
        } else {
            XCTFail("Expected reloadWebView effect")
        }
    }

    // MARK: - Complex Scenario Tests

    func testCompleteUserDowngradeAndUpgradeCycle() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext())

        // User removes chip
        let shouldShowPlaceholder = sessionState.handleChipRemoval()
        XCTAssertTrue(shouldShowPlaceholder)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // Navigation clears downgrade flag
        sessionState.notifyPageChanged()
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)

        // New context auto-attaches again
        sessionState.updateContext(makeTestContext(title: "New Page"))
        if case .attached = sessionState.chipState {
            // Expected
        } else {
            XCTFail("Expected attached chip state after navigation")
        }
    }

    func testNewChatFlowWithAutoAttachOn() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext())
        sessionState.handlePromptSubmission("Hello")

        // When - start new chat
        sessionState.resetToNoChat()

        // Then
        XCTAssertEqual(sessionState.frontendState, .noChat)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.isShowingNativeInput)
    }

    func testContextPushingOnlyAllowedForChatWithoutInitialContext() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true

        // No chat - context not pushed
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext())

        var pushedToFrontend = false
        sessionState.effects
            .sink { effect in
                if case .pushContextToFrontend = effect {
                    pushedToFrontend = true
                }
            }
            .store(in: &cancellables)

        // Reset and start chat without context
        sessionState.resetToNoChat()
        sessionState.handlePromptSubmission("Hello")
        XCTAssertEqual(sessionState.frontendState, .chatWithoutInitialContext)

        // Manual attach should push to frontend
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(title: "New context"))

        // Give time for effect to be emitted
        let expectation = expectation(description: "Wait for effect")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertTrue(pushedToFrontend)
    }

    // MARK: - Helpers

    private func makeTestContext(title: String = "Test Page") -> AIChatPageContext {
        let contextData = AIChatPageContextData(
            title: title,
            favicon: [],
            url: "https://example.com",
            content: "Test content",
            truncated: false,
            fullContentLength: 12
        )
        return AIChatPageContext(contextData: contextData, favicon: nil)
    }
}

// MARK: - Mock Pixel Handler

private final class MockContextualModePixelHandler: AIChatContextualModePixelFiring {
    var sheetOpenedFired = false
    var sheetDismissedFired = false
    var sessionRestoredFired = false
    var expandButtonTappedFired = false
    var newChatButtonTappedFired = false
    var quickActionSummarizeSelectedFired = false
    var pageContextPlaceholderShownFired = false
    var pageContextPlaceholderTappedFired = false
    var pageContextAutoAttachedFired = false
    var pageContextUpdatedOnNavigationFired = false
    var pageContextManuallyAttachedNativeFired = false
    var pageContextManuallyAttachedFrontendFired = false
    var pageContextRemovedNativeFired = false
    var pageContextRemovedFrontendFired = false
    var promptSubmittedWithContextFired = false
    var promptSubmittedWithoutContextFired = false
    var manualAttachBegan = false
    var manualAttachEnded = false
    var isManualAttachInProgress: Bool = false

    func fireSheetOpened() { sheetOpenedFired = true }
    func fireSheetDismissed() { sheetDismissedFired = true }
    func fireSessionRestored() { sessionRestoredFired = true }
    func fireExpandButtonTapped() { expandButtonTappedFired = true }
    func fireNewChatButtonTapped() { newChatButtonTappedFired = true }
    func fireQuickActionSummarizeSelected() { quickActionSummarizeSelectedFired = true }
    func firePageContextPlaceholderShown() { pageContextPlaceholderShownFired = true }
    func firePageContextPlaceholderTapped() { pageContextPlaceholderTappedFired = true }
    func firePageContextAutoAttached() { pageContextAutoAttachedFired = true }
    func firePageContextUpdatedOnNavigation(url: String) { pageContextUpdatedOnNavigationFired = true }
    func firePageContextManuallyAttachedNative() { pageContextManuallyAttachedNativeFired = true }
    func firePageContextManuallyAttachedFrontend() { pageContextManuallyAttachedFrontendFired = true }
    func firePageContextRemovedNative() { pageContextRemovedNativeFired = true }
    func firePageContextRemovedFrontend() { pageContextRemovedFrontendFired = true }
    func firePageContextCollectionEmpty() {}
    func firePageContextCollectionUnavailable() {}
    func firePromptSubmittedWithContext() { promptSubmittedWithContextFired = true }
    func firePromptSubmittedWithoutContext() { promptSubmittedWithoutContextFired = true }
    func beginManualAttach() { manualAttachBegan = true; isManualAttachInProgress = true }
    func endManualAttach() { manualAttachEnded = true; isManualAttachInProgress = false }

    func reset() {
        sheetOpenedFired = false
        sheetDismissedFired = false
        sessionRestoredFired = false
        expandButtonTappedFired = false
        newChatButtonTappedFired = false
        quickActionSummarizeSelectedFired = false
        pageContextPlaceholderShownFired = false
        pageContextPlaceholderTappedFired = false
        pageContextAutoAttachedFired = false
        pageContextUpdatedOnNavigationFired = false
        pageContextManuallyAttachedNativeFired = false
        pageContextManuallyAttachedFrontendFired = false
        pageContextRemovedNativeFired = false
        pageContextRemovedFrontendFired = false
        promptSubmittedWithContextFired = false
        promptSubmittedWithoutContextFired = false
        manualAttachBegan = false
        manualAttachEnded = false
        isManualAttachInProgress = false
    }
}

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
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockSettings = MockAIChatSettingsProvider()
        mockPixelHandler = MockContextualModePixelHandler()
        mockFeatureFlagger = MockFeatureFlagger()
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger
        )
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sessionState = nil
        mockSettings = nil
        mockPixelHandler = nil
        mockFeatureFlagger = nil
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

    func testUpdateContextWithUnifiedToggleInputAutoAttachEnabledFiresPixel() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true)
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

    /// Navigating to a non-attachable page (e.g. a PDF) clears via a nil update; the persistent
    /// UTI host chip must be cleared too, or the previous page's context rides the next prompt.
    func testUpdateContextWithNilDeliversUTIChipClear() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(title: "Previous Page"))

        var receivedEffect: SheetEffect?
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    receivedEffect = effect
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.updateContext(nil)

        // Then
        if case .deliverPageContext(let contextData, let targets) = receivedEffect {
            XCTAssertNil(contextData)
            XCTAssertTrue(targets.contains(.utiChip))
        } else {
            XCTFail("Expected deliverPageContext effect clearing the UTI chip")
        }
    }

    func testUpdateContextWithIdleNilDoesNotClearManualAttachmentWhenAutoAttachDisabled() {
        mockSettings.isAutomaticContextAttachmentEnabled = false
        let context = makeTestContext(title: "Manually Attached Page")
        sessionState.beginManualAttach()
        sessionState.updateContext(context)

        sessionState.updateContext(nil)

        XCTAssertEqual(sessionState.latestContext?.title, context.title)
        if case .attached(let attachedContext) = sessionState.chipState {
            XCTAssertEqual(attachedContext.title, context.title)
        } else {
            XCTFail("Expected manually attached chip to survive idle nil replay")
        }
    }

    /// Extraction can return a titled payload with no content; measurement reports it as
    /// `.emptyContent`, so the attach path must treat it like nil instead of attaching an empty chip.
    func testWhenUpdateContextHasEmptyContentThenChipDowngradesToPlaceholder() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(title: "Previous Page"))

        // When
        sessionState.updateContext(makeTestContext(title: "Titled But Empty", content: ""))

        // Then
        XCTAssertNil(sessionState.latestContext)
        XCTAssertEqual(sessionState.chipState, .placeholder)
    }

    func testWhenUpdateContextHasEmptyContentThenUTIChipClearIsDelivered() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(title: "Previous Page"))

        var receivedEffect: SheetEffect?
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    receivedEffect = effect
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.updateContext(makeTestContext(title: "Titled But Empty", content: ""))

        // Then
        if case .deliverPageContext(let contextData, let targets) = receivedEffect {
            XCTAssertNil(contextData)
            XCTAssertTrue(targets.contains(.utiChip))
        } else {
            XCTFail("Expected deliverPageContext effect clearing the UTI chip")
        }
    }

    func testWhenUpdateContextHasEmptyContentDuringManualAttachThenManualAttachEnds() {
        // Given
        sessionState.beginManualAttach()

        // When
        sessionState.updateContext(makeTestContext(title: "Titled But Empty", content: ""))

        // Then
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertTrue(mockPixelHandler.manualAttachEnded)
        XCTAssertFalse(mockPixelHandler.pageContextManuallyAttachedNativeFired)
    }

    func testWhenIdleEmptyContentArrivesWithAutoAttachDisabledThenManualAttachmentSurvives() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = false
        let context = makeTestContext(title: "Manually Attached Page")
        sessionState.beginManualAttach()
        sessionState.updateContext(context)

        // When
        sessionState.updateContext(makeTestContext(title: "Titled But Empty", content: ""))

        // Then
        XCTAssertEqual(sessionState.latestContext?.title, context.title)
        if case .attached(let attachedContext) = sessionState.chipState {
            XCTAssertEqual(attachedContext.title, context.title)
        } else {
            XCTFail("Expected manually attached chip to survive idle empty-content replay")
        }
    }

    /// Signals-only payloads strip content anyway, so an empty-content result must still deliver
    /// its page-type signals to the frontend (page shortcuts / suggested prompts).
    func testWhenSignalsOnlyCollectionReturnsEmptyContentThenSignalsPayloadStillDelivered() {
        // Given
        let signals = AIChatPageTypeSignals(jsonLdType: ["Recipe"], ogType: "article", lang: "eu")
        var deliveredPayload: AIChatPageContextData?
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext(let payload, let targets) = effect, targets.contains(.frontendBridge) {
                    deliveredPayload = payload
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(makeTestContext(title: "Titled But Empty", content: "", pageTypeSignals: signals))

        // Then
        XCTAssertEqual(deliveredPayload?.pageTypeSignals, signals)
        XCTAssertEqual(deliveredPayload?.title, "Titled But Empty")
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

    func testSuggestionsRefreshSuspensionTracksPinnedContextWhenAutoAttachIsOff() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = false
        XCTAssertFalse(sessionState.shouldSuspendSuggestionsRefresh)

        // When
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(title: "Page A"))

        // Then
        XCTAssertTrue(sessionState.shouldSuspendSuggestionsRefresh)

        // When
        sessionState.downgradeToPlaceholder()

        // Then
        XCTAssertFalse(sessionState.shouldSuspendSuggestionsRefresh)
    }

    func testSuggestionsRefreshIsNotSuspendedForAttachedContextWhenAutoAttachIsOn() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true

        // When
        sessionState.updateContext(makeTestContext(title: "Page A"))

        // Then
        XCTAssertFalse(sessionState.shouldSuspendSuggestionsRefresh)
    }

    func testManualAttachWithAutoAttachOffStaysStickyAcrossNavigationWhileSheetIsOpen() {
        mockSettings.isAutomaticContextAttachmentEnabled = false
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(title: "Page A"))

        sessionState.notifyPageChanged()
        sessionState.updateContext(makeTestContext(title: "Page B"))

        if case .attached(let attachedContext) = sessionState.chipState {
            XCTAssertEqual(attachedContext.title, "Page A")
        } else {
            XCTFail("Expected manually attached chip to stay sticky across navigation")
        }
    }

    func testManualAttachWithAutoAttachOffDoesNotClearOnSheetDismissBeforeSubmit() {
        mockSettings.isAutomaticContextAttachmentEnabled = false
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(title: "Page A"))

        sessionState.handleSheetDismissed()

        if case .attached(let attachedContext) = sessionState.chipState {
            XCTAssertEqual(attachedContext.title, "Page A")
        } else {
            XCTFail("Expected same sheet session context to survive dismiss")
        }
    }

    func testManualAttachWithAutoAttachOffDoesNotClearOnSamePageReopen() {
        let pageURL = URL(string: "https://example.com/page-a")!
        mockSettings.isAutomaticContextAttachmentEnabled = false
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(title: "Page A", url: pageURL.absoluteString))
        sessionState.handleSheetDismissed()

        let didClear = sessionState.clearManualContextIfStale(for: pageURL)

        XCTAssertFalse(didClear)
        if case .attached(let attachedContext) = sessionState.chipState {
            XCTAssertEqual(attachedContext.title, "Page A")
        } else {
            XCTFail("Expected same-page reopen to keep manual context")
        }
    }

    func testManualAttachWithAutoAttachOffDoesNotClearOnSameDocumentReopen() {
        let attachedURL = URL(string: "https://example.com/page-a#attached")!
        let currentPageURL = URL(string: "https://example.com/page-a#current")!
        mockSettings.isAutomaticContextAttachmentEnabled = false
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(title: "Page A", url: attachedURL.absoluteString))
        sessionState.handleSheetDismissed()

        let didClear = sessionState.clearManualContextIfStale(for: currentPageURL)

        XCTAssertFalse(didClear)
        if case .attached(let attachedContext) = sessionState.chipState {
            XCTAssertEqual(attachedContext.title, "Page A")
        } else {
            XCTFail("Expected same-document reopen to keep manual context")
        }
    }

    func testManualAttachWithAutoAttachOffClearsOnDifferentPageReopenBeforeSubmit() {
        let pageAURL = URL(string: "https://example.com/page-a")!
        let pageBURL = URL(string: "https://example.com/page-b")!
        mockSettings.isAutomaticContextAttachmentEnabled = false
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(title: "Page A", url: pageAURL.absoluteString))
        sessionState.handleSheetDismissed()

        let didClear = sessionState.clearManualContextIfStale(for: pageBURL)

        XCTAssertTrue(didClear)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertNil(sessionState.latestContext)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertEqual(sessionState.viewState.quickActions, [.askAboutPage])
    }

    func testManualAttachWithAutoAttachOffClearsActiveChatOnDifferentPageReopen() {
        let pageAURL = URL(string: "https://example.com/page-a")!
        let pageBURL = URL(string: "https://example.com/page-b")!
        mockSettings.isAutomaticContextAttachmentEnabled = false
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(title: "Page A", url: pageAURL.absoluteString))
        sessionState.beginChatForUTISubmission()
        sessionState.handleSheetDismissed()

        let didClear = sessionState.clearManualContextIfStale(for: pageBURL)

        XCTAssertTrue(didClear)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertNil(sessionState.latestContext)
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

    func testNotifyPageChangedClearsTemporaryUserDowngradeWhenAutoAttachIsOn() {
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

    func testBeginChatForUTISubmissionDoesNotStorePageContextURLAsChatURL() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(url: "https://example.com/article"))

        // When
        sessionState.beginChatForUTISubmission()

        // Then
        XCTAssertEqual(sessionState.frontendState, .chatWithInitialContext)
        XCTAssertNil(sessionState.contextualChatURL)
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

        mockSettings.isAutomaticContextAttachmentEnabled = true
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

    func testEffectsPublisherEmitsDeliverPageContext() {
        // Given
        sessionState.handlePromptSubmission("Hello") // Start chat without context
        sessionState.beginManualAttach(fromFrontend: true)

        let expectation = expectation(description: "Effects publishes push context")
        var receivedEffect: SheetEffect?

        sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    receivedEffect = effect
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.updateContext(makeTestContext())

        waitForExpectations(timeout: 1.0)

        // Then
        if case .deliverPageContext(let contextData, let targets) = receivedEffect {
            XCTAssertEqual(contextData?.title, "Test Page")
            XCTAssertEqual(targets, .frontendBridge)
        } else {
            XCTFail("Expected deliverPageContext effect")
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

    func testUserDowngradeBlocksLateResultUntilNavigationOrManualAttach() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext())

        // User removes chip
        let shouldShowPlaceholder = sessionState.handleChipRemoval()
        XCTAssertTrue(shouldShowPlaceholder)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // A late collection result still does not auto-attach
        sessionState.updateContext(makeTestContext(title: "New Page"))
        XCTAssertEqual(sessionState.chipState, .placeholder)

        // A real navigation clears the temporary removal so auto-attach can run again
        sessionState.notifyPageChanged()
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.shouldTriggerAutoCollect(for: URL(string: "https://example.com/new")!))
        sessionState.updateContext(makeTestContext(title: "Navigated Page"))
        if case .attached = sessionState.chipState {
            // Expected
        } else {
            XCTFail("Expected attached chip state after navigation auto-attach")
        }

        XCTAssertTrue(sessionState.handleChipRemoval())

        // Manual attach clears the opt-out and attaches again
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(title: "Manual Page"))
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        if case .attached = sessionState.chipState {
            // Expected
        } else {
            XCTFail("Expected attached chip state after manual attach")
        }
    }

    func testBaseWebUTIWithoutImmediateContextualModeAllowsAutoAttachAfterNavigation() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true, isImmediateContextual: false)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let pageURL = URL(string: "https://example.com")!
        sessionState.updateContext(makeTestContext(url: pageURL.absoluteString))
        XCTAssertTrue(sessionState.handleChipRemoval())
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // When - base web UTI is active and the page changes
        sessionState.notifyPageChanged(pageURL: pageURL)

        // Then - production behavior allows auto-attach after a real navigation/reload
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.shouldTriggerAutoCollect(for: pageURL))
    }

    func testPreSubmitUTIOptOutBlocksLateContextResultUntilNavigation() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true, isImmediateContextual: true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let pageURL = URL(string: "https://example.com")!
        sessionState.updateContext(makeTestContext(url: pageURL.absoluteString))

        if case .attached = sessionState.chipState {
            // Expected
        } else {
            XCTFail("Expected initial auto-attached chip state")
        }

        // When - user opts out before first submit
        let shouldShowPlaceholder = sessionState.handleChipRemoval()
        XCTAssertTrue(shouldShowPlaceholder)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        var deliveredContexts: [AIChatPageContextData?] = []
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext(let data, _) = effect {
                    deliveredContexts.append(data)
                }
            }
            .store(in: &cancellables)

        // Then - a late collection result should not reattach or deliver to the UTI chip
        sessionState.updateContext(makeTestContext(title: "Late Page", url: pageURL.absoluteString))
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertTrue(deliveredContexts.isEmpty)
    }

    func testPreSubmitUTIOptOutAllowsAutoCollectAfterDifferentPageNavigation() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true, isImmediateContextual: true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let pageURL = URL(string: "https://example.com")!
        let newPageURL = URL(string: "https://example.com/new")!
        sessionState.updateContext(makeTestContext(url: pageURL.absoluteString))
        XCTAssertTrue(sessionState.handleChipRemoval())
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // When - didFinish reports a real page change
        sessionState.notifyPageChanged(pageURL: newPageURL)

        // Then - production pre-submit behavior gives auto-attach another chance after navigation
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.shouldTriggerAutoCollect(for: newPageURL))
    }

    func testPreSubmitUTIOptOutAllowsAutoCollectAfterSamePageReload() {
        sessionState.updateUnifiedToggleInputActive(true, isImmediateContextual: true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        let pageURL = URL(string: "https://example.com")!
        sessionState.updateContext(makeTestContext(url: pageURL.absoluteString))
        XCTAssertTrue(sessionState.handleChipRemoval())
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        sessionState.notifyPageChanged(pageURL: pageURL)

        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.shouldTriggerAutoCollect(for: pageURL))
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
                if case .deliverPageContext = effect {
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

        XCTAssertTrue(pushedToFrontend)
    }

    // MARK: - Multiple Page Contexts Tests

    func testAutoAttachPushesContextWhenMultipleContextsFlagEnabled() {
        // Given - start chat WITH initial context, then navigate
        mockFeatureFlagger.enabledFeatureFlags = [.multiplePageContexts]
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(title: "Page A"))
        sessionState.handlePromptSubmission("Hello")
        XCTAssertEqual(sessionState.frontendState, .chatWithInitialContext)

        var pushedContexts: [AIChatPageContextData?] = []
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext(let data, _) = effect {
                    pushedContexts.append(data)
                }
            }
            .store(in: &cancellables)

        // When - auto-attach pushes new context
        sessionState.notifyPageChanged()
        sessionState.updateContext(makeTestContext(title: "Page B"))

        // Then
        XCTAssertEqual(pushedContexts.count, 1)
        XCTAssertEqual(pushedContexts.first??.title, "Page B")
    }

    func testAutoAttachDoesNotPushContextWhenMultipleContextsFlagDisabled() {
        // Given - start chat WITH initial context, flag OFF (default)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(title: "Page A"))
        sessionState.handlePromptSubmission("Hello")
        XCTAssertEqual(sessionState.frontendState, .chatWithInitialContext)

        var pushedToFrontend = false
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    pushedToFrontend = true
                }
            }
            .store(in: &cancellables)

        // When - navigate and update context
        sessionState.notifyPageChanged()
        sessionState.updateContext(makeTestContext(title: "Page B"))

        // Then - no push (backward compatible)
        XCTAssertFalse(pushedToFrontend)
    }

    func testAutoAttachDeliversContextForUTIChipWhenMultipleContextsFlagDisabled() {
        // Given - start chat WITH initial context, flag OFF (default), UTI active
        sessionState.updateUnifiedToggleInputActive(true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(title: "Page A"))
        sessionState.handlePromptSubmission("Hello")
        mockPixelHandler.pageContextAutoAttachedFired = false

        var deliveredContexts: [AIChatPageContextData?] = []
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext(let data, _) = effect {
                    deliveredContexts.append(data)
                }
            }
            .store(in: &cancellables)

        // When - navigate and update context
        sessionState.notifyPageChanged()
        sessionState.updateContext(makeTestContext(title: "Page B"))

        // Then - gate A emits for the UTI chip even though gate B remains closed
        XCTAssertEqual(deliveredContexts.count, 1)
        XCTAssertEqual(deliveredContexts.first??.title, "Page B")
        XCTAssertTrue(sessionState.shouldDeliverToUTIChip(deliveredContexts.first!))
        XCTAssertFalse(sessionState.shouldDeliverToFrontendBridge(deliveredContexts.first!))
        XCTAssertFalse(mockPixelHandler.pageContextAutoAttachedFired)
    }

    // MARK: - Stale Auto-Attach Echo Tests (re-attach after submit)

    private func utiDeliveryEffects(_ block: () -> Void) -> [AIChatPageContextData?] {
        var delivered: [AIChatPageContextData?] = []
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext(let data, let targets) = effect, targets.contains(.utiChip) {
                    delivered.append(data)
                }
            }
            .store(in: &cancellables)
        block()
        return delivered
    }

    /// Regression test for the bug where, after submitting the first prompt WITH context via the
    /// contextual UTI, a late auto-attach re-collection for the SAME page (no navigation in between)
    /// resurrected the UTI chip as pending — silently riding the next message. The stale echo must
    /// not produce any delivery at all, so the chip stays untouched in its post-submit `.delivered`
    /// state.
    func testLateAutoAttachEchoAfterUTISubmissionDoesNotResurrectChip() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(url: "https://example.com/article"))
        sessionState.beginChatForUTISubmission()
        XCTAssertEqual(sessionState.frontendState, .chatWithInitialContext)

        // When
        let delivered = utiDeliveryEffects {
            sessionState.updateContext(makeTestContext(title: "Article (updated)", url: "https://example.com/article"))
        }

        // Then
        XCTAssertTrue(delivered.isEmpty)
    }

    func testStaleAutoAttachEchoDoesNotMutateStoredContext() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(title: "Original", url: "https://example.com/article"))
        sessionState.beginChatForUTISubmission()
        XCTAssertEqual(sessionState.intendedAttachedContext?.title, "Original")

        // When a stale echo of the already-submitted page arrives with a refreshed title
        sessionState.updateContext(makeTestContext(title: "Echo (updated)", url: "https://example.com/article"))

        // Then the stored attached context still reflects what was submitted, not the ignored echo
        XCTAssertEqual(sessionState.intendedAttachedContext?.title, "Original")
    }

    func testUTIChipDeliveryStateMarksStaleEchoDeliveredAndFreshContextPending() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(url: "https://example.com/article"))
        sessionState.beginChatForUTISubmission()

        // Then
        let echo = makeTestContext(url: "https://example.com/article").contextData
        guard case .delivered = sessionState.utiChipDeliveryState(forDelivering: echo) else {
            return XCTFail("Expected stale echo of already-submitted page to be .delivered")
        }

        let fresh = makeTestContext(url: "https://example.com/other").contextData
        guard case .pendingSubmit = sessionState.utiChipDeliveryState(forDelivering: fresh) else {
            return XCTFail("Expected fresh context to be .pendingSubmit")
        }
    }

    func testMarkUTIContextDeliveredRerendersChipAndMarksPageDelivered() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(url: "https://example.com/article"))

        // When
        let delivered = utiDeliveryEffects {
            sessionState.markUTIContextDelivered()
        }

        // Then
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first??.url, "https://example.com/article")

        let sameURL = makeTestContext(url: "https://example.com/article").contextData
        guard case .delivered = sessionState.utiChipDeliveryState(forDelivering: sameURL) else {
            return XCTFail("Expected the delivered page to be marked .delivered")
        }
    }

    func testManualReattachOfSameURLAfterSubmitStillDelivers() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(url: "https://example.com/article"))
        sessionState.beginChatForUTISubmission()

        // When
        sessionState.beginManualAttach()
        let delivered = utiDeliveryEffects {
            sessionState.updateContext(makeTestContext(url: "https://example.com/article"))
        }

        // Then
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first??.url, "https://example.com/article")

        let reattached = makeTestContext(url: "https://example.com/article").contextData
        guard case .pendingSubmit = sessionState.utiChipDeliveryState(forDelivering: reattached) else {
            return XCTFail("Manual same-URL re-attach after submit must be .pendingSubmit, not suppressed as a stale echo")
        }
    }

    func testAutoAttachAfterNavigationBackToSameURLStillDelivers() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(url: "https://example.com/article"))
        sessionState.beginChatForUTISubmission()

        // When
        sessionState.notifyPageChanged()
        let delivered = utiDeliveryEffects {
            sessionState.updateContext(makeTestContext(url: "https://example.com/article"))
        }

        // Then
        XCTAssertEqual(delivered.count, 1)
    }

    func testAutoAttachForDifferentURLAfterSubmitStillDelivers() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(url: "https://example.com/page-a"))
        sessionState.beginChatForUTISubmission()

        // When
        let delivered = utiDeliveryEffects {
            sessionState.updateContext(makeTestContext(url: "https://example.com/page-b"))
        }

        // Then
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first??.url, "https://example.com/page-b")
    }

    func testUTINonNilContextDoesNotDeliverToFrontendForChatWithoutInitialContext() {
        sessionState.updateUnifiedToggleInputActive(true)
        sessionState.handlePromptSubmission("Hello")

        let context = makeTestContext().contextData

        XCTAssertTrue(sessionState.shouldDeliverToUTIChip(context))
        XCTAssertFalse(sessionState.shouldDeliverToFrontendBridge(context))
    }

    func testUTINonNilContextDoesNotDeliverToFrontendForRestoredChat() {
        sessionState.updateUnifiedToggleInputActive(true)
        sessionState.restoreChat(with: URL(string: "https://duck.ai/chat/abc")!)

        let context = makeTestContext().contextData

        XCTAssertTrue(sessionState.shouldDeliverToUTIChip(context))
        XCTAssertFalse(sessionState.shouldDeliverToFrontendBridge(context))
    }

    func testNotifyFrontendOfNavigationEmitsFrontendOnlyNullContextWhenUTIInactive() {
        // Given - chat with initial context, flag ON
        // Note: auto-attach ON is only needed to reach .chatWithInitialContext state.
        // In production, notifyFrontendOfMultiContextNavigation() is called when auto-collect is OFF.
        mockFeatureFlagger.enabledFeatureFlags = [.multiplePageContexts]
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(title: "Page A"))
        sessionState.handlePromptSubmission("Hello")

        let expectation = expectation(description: "Null context pushed")
        var receivedEffect: SheetEffect?

        sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    receivedEffect = effect
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.notifyFrontendOfMultiContextNavigation()

        waitForExpectations(timeout: 1.0)

        // Then
        if case .deliverPageContext(let contextData, let targets) = receivedEffect {
            XCTAssertNil(contextData)
            XCTAssertEqual(targets, .frontendBridge)
            XCTAssertFalse(targets.contains(.utiChip))
            XCTAssertFalse(targets.contains(.utiAttachAffordance))
        } else {
            XCTFail("Expected deliverPageContext effect with nil")
        }
    }

    func testNotifyFrontendOfNavigationEmitsUTIAttachAffordanceWhenUTIActive() {
        // Given - chat with initial context, multi-context ON, UTI active
        mockFeatureFlagger.enabledFeatureFlags = [.multiplePageContexts]
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateUnifiedToggleInputActive(true)
        sessionState.updateContext(makeTestContext(title: "Page A"))
        sessionState.handlePromptSubmission("Hello")

        let expectation = expectation(description: "Null context pushed")
        var receivedEffect: SheetEffect?

        sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    receivedEffect = effect
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        mockSettings.isAutomaticContextAttachmentEnabled = false
        sessionState.notifyFrontendOfMultiContextNavigation()

        waitForExpectations(timeout: 1.0)

        // Then - nil is a multi-context navigation affordance, not a detach
        if case .deliverPageContext(let contextData, let targets) = receivedEffect {
            XCTAssertNil(contextData)
            XCTAssertTrue(targets.contains(.frontendBridge))
            XCTAssertTrue(targets.contains(.utiAttachAffordance))
            XCTAssertFalse(targets.contains(.utiChip))
        } else {
            XCTFail("Expected deliverPageContext effect with nil")
        }
    }

    func testNotifyFrontendOfNavigationDoesNothingWhenFlagDisabled() {
        // Given - chat with initial context, flag OFF (default)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext(title: "Page A"))
        sessionState.handlePromptSubmission("Hello")

        var pushedToFrontend = false
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    pushedToFrontend = true
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.notifyFrontendOfMultiContextNavigation()

        // Then - nothing emitted
        XCTAssertFalse(pushedToFrontend)
    }

    func testNotifyFrontendOfNavigationDoesNothingInNoChat() {
        // Given - no active chat, flag ON
        mockFeatureFlagger.enabledFeatureFlags = [.multiplePageContexts]

        var pushedToFrontend = false
        sessionState.effects
            .sink { effect in
                if case .deliverPageContext = effect {
                    pushedToFrontend = true
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.notifyFrontendOfMultiContextNavigation()

        // Then - nothing emitted (no chat = frontend bridge delivery false)
        XCTAssertFalse(pushedToFrontend)
    }

    // MARK: - Quick Actions Tests

    func testQuickActionsDefaultsToAskAboutPageWhenPlaceholder() {
        XCTAssertEqual(sessionState.viewState.quickActions, [.askAboutPage])
    }

    func testQuickActionsIsSummarizePageWhenAttached() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true

        // When
        sessionState.updateContext(makeTestContext())

        // Then
        XCTAssertEqual(sessionState.viewState.quickActions, [.summarizePage])
    }

    func testQuickActionsTransitionsOnAttach() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        XCTAssertEqual(sessionState.viewState.quickActions, [.askAboutPage])

        // When
        sessionState.updateContext(makeTestContext())

        // Then
        XCTAssertEqual(sessionState.viewState.quickActions, [.summarizePage])
    }

    func testQuickActionsTransitionsOnChipRemoval() {
        // Given
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext())
        XCTAssertEqual(sessionState.viewState.quickActions, [.summarizePage])

        // When
        sessionState.downgradeToPlaceholder()

        // Then
        XCTAssertEqual(sessionState.viewState.quickActions, [.askAboutPage])
    }

    func testQuickActionsEmptyWhenPageNotAttachable() {
        // Given a non-attachable page (blocklisted), the "Ask about page" affordance is suppressed.
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            isCurrentPageAttachable: { false }
        )

        XCTAssertEqual(sessionState.viewState.quickActions, [])
    }

    func testQuickActionsShowAskAboutPageWhenPageAttachable() {
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            isCurrentPageAttachable: { true }
        )

        XCTAssertEqual(sessionState.viewState.quickActions, [.askAboutPage])
    }

    func testQuickActionsRefreshedForCurrentPageWhenAttachabilityChanges() {
        var attachable = true
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            isCurrentPageAttachable: { attachable }
        )
        XCTAssertEqual(sessionState.viewState.quickActions, [.askAboutPage])

        // A URL change to a non-attachable page must refresh the quick actions, not leave them stale.
        attachable = false
        sessionState.refreshForCurrentPage()

        XCTAssertEqual(sessionState.viewState.quickActions, [])
    }

    // MARK: - Suggested Prompts Coexistence Tests

    func testQuickActionsIsAskAboutPageWhenSuggestedPromptsOnAndPlaceholder() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger
        )

        // Then - auto-attach off (placeholder) pins "Ask about page" below the suggestions
        XCTAssertEqual(sessionState.viewState.quickActions, [.askAboutPage])
    }

    func testQuickActionsIsEmptyWhenSuggestedPromptsOnAndAttached() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger
        )

        // When - context attached (auto-attach on)
        sessionState.updateContext(makeTestContext())

        // Then - only suggestions remain, no pinned quick action
        XCTAssertEqual(sessionState.viewState.quickActions, [])
    }

    // MARK: - Suggested Prompts Loading Tests

    func testSuggestionsPopulateViewStateWhenLoadingCompletes() {
        // Given
        let expected = [ContextualSuggestedPrompt(id: "summarize-page", label: "Summarize this page", prompt: "Summarize this page.", icon: "summary")]
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: MockContextualSuggestedPromptsProvider(suggestions: expected)
        )

        let loaded = expectation(description: "suggestions loaded")
        sessionState.$viewState
            .dropFirst()
            .sink { state in
                if state.suggestionsLoadState == .loaded, state.suggestions == expected {
                    loaded.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - spinner starts, then real signals arrive and drive the resolve
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(makeTestContext())

        // Then
        wait(for: [loaded], timeout: 1.0)
    }

    func testSuggestionsClearedOnReset() {
        // Given
        let expected = [ContextualSuggestedPrompt(id: "note-page", label: "Key takeaways", prompt: "Key takeaways?", icon: "note")]
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: MockContextualSuggestedPromptsProvider(suggestions: expected)
        )

        let loaded = expectation(description: "suggestions loaded")
        sessionState.$viewState
            .dropFirst()
            .sink { state in
                if state.suggestionsLoadState == .loaded, state.suggestions == expected {
                    loaded.fulfill()
                }
            }
            .store(in: &cancellables)
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(makeTestContext())
        wait(for: [loaded], timeout: 1.0)

        // When
        sessionState.resetToNoChat()

        // Then
        XCTAssertTrue(sessionState.suggestions.isEmpty)
        XCTAssertEqual(sessionState.suggestionsLoadState, .loaded)
    }

    func testSuggestionsNotLoadedWhenSuggestedPromptsFlagOff() {
        // Given - flag off (default); provider would return values if it were called
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: MockContextualSuggestedPromptsProvider(
                suggestions: [ContextualSuggestedPrompt(id: "summarize-page", label: "Summarize this page", prompt: "Summarize this page.", icon: "summary")]
            )
        )

        // When
        sessionState.markPendingSignalsOnlyCollection()

        // Then - loading never begins, so suggestions stay empty and state stays loaded
        XCTAssertTrue(sessionState.suggestions.isEmpty)
        XCTAssertEqual(sessionState.suggestionsLoadState, .loaded)
    }

    func testSuggestionsResolveReceivesRealPageSignals() {
        // Given
        let expected = [ContextualSuggestedPrompt(id: "summarize-page", label: "Summarize this page", prompt: "Summarize this page.", icon: "summary")]
        let mockProvider = MockContextualSuggestedPromptsProvider(suggestions: expected)
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: mockProvider
        )

        let loaded = expectation(description: "suggestions loaded")
        sessionState.$viewState
            .dropFirst()
            .sink { state in
                if state.suggestionsLoadState == .loaded, state.suggestions == expected {
                    loaded.fulfill()
                }
            }
            .store(in: &cancellables)

        let signals = AIChatPageTypeSignals(jsonLdType: ["Recipe"], ogType: "article", lang: "eu")

        // When - spinner starts, then real page signals arrive via updateContext
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(makeTestContext(url: "https://recipes.example/eu", pageTypeSignals: signals))

        // Then - the real signals + url + uiLocale reach the resolver seam
        wait(for: [loaded], timeout: 1.0)
        XCTAssertEqual(mockProvider.lastInput?.pageTypeSignals, signals)
        XCTAssertEqual(mockProvider.lastInput?.url, "https://recipes.example/eu")
        XCTAssertEqual(mockProvider.lastInput?.uiLocale, Locale.current.identifier)
    }

    func testWhenAttachedChipIsRemovedThenAskAboutPageReplacesLastSuggestionUntilContextIsAttachedAgain() {
        // Given
        let expected = makeSuggestedPrompts(ids: ["one", "two", "three", "four"])
        let mockProvider = MockContextualSuggestedPromptsProvider(suggestions: expected)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: mockProvider
        )

        let loaded = expectation(description: "suggestions loaded")
        sessionState.$viewState
            .dropFirst()
            .filter { state in
                state.suggestionsLoadState == .loaded && state.suggestions == expected
            }
            .first()
            .sink { _ in
                loaded.fulfill()
            }
            .store(in: &cancellables)

        sessionState.beginLoadingSuggestions()
        let context = makeTestContext()
        sessionState.updateContext(context)
        wait(for: [loaded], timeout: 1.0)

        // When - removing the attached chip introduces the quick action.
        sessionState.downgradeToPlaceholder()

        // Then - the full resolved set is retained, while only the first three render.
        XCTAssertEqual(sessionState.suggestions, expected)
        XCTAssertEqual(sessionState.viewState.suggestions, Array(expected.prefix(3)))
        XCTAssertEqual(sessionState.viewState.quickActions, [.askAboutPage])

        // When - attaching context removes the quick action.
        sessionState.attachContextFromSuggestionTap(context)

        // Then - the fourth suggestion returns without another resolve.
        XCTAssertEqual(sessionState.viewState.suggestions, expected)
        XCTAssertEqual(sessionState.viewState.quickActions, [])
    }

    func testWhenTranslateWouldBeTrimmedThenItReplacesThirdSuggestion() {
        // Given
        let expected = makeSuggestedPrompts(ids: ["one", "two", "three", "translate-page"])
        let mockProvider = MockContextualSuggestedPromptsProvider(
            suggestions: expected,
            prioritySuggestionIDs: ["translate-page"]
        )
        mockSettings.isAutomaticContextAttachmentEnabled = true
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: mockProvider
        )

        let loaded = expectation(description: "suggestions loaded")
        sessionState.$viewState
            .dropFirst()
            .sink { state in
                if state.suggestionsLoadState == .loaded, state.suggestions == expected {
                    loaded.fulfill()
                }
            }
            .store(in: &cancellables)

        sessionState.beginLoadingSuggestions()
        sessionState.updateContext(makeTestContext())
        wait(for: [loaded], timeout: 1.0)

        // When
        sessionState.downgradeToPlaceholder()

        // Then
        XCTAssertEqual(sessionState.viewState.suggestions.map(\.id), ["one", "two", "translate-page"])
        XCTAssertEqual(sessionState.viewState.quickActions, [.askAboutPage])
    }

    func testWhenPageIsNotAttachableThenAllFourSuggestionsRemainVisible() {
        // Given
        let expected = makeSuggestedPrompts(ids: ["one", "two", "three", "four"])
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: MockContextualSuggestedPromptsProvider(suggestions: expected),
            isCurrentPageAttachable: { false }
        )

        let loaded = expectation(description: "suggestions loaded")
        sessionState.$viewState
            .dropFirst()
            .sink { state in
                if state.suggestionsLoadState == .loaded, state.suggestions == expected {
                    loaded.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(makeTestContext())

        // Then
        wait(for: [loaded], timeout: 1.0)
        XCTAssertEqual(sessionState.viewState.quickActions, [])
    }

    func testSuggestionsResolveOnAutoAttachOnPath() {
        // Given - auto-attach ON: the spinner is started by the coordinator via beginLoadingSuggestions,
        // not markPendingSignalsOnlyCollection. The resolve is keyed on `.loading`, so it must still fire.
        let expected = [ContextualSuggestedPrompt(id: "key-takeaways", label: "Key takeaways", prompt: "Key takeaways?", icon: "note")]
        mockSettings.isAutomaticContextAttachmentEnabled = true
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: MockContextualSuggestedPromptsProvider(suggestions: expected)
        )

        let loaded = expectation(description: "suggestions loaded")
        sessionState.$viewState
            .dropFirst()
            .sink { state in
                if state.suggestionsLoadState == .loaded, state.suggestions == expected {
                    loaded.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - simulate the auto-attach-ON coordinator path (no markPending / no pendingSignalsOnly flag)
        sessionState.beginLoadingSuggestions()
        sessionState.updateContext(makeTestContext())

        // Then
        wait(for: [loaded], timeout: 1.0)
    }

    func testSuggestionsFallBackToDefaultsOnNilContext() {
        // Given
        let defaults = [ContextualSuggestedPrompt(id: "summarize-page", label: "Summarize this page", prompt: "Summarize this page.", icon: "summary")]
        let mockProvider = MockContextualSuggestedPromptsProvider(suggestions: defaults)
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: mockProvider
        )

        let loaded = expectation(description: "suggestions loaded")
        sessionState.$viewState
            .dropFirst()
            .sink { state in
                if state.suggestionsLoadState == .loaded, state.suggestions == defaults {
                    loaded.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - collection returns nil (empty / decode-fail)
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(nil)

        // Then - spinner resolves to defaults with empty signals, never hangs
        wait(for: [loaded], timeout: 1.0)
        XCTAssertNil(mockProvider.lastInput?.pageTypeSignals)
        XCTAssertNil(mockProvider.lastInput?.url)
    }

    // MARK: - Suggestion Tap Attach Tests

    func testAttachContextFromSuggestionTapAttachesChip() {
        // When
        sessionState.attachContextFromSuggestionTap(makeTestContext(title: "Recipe", url: "https://example.com/recipe"))

        // Then
        guard case .attached(let attached) = sessionState.chipState else {
            return XCTFail("Expected chip to be attached")
        }
        XCTAssertEqual(attached.contextData.url, "https://example.com/recipe")
    }

    func testAttachContextFromSuggestionTapClearsUserDowngrade() {
        // Given - the user previously removed the chip (X-tap → placeholder + opted out)
        mockSettings.isAutomaticContextAttachmentEnabled = true
        sessionState.updateContext(makeTestContext())
        _ = sessionState.handleChipRemoval()
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // When - tapping a suggestion force-attaches regardless of the prior downgrade
        sessionState.attachContextFromSuggestionTap(makeTestContext())

        // Then
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertEqual(sessionState.chipState.description, "attached")
    }

    func testAttachContextFromSuggestionTapDeliversToUTIChipWhenUTIActive() {
        // Given
        sessionState.updateUnifiedToggleInputActive(true)
        var receivedEffect: SheetEffect?
        sessionState.effects
            .sink { if case .deliverPageContext = $0 { receivedEffect = $0 } }
            .store(in: &cancellables)

        // When
        sessionState.attachContextFromSuggestionTap(makeTestContext(title: "Recipe"))

        // Then - full context delivered to the UTI chip only (never the FE bridge with UTI active)
        guard case .deliverPageContext(let contextData, let targets) = receivedEffect else {
            return XCTFail("Expected deliverPageContext effect")
        }
        XCTAssertEqual(contextData?.title, "Recipe")
        XCTAssertEqual(targets, .utiChip)
    }

    func testAttachContextFromSuggestionTapDoesNotDeliverWhenNotUTIAndNoChat() {
        // Given - UTI inactive (default) and no active chat: context is held natively only
        var receivedDeliver: SheetEffect?
        sessionState.effects
            .sink { if case .deliverPageContext = $0 { receivedDeliver = $0 } }
            .store(in: &cancellables)

        // When
        sessionState.attachContextFromSuggestionTap(makeTestContext())

        // Then - nothing pushed to the UTI chip or FE bridge
        XCTAssertNil(receivedDeliver)
    }

    func testAttachContextFromSuggestionTapUpdatesViewStateChip() {
        // When
        sessionState.attachContextFromSuggestionTap(makeTestContext())

        // Then
        XCTAssertEqual(sessionState.viewState.chipState.description, "attached")
    }

    // MARK: - Signals-Only Payload Tests

    func testSignalsOnlyCollectionEmitsStrippedPayloadToFrontendBridge() throws {
        // Given - suggestions ON, auto-attach OFF: the start surface collects signals only
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        mockSettings.isAutomaticContextAttachmentEnabled = false
        var delivered: [(context: AIChatPageContextData?, targets: PageContextDeliveryTargets)] = []
        sessionState.effects
            .sink { if case .deliverPageContext(let context, let targets) = $0 { delivered.append((context, targets)) } }
            .store(in: &cancellables)
        let signals = AIChatPageTypeSignals(jsonLdType: ["Recipe"], ogType: "article", lang: "eu")

        // When
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(makeTestContext(url: "https://example.com/recipe", pageTypeSignals: signals))

        // Then - exactly one FE-bridge payload: metadata + signals, content stripped
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered[0].targets, .frontendBridge)
        let payload = try XCTUnwrap(delivered[0].context)
        XCTAssertEqual(payload.content, "")
        XCTAssertEqual(payload.attached, false)
        XCTAssertEqual(payload.attachable, true)
        XCTAssertEqual(payload.pageTypeSignals, signals)
        XCTAssertEqual(payload.url, "https://example.com/recipe")
        XCTAssertEqual(payload.title, "Test Page")

        // And - a signals-only result must not count as a collected/attached page
        XCTAssertNil(sessionState.latestContext)
        XCTAssertEqual(sessionState.chipState, .placeholder)
    }

    func testSignalsOnlyCollectionWithNilContextEmitsNothing() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        mockSettings.isAutomaticContextAttachmentEnabled = false
        var delivered: [SheetEffect] = []
        sessionState.effects
            .sink { if case .deliverPageContext = $0 { delivered.append($0) } }
            .store(in: &cancellables)

        // When - collection fails (empty page / decode failure)
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(nil)

        // Then - nothing is pushed and the chip stays untouched
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertNil(sessionState.latestContext)
    }

    func testChipRemovalOnStartSurfaceEmitsDetachSignalThenSignalsOnlyPayload() throws {
        // Given - a chip attached on the start surface (suggestions ON, auto-attach OFF)
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        mockSettings.isAutomaticContextAttachmentEnabled = false
        let signals = AIChatPageTypeSignals(jsonLdType: ["JobPosting"], ogType: nil, lang: "en")
        sessionState.beginManualAttach()
        sessionState.updateContext(makeTestContext(pageTypeSignals: signals))
        XCTAssertEqual(sessionState.chipState.description, "attached")

        var delivered: [(context: AIChatPageContextData?, targets: PageContextDeliveryTargets)] = []
        sessionState.effects
            .sink { if case .deliverPageContext(let context, let targets) = $0 { delivered.append((context, targets)) } }
            .store(in: &cancellables)

        // When - the user removes the chip (X tap)
        sessionState.downgradeToPlaceholder()

        // Then - the FE first receives a detach signal (nil), then the signals-only payload,
        // in that order, so the suggestions surface keeps rendering page-tailored prompts.
        XCTAssertEqual(delivered.count, 2)
        XCTAssertNil(delivered[0].context)
        XCTAssertEqual(delivered[0].targets, .frontendBridge)
        XCTAssertEqual(delivered[1].targets, .frontendBridge)
        let payload = try XCTUnwrap(delivered[1].context)
        XCTAssertEqual(payload.content, "")
        XCTAssertEqual(payload.attached, false)
        XCTAssertEqual(payload.pageTypeSignals, signals)
    }

    // MARK: - Suggestions Resolve Race Tests

    func testStaleSuggestionsResolveFromPreviousNavigationIsDiscarded() async {
        // Given - a provider whose resolves complete only when the test says so
        let provider = GatedContextualSuggestedPromptsProvider()
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: provider
        )
        let stale = [ContextualSuggestedPrompt(id: "stale", label: "Stale", prompt: "Stale.", icon: "note")]
        let fresh = [ContextualSuggestedPrompt(id: "fresh", label: "Fresh", prompt: "Fresh.", icon: "note")]

        // When - navigation #1 starts a resolve that hangs
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(makeTestContext(url: "https://example.com/first"))
        await yieldUntil { provider.startedCount == 1 }

        // And - navigation #2 restarts loading and resolves first
        sessionState.beginLoadingSuggestions()
        sessionState.updateContext(makeTestContext(url: "https://example.com/second"))
        await yieldUntil { provider.startedCount == 2 }
        provider.resume(at: 1, returning: fresh)
        await yieldUntil { self.sessionState.suggestionsLoadState == .loaded }

        // And - the stale resolve from navigation #1 completes late
        provider.resume(at: 0, returning: stale)
        await yieldBriefly()

        // Then - the late result is discarded, navigation #2's suggestions stay
        XCTAssertEqual(sessionState.suggestions, fresh)
        XCTAssertEqual(sessionState.viewState.suggestions, fresh)
    }

    func testLateSuggestionsResolveAfterChatStartIsDiscarded() async {
        // Given - a resolve in flight on the start surface
        let provider = GatedContextualSuggestedPromptsProvider()
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: provider
        )
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(makeTestContext())
        await yieldUntil { provider.startedCount == 1 }

        // When - the user submits a prompt before the resolve completes, then it completes late
        sessionState.handlePromptSubmission("Hello")
        provider.resume(at: 0, returning: [ContextualSuggestedPrompt(id: "late", label: "Late", prompt: "Late.", icon: "note")])
        await yieldBriefly()

        // Then - the late result must not mutate view state mid-chat
        XCTAssertEqual(sessionState.frontendState, .chatWithoutInitialContext)
        XCTAssertTrue(sessionState.suggestions.isEmpty)
        XCTAssertTrue(sessionState.viewState.suggestions.isEmpty)
    }

    // MARK: - UTI Submission Transition Tests

    func testBeginChatForUTISubmissionWithAttachedChip() {
        // Given
        sessionState.attachContextFromSuggestionTap(makeTestContext())

        // When
        sessionState.beginChatForUTISubmission()

        // Then
        XCTAssertEqual(sessionState.frontendState, .chatWithInitialContext)
        XCTAssertTrue(mockPixelHandler.promptSubmittedWithContextFired)
        XCTAssertFalse(mockPixelHandler.promptSubmittedWithoutContextFired)
        guard case .webView = sessionState.viewState.content else {
            return XCTFail("Expected webView content after UTI submission")
        }
    }

    func testBeginChatForUTISubmissionWithPlaceholderChip() {
        // When
        sessionState.beginChatForUTISubmission()

        // Then
        XCTAssertEqual(sessionState.frontendState, .chatWithoutInitialContext)
        XCTAssertTrue(mockPixelHandler.promptSubmittedWithoutContextFired)
        XCTAssertFalse(mockPixelHandler.promptSubmittedWithContextFired)
        XCTAssertNil(sessionState.contextualChatURL)
    }

    func testBeginChatForUTISubmissionIgnoredInRestoredState() {
        // Given
        sessionState.restoreChat(with: URL(string: "https://duck.ai/?chat=abc")!)

        // When
        sessionState.beginChatForUTISubmission()

        // Then - restored state is preserved and no submission pixels fire
        XCTAssertEqual(sessionState.frontendState, .restoredChat)
        XCTAssertFalse(mockPixelHandler.promptSubmittedWithContextFired)
        XCTAssertFalse(mockPixelHandler.promptSubmittedWithoutContextFired)
    }

    // MARK: - Helpers

    /// Yields the main actor until `condition` holds (or the timeout elapses), letting
    /// session-state resolve tasks run between checks.
    private func yieldUntil(_ condition: () -> Bool, timeout: TimeInterval = 2.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
    }

    /// Yields a bounded number of times so an (incorrectly) scheduled task would get a chance to run.
    private func yieldBriefly() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    private func makeSuggestedPrompts(ids: [String]) -> [ContextualSuggestedPrompt] {
        ids.map { id in
            ContextualSuggestedPrompt(id: id, label: id, prompt: "\(id).", icon: nil)
        }
    }

    private func makeTestContext(title: String = "Test Page",
                                 url: String = "https://example.com",
                                 content: String = "Test content",
                                 pageTypeSignals: AIChatPageTypeSignals? = nil) -> AIChatPageContext {
        let contextData = AIChatPageContextData(
            title: title,
            favicon: [],
            url: url,
            content: content,
            truncated: false,
            fullContentLength: content.count,
            pageTypeSignals: pageTypeSignals
        )
        return AIChatPageContext(contextData: contextData, favicon: nil)
    }

    private func makeSelection(_ content: String = "selected text") -> AIChatSelectionContextData {
        AIChatSelectionContextBuilder.makeSelection(text: content, url: URL(string: "https://example.com/article"))
    }

    // MARK: - Attached Text Selections

    func testAttachSelectionAppendsAndReportsSuccess() {
        XCTAssertTrue(sessionState.attachSelection(makeSelection("first"), pageTitle: "Article"))
        XCTAssertTrue(sessionState.attachSelection(makeSelection("second"), pageTitle: "Article"))

        XCTAssertEqual(sessionState.attachedSelections.map(\.content), ["first", "second"])
        XCTAssertEqual(sessionState.attachedSelectionPageTitle, "Article")
    }

    func testSelectionsAccumulateUpToTheCap() {
        for index in 0..<AIChatSelectionContextBuilder.maxAttachedSelections {
            XCTAssertTrue(sessionState.attachSelection(makeSelection("selection \(index)"), pageTitle: nil))
        }

        XCTAssertEqual(sessionState.attachedSelections.count, AIChatSelectionContextBuilder.maxAttachedSelections)
    }

    /// At the cap the newcomer is refused rather than displacing an existing selection, so nothing the
    /// user already collected disappears without them asking.
    func testAttachSelectionBeyondTheCapIsRefusedAndKeepsExistingSelections() {
        for index in 0..<AIChatSelectionContextBuilder.maxAttachedSelections {
            sessionState.attachSelection(makeSelection("selection \(index)"), pageTitle: nil)
        }
        let before = sessionState.attachedSelections.map(\.id)

        XCTAssertFalse(sessionState.attachSelection(makeSelection("one too many"), pageTitle: nil))

        XCTAssertEqual(sessionState.attachedSelections.map(\.id), before)
    }

    func testRemoveAttachedSelectionRemovesOnlyThatSelection() {
        let first = makeSelection("first")
        let second = makeSelection("second")
        sessionState.attachSelection(first, pageTitle: "Article")
        sessionState.attachSelection(second, pageTitle: "Article")

        sessionState.removeAttachedSelection(id: first.id)

        XCTAssertEqual(sessionState.attachedSelections.map(\.id), [second.id])
        XCTAssertEqual(sessionState.attachedSelectionPageTitle, "Article")
    }

    func testRemovingTheLastSelectionClearsThePageTitle() {
        let selection = makeSelection()
        sessionState.attachSelection(selection, pageTitle: "Article")

        sessionState.removeAttachedSelection(id: selection.id)

        XCTAssertTrue(sessionState.attachedSelections.isEmpty)
        XCTAssertNil(sessionState.attachedSelectionPageTitle)
    }

    func testRemovingAnUnknownSelectionIsANoOp() {
        let selection = makeSelection()
        sessionState.attachSelection(selection, pageTitle: "Article")

        sessionState.removeAttachedSelection(id: "not-attached")

        XCTAssertEqual(sessionState.attachedSelections.map(\.id), [selection.id])
    }

    func testRemovingASelectionFreesCapacityAtTheCap() {
        for index in 0..<AIChatSelectionContextBuilder.maxAttachedSelections {
            sessionState.attachSelection(makeSelection("selection \(index)"), pageTitle: nil)
        }
        let removed = sessionState.attachedSelections[0]

        sessionState.removeAttachedSelection(id: removed.id)

        XCTAssertTrue(sessionState.attachSelection(makeSelection("replacement"), pageTitle: nil))
        XCTAssertEqual(sessionState.attachedSelections.count, AIChatSelectionContextBuilder.maxAttachedSelections)
    }

    func testConsumeAttachedSelectionsClearsTheList() {
        sessionState.attachSelection(makeSelection(), pageTitle: "Article")

        sessionState.consumeAttachedSelections()

        XCTAssertTrue(sessionState.attachedSelections.isEmpty)
        XCTAssertNil(sessionState.attachedSelectionPageTitle)
    }

    func testClearAttachedSelectionsClearsTheList() {
        sessionState.attachSelection(makeSelection(), pageTitle: "Article")

        sessionState.clearAttachedSelections()

        XCTAssertTrue(sessionState.attachedSelections.isEmpty)
        XCTAssertNil(sessionState.attachedSelectionPageTitle)
    }

    func testResetToNoChatClearsSelectionsByDefault() {
        sessionState.attachSelection(makeSelection(), pageTitle: "Article")

        sessionState.resetToNoChat()

        XCTAssertTrue(sessionState.attachedSelections.isEmpty)
        XCTAssertNil(sessionState.attachedSelectionPageTitle)
    }

    /// The inactivity timer ends the chat but must not destroy text the user gathered across pages.
    func testResetToNoChatCanPreserveSelections() {
        let selection = makeSelection()
        sessionState.attachSelection(selection, pageTitle: "Article")

        sessionState.resetToNoChat(preservingSelections: true)

        XCTAssertEqual(sessionState.attachedSelections.map(\.id), [selection.id])
        XCTAssertEqual(sessionState.attachedSelectionPageTitle, "Article")
    }

    // MARK: - Suggestions vs Attachment Count

    /// One attachment still allows suggestions — that is today's auto-attach behaviour and the
    /// single-selection case this feature relies on.
    func testSuggestionsSurviveASingleAttachment() {
        let expected = [ContextualSuggestedPrompt(id: "summarize-selection", label: "Summarize this selection", prompt: "Summarize this selection.", icon: "summary")]
        makeSessionStateWithSuggestions(expected)

        sessionState.attachSelection(makeSelection(), pageTitle: "Article")

        XCTAssertEqual(sessionState.viewState.suggestions, expected)
    }

    /// Two attachments and the user has assembled something specific; a one-line suggestion can no
    /// longer say which part of it it acts on.
    func testSuggestionsAreHiddenOnceTwoSelectionsAreAttached() {
        makeSessionStateWithSuggestions([ContextualSuggestedPrompt(id: "summarize-selection", label: "l", prompt: "p", icon: nil)])

        sessionState.attachSelection(makeSelection("one"), pageTitle: nil)
        sessionState.attachSelection(makeSelection("two"), pageTitle: nil)

        XCTAssertTrue(sessionState.viewState.suggestions.isEmpty)
    }

    /// Auto-attached page context counts the same as anything else, so a selection alongside it makes
    /// two. Recorded because it means selection suggestions never appear for auto-attach users.
    func testSuggestionsAreHiddenWhenPageContextAndASelectionAreBothAttached() {
        makeSessionStateWithSuggestions([ContextualSuggestedPrompt(id: "summarize-selection", label: "l", prompt: "p", icon: nil)])
        sessionState.attachContextFromSuggestionTap(makeTestContext())
        XCTAssertEqual(sessionState.chipState.description, "attached", "precondition: page context is attached")

        sessionState.attachSelection(makeSelection(), pageTitle: nil)

        XCTAssertTrue(sessionState.viewState.suggestions.isEmpty)
    }

    /// The rule is about attachments in general, not text selections — an image counts too.
    func testSuggestionsAreHiddenWhenAnImageJoinsASelection() {
        makeSessionStateWithSuggestions([ContextualSuggestedPrompt(id: "summarize-selection", label: "l", prompt: "p", icon: nil)])
        sessionState.attachSelection(makeSelection(), pageTitle: nil)
        XCTAssertFalse(sessionState.viewState.suggestions.isEmpty)

        var imageCount = 0
        sessionState.inputAttachmentCount = { imageCount }
        imageCount = 1
        sessionState.refreshForAttachmentChange()

        XCTAssertTrue(sessionState.viewState.suggestions.isEmpty)
    }

    /// Loads real suggestions into the state so visibility rules can be observed.
    private func makeSessionStateWithSuggestions(_ suggestions: [ContextualSuggestedPrompt]) {
        mockFeatureFlagger.enabledFeatureFlags = [.contextualSuggestedPrompts]
        sessionState = AIChatContextualChatSessionState(
            aiChatSettings: mockSettings,
            pixelHandler: mockPixelHandler,
            featureFlagger: mockFeatureFlagger,
            suggestedPromptsProvider: MockContextualSuggestedPromptsProvider(suggestions: suggestions)
        )

        let loaded = expectation(description: "suggestions loaded")
        loaded.assertForOverFulfill = false
        sessionState.$viewState
            .dropFirst()
            .sink { state in
                if state.suggestionsLoadState == .loaded, state.suggestions == suggestions {
                    loaded.fulfill()
                }
            }
            .store(in: &cancellables)
        sessionState.markPendingSignalsOnlyCollection()
        sessionState.updateContext(makeTestContext())
        wait(for: [loaded], timeout: 1.0)
    }

    // MARK: - Submission Telemetry

    /// The prompt-submitted pixel must not claim a submission that delivery may still abandon.
    func testDeferredSubmissionPixelDoesNotFireUntilDeliveryIsConfirmed() {
        sessionState.beginChatForUTISubmission(deferringSubmissionPixel: true)
        XCTAssertFalse(mockPixelHandler.promptSubmittedWithoutContextFired)

        sessionState.confirmDeferredSubmissionPixel()
        XCTAssertTrue(mockPixelHandler.promptSubmittedWithoutContextFired)
    }

    func testDiscardedSubmissionPixelNeverFires() {
        sessionState.beginChatForUTISubmission(deferringSubmissionPixel: true)

        sessionState.discardDeferredSubmissionPixel()
        sessionState.confirmDeferredSubmissionPixel()

        XCTAssertFalse(mockPixelHandler.promptSubmittedWithoutContextFired)
    }

    func testConfirmingTwiceFiresOnlyOnce() {
        sessionState.beginChatForUTISubmission(deferringSubmissionPixel: true)

        sessionState.confirmDeferredSubmissionPixel()
        mockPixelHandler.promptSubmittedWithoutContextFired = false
        sessionState.confirmDeferredSubmissionPixel()

        XCTAssertFalse(mockPixelHandler.promptSubmittedWithoutContextFired)
    }

    func testUndeferredSubmissionStillFiresImmediately() {
        sessionState.beginChatForUTISubmission()
        XCTAssertTrue(mockPixelHandler.promptSubmittedWithoutContextFired)
    }

    /// The with/without-context pixels describe page context and are blind to selections, so submitting
    /// with selections attached needs its own signal — otherwise the Ask funnel has no bottom.
    func testSubmittingWithSelectionsReportsHowMany() {
        sessionState.attachSelection(makeSelection("one"), pageTitle: "Article")
        sessionState.attachSelection(makeSelection("two"), pageTitle: "Article")

        sessionState.handlePromptSubmission("what do these say?")

        XCTAssertEqual(mockPixelHandler.promptSubmittedWithSelectionsCounts, [2])
    }

    func testSubmittingWithoutSelectionsReportsNothing() {
        sessionState.handlePromptSubmission("plain question")

        XCTAssertTrue(mockPixelHandler.promptSubmittedWithSelectionsCounts.isEmpty)
    }

    func testUTISubmissionAlsoReportsAttachedSelectionCount() {
        sessionState.attachSelection(makeSelection(), pageTitle: "Article")

        sessionState.beginChatForUTISubmission()

        XCTAssertEqual(mockPixelHandler.promptSubmittedWithSelectionsCounts, [1])
    }

    /// Quick actions survive an attached selection even though suggestions don't. "Ask about page" is
    /// the only route to attaching page context, so hiding it would make a selection and page context
    /// mutually exclusive — which the coexistence decision forbids.
    func testQuickActionsRemainVisibleWhileASelectionIsAttached() {
        sessionState.updateContext(makeTestContext())
        let expected = sessionState.viewState.quickActions
        XCTAssertFalse(expected.isEmpty, "precondition: the page offers quick actions")

        sessionState.attachSelection(makeSelection(), pageTitle: "Article")

        XCTAssertEqual(sessionState.viewState.quickActions, expected)
    }

    /// Attaching a selection re-resolves rather than merely re-rendering: page-scoped and
    /// selection-scoped suggestions are different catalog entries, so without a re-resolve the row would
    /// keep offering "Summarize this page" next to an attached paragraph.
    func testAttachingASelectionReResolvesTheSuggestions() {
        let pageSuggestions = [ContextualSuggestedPrompt(id: "summarize-page", label: "Summarize this page", prompt: "p", icon: nil)]
        makeSessionStateWithSuggestions(pageSuggestions)

        let reResolved = expectation(description: "suggestions re-resolved for the selection scope")
        reResolved.assertForOverFulfill = false
        sessionState.$viewState
            .dropFirst()
            .sink { state in
                if state.suggestionsLoadState == .loading { reResolved.fulfill() }
            }
            .store(in: &cancellables)

        sessionState.attachSelection(makeSelection(), pageTitle: "Article")

        wait(for: [reResolved], timeout: 1.0)
    }

}

// MARK: - Mock Pixel Handler

private final class MockContextualModePixelHandler: AIChatContextualModePixelFiring {
    func fireSelectionAction(_ action: AIChatTextSelectionAction) {}
    func fireSelectionLimitReached() {}
    func fireSelectionRemoved() {}
    func firePromptSubmittedWithSelections(count: Int) { promptSubmittedWithSelectionsCounts.append(count) }
    var promptSubmittedWithSelectionsCounts: [Int] = []
    var sheetOpenedFired = false
    var sheetDismissedFired = false
    var sessionRestoredFired = false
    var expandButtonTappedFired = false
    var newChatButtonTappedFired = false
    var quickActionSummarizeSelectedFired = false
    var quickActionAskAboutPageShownCount = 0
    var fireButtonTappedFired = false
    var fireButtonConfirmedFired = false
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
    func fireHeaderTitleTapped() {}
    func fireNewChatButtonTapped() { newChatButtonTappedFired = true }
    func fireQuickActionSummarizeSelected() { quickActionSummarizeSelectedFired = true }
    func fireQuickActionAskAboutPageShown() { quickActionAskAboutPageShownCount += 1 }
    func fireQuickActionAskAboutPageSelected() {}
    func fireAskAboutPageSuggestionSelected(pageType: SuggestionsPageType) {}
    func fireSuggestionSelected(suggestionId: String, pageType: SuggestionsPageType) {}
    func fireSuggestionsViewed(isSmart: Bool, pageType: SuggestionsPageType) {}
    func fireSuggestionsContextCollectionTimedOut() {}
    func fireRecentChatsPopupDisplayed() {}
    func fireRecentChatSelected() {}
    func fireViewAllChatsTapped() {}
    func fireFireButtonTapped() { fireButtonTappedFired = true }
    func fireFireButtonConfirmed() { fireButtonConfirmedFired = true }
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
        quickActionAskAboutPageShownCount = 0
        fireButtonTappedFired = false
        fireButtonConfirmedFired = false
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

// MARK: - Mock Suggested Prompts Provider

private final class MockContextualSuggestedPromptsProvider: ContextualSuggestedPromptsProviding {
    let suggestions: [ContextualSuggestedPrompt]
    let maxSuggestedPrompts: Int
    let prioritySuggestionIDs: Set<String>
    private(set) var lastInput: ResolvePageSuggestionsInput?

    init(suggestions: [ContextualSuggestedPrompt],
         maxSuggestedPrompts: Int = 4,
         prioritySuggestionIDs: Set<String> = []) {
        self.suggestions = suggestions
        self.maxSuggestedPrompts = maxSuggestedPrompts
        self.prioritySuggestionIDs = prioritySuggestionIDs
    }

    func resolveSuggestions(_ input: ResolvePageSuggestionsInput) async -> ResolvedPageSuggestions {
        lastInput = input
        return ResolvedPageSuggestions(suggestions: suggestions, isSmart: false, pageType: .none)
    }
}

// MARK: - Gated Suggested Prompts Provider

/// Provider whose resolves hang until the test resumes them, for exercising in-flight races.
@MainActor
private final class GatedContextualSuggestedPromptsProvider: ContextualSuggestedPromptsProviding {
    let maxSuggestedPrompts = 4
    let prioritySuggestionIDs: Set<String> = []
    private(set) var startedCount = 0
    private var continuations: [CheckedContinuation<ResolvedPageSuggestions, Never>] = []

    func resolveSuggestions(_ input: ResolvePageSuggestionsInput) async -> ResolvedPageSuggestions {
        startedCount += 1
        return await withCheckedContinuation { continuations.append($0) }
    }

    /// Resumes the resolve started as the `index`-th call (0-based), in any order the test needs.
    func resume(at index: Int, returning suggestions: [ContextualSuggestedPrompt]) {
        continuations[index].resume(returning: ResolvedPageSuggestions(suggestions: suggestions, isSmart: false, pageType: .none))
    }
}

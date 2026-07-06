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

    // MARK: - Helpers

    private func makeTestContext(title: String = "Test Page", url: String = "https://example.com") -> AIChatPageContext {
        let contextData = AIChatPageContextData(
            title: title,
            favicon: [],
            url: url,
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
    var fireButtonTappedFired = false
    var fireButtonConfirmedFired = false
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
    func fireQuickActionAskAboutPageSelected() {}
    func fireRecentChatsPopupDisplayed() {}
    func fireRecentChatSelected() {}
    func fireViewAllChatsTapped() {}
    func fireFireButtonTapped() { fireButtonTappedFired = true }
    func fireFireButtonConfirmed() { fireButtonConfirmedFired = true }
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
        fireButtonTappedFired = false
        fireButtonConfirmedFired = false
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

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

final class AIChatContextualChatSessionStateTests: XCTestCase {

    private var sessionState: AIChatContextualChatSessionState!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sessionState = AIChatContextualChatSessionState()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sessionState = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        // Then
        XCTAssertEqual(sessionState.frontendState, .noChat)
        XCTAssertEqual(sessionState.chipState, .none)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.isShowingNativeInput)
    }

    // MARK: - Frontend Chat State Transition Tests

    func testStartChatWithContext() {
        // When
        sessionState.startChat(withContext: true)

        // Then
        XCTAssertEqual(sessionState.frontendState, .chatWithInitialContext)
    }

    func testStartChatWithoutContext() {
        // When
        sessionState.startChat(withContext: false)

        // Then
        XCTAssertEqual(sessionState.frontendState, .chatWithoutInitialContext)
    }

    func testResetToNoChat() {
        // Given
        sessionState.startChat(withContext: true)
        XCTAssertEqual(sessionState.frontendState, .chatWithInitialContext)

        // When
        sessionState.resetToNoChat()

        // Then
        XCTAssertEqual(sessionState.frontendState, .noChat)
        XCTAssertTrue(sessionState.isShowingNativeInput)
    }

    func testResetToNoChatFromChatWithoutContext() {
        // Given
        sessionState.startChat(withContext: false)
        XCTAssertEqual(sessionState.frontendState, .chatWithoutInitialContext)

        // When
        sessionState.resetToNoChat()

        // Then
        XCTAssertEqual(sessionState.frontendState, .noChat)
    }

    // MARK: - Chip State Transition Tests

    func testAttachChip() {
        // When
        sessionState.attachChip()

        // Then
        XCTAssertEqual(sessionState.chipState, .attached)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testAttachChipClearsUserDowngradeFlag() {
        // Given
        sessionState.attachChip()
        sessionState.handleChipRemoval(hasSnapshot: true)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // When
        sessionState.attachChip()

        // Then
        XCTAssertEqual(sessionState.chipState, .attached)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testShowPlaceholder() {
        // When
        sessionState.showPlaceholder()
        
        // Then
        XCTAssertEqual(sessionState.chipState, .placeholder)
    }

    // MARK: - Handle Chip Removal Tests

    func testHandleChipRemovalWithSnapshotDowngradesToPlaceholder() {
        // Given
        sessionState.attachChip()

        // When
        let result = sessionState.handleChipRemoval(hasSnapshot: true)

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)
    }

    func testHandleChipRemovalWithoutSnapshotHidesChip() {
        // Given
        sessionState.attachChip()

        // When
        let result = sessionState.handleChipRemoval(hasSnapshot: false)

        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(sessionState.chipState, .none)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testHandleChipRemovalWhenNotAttachedReturnsFalse() {
        // Given
        sessionState.showPlaceholder()

        // When
        let result = sessionState.handleChipRemoval(hasSnapshot: true)

        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(sessionState.chipState, .placeholder)
    }

    func testHandleChipRemovalWhenChipIsNoneReturnsFalse() {
        // When
        let result = sessionState.handleChipRemoval(hasSnapshot: true)

        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(sessionState.chipState, .none)
    }

    // MARK: - Reset Chip State For New Chat Tests

    func testResetChipStateForNewChatWithSnapshotAndAutoAttachEnabled() {
        // When
        sessionState.resetChipStateForNewChat(hasSnapshot: true, autoAttachEnabled: true)

        // Then
        XCTAssertEqual(sessionState.chipState, .attached)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testResetChipStateForNewChatWithSnapshotAndAutoAttachDisabled() {
        // When
        sessionState.resetChipStateForNewChat(hasSnapshot: true, autoAttachEnabled: false)

        // Then
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testResetChipStateForNewChatWithoutSnapshot() {
        // When
        sessionState.resetChipStateForNewChat(hasSnapshot: false, autoAttachEnabled: true)

        // Then
        XCTAssertEqual(sessionState.chipState, .none)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testResetChipStateForNewChatWithoutSnapshotAutoAttachDisabled() {
        // When
        sessionState.resetChipStateForNewChat(hasSnapshot: false, autoAttachEnabled: false)

        // Then
        XCTAssertEqual(sessionState.chipState, .none)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testResetChipStateForNewChatClearsUserDowngradeFlag() {
        // Given
        sessionState.attachChip()
        sessionState.handleChipRemoval(hasSnapshot: true)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // When
        sessionState.resetChipStateForNewChat(hasSnapshot: true, autoAttachEnabled: true)

        // Then
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    // MARK: - Business Logic Tests: shouldUpdateUI

    func testShouldUpdateUIReturnsAutoAttachSetting() {
        // When / Then
        XCTAssertTrue(sessionState.shouldUpdateUI(autoAttachEnabled: true))
        XCTAssertFalse(sessionState.shouldUpdateUI(autoAttachEnabled: false))
    }

    // MARK: - Business Logic Tests: canPushToFrontend

    func testCanPushToFrontendWhenChatWithoutInitialContextReturnsTrue() {
        // Given
        sessionState.startChat(withContext: false)

        // When / Then
        XCTAssertTrue(sessionState.canPushToFrontend())
    }

    func testCanPushToFrontendWhenChatWithInitialContextReturnsFalse() {
        // Given
        sessionState.startChat(withContext: true)

        // When / Then
        XCTAssertFalse(sessionState.canPushToFrontend())
    }

    func testCanPushToFrontendWhenNoChatReturnsFalse() {
        // When / Then
        XCTAssertFalse(sessionState.canPushToFrontend())
    }

    // MARK: - Business Logic Tests: shouldAllowAutomaticUpgrade

    func testShouldAllowAutomaticUpgradeWhenUserDidNotDowngradeReturnsTrue() {
        // When / Then
        XCTAssertTrue(sessionState.shouldAllowAutomaticUpgrade())
    }

    func testShouldAllowAutomaticUpgradeWhenUserDowngradedReturnsFalse() {
        // Given
        sessionState.attachChip()
        sessionState.handleChipRemoval(hasSnapshot: true)

        // When / Then
        XCTAssertFalse(sessionState.shouldAllowAutomaticUpgrade())
    }

    // MARK: - Business Logic Tests: clearUserDowngradeOnNavigation

    func testClearUserDowngradeOnNavigationWhenFlagIsSet() {
        // Given
        sessionState.attachChip()
        sessionState.handleChipRemoval(hasSnapshot: true)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)

        // When
        sessionState.clearUserDowngradeOnNavigation()

        // Then
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testClearUserDowngradeOnNavigationWhenFlagIsNotSet() {
        // Given
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)

        // When
        sessionState.clearUserDowngradeOnNavigation()

        // Then
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    // MARK: - Business Logic Tests: isShowingNativeInput

    func testIsShowingNativeInputWhenNoChat() {
        // When / Then
        XCTAssertTrue(sessionState.isShowingNativeInput)
    }

    func testIsShowingNativeInputWhenChatStarted() {
        // Given
        sessionState.startChat(withContext: true)

        // When / Then
        XCTAssertFalse(sessionState.isShowingNativeInput)
    }

    func testIsShowingNativeInputWhenChatStartedWithoutContext() {
        // Given
        sessionState.startChat(withContext: false)

        // When / Then
        XCTAssertFalse(sessionState.isShowingNativeInput)
    }

    func testIsShowingNativeInputAfterReset() {
        // Given
        sessionState.startChat(withContext: true)

        // When
        sessionState.resetToNoChat()

        // Then
        XCTAssertTrue(sessionState.isShowingNativeInput)
    }

    // MARK: - Combine Publisher Tests

    func testFrontendStatePublisherEmitsChanges() {
        // Given
        let expectation = expectation(description: "Frontend state publishes changes")
        var receivedStates: [FrontendChatState] = []

        sessionState.$frontendState
            .sink { state in
                receivedStates.append(state)
                if receivedStates.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.startChat(withContext: true)
        sessionState.resetToNoChat()

        waitForExpectations(timeout: 1.0)

        // Then
        XCTAssertEqual(receivedStates.count, 3)
        XCTAssertEqual(receivedStates[0], .noChat)
        XCTAssertEqual(receivedStates[1], .chatWithInitialContext)
        XCTAssertEqual(receivedStates[2], .noChat)
    }

    func testChipStatePublisherEmitsChanges() {
        // Given
        let expectation = expectation(description: "Chip state publishes changes")
        var receivedStates: [ChipState] = []

        sessionState.$chipState
            .sink { state in
                receivedStates.append(state)
                if receivedStates.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        sessionState.attachChip()
        sessionState.showPlaceholder()

        waitForExpectations(timeout: 1.0)

        // Then
        XCTAssertEqual(receivedStates.count, 3)
        XCTAssertEqual(receivedStates[0], .none)
        XCTAssertEqual(receivedStates[1], .attached)
        XCTAssertEqual(receivedStates[2], .placeholder)
    }

    // MARK: - Complex Scenario Tests

    func testCompleteUserDowngradeAndUpgradeCycle() {
        // Given
        sessionState.attachChip()
        XCTAssertEqual(sessionState.chipState, .attached)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)

        // When
        let shouldShowPlaceholder = sessionState.handleChipRemoval(hasSnapshot: true)

        // Then
        XCTAssertTrue(shouldShowPlaceholder)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertTrue(sessionState.userDowngradedToPlaceholder)
        XCTAssertFalse(sessionState.shouldAllowAutomaticUpgrade())

        // When
        sessionState.clearUserDowngradeOnNavigation()

        // Then
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.shouldAllowAutomaticUpgrade())
    }

    func testNewChatFlowWithAutoAttachOn() {
        // Given
        sessionState.startChat(withContext: true)
        sessionState.attachChip()

        // When
        sessionState.resetToNoChat()
        sessionState.resetChipStateForNewChat(hasSnapshot: true, autoAttachEnabled: true)

        // Then
        XCTAssertEqual(sessionState.frontendState, .noChat)
        XCTAssertEqual(sessionState.chipState, .attached)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.isShowingNativeInput)
    }

    func testNewChatFlowWithAutoAttachOff() {
        // Given
        sessionState.startChat(withContext: false)
        sessionState.showPlaceholder()

        // When
        sessionState.resetToNoChat()
        sessionState.resetChipStateForNewChat(hasSnapshot: true, autoAttachEnabled: false)

        // Then
        XCTAssertEqual(sessionState.frontendState, .noChat)
        XCTAssertEqual(sessionState.chipState, .placeholder)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
        XCTAssertTrue(sessionState.isShowingNativeInput)
    }

    func testContextPushingOnlyAllowedForChatWithoutInitialContext() {
        // Given / When / Then
        XCTAssertFalse(sessionState.canPushToFrontend())

        sessionState.startChat(withContext: false)
        XCTAssertTrue(sessionState.canPushToFrontend())

        sessionState.resetToNoChat()
        sessionState.startChat(withContext: true)
        XCTAssertFalse(sessionState.canPushToFrontend())
    }

    // MARK: - Edge Case Tests

    func testMultipleChipAttachmentsDoNotBreakState() {
        // When
        sessionState.attachChip()
        XCTAssertEqual(sessionState.chipState, .attached)

        sessionState.attachChip()
        XCTAssertEqual(sessionState.chipState, .attached)

        sessionState.attachChip()

        // Then
        XCTAssertEqual(sessionState.chipState, .attached)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testMultipleClearUserDowngradeCallsAreSafe() {
        // When
        sessionState.clearUserDowngradeOnNavigation()
        sessionState.clearUserDowngradeOnNavigation()

        // Then
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }

    func testChipRemovalFromPlaceholderStateDoesNotChangeState() {
        // Given
        sessionState.showPlaceholder()
        let initialState = sessionState.chipState

        // When
        let result = sessionState.handleChipRemoval(hasSnapshot: true)

        // Then
        XCTAssertFalse(result)
        XCTAssertEqual(sessionState.chipState, initialState)
        XCTAssertFalse(sessionState.userDowngradedToPlaceholder)
    }
}

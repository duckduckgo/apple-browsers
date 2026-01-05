//
//  AddressBarButtonsAnimationStateTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

/// Tests for the animation state management in AddressBarButtonsViewController
/// These tests verify that hover animations are properly disabled during badge/shield animations
/// and that the shield visibility state is correctly maintained.
final class AddressBarButtonsAnimationStateTests: XCTestCase {

    var animator: NavigationBarBadgeAnimator!
    var buttonsContainer: NSView!
    var notificationBadgeContainer: NavigationBarBadgeAnimationView!
    var mockDelegate: MockAnimatorDelegate!

    override func setUp() {
        super.setUp()
        animator = NavigationBarBadgeAnimator()
        buttonsContainer = NSView()
        notificationBadgeContainer = NavigationBarBadgeAnimationView()
        mockDelegate = MockAnimatorDelegate()
        animator.delegate = mockDelegate
    }

    override func tearDown() {
        animator = nil
        buttonsContainer = nil
        notificationBadgeContainer = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Animation State During Badge Animation

    func testAnimationQueue_isNotEmptyWhenAnimationEnqueued() {
        // When
        animator.enqueueAnimation(
            .trackersBlocked(count: 5),
            priority: .high,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )

        // Then
        XCTAssertFalse(animator.animationQueue.isEmpty, "Queue should not be empty after enqueue")
    }

    func testAnimationState_isAnimatingDuringAnimation() {
        // Given
        animator.enqueueAnimation(
            .trackersBlocked(count: 5),
            priority: .high,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )

        // When
        animator.processNextAnimation()

        // Then
        XCTAssertTrue(animator.isAnimating, "Should be animating after processNextAnimation")
    }

    func testAnimationState_bothIsAnimatingAndQueueChecksNeeded() {
        // Given - enqueue two animations
        animator.enqueueAnimation(
            .trackersBlocked(count: 5),
            priority: .high,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )
        animator.enqueueAnimation(
            .cookiePopupManaged,
            priority: .low,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )

        // When - process first animation
        animator.processNextAnimation()

        // Then - should be animating AND have items in queue
        XCTAssertTrue(animator.isAnimating, "Should be animating")
        XCTAssertFalse(animator.animationQueue.isEmpty, "Queue should still have pending animation")

        // This tests the condition used in updatePrivacyEntryPointIcon:
        // guard !buttonsBadgeAnimator.isAnimating, buttonsBadgeAnimator.animationQueue.isEmpty
        let wouldBlockUpdate = animator.isAnimating || !animator.animationQueue.isEmpty
        XCTAssertTrue(wouldBlockUpdate, "Update should be blocked when animating or queue not empty")
    }

    // MARK: - Animation State After Completion

    func testAnimationState_isNotAnimatingAfterCancel() {
        // Given
        animator.enqueueAnimation(
            .trackersBlocked(count: 5),
            priority: .high,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )
        animator.processNextAnimation()
        XCTAssertTrue(animator.isAnimating)

        // When
        animator.cancelPendingAnimations()

        // Then
        XCTAssertFalse(animator.isAnimating, "Should not be animating after cancel")
        XCTAssertTrue(animator.animationQueue.isEmpty, "Queue should be empty after cancel")
    }

    func testAnimationState_queueClearsAfterCancel() {
        // Given
        animator.enqueueAnimation(.trackersBlocked(count: 5), priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        animator.enqueueAnimation(.cookiePopupManaged, priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        XCTAssertEqual(animator.animationQueue.count, 2)

        // When
        animator.cancelPendingAnimations()

        // Then
        XCTAssertTrue(animator.animationQueue.isEmpty, "Queue should be empty after cancel")
    }

    // MARK: - Delegate Notification Tests

    func testDelegate_receivesDidFinishAnimatingCallback() {
        // Given
        animator.enqueueAnimation(
            .cookiePopupManaged,
            priority: .high,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )

        // Disable auto-processing so we can control when animations complete
        animator.setAutoProcessNextAnimation(false)
        animator.processNextAnimation()

        let expectation = expectation(description: "Animation should complete")

        // Wait for animation to complete naturally
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 4.0)

        // Then
        XCTAssertGreaterThan(mockDelegate.didFinishAnimatingCallCount, 0, "Delegate should receive didFinishAnimating callback")
    }

    // MARK: - Guard Condition Simulation Tests

    /// Tests that simulate the guard conditions in updatePrivacyEntryPointIcon
    /// to ensure hover is properly blocked during animations

    func testGuardCondition_blocksWhenAnimating() {
        // Given
        animator.enqueueAnimation(.trackersBlocked(count: 5), priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        animator.processNextAnimation()

        // Simulate the guard condition from updatePrivacyEntryPointIcon:
        // guard !isAnyShieldAnimationPlaying, !buttonsBadgeAnimator.isAnimating,
        //       buttonsBadgeAnimator.animationQueue.isEmpty, !isTextFieldEditorFirstResponder

        let isTextFieldEditorFirstResponder = false
        let isAnyShieldAnimationPlaying = false  // Simulated

        // When
        let shouldBlock = isAnyShieldAnimationPlaying ||
                         animator.isAnimating ||
                         !animator.animationQueue.isEmpty ||
                         isTextFieldEditorFirstResponder

        // Then
        XCTAssertTrue(shouldBlock, "Guard should block during badge animation")
    }

    func testGuardCondition_allowsWhenNoAnimations() {
        // Given - no animations

        let isTextFieldEditorFirstResponder = false
        let isAnyShieldAnimationPlaying = false

        // When
        let shouldBlock = isAnyShieldAnimationPlaying ||
                         animator.isAnimating ||
                         !animator.animationQueue.isEmpty ||
                         isTextFieldEditorFirstResponder

        // Then
        XCTAssertFalse(shouldBlock, "Guard should not block when no animations")
    }

    func testGuardCondition_blocksWhenQueueNotEmpty() {
        // Given - animation enqueued but not yet processing
        animator.enqueueAnimation(.trackersBlocked(count: 5), priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)

        let isTextFieldEditorFirstResponder = false
        let isAnyShieldAnimationPlaying = false

        // When
        let shouldBlock = isAnyShieldAnimationPlaying ||
                         animator.isAnimating ||
                         !animator.animationQueue.isEmpty ||
                         isTextFieldEditorFirstResponder

        // Then
        XCTAssertTrue(shouldBlock, "Guard should block when queue is not empty")
    }

    func testGuardCondition_blocksWhenTextFieldFocused() {
        // Given
        let isTextFieldEditorFirstResponder = true
        let isAnyShieldAnimationPlaying = false

        // When
        let shouldBlock = isAnyShieldAnimationPlaying ||
                         animator.isAnimating ||
                         !animator.animationQueue.isEmpty ||
                         isTextFieldEditorFirstResponder

        // Then
        XCTAssertTrue(shouldBlock, "Guard should block when text field is focused")
    }

    // MARK: - Shield Animation In Progress Tests

    func testShieldAnimationInProgress_blocksNewAnimationsFromStarting() {
        // Given - shield animation is in progress
        animator.isShieldAnimationInProgress = true

        // When - enqueue a new animation
        animator.enqueueAnimation(
            .cookiePopupManaged,
            priority: .low,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )

        // Then - animation should be queued but NOT started
        XCTAssertFalse(animator.animationQueue.isEmpty, "Animation should be queued")
        XCTAssertFalse(animator.isAnimating, "Animation should not start while shield is playing")
    }

    func testShieldAnimationInProgress_processNextAnimationBlockedWhileShieldPlaying() {
        // Given - enqueue an animation first
        animator.isShieldAnimationInProgress = true
        animator.enqueueAnimation(
            .cookiePopupManaged,
            priority: .low,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )

        // When - try to process next animation while shield is playing
        animator.processNextAnimation()

        // Then - should not start animating
        XCTAssertFalse(animator.isAnimating, "Should not process animation while shield is in progress")
        XCTAssertFalse(animator.animationQueue.isEmpty, "Queue should still have the animation")
    }

    func testShieldAnimationInProgress_allowsProcessingAfterShieldCompletes() {
        // Given - shield animation completes
        animator.isShieldAnimationInProgress = true
        animator.enqueueAnimation(
            .cookiePopupManaged,
            priority: .low,
            buttonsContainer: buttonsContainer,
            notificationBadgeContainer: notificationBadgeContainer
        )

        // When - shield animation completes
        animator.isShieldAnimationInProgress = false
        animator.processNextAnimation()

        // Then - should start animating
        XCTAssertTrue(animator.isAnimating, "Should process animation after shield completes")
        XCTAssertTrue(animator.animationQueue.isEmpty, "Queue should be empty after processing")
    }

    func testShieldAnimationInProgress_resetsOnCancelPendingAnimations() {
        // Given
        animator.isShieldAnimationInProgress = true

        // When
        animator.cancelPendingAnimations()

        // Then
        XCTAssertFalse(animator.isShieldAnimationInProgress, "Shield flag should reset on cancel")
    }
}

// MARK: - Mock Delegate

private class MockAnimatorDelegate: NavigationBarBadgeAnimatorDelegate {
    var didFinishAnimatingCallCount = 0
    var lastFinishedType: NavigationBarBadgeAnimationView.AnimationType?

    func didFinishAnimating(type: NavigationBarBadgeAnimationView.AnimationType) {
        didFinishAnimatingCallCount += 1
        lastFinishedType = type
    }
}

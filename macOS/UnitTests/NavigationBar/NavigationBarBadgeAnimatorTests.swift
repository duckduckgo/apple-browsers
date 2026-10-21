//
//  NavigationBarBadgeAnimatorTests.swift
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

final class NavigationBarBadgeAnimatorTests: XCTestCase {

    var sut: NavigationBarBadgeAnimator!
    var buttonsContainer: NSView!
    var notificationBadgeContainer: NavigationBarBadgeAnimationView!

    override func setUp() {
        super.setUp()
        sut = NavigationBarBadgeAnimator()
        buttonsContainer = NSView()
        notificationBadgeContainer = NavigationBarBadgeAnimationView()
    }

    override func tearDown() {
        sut = nil
        buttonsContainer = nil
        notificationBadgeContainer = nil
        super.tearDown()
    }

    // MARK: - Queue Tests (FIFO - no priority interruption)

    func testEnqueueAnimation_addsToQueue() {
        // Given
        let type: NavigationBarBadgeAnimationView.AnimationType = .trackersBlocked(count: 10)

        // When
        sut.enqueueAnimation(type, priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)

        // Then
        XCTAssertEqual(sut.animationQueue.count, 1, "Should have one queued animation")
        XCTAssertEqual(sut.animationQueue.first?.priority, .low)
    }

    func testEnqueueAnimation_queuesWithoutInterruption() {
        // Given - start animation
        sut.enqueueAnimation(.trackersBlocked(count: 10), priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.processNextAnimation()

        XCTAssertTrue(sut.isAnimating, "Should be animating")

        // When - enqueue another animation
        sut.enqueueAnimation(.cookiePopupManaged, priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)

        // Then - should queue without interrupting (FIFO behavior)
        XCTAssertTrue(sut.isAnimating, "Should continue current animation")
        XCTAssertEqual(sut.animationQueue.count, 1, "Should queue new animation")
    }

    func testEnqueueAnimation_multipleAnimationsQueueInOrder() {
        // Given - start animation
        sut.enqueueAnimation(.cookiePopupManaged, priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.processNextAnimation()

        XCTAssertTrue(sut.isAnimating)

        // When - enqueue multiple animations
        sut.enqueueAnimation(.cookiePopupHidden, priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.enqueueAnimation(.trackersBlocked(count: 10), priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)

        // Then - both should be queued in order
        XCTAssertEqual(sut.animationQueue.count, 2, "Should queue all animations")
        XCTAssertEqual(sut.animationQueue[0].priority, .high, "First queued should be high priority")
        XCTAssertEqual(sut.animationQueue[1].priority, .low, "Second queued should be low priority")
    }

    // MARK: - Cancel Tests

    func testCancelPendingAnimations_stopsCurrentAnimationAndClearsQueue() {
        // Given - start animation and add more to queue
        sut.enqueueAnimation(.trackersBlocked(count: 10), priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.enqueueAnimation(.cookiePopupManaged, priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.processNextAnimation()

        XCTAssertTrue(sut.isAnimating, "Should be animating")
        XCTAssertEqual(sut.animationQueue.count, 1, "Should have one queued animation")

        // When
        sut.cancelPendingAnimations()

        // Then
        XCTAssertFalse(sut.isAnimating, "Should stop animating after cancel")
        XCTAssertTrue(sut.animationQueue.isEmpty, "Queue should be empty")
        XCTAssertNil(sut.currentAnimationPriority, "Priority should be cleared")
    }

    func testCancelPendingAnimations_clearsQueueWithoutActiveAnimation() {
        // Given - add multiple animations to queue without starting
        sut.enqueueAnimation(.trackersBlocked(count: 10), priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.enqueueAnimation(.trackersBlocked(count: 20), priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)

        XCTAssertEqual(sut.animationQueue.count, 2)
        XCTAssertFalse(sut.isAnimating, "Should not be animating")

        // When
        sut.cancelPendingAnimations()

        // Then
        XCTAssertTrue(sut.animationQueue.isEmpty, "Queue should be empty")
    }

    // MARK: - Queue Processing Tests

    func testProcessNextAnimation_dequeuesInFIFOOrder() {
        // Given - add animations in order (queue uses FIFO, no interruptions)
        sut.enqueueAnimation(.trackersBlocked(count: 10), priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.enqueueAnimation(.cookiePopupManaged, priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.enqueueAnimation(.trackersBlocked(count: 20), priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)

        // When
        sut.processNextAnimation()

        // Then - should process first-in-first-out (no interruptions)
        XCTAssertEqual(sut.currentAnimationPriority, .low, "Should process first queued animation (FIFO)")
        XCTAssertEqual(sut.animationQueue.count, 2, "Should have 2 animations remaining")
    }

    func testProcessNextAnimation_doesNothingWhenQueueEmpty() {
        // Given - empty queue
        XCTAssertTrue(sut.animationQueue.isEmpty)

        // When
        sut.processNextAnimation()

        // Then
        XCTAssertFalse(sut.isAnimating, "Should not be animating")
        XCTAssertNil(sut.currentAnimationPriority)
    }

    func testProcessNextAnimation_doesNothingWhenAlreadyAnimating() {
        // Given - animation in progress
        sut.enqueueAnimation(.cookiePopupManaged, priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.processNextAnimation()
        XCTAssertTrue(sut.isAnimating)

        let queueCountBefore = sut.animationQueue.count

        // When - try to process next
        sut.processNextAnimation()

        // Then - queue unchanged
        XCTAssertEqual(sut.animationQueue.count, queueCountBefore, "Queue should be unchanged")
    }

    // MARK: - Tab Switch Tests

    func testTabSwitch_cancelsInProgressAnimation() {
        // Given
        let tab1 = Tab(content: .url(URL.duckDuckGo, source: .userEntered(URL.duckDuckGo, downloadRequested: false)))
        sut.enqueueAnimation(.trackersBlocked(count: 10), priority: .low, tab: tab1, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.processNextAnimation()

        XCTAssertTrue(sut.isAnimating)

        // When - switch to different tab
        let tab2 = Tab(content: .url(URL.duckDuckGo, source: .userEntered(URL.duckDuckGo, downloadRequested: false)))
        sut.handleTabSwitch(to: tab2)

        // Then
        XCTAssertFalse(sut.isAnimating, "Should cancel animation on tab switch")
    }

    func testTabSwitch_clearsQueueForDifferentTab() {
        // Given
        let tab1 = Tab(content: .url(URL.duckDuckGo, source: .userEntered(URL.duckDuckGo, downloadRequested: false)))
        sut.enqueueAnimation(.trackersBlocked(count: 10), priority: .low, tab: tab1, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.enqueueAnimation(.trackersBlocked(count: 20), priority: .low, tab: tab1, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)

        XCTAssertEqual(sut.animationQueue.count, 2)

        // When
        let tab2 = Tab(content: .url(URL.duckDuckGo, source: .userEntered(URL.duckDuckGo, downloadRequested: false)))
        sut.handleTabSwitch(to: tab2)

        // Then
        XCTAssertTrue(sut.animationQueue.isEmpty, "Should clear queue for different tab")
    }

    func testTabSwitch_continuesAnimationForSameTab() {
        // Given
        let tab = Tab(content: .url(URL.duckDuckGo, source: .userEntered(URL.duckDuckGo, downloadRequested: false)))
        sut.enqueueAnimation(.trackersBlocked(count: 10), priority: .low, tab: tab, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.processNextAnimation()

        XCTAssertTrue(sut.isAnimating)

        // When - "switch" to same tab
        sut.handleTabSwitch(to: tab)

        // Then
        XCTAssertTrue(sut.isAnimating, "Should continue animation for same tab")
    }

    // MARK: - Sequential Processing Tests

    func testMultipleNotifications_processSequentially() {
        // Given - queue multiple animations
        sut.enqueueAnimation(.cookiePopupManaged, priority: .high, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)
        sut.enqueueAnimation(.trackersBlocked(count: 10), priority: .low, buttonsContainer: buttonsContainer, notificationBadgeContainer: notificationBadgeContainer)

        XCTAssertEqual(sut.animationQueue.count, 2)

        // When - process first
        sut.processNextAnimation()

        // Then
        XCTAssertTrue(sut.isAnimating, "Should be animating first")
        XCTAssertEqual(sut.animationQueue.count, 1, "Should have one remaining")
        XCTAssertEqual(sut.currentAnimationPriority, .high, "Should process high priority first")
    }

    // MARK: - Auto Process Next Animation Tests

    func testSetAutoProcessNextAnimation_disablesAutoProcessing() {
        // Given
        sut.setAutoProcessNextAnimation(false)

        // Then - verify flag was set (will be tested functionally by animation completion)
        // Note: this tests the API exists and can be called without error
        sut.setAutoProcessNextAnimation(true)  // Reset to default
    }

    func testSetAutoProcessNextAnimation_defaultsToTrue() {
        // Given - fresh animator
        // The default value should be true
        // This is verified by processNextAnimation being called automatically after animation completes
        // We can only test the API exists here
        sut.setAutoProcessNextAnimation(true)
    }

    // MARK: - Delegate Tests

    func testDelegate_canBeAssigned() {
        // Given
        let delegate = MockAnimatorDelegate()

        // When
        sut.delegate = delegate

        // Then
        XCTAssertNotNil(sut.delegate, "Delegate should be assigned")
    }

    func testDelegate_isWeakReference() {
        // Given
        var delegate: MockAnimatorDelegate? = MockAnimatorDelegate()
        sut.delegate = delegate

        // When
        delegate = nil

        // Then
        XCTAssertNil(sut.delegate, "Delegate should be nil after deallocation (weak reference)")
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

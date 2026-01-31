//
//  WarnBeforeQuitManagerTests.swift
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

import AppKit
import Combine
import Common
import OSLog
import PixelKit
import PixelKitTestingUtilities
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WarnBeforeQuitManagerTests: XCTestCase, Sendable {

    enum Constants {
        static let earlyReleaseTimeAdvance: TimeInterval = 0.01
        static let expectationTimeout: TimeInterval = 1.0
    }

    override var allowedNonNilVariables: Set<String> {
        ["collectedStatesLock"]
    }

    var now: Date!
    var stateTask: Task<Void, Never>?

    nonisolated(unsafe) private var _collectedStates: [WarnBeforeQuitManager.State] = []
    nonisolated(unsafe) private var collectedStatesLock: NSLock = NSLock()
    nonisolated(unsafe) private var testCompleted: Bool = false
    nonisolated var collectedStates: [WarnBeforeQuitManager.State] {
        get {
            collectedStatesLock.withLock { return _collectedStates }
        }
        _modify {
            collectedStatesLock.withLock {
                if testCompleted {
                    XCTFail("[\(name)] State mutation after test completion")
                }
            }
            collectedStatesLock.lock()
            yield &_collectedStates
            collectedStatesLock.unlock()
        }
    }
    nonisolated(unsafe) var expectations: [XCTestExpectation] = []

    // Expected time values captured at test start
    var startTime: TimeInterval!
    var targetTime: TimeInterval!

    // Simple boolean flag for testing warning enabled state
    var isWarningEnabled: Bool = true

    // Mock delegate for testing
    var mockDelegate: MockWarnBeforeQuitManagerDelegate!

    override func setUp() async throws {
        now = Date()
        _collectedStates = []
        testCompleted = false

        // Capture expected times at test start (before manager advances time)
        startTime = now.timeIntervalSinceReferenceDate
        targetTime = startTime + WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration

        // Reset warning enabled state
        isWarningEnabled = true

        // Create mock delegate
        mockDelegate = MockWarnBeforeQuitManagerDelegate()
        mockDelegate.repostedEvents = []
    }

    override func tearDown() async throws {
        // Mark test as completed to detect state leakage
        collectedStatesLock.withLock {
            testCompleted = true
        }

        // Cancel state collection task
        stateTask?.cancel()
        stateTask = nil

        // Clear collected states and expectations
        _collectedStates = []
        expectations = []
        now = nil
        startTime = nil
        targetTime = nil
        isWarningEnabled = true
        customAssert = nil
        TestRunHelper.allowAppSendUserEvents = false

        // Clean up mock delegate
        mockDelegate = nil
    }

    // MARK: - Initialization Tests

    func testInitWithValidCmdQEventSucceeds() {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, delegate: mockDelegate)

        // Then
        XCTAssertNotNil(manager)
    }

    func testInitWithInvalidEventFails() {
        // Given - keyUp event
        let event = createKeyEvent(type: .keyUp, character: "q", modifierFlags: .command)

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, delegate: mockDelegate)

        // Then
        XCTAssertNil(manager)
    }

    func testInitWithoutModifierFails() {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q")

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, delegate: mockDelegate)

        // Then
        XCTAssertNil(manager)
    }

    func testInitWithCmdWEventSucceeds() {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, action: .close, isWarningEnabled: { self.isWarningEnabled }, delegate: mockDelegate)

        // Then
        XCTAssertNotNil(manager)
    }

    func testInitFiltersDeviceDependentFlags() {
        // Given - Cmd+Q with device-dependent flags mixed in
        let flagsWithDeviceDependent: NSEvent.ModifierFlags = [.command, .numericPad, .function]
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: flagsWithDeviceDependent)

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, delegate: mockDelegate)

        // Then - Manager should be created and filter to only device-independent flags
        XCTAssertNotNil(manager, "Manager should successfully filter device-dependent flags")
    }

    // MARK: - State Stream Tests

    func testStateStreamEmitsHoldingAndCompletedStatesWhenHoldDurationReached() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Event receiver that advances time past the deadline (hold duration + animation buffer)
        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, animationDelay: 0, delegate: mockDelegate))

        // When
        let expectations = setupExpectationsForStateChanges(3, manager: manager)

        // Start shouldTerminate - it will enter sync event loop and complete hold
        let query = manager.shouldTerminate(isAsync: false)

        // Wait for both states
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - quit action returns async decision to fire pixel before quitting
        guard case .async(let task) = query else {
            XCTFail("Expected async decision for quit action (fires pixel), got: \(query)")
            return
        }

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        XCTAssertEqual(decision, .next)
        // Time was advanced past progressThreshold directly to full duration, so .holding startTime reflects that
        let holdingStartTime = startTime + totalDuration + Constants.earlyReleaseTimeAdvance
        let holdingTargetTime = holdingStartTime + WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .holding(startTime: holdingStartTime, targetTime: holdingTargetTime),
            .completed(shouldProceed: true)
        ])

        // Verify warning wasn't disabled
        XCTAssertTrue(isWarningEnabled)
    }

    func testEarlyReleaseTransitionsToWaitingForSecondPress() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mock timer that captures callback
        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, block in
            timerCallback = block
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, timerFactory: timerFactory, animationDelay: 0, delegate: mockDelegate))

        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // When - start shouldTerminate - key will be released early (before progressThreshold)
        let query = manager.shouldTerminate(isAsync: false)

        // Wait for both states
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - should return async query for waiting phase
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress
        ])

        // Clean up task by triggering timer callback
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)
        timerCallback?()
        _ = try? await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)
    }

    func testStateStreamEmitsCompletedWhenSecondPressReceived() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, timerFactory: timerFactory, animationDelay: 0, delegate: mockDelegate))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start shouldTerminate
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips first .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(3, manager: manager)

        // Post second Cmd+Q keydown - this triggers new .keyDown -> .holding -> .completed sequence
        let secondPress = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        Logger.tests.debug("\(self.name): Calling interceptor with \(secondPress) time: \(self.now)")
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(secondPress)

        // Wait for async task and completion state
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then
        XCTAssertEqual(decision, .next)
        // Second press is a full hold so it has .keyDown -> .holding -> .completed
        let secondPressStartTime = startTime + Constants.earlyReleaseTimeAdvance + WarnBeforeQuitManager.Constants.progressThreshold
        let secondPressTargetTime = secondPressStartTime + WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .keyDown,
            .holding(startTime: secondPressStartTime, targetTime: secondPressTargetTime),
            .completed(shouldProceed: true)
        ])
    }

    func testStateStreamEmitsCompletedWhenEscapePressed() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, timerFactory: timerFactory, animationDelay: 0, delegate: mockDelegate))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start shouldTerminate
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Post Escape keydown
        let escapeEvent = createKeyEvent(type: .keyDown, character: "\u{1B}", keyCode: 53)
        Logger.tests.debug("\(self.name): Calling interceptor with \(escapeEvent) time: \(self.now)")
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        let consumedEvent = mockDelegate.eventInterceptor?.interceptor(escapeEvent)
        XCTAssertNil(consumedEvent, "Escape should be consumed (return nil), not passed through")
        XCTAssertEqual(mockDelegate.repostedEvents, [], "Escape should not be in repostedEvents")

        // Wait for async task and completion state
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - should cancel and Escape was consumed (not passed through)
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])

        // Verify warning wasn't disabled
        XCTAssertTrue(isWarningEnabled)
    }

    func testStateStreamEmitsCompletedWhenTimerExpires() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mock timer that captures duration and callback
        var capturedDuration: TimeInterval?
        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { duration, block in
            capturedDuration = duration
            timerCallback = block
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, timerFactory: timerFactory, animationDelay: 0, delegate: mockDelegate))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start shouldTerminate
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        // Then - verify timer was created with correct duration
        XCTAssertEqual(capturedDuration, WarnBeforeQuitManager.Constants.hideawayDuration)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Fire the timer to trigger completion
        timerCallback?()

        // Wait for completion state and task
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])
    }

    // MARK: - ApplicationTerminationDecider Tests

    func testShouldTerminateReturnsNextWhenAsync() throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, animationDelay: 0, delegate: mockDelegate))

        // When
        let query = manager.shouldTerminate(isAsync: true)

        // Then
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision, got: \(query)")
            return
        }
        XCTAssertEqual(decision, .next)
    }

    // MARK: - Don't Ask Again Tests

    func testShouldTerminateReturnsNextWhenWarningDisabled() throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, animationDelay: 0, delegate: mockDelegate))

        // Verify initial state
        XCTAssertTrue(isWarningEnabled)

        // When - disable warning by setting preference
        isWarningEnabled = false

        // Then - subsequent calls return .sync(.next) immediately
        let query = manager.shouldTerminate(isAsync: false)
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision, got: \(query)")
            return
        }
        XCTAssertEqual(decision, .next)
    }

    func testDisableWarningBreaksSynchronousLoop() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let dummyEvent = createKeyEvent(type: .flagsChanged, modifierFlags: .command)

        var manager: WarnBeforeQuitManager!
        var expectations: [XCTestExpectation]!

        // Event receiver that waits for .keyDown on call 1, disables preference on call 2 (warning disabled before .holding)
        let eventReceiver = makeEventReceiver(events: [
            (event: dummyEvent, timeAdvance: 0),  // First call
            (event: dummyEvent, timeAdvance: 0),  // Second call - triggers preference disable
            (event: dummyEvent, timeAdvance: 0)   // Third call - guard check will trigger "Warning disabled" path
        ]) { [weak self] callCount in
            if let self, callCount == 1 {
                // Wait for .keyDown state to be collected
                wait(for: expectations, timeout: Constants.expectationTimeout)
            } else if callCount == 2 {
                // Second call: disable warning preference to break loop before .holding
                self!.isWarningEnabled = false
            }
        }

        mockDelegate.eventReceiver = eventReceiver
        manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, animationDelay: 0, delegate: mockDelegate))
        // Receive .keyDown state
        expectations = setupExpectationsForStateChanges(1, manager: manager)

        // Verify initial state
        XCTAssertTrue(isWarningEnabled)

        // Receive .completed state
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // When - start the termination flow
        let queryTask = Task { @MainActor in
            manager!.shouldTerminate(isAsync: false)
        }

        // Wait for completion
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)
        let query = try await queryTask.value(cancellingTaskOnTimeout: Constants.expectationTimeout)

        // Then - warning should be disabled
        XCTAssertFalse(isWarningEnabled)

        // And quit action returns async to fire pixel (hold completed successfully)
        guard case .async(let task) = query else {
            XCTFail("Expected async decision for quit action (fires pixel), got: \(query)")
            return
        }

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        XCTAssertEqual(decision, .next)

        // Verify both states were collected (warning disabled before .holding, so it's skipped)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .completed(shouldProceed: true)
        ])
    }

    func testHoldingKeyToCompletionQuitsApp() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        // Event receiver that advances time past the deadline (hold duration + animation buffer)
        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // When - user holds key to completion
        let expectations = setupExpectationsForStateChanges(3, manager: manager)

        let query = manager.shouldTerminate(isAsync: false)

        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - holding key to completion allows quit
        guard case .async(let task) = query else {
            XCTFail("Expected async decision for quit action (fires pixel), got: \(query)")
            return
        }

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        XCTAssertEqual(decision, .next)

        // Verify flow went through keyDown -> holding -> completed
        let holdingStartTime = startTime + totalDuration + Constants.earlyReleaseTimeAdvance
        let holdingTargetTime = holdingStartTime + WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .holding(startTime: holdingStartTime, targetTime: holdingTargetTime),
            .completed(shouldProceed: true)
        ])

        pixelFiring.verifyExpectations()
    }

    func testDisableWarningDuringAsyncWait() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mock timer that doesn't fire automatically
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // Verify initial state
        XCTAssertTrue(isWarningEnabled)

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start async wait
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Disable warning during async wait by setting preference
        isWarningEnabled = false

        // Post a mouse click to trigger the async check in the event handler
        // The DispatchQueue.main.async will check isWarningEnabled() and resume with true
        let mouseClick = createMouseEvent(type: .leftMouseDown)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(mouseClick)

        // Wait for completion
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Clicking after disabling preference makes resume() return true (quit allowed)
        XCTAssertEqual(decision, .next)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: true)
        ])

        // Verify event was passed through (reposted when warning is disabled)
        XCTAssertEqual(mockDelegate.repostedEvents, [mouseClick], "Mouse event should be reposted exactly once when warning is disabled")
    }

    func testShouldTerminateAfterDisabled() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, animationDelay: 0, delegate: mockDelegate))

        // Start state collection to verify no states are emitted
        _ = setupExpectationsForStateChanges(0, manager: manager)

        // Verify initial state
        XCTAssertTrue(isWarningEnabled)

        // When - disable warning by setting preference
        isWarningEnabled = false

        // Then - subsequent calls return .sync(.next) immediately
        let query = manager.shouldTerminate(isAsync: false)
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision after disabling, got: \(query)")
            return
        }
        XCTAssertEqual(decision, .next)

        // Verify no states were collected (bypassed state machine)
        XCTAssertTrue(collectedStates.isEmpty)
    }

    func testTaskCancellationTriggersCleanup() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        // Use REAL timer to verify cancellation behavior
        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, animationDelay: 0, delegate: mockDelegate))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start async wait (real timer created with 4.0s duration)
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Cancel the task - should trigger cleanup
        task.cancel()

        // Wait for the task to complete after cancellation
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - verify decision is cancel
        XCTAssertEqual(decision, .cancel)

        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])

        // Verify callbacks don't crash after completion
        manager.setMouseHovering(true)
        manager.setMouseHovering(false)
    }

    // MARK: - Hover State Tests

    func testHoverBeforeWaitPhaseStoresStateInternally() throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, animationDelay: 0, delegate: mockDelegate))

        // When - hover called before entering wait phase (no callback set)
        // Then - should store state internally without crashing
        manager.setMouseHovering(true)
        manager.setMouseHovering(false)
        manager.setMouseHovering(true)
    }

    func testHoverDuringWaitPhasePausesTimer() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])

        var expectations: [XCTestExpectation]!

        // Event receiver that waits for .keyDown on call 0, then returns release event (early release skips .holding)
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ]) { [weak self] callCount in
            if let self, callCount == 0 {
                // Wait for .keyDown state to be collected
                wait(for: expectations, timeout: Constants.expectationTimeout)
            }
        }

        // Mock timer that captures all durations and the callback
        var capturedDurations: [TimeInterval] = []
        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { duration, callback in
            capturedDurations.append(duration)
            timerCallback = callback
            return Timer()
        }

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, timerFactory: timerFactory, animationDelay: 0, delegate: mockDelegate))

        // Receive .keyDown state
        expectations = setupExpectationsForStateChanges(1, manager: manager)

        // Receive .waitingForSecondPress state
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // When - start wait phase (timer starts with normal duration)
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for waiting state
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Verify initial timer created with normal hideaway duration
        XCTAssertEqual(capturedDurations.count, 1)
        XCTAssertEqual(capturedDurations[0], WarnBeforeQuitManager.Constants.hideawayDuration)

        // Hover (stops timer) then exit hover (restarts timer)
        manager.setMouseHovering(true)
        manager.setMouseHovering(false)

        // Then - verify timer was restarted with normal duration (no extended duration anymore)
        XCTAssertEqual(capturedDurations.count, 2)
        XCTAssertEqual(capturedDurations[1], WarnBeforeQuitManager.Constants.hideawayDuration)

        // Verify both states were collected (early release skips .holding)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress
        ])

        // Trigger timer expiry to cancel
        let expectations3 = setupExpectationsForStateChanges(1, manager: manager)
        timerCallback?()

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations3, timeout: Constants.expectationTimeout)

        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])
    }

    // MARK: - Multiple shouldTerminate Calls Tests

    func testMultipleShouldTerminateCallsWhileFirstInProgress() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mock timer that captures callback
        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, block in
            timerCallback = block
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, timerFactory: timerFactory, animationDelay: 0, delegate: mockDelegate))

        // Set up state collection for first call's states (expecting 2 states: .keyDown and .waitingForSecondPress)
        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // When - first call returns async
        let query1 = manager.shouldTerminate(isAsync: false)
        guard case .async(let task1) = query1 else {
            XCTFail("Expected first call to return async query, got: \(query1)")
            return
        }

        // Set custom assertion handler to verify it fires
        var assertionFired = false
        customAssert = { condition, message, file, line in
            let conditionValue = condition()
            guard !conditionValue else { return }
            assertionFired = true
            let messageValue = message()
            Logger.tests.debug("\(self.name): Assertion fired: \(messageValue) at \(file):\(line)")
        }
        // Second call immediately while first is still in progress
        let query2 = manager.shouldTerminate(isAsync: false)

        // Then - second call should return .sync(.next) because first is already in progress
        guard case .sync(let decision) = query2 else {
            XCTFail("Expected second call to return sync decision, got: \(query2)")
            task1.cancel()
            return
        }
        XCTAssertEqual(decision, .next)

        // Verify assertion fired (currentState was not .idle)
        XCTAssertTrue(assertionFired, "Assertion should have fired when second call detected currentState != .idle")

        // Wait for first call's states (.keyDown and .waitingForSecondPress, early release skips .holding)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Verify only first call's states were collected (second call bypassed state machine)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress
        ])

        // Clean up task by triggering timer callback
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)
        timerCallback?()
        _ = try? await task1.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)
    }

    func testShouldTerminateAfterCompletionWithCancel() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mock timer that captures callback
        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, block in
            timerCallback = block
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        // Provide event only for first call - second call should not enter event loop
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, timerFactory: timerFactory, animationDelay: 0, delegate: mockDelegate))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - first flow completes with cancel (timer expires)
        let query1 = manager.shouldTerminate(isAsync: false)
        guard case .async(let task1) = query1 else {
            XCTFail("Expected async query, got: \(query1)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Fire timer to complete first flow
        timerCallback?()

        Logger.tests.debug("\(self.name): Waiting for first flow to complete")
        let decision1 = try await task1.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - first flow cancels
        XCTAssertEqual(decision1, .cancel)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])

        // Track assertion for second call (currentState is .completed from first flow, not .idle)
        var assertionFired = false
        customAssert = { condition, message, file, line in
            let conditionValue = condition()
            guard !conditionValue else { return }
            assertionFired = true
            let messageValue = message()
            Logger.tests.debug("\(self.name): Assertion fired: \(messageValue) at \(file):\(line)")
        }

        // When - call shouldTerminate again after completion
        let query2 = manager.shouldTerminate(isAsync: false)

        // Verify assertion fired (currentState was not .idle after first flow)
        XCTAssertTrue(assertionFired, "Assertion should have fired when second call detected currentState != .idle")

        // Then - should return .sync(.next) because currentState is .completed, not .idle
        guard case .sync(let decision2) = query2 else {
            XCTFail("Expected second call to return sync decision, got: \(query2)")
            return
        }
        XCTAssertEqual(decision2, .next)

        // Verify only first flow's states were collected (second call bypassed state machine)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])
    }

    // MARK: - Character Key Release Tests

    func testEarlyReleaseFollowedBySecondPressCompletes() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let qKeyUpEvent = createKeyEvent(type: .keyUp, character: "q", modifierFlags: .command)
        let eventReceiver = makeEventReceiver(events: [
            (event: qKeyUpEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, action: .quit, isWarningEnabled: { self.isWarningEnabled }, now: { self.now }, timerFactory: timerFactory, animationDelay: 0, delegate: mockDelegate))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start termination flow
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips first .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(3, manager: manager)

        // Post second Q keydown (while Cmd still held) - this triggers new .keyDown -> .holding -> .completed sequence
        let secondPress = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(secondPress)

        // Wait for completion
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - should complete with quit allowed
        XCTAssertEqual(decision, .next)
        // Second press is a full hold so it has .keyDown -> .holding -> .completed
        let secondPressStartTime = startTime + Constants.earlyReleaseTimeAdvance + WarnBeforeQuitManager.Constants.progressThreshold
        let secondPressTargetTime = secondPressStartTime + WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .keyDown,
            .holding(startTime: secondPressStartTime, targetTime: secondPressTargetTime),
            .completed(shouldProceed: true)
        ])
    }

    // MARK: - Mouse Click Tests

    func testLeftMouseClickDuringWait() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start async wait
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Simulate left mouse click
        let mouseClick = createMouseEvent(type: .leftMouseDown)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed during waitingForSecondPress")
        _ = mockDelegate.eventInterceptor?.interceptor(mouseClick)

        // Wait for completion
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - should cancel
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])

        // Verify event was reposted
        XCTAssertEqual(mockDelegate.repostedEvents, [mouseClick], "Mouse event should be reposted exactly once")

        // Verify pixels were fired
        pixelFiring.verifyExpectations()
    }

    func testRightMouseClickDuringWait() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start async wait
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Simulate right mouse click
        let mouseClick = createMouseEvent(type: .rightMouseDown)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed during waitingForSecondPress")
        _ = mockDelegate.eventInterceptor?.interceptor(mouseClick)

        // Wait for completion
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - should cancel
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])

        // Verify event was reposted
        XCTAssertEqual(mockDelegate.repostedEvents, [mouseClick], "Mouse event should be reposted exactly once")

        // Verify pixels were fired
        pixelFiring.verifyExpectations()
    }

    func testOtherKeyPressDuringWait() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        // Mock timer to prevent automatic expiry (event will cancel instead)
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let qKeyUpEvent = createKeyEvent(type: .keyUp, character: "q", modifierFlags: .command)
        let eventReceiver = makeEventReceiver(events: [
            (event: qKeyUpEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start termination flow
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Post unrelated key (should cancel but pass through)
        let otherKey = createKeyEvent(type: .keyDown, character: "a", modifierFlags: [])
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(otherKey)

        // Wait for completion
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - should cancel (not quit) and event was passed through
        XCTAssertEqual(decision, .cancel)

        // Verify event was passed through (reposted)
        XCTAssertEqual(mockDelegate.repostedEvents, [otherKey], "Other key event should be reposted exactly once")
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])

        // Verify pixels were fired
        pixelFiring.verifyExpectations()
    }

    func testOtherMouseDownCancelsFlow() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start async wait
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Simulate other mouse button click
        let mouseClick = createMouseEvent(type: .otherMouseDown)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(mouseClick)

        let interceptorResetExpectation = expectation(description: "Event interceptor reset")
        mockDelegate.didResetInterceptor = {
            interceptorResetExpectation.fulfill()
        }

        // Wait for completion
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2 + [interceptorResetExpectation], timeout: Constants.expectationTimeout)

        // Then - should cancel
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])

        // Verify event was reposted
        XCTAssertNil(mockDelegate.eventInterceptor, "Event interceptor should be reset after completion")
        XCTAssertEqual(mockDelegate.repostedEvents, [mouseClick], "Mouse event should be reposted exactly once")

        // Verify pixels were fired
        pixelFiring.verifyExpectations()
    }

    // MARK: - Complex State Flow Tests

    func testWaitingForSecondPressToHoldingToQuickTapComplete() async throws {
        // Given - wait -> hold (2nd press) -> early release -> quick tap completes
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        // Mock timer to prevent automatic expiry during waiting phases
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])

        // Event receiver provides events for each hold phase:
        // 1. First hold: release early (before progressThreshold) → waitingForSecondPress
        // 2. Second hold: reach threshold (→ holding), then release after quickTapDetectionBuffer → back to waitingForSecondPress  
        // 3. Third hold: quick tap (release before progressThreshold) → confirms and completes
        // Note: To avoid quick-tap confirmation on second hold, it must be released after progressThreshold + quickTapDetectionBuffer (0.15s total)
        let secondHoldReleaseTime: TimeInterval = 0.06  // After reaching threshold (0.1s), release at 0.06s = 0.16s total (> 0.15s threshold)

        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance),             // First hold: release at 0.01s
            (event: nil, timeAdvance: WarnBeforeQuitManager.Constants.progressThreshold),      // Second hold: advance to progress threshold
            (event: releaseEvent, timeAdvance: secondHoldReleaseTime),                         // Second hold: release while in holding (total 0.16s)
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)              // Third hold: quick tap at 0.01s confirms
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // Expect: keyDown -> waitingForSecondPress
        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start flow
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        // Now in waitingForSecondPress - post second press
        // Expect: keyDown -> holding -> waitingForSecondPress
        let expectations2 = setupExpectationsForStateChanges(3, manager: manager)

        let secondPress = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(secondPress)

        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Now in waitingForSecondPress again - post third press (quick tap)
        // Expect: keyDown -> waitingForSecondPress -> completed (quick tap sets waitingForSecondPress, then confirms)
        let expectations3 = setupExpectationsForStateChanges(3, manager: manager)

        let thirdPress = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(thirdPress)

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations3, timeout: Constants.expectationTimeout)

        // Then
        XCTAssertEqual(decision, .next)

        // Verify state progression: first press early release, second press hold then release, third press quick tap confirms
        // Second press's holding state starts after first release + progressThreshold
        let secondPressHoldingStartTime = startTime + Constants.earlyReleaseTimeAdvance + WarnBeforeQuitManager.Constants.progressThreshold
        XCTAssertEqual(collectedStates, [
            .keyDown,                                   // First press starts
            .waitingForSecondPress,                     // First press released early
            .keyDown,                                   // Second press starts
            .holding(startTime: secondPressHoldingStartTime, targetTime: secondPressHoldingStartTime + WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration),  // Second press reaches threshold
            .waitingForSecondPress,                     // Second press released during holding
            .keyDown,                                   // Third press starts (quick tap)
            .waitingForSecondPress,                     // Third press released (before quick tap check)
            .completed(shouldProceed: true)             // Third press quick tap confirmed
        ])

        pixelFiring.verifyExpectations()
    }

    func testWaitingForSecondPressToHoldingToWaitingToTimeout() async throws {
        // Given - wait -> hold (2nd press) -> early release -> wait times out
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, callback in
            timerCallback = callback
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let secondReleaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])

        // Release after progressThreshold to ensure we're in holding state (total > 0.15s to avoid quick tap)
        let secondHoldReleaseTime: TimeInterval = 0.06  // After threshold, release at +0.06s (total 0.16s > 0.15s)

        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance),           // First release - enter waiting
            (event: nil, timeAdvance: WarnBeforeQuitManager.Constants.progressThreshold),    // Second press: advance to threshold
            (event: secondReleaseEvent, timeAdvance: secondHoldReleaseTime)                  // Second release during holding - back to waiting
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // Expect states: .keyDown -> .waitingForSecondPress
        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        // Post second press during waiting
        // Expect states: .keyDown -> .holding -> .waitingForSecondPress
        let expectations2 = setupExpectationsForStateChanges(3, manager: manager)

        let secondPress = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(secondPress)

        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Now trigger timer expiry
        let expectations3 = setupExpectationsForStateChanges(1, manager: manager)
        timerCallback?()

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations3, timeout: Constants.expectationTimeout)

        // Then
        XCTAssertEqual(decision, .cancel)

        // Verify state progression
        // Second press's holding state starts after first release + progressThreshold
        let secondPressHoldingStartTime = startTime + Constants.earlyReleaseTimeAdvance + WarnBeforeQuitManager.Constants.progressThreshold
        XCTAssertEqual(collectedStates, [
            .keyDown,                                   // First press starts
            .waitingForSecondPress,                     // First press released early
            .keyDown,                                   // Second press starts
            .holding(startTime: secondPressHoldingStartTime, targetTime: secondPressHoldingStartTime + WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration),  // Second press reaches threshold
            .waitingForSecondPress,                     // Second press released during holding
            .completed(shouldProceed: false)            // Timer expires
        ])

        pixelFiring.verifyExpectations()
    }

    func testWaitingForKeyReleaseAfterCompletion() async throws {
        // Given - user holds key through completion and releases after
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let releaseEvent = createKeyEvent(type: .keyUp, character: "q", modifierFlags: .command)

        // Flow: advance to threshold -> complete hold -> wait for key release -> key released
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: WarnBeforeQuitManager.Constants.progressThreshold),  // Advance to threshold (enter holding)
            (event: nil, timeAdvance: WarnBeforeQuitManager.Constants.requiredHoldDuration),  // Complete hold
            (event: releaseEvent, timeAdvance: 0)  // Key released in waitForKeyRelease
        ])

        // Mock modifier check to return true (key is held) to trigger waitForKeyRelease loop
        let isModifierHeld: (NSEvent.ModifierFlags) -> Bool = { _ in true }

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            isModifierHeld: isModifierHeld,
            delegate: mockDelegate
        ))

        // Expect states: .keyDown -> .holding -> .completed
        let stateExpectations = setupExpectationsForStateChanges(3, manager: manager)

        // When
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: stateExpectations, timeout: Constants.expectationTimeout)

        // Then - flow completes successfully
        XCTAssertEqual(decision, .next)

        let holdingStartTime = startTime + WarnBeforeQuitManager.Constants.progressThreshold
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .holding(startTime: holdingStartTime, targetTime: holdingStartTime + totalDuration),
            .completed(shouldProceed: true)
        ])

        // Call deciderSequenceCompleted to trigger waitForKeyRelease (simulates ApplicationTerminationDeciderProxy behavior)
        manager.deciderSequenceCompleted(shouldProceed: true)

        pixelFiring.verifyExpectations()
    }

    func testWaitingForSecondPressCancelledByOtherKey() async throws {
        // Given - first press released early, then other key pressed during waiting
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])

        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)  // First release - enter waiting
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // Expect states: .keyDown -> .waitingForSecondPress
        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        // Post other key press during waiting
        // Expect state: .completed(shouldProceed: false)
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        let otherKeyPress = createKeyEvent(type: .keyDown, character: "x", modifierFlags: [])
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(otherKeyPress)

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - should cancel
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .waitingForSecondPress,
            .completed(shouldProceed: false)
        ])

        // Verify pixels were fired
        pixelFiring.verifyExpectations()
    }

    // MARK: - Event Reposting Tests

    func testOtherEventsRepostedDuringHold() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mouse events are reposted and cancel the flow
        let mouseEvent = createMouseEvent(type: .leftMouseDown)

        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: Constants.earlyReleaseTimeAdvance),  // First, advance to enter .holding state
            (event: mouseEvent, timeAdvance: 0)  // Then return mouse event - should repost and cancel
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // When - mouse event received during .holding state
        let stateExpectations = setupExpectationsForStateChanges(3, manager: manager)

        let query = manager.shouldTerminate(isAsync: false)

        await fulfillment(of: stateExpectations, timeout: Constants.expectationTimeout)

        // Then - quit action returns .sync(.cancel) (pixel fires in detached Task)
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision with .cancel, got: \(query)")
            return
        }

        XCTAssertEqual(decision, .cancel)

        // During holding phase, events come through eventReceiver and are reposted via delegate.postEvent
        XCTAssertEqual(mockDelegate.repostedEvents, [mouseEvent], "Mouse event should be reposted exactly once during holding phase")

        // Verify flow entered .holding then was cancelled
        let holdingStartTime = startTime + Constants.earlyReleaseTimeAdvance
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .holding(startTime: holdingStartTime, targetTime: holdingStartTime + WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration),
            .completed(shouldProceed: false)
        ])

        // Verify pixels were fired
        pixelFiring.verifyExpectations()
    }

    // MARK: - Action-Specific Behavior Tests

    func testQuitActionWithCompletionReturnsAsyncWhenShouldQuit() async throws {
        // Given - quit action that completes with shouldQuit=true
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // When - hold completes with shouldQuit=true
        let expectations = setupExpectationsForStateChanges(3, manager: manager)
        let query = manager.shouldTerminate(isAsync: false)

        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - should return .async with pixel firing task
        guard case .async(let task) = query else {
            XCTFail("Expected async query for quit action with shouldQuit=true, got: \(query)")
            return
        }

        // Wait for async task to complete
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        XCTAssertEqual(decision, .next)

        // Verify pixels were fired
        pixelFiring.verifyExpectations()
    }

    func testQuitActionWithCancellationReturnsSyncCancel() async throws {
        // Given - quit action that cancels (shouldQuit=false)
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, callback in
            timerCallback = callback
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // When
        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // When - key released early, enters waitingForSecondPress
        let query = manager.shouldTerminate(isAsync: false)

        // Then - should return .async for wait phase
        guard case .async(let task) = query else {
            XCTFail("Expected async query for wait phase, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Now set up expectation for completion state BEFORE triggering timer
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Trigger timer expiry to cancel
        timerCallback?()

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        XCTAssertEqual(decision, .cancel)

        // Verify pixels were fired
        pixelFiring.verifyExpectations()
    }

    func testCloseTabActionReturnsSyncImmediately() async throws {
        // Given - close tab action (not quit)
        let event = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            // No pixels should be fired for close tab action
        ])

        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .close,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // When - hold completes
        let expectations = setupExpectationsForStateChanges(3, manager: manager)
        let query = manager.shouldTerminate(isAsync: false)

        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - should return .sync immediately (not .async) for close tab action
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision for close tab action, got: \(query)")
            return
        }
        XCTAssertEqual(decision, .next)

        // Verify no pixels were fired
        pixelFiring.verifyExpectations()
    }

    func testCloseTabActionReturnsSyncCancelWhenCancelled() async throws {
        // Given - close tab action that gets cancelled
        let event = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            // No pixels should be fired for close tab action
        ])

        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, callback in
            timerCallback = callback
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .close,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // When - key released early
        let query = manager.shouldTerminate(isAsync: false)

        // Then - should return .async for wait phase
        guard case .async(let task) = query else {
            XCTFail("Expected async query for wait phase, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Now set up expectation for completion state BEFORE triggering timer
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Trigger timer expiry to cancel
        timerCallback?()

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        XCTAssertEqual(decision, .cancel)

        // Verify no pixels were fired
        pixelFiring.verifyExpectations()
    }

    func testCloseTabActionReturnsSyncCancelWhenCancelledDuringHold() async throws {
        // Given - close tab action cancelled by other key during holding phase
        let event = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            // No pixels should be fired for close tab action
        ])

        let otherKeyEvent = createKeyEvent(type: .keyDown, character: "x", modifierFlags: [])
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: Constants.earlyReleaseTimeAdvance),  // Advance to enter holding
            (event: otherKeyEvent, timeAdvance: 0)  // Other key cancels
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .close,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // Expect states: .keyDown -> .holding -> .completed(shouldProceed: false)
        let expectations = setupExpectationsForStateChanges(3, manager: manager)

        // When - other key pressed during hold
        let query = manager.shouldTerminate(isAsync: false)

        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - should return .sync(.cancel) immediately for close tab action
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision for close tab action, got: \(query)")
            return
        }
        XCTAssertEqual(decision, .cancel)

        // Verify state progression: keyDown -> holding -> completed(shouldProceed: false)
        let holdingStartTime = startTime + Constants.earlyReleaseTimeAdvance
        XCTAssertEqual(collectedStates, [
            .keyDown,
            .holding(startTime: holdingStartTime, targetTime: holdingStartTime + WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration),
            .completed(shouldProceed: false)
        ])

        // Verify no pixels were fired
        pixelFiring.verifyExpectations()
    }

    func testEventInterceptorInstalledWhenQuittingViaHold() async throws {
        // Given - quit action that completes successfully via hold
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // When - hold completes
        let expectations = setupExpectationsForStateChanges(3, manager: manager)
        let query = manager.shouldTerminate(isAsync: false)

        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - should return .async with event interceptor installed
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Verify event interceptor is installed
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed when quitting")

        // Test that interceptor consumes Cmd+Q events
        let cmdQEvent = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let result = mockDelegate.eventInterceptor?.interceptor(cmdQEvent)
        XCTAssertNil(result, "Event interceptor should consume Cmd+Q events")

        // Test that interceptor passes through other events
        let otherEvent = createKeyEvent(type: .keyDown, character: "a", modifierFlags: [])
        let passedThrough = mockDelegate.eventInterceptor?.interceptor(otherEvent)
        XCTAssertNotNil(passedThrough, "Event interceptor should pass through non-Cmd+Q events")

        // Clean up
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        XCTAssertEqual(decision, .next)
        pixelFiring.verifyExpectations()
    }

    func testEventInterceptorInstalledWhenClosingTabViaHold() async throws {
        // Given - close tab action that completes successfully via hold
        let event = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)

        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .close,
            isWarningEnabled: { self.isWarningEnabled },
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // When - hold completes
        let expectations = setupExpectationsForStateChanges(3, manager: manager)
        let query = manager.shouldTerminate(isAsync: false)

        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - should return .sync with event interceptor installed
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision for close tab action, got: \(query)")
            return
        }
        XCTAssertEqual(decision, .next)

        // Verify event interceptor is installed (prevents beeps for Cmd+W)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed when closing tab")

        // Test that interceptor consumes Cmd+W events
        let cmdWEvent = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)
        let result = mockDelegate.eventInterceptor?.interceptor(cmdWEvent)
        XCTAssertNil(result, "Event interceptor should consume Cmd+W events")

        // Test that interceptor passes through other events
        let otherEvent = createKeyEvent(type: .keyDown, character: "a", modifierFlags: [])
        let passedThrough = mockDelegate.eventInterceptor?.interceptor(otherEvent)
        XCTAssertNotNil(passedThrough, "Event interceptor should pass through non-Cmd+W events")
    }

    func testEventInterceptorInstalledWhenQuittingViaSecondPress() async throws {
        // Given - quit action with second press
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start termination flow
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(3, manager: manager)

        // Post second press - triggers new .keyDown -> .holding -> .completed sequence
        let secondPress = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(secondPress)

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - event interceptor should be installed after second press
        XCTAssertEqual(decision, .next)

        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed after second press")

        // Test that interceptor consumes Cmd+Q events
        let cmdQEvent = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let result = mockDelegate.eventInterceptor?.interceptor(cmdQEvent)
        XCTAssertNil(result, "Event interceptor should consume Cmd+Q events")

        pixelFiring.verifyExpectations()
    }

    func testEventInterceptorInstalledWhenClosingTabViaSecondPress() async throws {
        // Given - close tab action with second press
        let event = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .close,
            isWarningEnabled: { self.isWarningEnabled },
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start termination flow
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(3, manager: manager)

        // Post second press - triggers new .keyDown -> .holding -> .completed sequence
        let secondPress = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(secondPress)

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - event interceptor should be installed after second press
        XCTAssertEqual(decision, .next)

        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed for close tab after second press")

        // Test that interceptor consumes Cmd+W events
        let cmdWEvent = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)
        let result = mockDelegate.eventInterceptor?.interceptor(cmdWEvent)
        XCTAssertNil(result, "Event interceptor should consume Cmd+W events")
    }

    func testEventInterceptorNotInstalledWhenCancelling() async throws {
        // Given - quit action that gets cancelled via timer expiry
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, callback in
            timerCallback = callback
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // When - key released early
        let query = manager.shouldTerminate(isAsync: false)

        // Then - should return .async for wait phase
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Now set up expectation for completion state BEFORE triggering timer
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Trigger timer expiry to cancel the wait
        timerCallback?()

        // Wait for async task and completion state
        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        XCTAssertEqual(decision, .cancel)

        // Verify event interceptor is cleaned up after cancelling
        XCTAssertNil(mockDelegate.eventInterceptor, "Event interceptor should be cleaned up after cancelling")

        pixelFiring.verifyExpectations()
    }

    // MARK: - Pixel Firing Tests

    func testShownPixelFiredWhenEnteringHoldingState() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        // When
        let expectations = setupExpectationsForStateChanges(3, manager: manager)
        let query = manager.shouldTerminate(isAsync: false)

        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - quit action returns async to fire pixel
        guard case .async(let task) = query else {
            XCTFail("Expected async decision for quit action (fires pixel), got: \(query)")
            return
        }

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        XCTAssertEqual(decision, .next)
        pixelFiring.verifyExpectations()
    }

    func testCancelledPixelFiredWhenKeyReleasedEarly() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, callback in
            timerCallback = callback
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // When
        let query = manager.shouldTerminate(isAsync: false)

        // Then
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Now set up expectation for completion state BEFORE triggering timer
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Trigger timer expiry to cancel
        timerCallback?()

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        XCTAssertEqual(decision, .cancel)

        pixelFiring.verifyExpectations()
    }

    func testConfirmedPixelFiredOnSecondPress() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        // Mock timer to prevent automatic expiry
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(3, manager: manager)

        // Post second press - triggers new .keyDown -> .holding -> .completed sequence
        let secondPress = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed")
        _ = mockDelegate.eventInterceptor?.interceptor(secondPress)

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then
        XCTAssertEqual(decision, .next)
        pixelFiring.verifyExpectations()
    }

    // MARK: - Key Release Wait Tests
    //
    // These tests verify that waitForKeyRelease is ONLY called during the synchronous
    // event handling phase (when we're actively consuming keyDown events), and NOT
    // called from deciderSequenceCompleted (which happens after
    // async operations complete and we're no longer in the event loop context).

    func testWaitForKeyReleaseCalledFromDelegateCallbackNotDuringHoldingPhase() async throws {
        // Given - quit action that completes by holding
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        var callCount = 0
        let eventReceiver: (NSEvent.EventTypeMask, Date, RunLoop.Mode, Bool) -> NSEvent? = { [self] mask, deadline, _, _ in
            defer { callCount += 1 }

            if callCount == 0 {
                // First call (.keyDown phase): advance time past progressThreshold
                now = now.addingTimeInterval(WarnBeforeQuitManager.Constants.progressThreshold + 0.001)
                return nil
            } else if callCount == 1 {
                // Second call (.holding phase): advance time past full hold duration
                now = now.addingTimeInterval(WarnBeforeQuitManager.Constants.requiredHoldDuration)
                return nil
            } else {
                // Third call onwards: would be waitForKeyRelease checking for key up
                // But in test environment, NSEvent.modifierFlags is empty, so waitForKeyRelease
                // returns early without actually waiting (it detects key is already released)
                return createKeyEvent(type: .keyUp, character: "q", modifierFlags: [])
            }
        }

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations = setupExpectationsForStateChanges(3, manager: manager)

        // When - complete the quit sequence
        let query = manager.shouldTerminate(isAsync: false)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - eventReceiver should be called twice during holding phase (.keyDown then .holding)
        XCTAssertEqual(callCount, 2, "eventReceiver should be called twice during holding phase (.keyDown and .holding)")

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        XCTAssertEqual(decision, .next)

        // When deciderSequenceCompleted is called after async operations,
        // it should call waitForKeyRelease (which returns early in test environment since modifiers are not held)
        manager.deciderSequenceCompleted(shouldProceed: true)

        // Then - waitForKeyRelease was called and returned early (eventReceiver not called again since modifiers are empty)
        // The key check is that isShortcutKeyHeld is properly managed
        XCTAssertEqual(callCount, 2, "eventReceiver should not be called again since NSEvent.modifierFlags is empty in test environment")

        pixelFiring.verifyExpectations()
    }

    // MARK: - deciderSequenceCompleted Tests

    func testSequenceCompletedCalledWithTrueWhenQuitting() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations = setupExpectationsForStateChanges(3, manager: manager)

        // When - complete the quit sequence
        let query = manager.shouldTerminate(isAsync: false)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        XCTAssertEqual(decision, .next)

        // Then - simulate handler calling deciderSequenceCompleted
        manager.deciderSequenceCompleted(shouldProceed: true)

        // Verify the callback was received (no crash, cleanup performed)
        // The actual cleanup behavior would be verified by checking internal state
        // For now, we just verify the method can be called without issues
    }

    func testSequenceCompletedCalledWithFalseWhenCancelling() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitCancelled, frequency: .standard)
        ])

        var timerCallback: (() -> Void)?
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, callback in
            timerCallback = callback
            return Timer()
        }

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            timerFactory: timerFactory,
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // When - cancel the quit sequence
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        // Wait for .keyDown and .waitingForSecondPress states (early release skips .holding)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Now set up expectation for completion state BEFORE triggering timer
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Trigger timer expiry to cancel
        timerCallback?()

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        XCTAssertEqual(decision, .cancel)

        // Then - simulate handler calling deciderSequenceCompleted
        manager.deciderSequenceCompleted(shouldProceed: false)

        // Verify the callback was received (no crash, cleanup performed)
    }

    func testSequenceCompletedCanBeCalledMultipleTimes() throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            animationDelay: 0
        ))

        // When/Then - calling multiple times should not crash
        manager.deciderSequenceCompleted(shouldProceed: true)
        manager.deciderSequenceCompleted(shouldProceed: false)
        manager.deciderSequenceCompleted(shouldProceed: true)

        // No assertion needed - just verifying no crash occurs
    }

    func testDeciderSequenceCompletedCleansUpEventInterceptor() async throws {
        // Given - quit action that completes via hold and installs event interceptor
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let pixelFiring = PixelKitMock(expecting: [
            .init(pixel: GeneralPixel.warnBeforeQuitShown, frequency: .dailyAndCount),
            .init(pixel: GeneralPixel.warnBeforeQuitQuit, frequency: .standard)
        ])

        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .quit,
            isWarningEnabled: { self.isWarningEnabled },
            pixelFiring: pixelFiring,
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations = setupExpectationsForStateChanges(3, manager: manager)

        // When - hold completes
        let query = manager.shouldTerminate(isAsync: false)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        guard case .async(let task) = query else {
            XCTFail("Expected async query, got: \(query)")
            return
        }

        let decision = try await task.value(cancellingTaskOnTimeout: Constants.expectationTimeout)
        XCTAssertEqual(decision, .next)

        // Then - verify event interceptor is installed
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed after hold completes")

        // When - deciderSequenceCompleted is called
        manager.deciderSequenceCompleted(shouldProceed: true)

        // Wait for async cleanup to complete
        let cleanupExpectation = expectation(description: "Event interceptor cleanup")
        DispatchQueue.main.async {
            cleanupExpectation.fulfill()
        }
        await fulfillment(of: [cleanupExpectation], timeout: Constants.expectationTimeout)

        // Then - event interceptor should be cleaned up
        XCTAssertNil(mockDelegate.eventInterceptor, "Event interceptor should be cleaned up after deciderSequenceCompleted")

        pixelFiring.verifyExpectations()
    }

    func testDeciderSequenceCompletedCleansUpEventInterceptorForCloseTab() async throws {
        // Given - close tab action that completes via hold and installs event interceptor
        let event = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)

        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        let eventReceiver = makeEventReceiver(events: [
            (event: nil, timeAdvance: totalDuration + Constants.earlyReleaseTimeAdvance)
        ])

        mockDelegate.eventReceiver = eventReceiver
        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            action: .close,
            isWarningEnabled: { self.isWarningEnabled },
            now: { self.now },
            animationDelay: 0,
            delegate: mockDelegate
        ))

        let expectations = setupExpectationsForStateChanges(3, manager: manager)

        // When - hold completes
        let query = manager.shouldTerminate(isAsync: false)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision for close tab action, got: \(query)")
            return
        }
        XCTAssertEqual(decision, .next)

        // Then - verify event interceptor is installed
        XCTAssertNotNil(mockDelegate.eventInterceptor, "Event interceptor should be installed after hold completes")

        // When - deciderSequenceCompleted is called (as MainMenuActions does)
        manager.deciderSequenceCompleted(shouldProceed: true)

        // Wait for async cleanup to complete
        let cleanupExpectation = expectation(description: "Event interceptor cleanup")
        DispatchQueue.main.async {
            cleanupExpectation.fulfill()
        }
        await fulfillment(of: [cleanupExpectation], timeout: Constants.expectationTimeout)

        // Then - event interceptor should be cleaned up
        XCTAssertNil(mockDelegate.eventInterceptor, "Event interceptor should be cleaned up after deciderSequenceCompleted")
    }

    func testPixelFiringTimeout() async throws {
        // Given - pixel that never completes (simulates network timeout)
        final class SlowPixelFiring: PixelFiring, Sendable {
            let fireExpectation: XCTestExpectation
            let completionExpectation: XCTestExpectation
            init(fireExpectation: XCTestExpectation, completionExpectation: XCTestExpectation) {
                self.fireExpectation = fireExpectation
                self.completionExpectation = completionExpectation
            }
            public func fire(_ event: PixelKitEvent,
                             frequency: PixelKit.Frequency,
                             withAdditionalParameters: [String: String]?,
                             onComplete: @escaping PixelKit.CompletionBlock) {
                fireExpectation.fulfill()
                // Never call completion handler - simulates timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.completionExpectation.fulfill()
                    onComplete(true, nil)
                }
            }
        }
        let fireExpectation = expectation(description: "Pixel fired")
        let completionExpectation = expectation(description: "Completion called")
        completionExpectation.isInverted = true
        let pixelFiring = SlowPixelFiring(fireExpectation: fireExpectation, completionExpectation: completionExpectation)
        await pixelFiring.fireAndWait(GeneralPixel.warnBeforeQuitQuit, frequency: .standard, timeout: 0.1)

        await fulfillment(of: [fireExpectation, completionExpectation], timeout: 0.2)
    }

    // MARK: - Helpers

    /// Sets up expectations for N state changes and starts observing the state stream
    /// - Parameters:
    ///   - count: Number of state changes to expect
    ///   - manager: The manager to observe
    /// - Returns: Array of expectations to wait for
    func setupExpectationsForStateChanges(_ count: Int, manager: WarnBeforeQuitManager) -> [XCTestExpectation] {
        let newExpectations = (0..<count).map { expectation(description: "State change \($0 + expectations.count)") }
        expectations.append(contentsOf: newExpectations)
        // the 1st task keeps going
        guard expectations.count == newExpectations.count else { return newExpectations }

        stateTask = Task.detached { [weak self, name] in
            var expectationIndex = 0

            Logger.tests.debug("\(name): Subscribed to state stream")
            for await state in manager.stateStream {
                guard let self else { break }

                // Check if test has completed - fail if state collection continues
                let isCompleted = self.collectedStatesLock.withLock { self.testCompleted }
                if isCompleted {
                    XCTFail("[\(name)] State emitted after test completion: \(String(describing: state))")
                    break
                }

                // Thread-safe state collection via computed property
                Logger.tests.debug("\(name): Collected state \(String(describing: state)), fulfilling expectation at: \(expectationIndex)")
                self.collectedStates.append(state)

                guard expectationIndex < self.expectations.count else {
                    XCTFail("\(name): Tried to fulfill expectation at index \(expectationIndex) but there are only \(self.expectations.count)")
                    break
                }

                let expectation = self.expectations[expectationIndex]

                expectation.fulfill()
                expectationIndex += 1
            }
        }

        return newExpectations
    }

    /// Creates an event receiver that returns a sequence of events
    /// - Parameter events: Array of tuples containing optional event and time advance
    /// - Returns: Event receiver closure
    func makeEventReceiver(events: [(event: NSEvent?, timeAdvance: TimeInterval)], onCall: ((Int) -> Void)? = nil) -> (NSEvent.EventTypeMask, Date, RunLoop.Mode, Bool) -> NSEvent? {
        var callCount = 0

        return { [weak self, name] _, deadline, _, _ in
            guard let self else { return nil }
            defer { callCount += 1 }

            // Check if we've exceeded the configured events
            guard callCount < events.count else {
                // No more events configured - advance time to deadline to simulate waiting
                let timeToDeadline = deadline.timeIntervalSinceReferenceDate - self.now.timeIntervalSinceReferenceDate
                if timeToDeadline > 0 {
                    self.now = deadline
                    Logger.tests.debug("\(name): Event receiver call \(callCount) - no more events, advanced time by \(timeToDeadline) to deadline, returning nil")
                } else {
                    Logger.tests.debug("\(name): Event receiver call \(callCount) - no more events, already at/past deadline, returning nil")
                }
                return nil
            }

            let (event, timeAdvance) = events[callCount]

            // Advance time if specified
            if timeAdvance > 0 {
                self.now = self.now.addingTimeInterval(timeAdvance)
            }

            // Check if deadline reached
            if self.now >= deadline {
                Logger.tests.debug("\(name): Event receiver call \(callCount) - deadline reached, returning nil\(timeAdvance > 0 ? ", advanced time by \(timeAdvance)" : "")")
                return nil
            }

            // Execute custom action before returning event
            onCall?(callCount)

            if let event = event {
                Logger.tests.debug("\(name): Event receiver call \(callCount) - returning event: \(event)\(timeAdvance > 0 ? ", advanced time by \(timeAdvance)" : "")")
            } else {
                Logger.tests.debug("\(name): Event receiver call \(callCount) - returning nil\(timeAdvance > 0 ? ", advanced time by \(timeAdvance)" : "")")
            }
            return event
        }
    }

    private func createKeyEvent(
        type: NSEvent.EventType,
        character: String = "",
        modifierFlags: NSEvent.ModifierFlags = [],
        keyCode: UInt16 = 0
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func createMouseEvent(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 100, y: 0),
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
    }
}

@MainActor
final class MockWarnBeforeQuitManagerDelegate: WarnBeforeQuitManagerDelegate {
    var eventInterceptor: (token: UUID, interceptor: ((NSEvent) -> NSEvent?))?
    var didResetInterceptor: (() -> Void)?

    // Events that were passed through (reposted) by the interceptor
    var repostedEvents: [NSEvent] = []

    // Custom event receiver for testing (replaces nextEvent)
    var eventReceiver: ((NSEvent.EventTypeMask, Date, RunLoop.Mode, Bool) -> NSEvent?)?

    var eventInterceptorToken: UUID? {
        eventInterceptor?.token
    }

    func installEventInterceptor(token: UUID, interceptor: @escaping (NSEvent) -> NSEvent?) {
        // Only install if no existing interceptor or token matches (same pattern as Application)
        guard eventInterceptor == nil || eventInterceptor?.token == token else { return }
        // Wrap the interceptor to track reposted events
        eventInterceptor = (token: token, interceptor: { [weak self] event in
            let result = interceptor(event)
            // If interceptor returns event (not nil), it was reposted/passed through
            if let repostedEvent = result {
                self?.repostedEvents.append(repostedEvent)
            }
            return result
        })
    }

    func resetEventInterceptor(token: UUID?) {
        guard eventInterceptor?.token == token else { return }
        eventInterceptor = nil
        didResetInterceptor?()
    }

    func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?, inMode mode: RunLoop.Mode, dequeue: Bool) -> NSEvent? {
        // Use custom event receiver if provided (for testing), otherwise use NSApp
        if let eventReceiver = eventReceiver {
            return eventReceiver(mask, expiration ?? .distantFuture, mode, dequeue)
        }
        return NSApp.nextEvent(matching: mask, until: expiration, inMode: mode, dequeue: dequeue)
    }

    func postEvent(_ event: NSEvent, atStart: Bool) {
        // Track reposted events for validation
        repostedEvents.append(event)
        // In tests, we don't actually post to NSApp - just track it
    }
}

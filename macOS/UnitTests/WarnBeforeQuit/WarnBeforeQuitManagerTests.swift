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
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WarnBeforeQuitManagerTests: XCTestCase, Sendable {

    enum Constants {
        static let earlyReleaseTimeAdvance: TimeInterval = 0.01
        static let expectationTimeout: TimeInterval = 1.0
    }

    var now: Date!
    var stateTask: Task<Void, Never>?

    nonisolated(unsafe) private var _collectedStates: [WarnBeforeQuitManager.State] = []
    nonisolated(unsafe) private var collectedStatesLock: NSLock!
    nonisolated var collectedStates: [WarnBeforeQuitManager.State] {
        get {
            collectedStatesLock.withLock { return _collectedStates }
        }
        _modify {
            collectedStatesLock.lock()
            yield &_collectedStates
            collectedStatesLock.unlock()
        }
    }
    nonisolated(unsafe) var expectations: [XCTestExpectation] = []

    // Expected time values captured at test start
    var startTime: TimeInterval!
    var targetTime: TimeInterval!
    var hideUntil: TimeInterval!
    var hideUntilAfterEarlyRelease: TimeInterval!

    // UserDefaults wrapper for testing
    var warnBeforeQuittingDefaults: UserDefaultsWrapper<Bool>!

    override func setUp() async throws {
        now = Date()
        collectedStatesLock = NSLock()
        _collectedStates = []

        // Capture expected times at test start (before manager advances time)
        startTime = now.timeIntervalSinceReferenceDate
        targetTime = startTime + WarnBeforeQuitManager.Constants.requiredHoldDuration
        hideUntil = startTime + WarnBeforeQuitManager.Constants.hideawayDuration
        hideUntilAfterEarlyRelease = startTime + Constants.earlyReleaseTimeAdvance + WarnBeforeQuitManager.Constants.hideawayDuration

        // Initialize UserDefaults wrapper and reset to ensure clean state
        warnBeforeQuittingDefaults = UserDefaultsWrapper<Bool>(key: .warnBeforeQuitting, defaultValue: true)
        warnBeforeQuittingDefaults.wrappedValue = true
    }

    override func tearDown() async throws {
        stateTask?.cancel()
        stateTask = nil
        _collectedStates = []
        collectedStatesLock = nil
        expectations = []
        now = nil
        startTime = nil
        targetTime = nil
        hideUntil = nil
        hideUntilAfterEarlyRelease = nil
        warnBeforeQuittingDefaults = nil
        customAssert = nil
        TestRunHelper.allowAppSendUserEvents = false
    }

    // MARK: - Initialization Tests

    func testInitWithValidCmdQEventSucceeds() {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue })

        // Then
        XCTAssertNotNil(manager)
    }

    func testInitWithInvalidEventFails() {
        // Given - keyUp event
        let event = createKeyEvent(type: .keyUp, character: "q", modifierFlags: .command)

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue })

        // Then
        XCTAssertNil(manager)
    }

    func testInitWithoutModifierFails() {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q")

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue })

        // Then
        XCTAssertNil(manager)
    }

    func testInitWithCmdWEventSucceeds() {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "w", modifierFlags: .command)

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue })

        // Then
        XCTAssertNotNil(manager)
    }

    func testInitFiltersDeviceDependentFlags() {
        // Given - Cmd+Q with device-dependent flags mixed in
        let flagsWithDeviceDependent: NSEvent.ModifierFlags = [.command, .numericPad, .function]
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: flagsWithDeviceDependent)

        // When
        let manager = WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue })

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

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver))

        // When
        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // Start shouldTerminate - it will enter sync event loop and complete hold
        let query = manager.shouldTerminate(isAsync: false)

        // Wait for both states
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - should return sync decision to proceed with quit
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision")
            return
        }
        XCTAssertEqual(decision, .next)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .completed(shouldQuit: true)
        ])

        // Verify warning wasn't disabled
        XCTAssertTrue(warnBeforeQuittingDefaults.wrappedValue)
    }

    func testStateStreamEmitsHoldingAndWaitingStatesWhenKeyReleasedEarly() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver))

        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // When - start shouldTerminate - key will be released early
        let query = manager.shouldTerminate(isAsync: false)

        // Wait for both states
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - should return async query for waiting phase
        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease)
        ])

        // Clean up task
        try await cancelTaskAndWaitForCompletion(task, manager: manager, expectedDecision: .cancel)

        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
        ])
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

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver, timerFactory: timerFactory))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start shouldTerminate
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Post second Cmd+Q keydown
        let secondPress = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        Logger.tests.debug("\(self.name): NSApp.postEvent \(secondPress) time: \(self.now)")
        TestRunHelper.allowAppSendUserEvents = true
        NSApp.postEvent(secondPress, atStart: true)

        // Wait for async task and completion state
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then
        XCTAssertEqual(decision, .next)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: true)
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

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver, timerFactory: timerFactory))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start shouldTerminate
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Set up monitor to verify Escape is NOT passed through (consumed)
        var escapeReceived = false
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape key
                escapeReceived = true
            }
            return event
        }
        defer { monitor.map(NSEvent.removeMonitor) }

        // Post Escape keydown
        let escapeEvent = createKeyEvent(type: .keyDown, character: "\u{1B}", keyCode: 53)
        Logger.tests.debug("\(self.name): NSApp.postEvent \(escapeEvent) time: \(self.now)")
        TestRunHelper.allowAppSendUserEvents = true
        NSApp.postEvent(escapeEvent, atStart: false)

        // Wait for async task and completion state
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Verify Escape was NOT passed through
        XCTAssertFalse(escapeReceived, "Escape should be consumed, not passed through")

        // Then - should cancel and Escape was consumed (not passed through)
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
        ])

        // Verify warning wasn't disabled
        XCTAssertTrue(warnBeforeQuittingDefaults.wrappedValue)
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

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver, timerFactory: timerFactory))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start shouldTerminate
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        // Then - verify timer was created with correct duration
        XCTAssertEqual(capturedDuration, WarnBeforeQuitManager.Constants.hideawayDuration)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Fire the timer to trigger completion
        timerCallback?()

        // Wait for completion state and task
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
        ])
    }

    // MARK: - ApplicationTerminationDecider Tests

    func testShouldTerminateReturnsNextWhenAsync() throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }))

        // When
        let query = manager.shouldTerminate(isAsync: true)

        // Then
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision")
            return
        }
        XCTAssertEqual(decision, .next)
    }

    // MARK: - Don't Ask Again Tests

    func testShouldTerminateReturnsNextWhenWarningDisabled() throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }))

        // Verify initial state
        XCTAssertTrue(warnBeforeQuittingDefaults.wrappedValue)

        // When - disable warning by setting preference
        warnBeforeQuittingDefaults.wrappedValue = false

        // Then - subsequent calls return .sync(.next) immediately
        let query = manager.shouldTerminate(isAsync: false)
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision")
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

        // Event receiver that waits for .holding on call 1, disables preference on call 2
        let eventReceiver = makeEventReceiver(events: [
            (event: dummyEvent, timeAdvance: 0),  // First call
            (event: dummyEvent, timeAdvance: 0),  // Second call - triggers preference disable
            (event: dummyEvent, timeAdvance: 0)   // Third call - guard check will trigger "Warning disabled" path
        ]) { [weak self] callCount in
            if let self, callCount == 1 {
                // Wait for .holding state to be collected
                wait(for: expectations, timeout: Constants.expectationTimeout)
            } else if callCount == 2 {
                // Second call: disable warning preference to break loop on next iteration
                self!.warnBeforeQuittingDefaults.wrappedValue = false
            }
        }

        manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver))
        // Receive .holding state
        expectations = setupExpectationsForStateChanges(1, manager: manager)

        // Verify initial state
        XCTAssertTrue(warnBeforeQuittingDefaults.wrappedValue)

        // Receive .completed state
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // When - start the termination flow
        let queryTask = Task { @MainActor in
            manager!.shouldTerminate(isAsync: false)
        }

        // Wait for completion
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)
        let query = try await withTimeout(Constants.expectationTimeout) { await queryTask.value }

        // Then - UserDefaults should be updated
        XCTAssertFalse(warnBeforeQuittingDefaults.wrappedValue)

        // And should complete with .sync(.next) - loop broke due to preference disabled
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision")
            return
        }
        XCTAssertEqual(decision, .next)

        // Verify both states were collected
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .completed(shouldQuit: true)
        ])
    }

    func testLoopEndsNaturallyWhenDeadlineReached() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Custom event receiver that returns non-release events past the deadline
        // to allow the loop to end naturally (line 214-216 in WarnBeforeQuitManager.swift)
        let totalDuration = WarnBeforeQuitManager.Constants.requiredHoldDuration + WarnBeforeQuitManager.Constants.animationBufferDuration
        var callCount = 0
        let eventReceiver: (NSEvent.EventTypeMask, Date, RunLoop.Mode, Bool) -> NSEvent? = { [self] _, _, _, _ in
            defer { callCount += 1 }

            // Return a non-release event that advances time past deadline
            if callCount == 0 {
                now = now.addingTimeInterval(totalDuration + Constants.earlyReleaseTimeAdvance)
                // Return a mouse event (will be reposted and loop continues)
                return createMouseEvent(type: .leftMouseDown)
            }

            // Second call: return nil after time is past deadline
            // This allows the while condition to become false naturally
            return nil
        }

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver))

        // When
        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        let query = manager.shouldTerminate(isAsync: false)

        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Then - loop ended naturally, should complete with quit
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision")
            return
        }
        XCTAssertEqual(decision, .next)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .completed(shouldQuit: true)
        ])
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

        let manager = try XCTUnwrap(WarnBeforeQuitManager(
            currentEvent: event,
            isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue },
            now: { self.now },
            eventReceiver: eventReceiver,
            timerFactory: timerFactory
        ))

        // Verify initial state
        XCTAssertTrue(warnBeforeQuittingDefaults.wrappedValue)

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start async wait
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Disable warning during async wait by setting preference
        warnBeforeQuittingDefaults.wrappedValue = false

        // Post a mouse click to trigger the async check in the event handler
        // The DispatchQueue.main.async will check isWarningEnabled() and resume with true
        let mouseClick = createMouseEvent(type: .leftMouseDown)
        TestRunHelper.allowAppSendUserEvents = true
        NSApp.postEvent(mouseClick, atStart: true)

        // Wait for completion
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Clicking after disabling preference makes resume() return true (quit allowed)
        XCTAssertEqual(decision, .next)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: true)
        ])
    }

    func testShouldTerminateAfterDisabled() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }))

        // Start state collection to verify no states are emitted
        _ = setupExpectationsForStateChanges(0, manager: manager)

        // Verify initial state
        XCTAssertTrue(warnBeforeQuittingDefaults.wrappedValue)

        // When - disable warning by setting preference
        warnBeforeQuittingDefaults.wrappedValue = false

        // Then - subsequent calls return .sync(.next) immediately
        let query = manager.shouldTerminate(isAsync: false)
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision after disabling")
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
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start async wait (real timer created with 1.5s duration)
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states to be collected
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Cancel the task - should trigger cleanup
        task.cancel()

        // Wait for the task to complete after cancellation
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - verify decision is cancel
        XCTAssertEqual(decision, .cancel)

        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
        ])

        // Verify callbacks don't crash after completion
        manager.setMouseHovering(true)
        manager.setMouseHovering(false)
    }

    // MARK: - Hover State Tests

    func testHoverBeforeWaitPhaseStoresStateInternally() throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }))

        // When - hover called before entering wait phase (no callback set)
        // Then - should store state internally without crashing
        manager.setMouseHovering(true)
        manager.setMouseHovering(false)
        manager.setMouseHovering(true)
    }

    func testHoverDuringWaitPhaseExtendsTimerDuration() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])

        var expectations: [XCTestExpectation]!

        // Event receiver that waits for .holding on call 0, then returns release event
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ]) { [weak self] callCount in
            if let self, callCount == 0 {
                // Wait for .holding state to be collected
                wait(for: expectations, timeout: Constants.expectationTimeout)
            }
        }

        // Mock timer that captures all durations
        var capturedDurations: [TimeInterval] = []
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { duration, _ in
            capturedDurations.append(duration)
            return Timer() // Don't fire, we'll cancel the Task manually
        }

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver, timerFactory: timerFactory))

        // Receive .holding state
        expectations = setupExpectationsForStateChanges(1, manager: manager)

        // Receive .waitingForSecondPress state
        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // When - start wait phase (timer starts with normal duration)
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for waiting state
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Verify initial timer created with normal hideaway duration
        XCTAssertEqual(capturedDurations.count, 1)
        XCTAssertEqual(capturedDurations[0], WarnBeforeQuitManager.Constants.hideawayDuration)

        // Hover to extend timer
        manager.setMouseHovering(true)
        manager.setMouseHovering(false)

        // Then - verify timer was restarted with extended duration
        XCTAssertEqual(capturedDurations.count, 2)
        XCTAssertEqual(capturedDurations[1], WarnBeforeQuitManager.Constants.extendedHideawayDuration)

        // Verify both states were collected
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease)
        ])

        // Cancel and wait for completion
        try await cancelTaskAndWaitForCompletion(task, manager: manager, expectedDecision: .cancel)

        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
        ])
    }

    // MARK: - Multiple shouldTerminate Calls Tests

    func testMultipleShouldTerminateCallsWhileFirstInProgress() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        let releaseEvent = createKeyEvent(type: .flagsChanged, modifierFlags: [.option])
        let eventReceiver = makeEventReceiver(events: [
            (event: releaseEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver))

        // Set up state collection for first call's states (only expecting 2 states, not 3)
        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        // When - first call returns async
        let query1 = manager.shouldTerminate(isAsync: false)
        guard case .async(let task1) = query1 else {
            XCTFail("Expected first call to return async query")
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
            XCTFail("Expected second call to return sync decision")
            task1.cancel()
            return
        }
        XCTAssertEqual(decision, .next)

        // Verify assertion fired (currentState was not .idle)
        XCTAssertTrue(assertionFired, "Assertion should have fired when second call detected currentState != .idle")

        // Wait for first call's states (.holding and .waitingForSecondPress)
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        // Verify only first call's states were collected (second call bypassed state machine)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease)
        ])

        // Cancel first task and wait for completion
        try await cancelTaskAndWaitForCompletion(task1, manager: manager, expectedDecision: .cancel)
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

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver, timerFactory: timerFactory))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - first flow completes with cancel (timer expires)
        let query1 = manager.shouldTerminate(isAsync: false)
        guard case .async(let task1) = query1 else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Fire timer to complete first flow
        timerCallback?()

        Logger.tests.debug("\(self.name): Waiting for first flow to complete")
        let decision1 = try await withTimeout(Constants.expectationTimeout) { await task1.value }
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - first flow cancels
        XCTAssertEqual(decision1, .cancel)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
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
            XCTFail("Expected second call to return sync decision")
            return
        }
        XCTAssertEqual(decision2, .next)

        // Verify only first flow's states were collected (second call bypassed state machine)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
        ])
    }

    // MARK: - Character Key Release Tests

    func testCharacterKeyReleaseDuringHold() async throws {
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

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver, timerFactory: timerFactory))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start termination flow
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Post second Q keydown (while Cmd still held)
        let secondPress = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)
        TestRunHelper.allowAppSendUserEvents = true
        NSApp.postEvent(secondPress, atStart: true)

        // Wait for completion
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - should complete with quit allowed
        XCTAssertEqual(decision, .next)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: true)
        ])
    }

    // MARK: - Mouse Click Tests

    func testLeftMouseClickDuringWait() async throws {
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

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver, timerFactory: timerFactory))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start async wait
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Simulate left mouse click
        let mouseClick = createMouseEvent(type: .leftMouseDown)
        TestRunHelper.allowAppSendUserEvents = true
        NSApp.postEvent(mouseClick, atStart: true)

        // Wait for completion
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - should cancel
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
        ])
    }

    func testRightMouseClickDuringWait() async throws {
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

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver, timerFactory: timerFactory))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start async wait
        let query = manager.shouldTerminate(isAsync: false)
        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Simulate right mouse click
        let mouseClick = createMouseEvent(type: .rightMouseDown)
        TestRunHelper.allowAppSendUserEvents = true
        NSApp.postEvent(mouseClick, atStart: true)

        // Wait for completion
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations2, timeout: Constants.expectationTimeout)

        // Then - should cancel
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
        ])
    }

    func testOtherKeyPressDuringWait() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Mock timer to prevent automatic expiry (event will cancel instead)
        let timerFactory: (TimeInterval, @escaping () -> Void) -> Timer = { _, _ in
            return Timer()
        }

        let qKeyUpEvent = createKeyEvent(type: .keyUp, character: "q", modifierFlags: .command)
        let eventReceiver = makeEventReceiver(events: [
            (event: qKeyUpEvent, timeAdvance: Constants.earlyReleaseTimeAdvance)
        ])

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver, timerFactory: timerFactory))

        let expectations1 = setupExpectationsForStateChanges(2, manager: manager)

        // When - start termination flow
        let query = manager.shouldTerminate(isAsync: false)

        guard case .async(let task) = query else {
            XCTFail("Expected async query")
            return
        }

        // Wait for .holding and .waitingForSecondPress states
        await fulfillment(of: expectations1, timeout: Constants.expectationTimeout)

        let expectations2 = setupExpectationsForStateChanges(1, manager: manager)

        // Set up monitor to verify event was passed through
        let eventPassedThroughExpectation = expectation(description: "Other key passed through")
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.characters == "a" {
                eventPassedThroughExpectation.fulfill()
            }
            return nil
        }
        defer { monitor.map(NSEvent.removeMonitor) }

        // Post unrelated key (should cancel but pass through)
        let otherKey = createKeyEvent(type: .keyDown, character: "a", modifierFlags: [])
        TestRunHelper.allowAppSendUserEvents = true
        NSApp.postEvent(otherKey, atStart: true)

        // Wait for completion and pass-through
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations2 + [eventPassedThroughExpectation], timeout: Constants.expectationTimeout)

        // Then - should cancel (not quit) and event was passed through
        XCTAssertEqual(decision, .cancel)
        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .waitingForSecondPress(hideUntil: hideUntilAfterEarlyRelease),
            .completed(shouldQuit: false)
        ])
    }

    // MARK: - Event Reposting Tests

    func testOtherEventsRepostedDuringHold() async throws {
        // Given
        let event = createKeyEvent(type: .keyDown, character: "q", modifierFlags: .command)

        // Event receiver that returns an unrelated key event - should cancel
        let otherKeyEvent = createKeyEvent(type: .keyDown, character: "a", modifierFlags: [])
        let eventReceiver = makeEventReceiver(events: [
            (event: otherKeyEvent, timeAdvance: 0) // First call returns 'a' key - should cancel
        ])

        let manager = try XCTUnwrap(WarnBeforeQuitManager(currentEvent: event, isWarningEnabled: { self.warnBeforeQuittingDefaults.wrappedValue }, now: { self.now }, eventReceiver: eventReceiver))

        // When
        let expectations = setupExpectationsForStateChanges(2, manager: manager)

        let query = manager.shouldTerminate(isAsync: false)

        // Then - should cancel (other key pressed during hold)
        guard case .sync(let decision) = query else {
            XCTFail("Expected sync decision")
            return
        }
        XCTAssertEqual(decision, .cancel)

        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        XCTAssertEqual(collectedStates, [
            .holding(startTime: startTime, targetTime: targetTime),
            .completed(shouldQuit: false)
        ])
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

    /// Properly cancels a task and waits for completion
    func cancelTaskAndWaitForCompletion(_ task: Task<TerminationDecision, Never>, manager: WarnBeforeQuitManager, expectedDecision: TerminationDecision, file: StaticString = #file, line: UInt = #line) async throws {
        let expectations = setupExpectationsForStateChanges(1, manager: manager)

        task.cancel()
        let decision = try await withTimeout(Constants.expectationTimeout) { await task.value }
        await fulfillment(of: expectations, timeout: Constants.expectationTimeout)

        XCTAssertEqual(decision, expectedDecision, file: file, line: line)
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
            location: NSPoint(x: 0, y: 100), // away from menu bar
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

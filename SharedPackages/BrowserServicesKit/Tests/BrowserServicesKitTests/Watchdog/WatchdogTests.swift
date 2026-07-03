//
//  WatchdogTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import Common
import Foundation
import XCTest
@testable import BrowserServicesKit

@MainActor
final class WatchdogTests: XCTestCase {

    var watchdog: Watchdog!

    override func setUp() {
        super.setUp()

        // Use short timeouts for faster tests
        watchdog = Watchdog(settings: .quickIntervals)
    }

    override func tearDown() {
        watchdog?.stop()
        watchdog = nil
        super.tearDown()
    }

    // MARK: - Mock Helper

    private final class ThreadsafeStore<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = [T]()

        var allValues: [T] {
            lock.withLock {
                storage
            }
        }

        var isEmpty: Bool {
            lock.withLock {
                storage.isEmpty
            }
        }

        func append(_ event: T) {
            lock.withLock {
                storage.append(event)
            }
        }

        func removeAll() {
            lock.withLock {
                storage.removeAll()
            }
        }
    }

    // MARK: - Basic Functionality Tests

    func testInitialState() {
        XCTAssertFalse(watchdog.isRunning, "Watchdog should not be running initially")
    }

    func testStart() {
        watchdog.start()
        XCTAssertTrue(watchdog.isRunning, "Watchdog should be running after start")
    }

    func testStop() {
        watchdog.stop()
        XCTAssertFalse(watchdog.isRunning, "Watchdog should not be running after stop")
    }

    func testMultipleStarts() {
        watchdog.start()
        let firstState = watchdog.isRunning

        watchdog.start() // Should cancel previous and start new
        let secondState = watchdog.isRunning

        XCTAssertTrue(firstState, "First start should make watchdog running")
        XCTAssertTrue(secondState, "Second start should keep watchdog running")
    }

    func testMultipleStops() {
        watchdog.start()
        watchdog.stop()
        watchdog.stop() // Should be safe to call multiple times

        XCTAssertFalse(watchdog.isRunning, "Multiple stops should be safe")
    }

    // MARK: - Pause / Resume Tests

    func testPauseAndResume() {
        watchdog.start()
        XCTAssertTrue(watchdog.isRunning, "Watchdog should be running")

        var isPaused = watchdog.isPaused
        XCTAssertFalse(isPaused, "Should not be paused initially")

        watchdog.pause()
        XCTAssertFalse(watchdog.isRunning, "Watchdog should not be running after pause")

        isPaused = watchdog.isPaused
        XCTAssertTrue(isPaused, "Should be paused after pause()")

        watchdog.resume()
        XCTAssertTrue(watchdog.isRunning, "Watchdog should be running after resume")
        XCTAssertFalse(watchdog.isPaused, "Should not be paused after resume()")

        watchdog.stop()
    }

    func testStartResetsPauseState() {
        watchdog.start()
        watchdog.pause()

        XCTAssertTrue(watchdog.isPaused, "Should be paused")

        // Starting again should reset pause state
        watchdog.stop()
        watchdog.start()

        XCTAssertTrue(watchdog.isRunning, "Should be running after restart")
        XCTAssertFalse(watchdog.isPaused, "Pause state should be reset after start()")

        watchdog.stop()
    }

    func testPauseWhenNotRunningIsNoOp() {
        watchdog.pause()
        XCTAssertFalse(watchdog.isPaused, "Should not be paused when pause called without running")
        XCTAssertFalse(watchdog.isRunning, "Should not be running")
    }

    func testResumeWhenNotPausedIsNoOp() {
        watchdog.start()
        watchdog.resume()
        XCTAssertTrue(watchdog.isRunning, "Should still be running")
        XCTAssertFalse(watchdog.isPaused, "Should not be paused")
    }

    func testPausePreventsHangDetection() async throws {
        let pauseWatchdog = Watchdog(settings: .quickIntervals)

        let receivedStates = ThreadsafeStore<WatchdogDetectionState>()
        let cancellable = pauseWatchdog.detectionStatePublisher.sink { event in
            receivedStates.append(event)
        }

        pauseWatchdog.start()
        pauseWatchdog.pause()

        XCTAssertTrue(pauseWatchdog.isPaused, "Should be paused")

        // Block main thread while paused - should not trigger hang detection
        try await blockMainThread(until: {
            receivedStates.allValues.containsState(.hanging)
        }, timeout: WatchdogSettings.quickIntervals.maximumHangDuration * 2)

        XCTAssertTrue(receivedStates.allValues.isEmpty, "Should not detect any hangs while paused")

        cancellable.cancel()
        pauseWatchdog.stop()
    }

    func testResumeAfterPauseDetectsHangs() async throws {
        let resumeWatchdog = Watchdog(settings: .quickIntervals)

        let receivedStates = ThreadsafeStore<WatchdogDetectionState>()
        let cancellable = resumeWatchdog.detectionStatePublisher.sink { event in
            receivedStates.append(event)
        }

        resumeWatchdog.start()
        resumeWatchdog.pause()
        XCTAssertTrue(resumeWatchdog.isPaused, "Should be paused")

        resumeWatchdog.resume()

        XCTAssertFalse(resumeWatchdog.isPaused, "Should not be paused after resume")

        // Block the main thread - should be detected
        try await blockMainThread {
            receivedStates.allValues.containsState(.hanging)
        }

        XCTAssertFalse(receivedStates.isEmpty, "Should detect hangs after resume")
        XCTAssertTrue(receivedStates.allValues.containsState(.hanging), "Should transition to hanging state after resume")

        cancellable.cancel()
        resumeWatchdog.stop()
    }

    // MARK: - Deinit Tests

    func testDeinitStopsWatchdog() async {
        var optionalWatchdog: Watchdog? = Watchdog(settings: .quickIntervals)
        optionalWatchdog?.start()

        XCTAssertTrue(optionalWatchdog?.isRunning == true)

        // Deinit should call stop()
        optionalWatchdog = nil

        // Note: We can't directly test the task cancellation from deinit,
        // but we can verify the pattern doesn't crash
        XCTAssertNil(optionalWatchdog)
    }

    // MARK: - Thread Safety Tests

    func testConcurrentStartStop() async {
        let expectation = XCTestExpectation(description: "All concurrent operations complete")
        expectation.expectedFulfillmentCount = 10

        await withTaskGroup(of: Void.self) { group in
            // Start multiple concurrent start/stop operations
            for i in 0..<10 {
                group.addTask { [watchdog] in
                    if i % 2 == 0 {
                        watchdog?.start()
                    } else {
                        watchdog?.stop()
                    }
                    expectation.fulfill()
                }
            }

            // Wait for all operations to complete
            await group.waitForAll()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        // Should not crash and should be in a valid state
        let finalState = watchdog.isRunning
        XCTAssertTrue(finalState == true || finalState == false, "Should be in a valid state")
    }

    func testIsRunningPropertyThreadSafety() async {
        watchdog.start()

        let results = await withTaskGroup(of: Bool.self) { group in
            // Read isRunning from multiple tasks simultaneously
            for _ in 0..<50 {
                group.addTask { [watchdog] in
                    return watchdog?.isRunning ?? false
                }
            }

            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        // All reads should be consistent since we didn't stop the watchdog
        XCTAssertTrue(results.allSatisfy { $0 == true }, "All concurrent reads should return true")
        XCTAssertEqual(results.count, 50, "Should have 50 results")
    }

    // MARK: - Memory Tests

    func testWatchdogDoesNotLeakMemory() async {
        weak var weakWatchdog: Watchdog?

        // Do the work directly on main actor (no Task needed)
        do {
            let localWatchdog = Watchdog(settings: .quickIntervals)
            weakWatchdog = localWatchdog

            localWatchdog.start()
            XCTAssertTrue(localWatchdog.isRunning)
            localWatchdog.stop()
            XCTAssertFalse(localWatchdog.isRunning)

            // localWatchdog goes out of scope here
        }

        // Give time for deallocation
        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        XCTAssertNil(weakWatchdog, "Watchdog should be deallocated")
    }

    // MARK: - Stability Tests

    func testRepeatedStartStopCycles() {
        // No sleeps needed - just verify state transitions work repeatedly
        for cycle in 0..<20 {
            watchdog.start()
            XCTAssertTrue(watchdog.isRunning, "Cycle \(cycle): Should be running after start")

            watchdog.stop()
            XCTAssertFalse(watchdog.isRunning, "Cycle \(cycle): Should be stopped after stop")
        }
    }

    // MARK: - Hang Detection Tests

    func testWatchdogDetectsMainThreadHang() async throws {
        let hangWatchdog = Watchdog(settings: .quickIntervals)

        let receivedStates = ThreadsafeStore<WatchdogDetectionState>()
        let cancellable = hangWatchdog.detectionStatePublisher.sink { event in
            receivedStates.append(event)
        }

        hangWatchdog.start()
        XCTAssertTrue(hangWatchdog.isRunning)

        try await blockMainThread {
            receivedStates.allValues.containsState(.hanging)
        }

        XCTAssertFalse(receivedStates.isEmpty, "Should detect hangs")
        XCTAssertTrue(receivedStates.allValues.containsState(.hanging), "Should transition to hanging state")

        cancellable.cancel()
        hangWatchdog.stop()
    }

    // MARK: - State Transitions

    func testHangStateTransitions() async throws {
        let hangWatchdog = Watchdog(settings: .quickIntervals)

        let receivedStates = ThreadsafeStore<WatchdogDetectionState>()
        let cancellable = hangWatchdog.detectionStatePublisher.sink { event in
            receivedStates.append(event)
        }

        hangWatchdog.start()

        // Test 1: Responsive -> Hanging
        try await blockMainThread {
            receivedStates.allValues.containsState(.hanging)
        }

        XCTAssertTrue(receivedStates.allValues.containsState(.hanging), "Should transition to .hanging state")

        // Test 2: Hanging -> Responsive (recovery)
        await sleep {
            receivedStates.allValues.containsState(.responsive)
        }

        XCTAssertTrue(receivedStates.allValues.containsState(.responsive), "Should recover to .responsive state")

        receivedStates.removeAll()

        // Test 3: Responsive -> Hanging -> Timeout
        try await blockMainThread {
            receivedStates.allValues.containsState(.timeout)
        }

        XCTAssertTrue(receivedStates.allValues.containsState(.timeout), "Should transition to .timeout state")

        receivedStates.removeAll()

        // Test 4: Timeout -> Responsive (responsive)
        await sleep {
            receivedStates.allValues.containsState(.responsive)
        }

        XCTAssertTrue(receivedStates.allValues.containsState(.responsive), "Should transition to .responsive state")

        cancellable.cancel()
        hangWatchdog.stop()
    }

    // MARK: - Recovery States

    func testRecoveryStatesAfterHanging() async throws {
        let recoveryWatchdog = Watchdog(settings: .quickIntervals)

        let receivedStates = ThreadsafeStore<WatchdogDetectionState>()
        let cancellable = recoveryWatchdog.detectionStatePublisher.sink { event in
            receivedStates.append(event)
        }

        recoveryWatchdog.start()

        try await blockMainThread {
            receivedStates.allValues.containsState(.hanging)
        }

        await sleep {
            receivedStates.allValues.containsState(.responsive)
        }

        XCTAssertTrue(receivedStates.allValues.containsRecovery(after: .hanging), "Should go through recovery state")
        XCTAssertTrue(receivedStates.allValues.containsState(.recovered(after: .hanging)), "Should go through recovered state")

        cancellable.cancel()
        recoveryWatchdog.stop()
    }

    func testRecoveryStatesAfterTimeout() async throws {
        let recoveryWatchdog = Watchdog(settings: .quickIntervals)

        let receivedStates = ThreadsafeStore<WatchdogDetectionState>()
        let cancellable = recoveryWatchdog.detectionStatePublisher.sink { event in
            receivedStates.append(event)
        }

        recoveryWatchdog.start()

        try await blockMainThread {
            receivedStates.allValues.containsState(.timeout)
        }

        receivedStates.removeAll()

        await sleep {
            receivedStates.allValues.containsState(.responsive)
        }

        XCTAssertTrue(receivedStates.allValues.containsRecovery(after: .timeout), "Should go through recovery state after timeout")
        XCTAssertTrue(receivedStates.allValues.containsState(.recovered(after: .timeout)), "Should go through recovered state after timeout")

        cancellable.cancel()
        recoveryWatchdog.stop()
    }

    // MARK: - Event Reporting

    func testHangRecoveredEventFires() async throws {
        let firedEvents = ThreadsafeStore<Watchdog.Event>()
        let eventMapper = EventMapping<Watchdog.Event> { event, _, _, _ in
            firedEvents.append(event)
        }
        let eventWatchdog = Watchdog(settings: .quickIntervals, eventMapper: eventMapper)

        let receivedStates = ThreadsafeStore<WatchdogDetectionState>()
        let cancellable = eventWatchdog.detectionStatePublisher.sink { event in
            receivedStates.append(event)
        }

        eventWatchdog.start()

        try await blockMainThread {
            receivedStates.allValues.containsState(.hanging)
        }

        await sleep {
            receivedStates.allValues.containsState(.recovered(after: .hanging))
        }

        XCTAssertTrue(firedEvents.allValues.containsEvent(Watchdog.Event.uiHangRecovered), "Should fire uiHangRecovered event")

        cancellable.cancel()
        eventWatchdog.stop()
    }

    func testHangNotRecoveredEventFires() async throws {
        let firedEvents = ThreadsafeStore<Watchdog.Event>()
        let eventMapper = EventMapping<Watchdog.Event> { event, _, _, _ in
            firedEvents.append(event)
        }
        let eventWatchdog = Watchdog(settings: .quickIntervals, eventMapper: eventMapper)

        let receivedStates = ThreadsafeStore<WatchdogDetectionState>()
        let cancellable = eventWatchdog.detectionStatePublisher.sink { event in
            receivedStates.append(event)
        }

        eventWatchdog.start()

        try await blockMainThread {
            receivedStates.allValues.containsState(.timeout)
        }

        XCTAssertTrue(firedEvents.allValues.containsEvent(Watchdog.Event.uiHangNotRecovered), "Should fire uiHangNotRecovered event")

        cancellable.cancel()
        eventWatchdog.stop()
    }

    func testNoHangRecoveredEventAfterTimeoutRecovery() async throws {
        let firedEvents = ThreadsafeStore<Watchdog.Event>()
        let eventMapper = EventMapping<Watchdog.Event> { event, _, _, _ in
            firedEvents.append(event)
        }
        let eventWatchdog = Watchdog(settings: .quickIntervals, eventMapper: eventMapper)

        let receivedStates = ThreadsafeStore<WatchdogDetectionState>()
        let cancellable = eventWatchdog.detectionStatePublisher.sink { event in
            receivedStates.append(event)
        }

        eventWatchdog.start()

        try await blockMainThread {
            receivedStates.allValues.containsState(.timeout)
        }

        receivedStates.removeAll()

        await sleep {
            receivedStates.allValues.containsState(.responsive)
        }

        XCTAssertFalse(firedEvents.allValues.containsEvent(Watchdog.Event.uiHangRecovered), "Should not fire uiHangRecovered after timeout recovery")

        cancellable.cancel()
        eventWatchdog.stop()
    }
}

// MARK: - Helpers

private extension WatchdogTests {

    func blockMainThread(until condition: @escaping () -> Bool, timeout: TimeInterval = 3.0) async throws {
        await withUnsafeContinuation { continuation in
            DispatchQueue.main.async {
                let deadline = Date().addingTimeInterval(timeout)
                while condition() == false && Date() < deadline {
                    // NO-OP
                }

                continuation.resume()
            }
        }
    }

    func sleep(until condition: @escaping () -> Bool, timeout: TimeInterval = 3.0) async {
        let task = Task.detached {
            let deadline = Date().addingTimeInterval(timeout)
            while condition() == false && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            }
        }

        await task.value
    }

}

private extension Collection where Element == WatchdogDetectionState {

    func containsState(_ state: WatchdogDetectionState) -> Bool {
        contains { $0 == state }
    }

    func containsRecovery(after origin: WatchdogRecoveryOrigin) -> Bool {
        contains {
            if case .recovery(let o, _) = $0, o == origin { return true }
            return false
        }
    }
}

private extension Collection where Element == Watchdog.Event {

    func containsEvent(_ eventCase: (Int) -> Watchdog.Event) -> Bool {
        let reference = eventCase(0)
        return contains {
            switch ($0, reference) {
            case (.uiHangRecovered, .uiHangRecovered),
                 (.uiHangNotRecovered, .uiHangNotRecovered):
                return true
            default:
                return false
            }
        }
    }
}

private extension WatchdogSettings {
    static let quickIntervals = WatchdogSettings(checkInterval: 0.1, minimumHangDuration: 0.3, maximumHangDuration: 1.5, requiredRecoveryHeartbeats: 1, timeoutRepeatCooldown: 2.0)
}

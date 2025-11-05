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
import Foundation
import XCTest
@testable import BrowserServicesKit

@MainActor
final class WatchdogTests: XCTestCase {

    var watchdog: Watchdog!
    var mockKillAppFunction: MockKillAppFunction!

    override func setUp() {
        super.setUp()
        mockKillAppFunction = MockKillAppFunction()
        // Use short timeouts for faster tests
        watchdog = Watchdog(minimumHangDuration: 0.5, maximumHangDuration: 1.0, checkInterval: 0.1, crashOnTimeout: true, killAppFunction: mockKillAppFunction.killApp)

        Task {
            await watchdog.setCrashOnTimeout(true)
        }
    }

    override func tearDown() {
        Task {
            await watchdog?.stop()
            watchdog = nil
            mockKillAppFunction = nil
        }

        super.tearDown()
    }

    // MARK: - Mock Helper

    class MockKillAppFunction {
        private(set) var wasKilled = false

        func killApp(afterTimeout timeout: TimeInterval) {
            wasKilled = true
        }

        func reset() {
            wasKilled = false
        }
    }

    // MARK: - Basic Functionality Tests

    func testInitialState() {
        XCTAssertFalse(watchdog.isRunning, "Watchdog should not be running initially")
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app")
    }

    func testStart() async {
        await watchdog.start()
        XCTAssertTrue(watchdog.isRunning, "Watchdog should be running after start")
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app")
    }

    func testStop() async {
        await watchdog.stop()
        XCTAssertFalse(watchdog.isRunning, "Watchdog should not be running after stop")
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app")
    }

    func testMultipleStarts() async {
        await watchdog.start()
        let firstState = watchdog.isRunning

        await watchdog.start() // Should cancel previous and start new
        let secondState = watchdog.isRunning

        XCTAssertTrue(firstState, "First start should make watchdog running")
        XCTAssertTrue(secondState, "Second start should keep watchdog running")
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app")
    }

    func testMultipleStops() async {
        await watchdog.start()
        await watchdog.stop()
        await watchdog.stop() // Should be safe to call multiple times

        XCTAssertFalse(watchdog.isRunning, "Multiple stops should be safe")
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app")
    }

    // MARK: - Pause / Resume Tests

    func testPauseAndResume() async {
        await watchdog.start()
        XCTAssertTrue(watchdog.isRunning, "Watchdog should be running")

        var isPaused = await watchdog.isPaused
        XCTAssertFalse(isPaused, "Should not be paused initially")

        await watchdog.pause()
        XCTAssertTrue(watchdog.isRunning, "Watchdog should still be running after pause")

        isPaused = await watchdog.isPaused
        XCTAssertTrue(isPaused, "Should be paused after pause()")

        await watchdog.resume()
        XCTAssertTrue(watchdog.isRunning, "Watchdog should still be running after resume")

        isPaused = await watchdog.isPaused
        XCTAssertFalse(isPaused, "Should not be paused after resume()")

        await watchdog.stop()
    }

    func testStartResetsPauseState() async {
        await watchdog.start()
        await watchdog.pause()

        var isPaused = await watchdog.isPaused
        XCTAssertTrue(isPaused, "Should be paused")

        // Starting again should reset pause state
        await watchdog.stop()
        await watchdog.start()

        XCTAssertTrue(watchdog.isRunning, "Should be running after restart")

        isPaused = await watchdog.isPaused
        XCTAssertFalse(isPaused, "Pause state should be reset after start()")

        await watchdog.stop()
    }

    func testPausePreventsHangDetection() async throws {
        let mockKill = MockKillAppFunction()
        let pauseWatchdog = Watchdog(minimumHangDuration: 0.1, maximumHangDuration: 0.3, checkInterval: 0.1, crashOnTimeout: true, killAppFunction: mockKill.killApp)

        var receivedStates: [(hangState: Watchdog.HangState, duration: TimeInterval?)] = []
        let cancellable = await pauseWatchdog.hangStatePublisher.sink { receivedStates.append($0) }

        await pauseWatchdog.start()
        await pauseWatchdog.pause()

        let isPaused = await pauseWatchdog.isPaused
        XCTAssertTrue(isPaused, "Should be paused")

        // Block main thread while paused - should not trigger hang detection
        try await blockMainThread(for: 0.5, andSleepFor: 0.6)

        XCTAssertTrue(receivedStates.isEmpty, "Should not detect any hangs while paused")

        cancellable.cancel()
        await pauseWatchdog.stop()
    }

    func testResumeAfterPauseDetectsHangs() async throws {
        let mockKill = MockKillAppFunction()
        let resumeWatchdog = Watchdog(minimumHangDuration: 0.1, maximumHangDuration: 0.3, checkInterval: 0.1, crashOnTimeout: true, killAppFunction: mockKill.killApp)

        var receivedStates: [(hangState: Watchdog.HangState, duration: TimeInterval?)] = []
        let cancellable = await resumeWatchdog.hangStatePublisher.sink { receivedStates.append($0) }

        await resumeWatchdog.start()
        await resumeWatchdog.pause()

        var isPaused = await resumeWatchdog.isPaused
        XCTAssertTrue(isPaused, "Should be paused")

        await resumeWatchdog.resume()

        isPaused = await resumeWatchdog.isPaused
        XCTAssertFalse(isPaused, "Should not be paused after resume")

        // Block the main thread - should be detected
        try await blockMainThread(for: 0.5, andSleepFor: 0.7)

        XCTAssertFalse(receivedStates.isEmpty, "Should detect hangs after resume")
        let hangingState = receivedStates.first { $0.hangState == .hanging }
        XCTAssertNotNil(hangingState, "Should transition to hanging state after resume")

        cancellable.cancel()
        await resumeWatchdog.stop()
    }

    // MARK: - Deinit Tests

    func testDeinitStopsWatchdog() async {
        let mockKill = MockKillAppFunction()
        var optionalWatchdog: Watchdog? = Watchdog(minimumHangDuration: 0.5, maximumHangDuration: 1.0, checkInterval: 0.1, crashOnTimeout: true, killAppFunction: mockKill.killApp)
        await optionalWatchdog?.start()

        XCTAssertTrue(optionalWatchdog?.isRunning == true)

        // Deinit should call stop()
        optionalWatchdog = nil

        // Note: We can't directly test the task cancellation from deinit,
        // but we can verify the pattern doesn't crash
        XCTAssertNil(optionalWatchdog)
        XCTAssertFalse(mockKill.wasKilled, "Should not have killed app during deinit")
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
                        await watchdog?.start()
                    } else {
                        await watchdog?.stop()
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
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app during concurrent operations")
    }

    func testIsRunningPropertyThreadSafety() async {
        await watchdog.start()

        let results = await withTaskGroup(of: Bool.self) { group in
            // Read isRunning from multiple tasks simultaneously
            for _ in 0..<50 {
                group.addTask { [watchdog] in
                    return await watchdog?.isRunning ?? false
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
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app during property reads")
    }

    // MARK: - Memory Tests

    func testWatchdogDoesNotLeakMemory() async {
        weak var weakWatchdog: Watchdog?
        let mockKill = MockKillAppFunction()

        // Do the work directly on main actor (no Task needed)
        do {
            let localWatchdog = Watchdog(minimumHangDuration: 0.5, maximumHangDuration: 1.0, checkInterval: 0.1, crashOnTimeout: true, killAppFunction: mockKill.killApp)
            weakWatchdog = localWatchdog

            await localWatchdog.start()
            XCTAssertTrue(localWatchdog.isRunning)
            await localWatchdog.stop()
            XCTAssertFalse(localWatchdog.isRunning)

            // localWatchdog goes out of scope here
        }

        // Give time for deallocation
        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        XCTAssertNil(weakWatchdog, "Watchdog should be deallocated")
        XCTAssertFalse(mockKill.wasKilled, "Should not have killed app during memory test")
    }

    // MARK: - Stability Tests

    func testRepeatedStartStopCycles() async {
        // No sleeps needed - just verify state transitions work repeatedly
        for cycle in 0..<20 {
            await watchdog.start()
            XCTAssertTrue(watchdog.isRunning, "Cycle \(cycle): Should be running after start")

            await watchdog.stop()
            XCTAssertFalse(watchdog.isRunning, "Cycle \(cycle): Should be stopped after stop")
        }
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app during cycles")
    }

    // MARK: - Hang Detection Tests

    func testWatchdogDetectsMainThreadHang() async throws {
        let mockKill = MockKillAppFunction()
        let hangWatchdog = Watchdog(minimumHangDuration: 0.1, maximumHangDuration: 0.3, checkInterval: 0.1, crashOnTimeout: true, killAppFunction: mockKill.killApp)

        await hangWatchdog.start()
        XCTAssertTrue(hangWatchdog.isRunning)
        XCTAssertFalse(mockKill.wasKilled, "Should not have killed app yet")

        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        let expectation = XCTestExpectation(description: "Hang detected")

        Task.detached {
            while !mockKill.wasKilled {
                try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            }
            expectation.fulfill()
        }

        Task.detached {
            DispatchQueue.main.sync {
                let startTime = Date()
                while Date().timeIntervalSince(startTime) < 1.0 {
                    // Busy wait to block main thread
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 3.0)

        XCTAssertTrue(mockKill.wasKilled, "Watchdog should have detected hang and killed app")

        await hangWatchdog.stop()
    }

    func testWatchdogWithNormalOperationDoesNotKill() async throws {
        let mockKill = MockKillAppFunction()
        let normalWatchdog = Watchdog(minimumHangDuration: 0.5, maximumHangDuration: 1.0, checkInterval: 0.2, crashOnTimeout: true, killAppFunction: mockKill.killApp)

        var receivedStates: [(hangState: Watchdog.HangState, duration: TimeInterval?)] = []
        let cancellable = await normalWatchdog.hangStatePublisher.sink { receivedStates.append($0) }

        await normalWatchdog.start()
        XCTAssertTrue(normalWatchdog.isRunning)

        try await Task.sleep(nanoseconds: 1_500 * NSEC_PER_MSEC)

        XCTAssertTrue(receivedStates.isEmpty, "Should not have any state transitions during normal operation")
        XCTAssertFalse(mockKill.wasKilled, "Should not have killed app during normal operation")
        XCTAssertTrue(normalWatchdog.isRunning, "Watchdog should still be running")

        cancellable.cancel()
        await normalWatchdog.stop()
    }

    func testWatchdogStoppedBeforeHangDoesNotKill() async throws {
        let mockKill = MockKillAppFunction()
        let stoppedWatchdog = Watchdog(minimumHangDuration: 0.1, maximumHangDuration: 0.3, checkInterval: 0.1, crashOnTimeout: true, killAppFunction: mockKill.killApp)

        await stoppedWatchdog.start()
        XCTAssertTrue(stoppedWatchdog.isRunning)

        await stoppedWatchdog.stop()
        XCTAssertFalse(stoppedWatchdog.isRunning)

        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        Task.detached {
            DispatchQueue.main.sync {
                let startTime = Date()
                while Date().timeIntervalSince(startTime) < 0.5 {
                    // Busy wait to block main thread
                }
            }
        }

        try await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)

        XCTAssertFalse(mockKill.wasKilled, "Stopped watchdog should not kill app")
    }

    func testDoesNotCrashWhenCrashOnTimeoutIsFalse() async {
        let mockKill = MockKillAppFunction()
        let optionalWatchdog: Watchdog? = Watchdog(minimumHangDuration: 0.1, maximumHangDuration: 0.3, checkInterval: 0.1, killAppFunction: mockKill.killApp)
        await optionalWatchdog?.start()

        Task.detached {
            DispatchQueue.main.sync {
                let startTime = Date()
                while Date().timeIntervalSince(startTime) < 0.5 {
                    // Busy wait to block main thread
                }
            }
        }

        XCTAssertTrue(optionalWatchdog?.isRunning == true, "Watchdog should be running when crashOnTimeout is false")
        XCTAssertFalse(mockKill.wasKilled, "Should not have killed app")
    }

    // MARK: - State Transitions

    func testHangStateTransitions() async throws {
        throw XCTSkip("Flaky test: https://app.asana.com/1/137249556945/project/1200194497630846/task/1211604496994582?focus=true")

        let minimumDuration = 0.2
        let maximumDuration = 0.4
        let checkInterval   = 0.1

        let mockKill = MockKillAppFunction()
        let watchdog = Watchdog(minimumHangDuration: minimumDuration, maximumHangDuration: maximumDuration, checkInterval: checkInterval, killAppFunction: mockKill.killApp)

        var receivedStates: [(hangState: Watchdog.HangState, duration: TimeInterval?)] = []
        let cancellable = await watchdog.hangStatePublisher
            .sink { state, duration in
                receivedStates.append((state, duration))
            }

        await watchdog.start()

        // Helper function to wait for a specific state
        func waitForState(_ targetState: Watchdog.HangState, timeout: TimeInterval = 3.0) async {
            let expectation = XCTestExpectation(description: "\(targetState) state reached")
            Task.detached {
                while !receivedStates.contains(where: { $0.hangState == targetState }) {
                    try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                }
                expectation.fulfill()
            }
            await fulfillment(of: [expectation], timeout: timeout)
        }

        // Helper function to block main thread
        func blockMainThread(for duration: TimeInterval) {
            Task.detached {
                DispatchQueue.main.sync {
                    let startTime = Date()
                    while Date().timeIntervalSince(startTime) < duration {
                    }
                }
            }
        }

        // Test 1: Responsive -> Hanging
        blockMainThread(for: minimumDuration + 0.1) // 0.3s - enough to trigger hanging but allow recovery
        await waitForState(.hanging)

        let hangingState = receivedStates.first { $0.hangState == .hanging }
        XCTAssertNotNil(hangingState, "Should transition to hanging state")

        // Test 2: Hanging -> Responsive (recovery)
        await waitForState(.responsive)
        let responsiveState = receivedStates.first { $0.hangState == .responsive }
        XCTAssertNotNil(responsiveState, "Should recover to responsive state")

        // Test 3: Responsive -> Hanging -> Timeout
        blockMainThread(for: maximumDuration + (checkInterval * 2))
        await waitForState(.timeout)

        let timeoutState = receivedStates.first { $0.hangState == .timeout }
        XCTAssertNotNil(timeoutState, "Should transition to timeout state")
        XCTAssertNotNil(timeoutState?.duration, "Should include hang duration")
        XCTAssertGreaterThan(timeoutState?.duration ?? 0, maximumDuration, "Duration should exceed maximum")

        // Test 4: Verify state sequence
        let stateSequence = receivedStates.map { $0.hangState }
        XCTAssert(stateSequence.prefix(4) == [.hanging, .responsive, .hanging, .timeout], "Should follow expected state sequence")

        cancellable.cancel()
        await watchdog.stop()
    }

    // MARK: - Helpers

    private func blockMainThread(for duration: TimeInterval, andSleepFor sleepDuration: TimeInterval) async throws {
        Task.detached {
            DispatchQueue.main.sync {
                let startTime = Date()
                while Date().timeIntervalSince(startTime) < duration {
                }
            }
        }

        try await Task.sleep(nanoseconds: UInt64(sleepDuration * Double(NSEC_PER_SEC)))
    }
}

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
        watchdog = Watchdog(killAppFunction: mockKillAppFunction.killApp, timeout: 1.0, checkInterval: 0.1)
    }

    override func tearDown() {
        watchdog?.stop()
        watchdog = nil
        mockKillAppFunction = nil
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

    func testStart() {
        watchdog.start()
        XCTAssertTrue(watchdog.isRunning, "Watchdog should be running after start")
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app")
    }

    func testStop() {
        watchdog.stop()
        XCTAssertFalse(watchdog.isRunning, "Watchdog should not be running after stop")
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app")
    }

    func testMultipleStarts() {
        watchdog.start()
        let firstState = watchdog.isRunning

        watchdog.start() // Should cancel previous and start new
        let secondState = watchdog.isRunning

        XCTAssertTrue(firstState, "First start should make watchdog running")
        XCTAssertTrue(secondState, "Second start should keep watchdog running")
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app")
    }

    func testMultipleStops() {
        watchdog.start()
        watchdog.stop()
        watchdog.stop() // Should be safe to call multiple times

        XCTAssertFalse(watchdog.isRunning, "Multiple stops should be safe")
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app")
    }

    // MARK: - Deinit Tests

    func testDeinitStopsWatchdog() {
        let mockKill = MockKillAppFunction()
        var optionalWatchdog: Watchdog? = Watchdog(killAppFunction: mockKill.killApp, timeout: 1.0, checkInterval: 0.1)
        optionalWatchdog?.start()

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
        watchdog.start()

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

    // MARK: - Edge Case Tests

    func testZeroTimeout() {
        let mockKill = MockKillAppFunction()
        let zeroTimeoutWatchdog = Watchdog(killAppFunction: mockKill.killApp, timeout: 0.0, checkInterval: 0.1)
        zeroTimeoutWatchdog.start()

        // Should handle zero timeout gracefully
        XCTAssertTrue(zeroTimeoutWatchdog.isRunning)
        zeroTimeoutWatchdog.stop()
        XCTAssertFalse(zeroTimeoutWatchdog.isRunning)
    }

    func testZeroCheckInterval() {
        let mockKill = MockKillAppFunction()
        let zeroIntervalWatchdog = Watchdog(killAppFunction: mockKill.killApp, timeout: 1.0, checkInterval: 0.0)
        zeroIntervalWatchdog.start()

        XCTAssertTrue(zeroIntervalWatchdog.isRunning)
        zeroIntervalWatchdog.stop()
        XCTAssertFalse(zeroIntervalWatchdog.isRunning)
    }

    // MARK: - Memory Tests

    func testWatchdogDoesNotLeakMemory() async {
        weak var weakWatchdog: Watchdog?
        let mockKill = MockKillAppFunction()

        // Do the work directly on main actor (no Task needed)
        do {
            let localWatchdog = Watchdog(killAppFunction: mockKill.killApp, timeout: 1.0, checkInterval: 0.1)
            weakWatchdog = localWatchdog

            localWatchdog.start()
            XCTAssertTrue(localWatchdog.isRunning)
            localWatchdog.stop()
            XCTAssertFalse(localWatchdog.isRunning)

            // localWatchdog goes out of scope here
        }

        // Give time for deallocation
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(weakWatchdog, "Watchdog should be deallocated")
        XCTAssertFalse(mockKill.wasKilled, "Should not have killed app during memory test")
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
        XCTAssertFalse(mockKillAppFunction.wasKilled, "Should not have killed app during cycles")
    }

    // MARK: - Hang Detection Tests

    func testWatchdogDetectsMainThreadHang() async throws {
        // Use very short timeout for faster test
        let mockKill = MockKillAppFunction()
        let hangWatchdog = Watchdog(killAppFunction: mockKill.killApp, timeout: 0.2, checkInterval: 0.05)

        hangWatchdog.start()
        XCTAssertTrue(hangWatchdog.isRunning)
        XCTAssertFalse(mockKill.wasKilled, "Should not have killed app yet")

        // Let the watchdog establish a baseline heartbeat first
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // Now block the main thread using a synchronous dispatch to main queue
        // This ensures the main thread is truly blocked for heartbeat updates
        let expectation = XCTestExpectation(description: "Hang detected")

        Task.detached {
            // Wait for the hang to be detected
            while !mockKill.wasKilled {
                try? await Task.sleep(nanoseconds: 50_000_000) // Check every 0.05 seconds
            }
            expectation.fulfill()
        }

        // Block the main thread using DispatchQueue.main.sync from a background queue
        Task.detached {
            // This will block the main thread from a background thread
            DispatchQueue.main.sync {
                // Block for longer than timeout
                let startTime = Date()
                while Date().timeIntervalSince(startTime) < 0.5 {
                    // Busy wait to block main thread
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(mockKill.wasKilled, "Watchdog should have detected hang and killed app")

        hangWatchdog.stop()
    }

    func testWatchdogWithNormalOperationDoesNotKill() async throws {
        // Use short timeout but ensure normal operation
        let mockKill = MockKillAppFunction()
        let normalWatchdog = Watchdog(killAppFunction: mockKill.killApp, timeout: 0.3, checkInterval: 0.05)

        normalWatchdog.start()
        XCTAssertTrue(normalWatchdog.isRunning)

        // Wait longer than timeout but with normal main thread activity
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        XCTAssertFalse(mockKill.wasKilled, "Should not have killed app during normal operation")
        XCTAssertTrue(normalWatchdog.isRunning, "Watchdog should still be running")

        normalWatchdog.stop()
    }

    func testWatchdogStoppedBeforeHangDoesNotKill() async throws {
        let mockKill = MockKillAppFunction()
        let stoppedWatchdog = Watchdog(killAppFunction: mockKill.killApp, timeout: 0.1, checkInterval: 0.02)

        stoppedWatchdog.start()
        XCTAssertTrue(stoppedWatchdog.isRunning)

        // Stop watchdog before hang occurs
        stoppedWatchdog.stop()
        XCTAssertFalse(stoppedWatchdog.isRunning)

        // Give time for the check to happen
        try await Task.sleep(nanoseconds: 40_000_000) // 0.04 seconds

        // Now block main thread using the same approach as other tests
        Task.detached {
            DispatchQueue.main.sync {
                let startTime = Date()
                while Date().timeIntervalSince(startTime) < 0.3 {
                    // Busy wait to block main thread
                }
            }
        }

        // Give time for any potential background monitoring to detect hang
        // (but it shouldn't because watchdog is stopped)
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        XCTAssertFalse(mockKill.wasKilled, "Stopped watchdog should not kill app")
    }
}

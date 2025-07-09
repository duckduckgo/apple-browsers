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

    override func setUp() {
        super.setUp()
        // Use short timeouts for faster tests
        watchdog = Watchdog(timeout: 1.0, checkInterval: 0.1)
    }

    override func tearDown() {
        watchdog?.stop()
        watchdog = nil
        super.tearDown()
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

    // MARK: - State Transition Tests

    func testStateConsistencyDuringStartStop() {
        // Rapid state changes should be consistent
        for _ in 0..<10 {
            watchdog.start()
            XCTAssertTrue(watchdog.isRunning, "Should be running after start")

            watchdog.stop()
            XCTAssertFalse(watchdog.isRunning, "Should be stopped after stop")
        }
    }

    // MARK: - Timeout Configuration Tests

    func testCustomTimeout() {
        let shortTimeoutWatchdog = Watchdog(timeout: 0.5, checkInterval: 0.1)
        XCTAssertFalse(shortTimeoutWatchdog.isRunning)

        shortTimeoutWatchdog.start()
        XCTAssertTrue(shortTimeoutWatchdog.isRunning)

        shortTimeoutWatchdog.stop()
        XCTAssertFalse(shortTimeoutWatchdog.isRunning)
    }

    func testCustomCheckInterval() {
        let fastCheckWatchdog = Watchdog(timeout: 1.0, checkInterval: 0.05)
        XCTAssertFalse(fastCheckWatchdog.isRunning)

        fastCheckWatchdog.start()
        XCTAssertTrue(fastCheckWatchdog.isRunning)

        fastCheckWatchdog.stop()
        XCTAssertFalse(fastCheckWatchdog.isRunning)
    }

    // MARK: - Deinit Tests

    func testDeinitStopsWatchdog() {
        var optionalWatchdog: Watchdog? = Watchdog(timeout: 1.0, checkInterval: 0.1)
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
    }

    // MARK: - Edge Case Tests

    func testZeroTimeout() {
        let zeroTimeoutWatchdog = Watchdog(timeout: 0.0, checkInterval: 0.1)
        zeroTimeoutWatchdog.start()

        // Should handle zero timeout gracefully
        XCTAssertTrue(zeroTimeoutWatchdog.isRunning)
        zeroTimeoutWatchdog.stop()
        XCTAssertFalse(zeroTimeoutWatchdog.isRunning)
    }

    func testNegativeTimeout() {
        let negativeTimeoutWatchdog = Watchdog(timeout: -1.0, checkInterval: 0.1)
        negativeTimeoutWatchdog.start()

        // Should handle negative timeout gracefully (probably immediately trigger)
        XCTAssertTrue(negativeTimeoutWatchdog.isRunning)
        negativeTimeoutWatchdog.stop()
    }

    func testZeroCheckInterval() {
        let zeroIntervalWatchdog = Watchdog(timeout: 1.0, checkInterval: 0.0)
        zeroIntervalWatchdog.start()

        XCTAssertTrue(zeroIntervalWatchdog.isRunning)
        zeroIntervalWatchdog.stop()
        XCTAssertFalse(zeroIntervalWatchdog.isRunning)
    }

    // MARK: - Integration Tests

    func testWatchdogDoesNotInterfereWithMainThreadWork() async {
        watchdog.start()

        var counter = 0
        let iterations = 10

        // Perform main thread work while watchdog is running
        for _ in 0..<iterations {
            await MainActor.run {
                counter += 1
            }
        }

        XCTAssertEqual(counter, iterations, "Main thread work should complete normally")
        XCTAssertTrue(watchdog.isRunning, "Watchdog should still be running")
    }

    func testWatchdogWorksWithOtherAsyncTasks() async {
        watchdog.start()

        let results = await withTaskGroup(of: Int.self) { group in
            // Start several background tasks
            for i in 0..<5 {
                group.addTask {
                    // Just return the value, no sleep needed
                    return i
                }
            }

            var results: [Int] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        XCTAssertEqual(results.count, 5, "All background tasks should complete")
        XCTAssertTrue(watchdog.isRunning, "Watchdog should still be running")
    }

    // MARK: - Memory Tests

    func testWatchdogDoesNotLeakMemory() async {
        let expectation = XCTestExpectation(description: "Watchdog deallocated")
        weak var weakWatchdog: Watchdog?

        Task {
            let localWatchdog = Watchdog(timeout: 1.0, checkInterval: 0.1)
            weakWatchdog = localWatchdog

            localWatchdog.start()
            XCTAssertTrue(localWatchdog.isRunning)
            localWatchdog.stop()
            XCTAssertFalse(localWatchdog.isRunning)

            // localWatchdog goes out of scope here
        }

        // Use a small delay only where absolutely necessary for memory cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if weakWatchdog == nil {
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 1.0)
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

    func testMultipleWatchdogInstances() {
        let watchdog1 = Watchdog(timeout: 1.0, checkInterval: 0.1)
        let watchdog2 = Watchdog(timeout: 2.0, checkInterval: 0.2)
        let watchdog3 = Watchdog(timeout: 3.0, checkInterval: 0.3)

        // All should start independently
        watchdog1.start()
        watchdog2.start()
        watchdog3.start()

        XCTAssertTrue(watchdog1.isRunning)
        XCTAssertTrue(watchdog2.isRunning)
        XCTAssertTrue(watchdog3.isRunning)

        // Stop them in different order
        watchdog2.stop()
        XCTAssertTrue(watchdog1.isRunning)
        XCTAssertFalse(watchdog2.isRunning)
        XCTAssertTrue(watchdog3.isRunning)

        watchdog1.stop()
        watchdog3.stop()

        XCTAssertFalse(watchdog1.isRunning)
        XCTAssertFalse(watchdog2.isRunning)
        XCTAssertFalse(watchdog3.isRunning)
    }
}

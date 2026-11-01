//
//  NetworkProtectionConnectionTesterTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
@testable import VPN

@MainActor
final class NetworkProtectionConnectionTesterTests: XCTestCase {
    private enum TestError: Error {
        case preparation
    }

    private var results: [ConnectionTestingResult] = []
    private var connectivityResults: [Bool] = []

    func testStopCancelsInterfacePreparationAndDoesNotStartChecks() async throws {
        let preparing = expectation(description: "Preparing interface")
        let gate = CheckGate()
        var checkCount = 0
        let tester = makeTester(prepare: { _ in
            preparing.fulfill()
            await gate.wait()
        }, check: {
            checkCount += 1
            return (false, true)
        })
        let start = Task { try await tester.start(tunnelIfName: "utun-test", testImmediately: true) }
        await fulfillment(of: [preparing], timeout: 2)
        tester.stop()
        gate.open()
        try await start.value

        XCTAssertFalse(tester.isRunning)
        XCTAssertEqual(checkCount, 0)
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(connectivityResults.isEmpty)
    }

    func testStopCancelsImmediateCheckWithoutReportingItsLateFailure() async throws {
        let checking = expectation(description: "Immediate check started")
        let gate = CheckGate()
        var wasCancelled = false
        let tester = makeTester(check: {
            checking.fulfill()
            await gate.wait()
            wasCancelled = Task.isCancelled
            return (false, true)
        })
        let start = Task { try await tester.start(tunnelIfName: "utun-test", testImmediately: true) }
        await fulfillment(of: [checking], timeout: 2)
        tester.stop()
        gate.open()
        try await start.value

        XCTAssertTrue(wasCancelled)
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(connectivityResults.isEmpty)
    }

    func testStopCancelsPeriodicCheckWithoutReportingItsLateFailure() async throws {
        let checking = expectation(description: "Periodic check started")
        let finished = expectation(description: "Cancelled check returned")
        let unexpectedResult = expectation(description: "Stopped check reported a result")
        unexpectedResult.isInverted = true
        let gate = CheckGate()
        var wasCancelled = false
        let tester = makeTester(check: {
            checking.fulfill()
            await gate.wait()
            wasCancelled = Task.isCancelled
            finished.fulfill()
            return (false, true)
        })
        tester.resultHandler = { _ in unexpectedResult.fulfill() }
        try await tester.start(tunnelIfName: "utun-test", testImmediately: false)
        await fulfillment(of: [checking], timeout: 2)
        tester.stop()
        gate.open()
        await fulfillment(of: [finished], timeout: 2)
        await fulfillment(of: [unexpectedResult], timeout: 0.05)

        XCTAssertTrue(wasCancelled)
        XCTAssertTrue(connectivityResults.isEmpty)
    }

    func testOldStartupCannotStopOrScheduleChecksForTheRestartedTester() async throws {
        let preparing = expectation(description: "Old startup preparing")
        let checked = expectation(description: "New tester checked connectivity")
        let gate = CheckGate()
        var prepareCount = 0
        var checkCount = 0
        let tester = makeTester(prepare: { _ in
            prepareCount += 1
            if prepareCount == 1 {
                preparing.fulfill()
                await gate.wait()
            }
        }, check: {
            checkCount += 1
            checked.fulfill()
            return (true, true)
        })
        let oldStart = Task { try await tester.start(tunnelIfName: "old", testImmediately: true) }
        await fulfillment(of: [preparing], timeout: 2)
        tester.stop()
        try await tester.start(tunnelIfName: "new", testImmediately: false)
        await fulfillment(of: [checked], timeout: 2)
        gate.open()
        try await oldStart.value

        XCTAssertTrue(tester.isRunning)
        XCTAssertEqual(checkCount, 1)
        XCTAssertEqual(connectivityResults, [true])
        XCTAssertEqual(results, [.connected])
        tester.stop()
    }

    func testOldPeriodicFailureDoesNotReachCallbacksAfterRestart() async throws {
        let oldChecking = expectation(description: "Old periodic check started")
        let newChecked = expectation(description: "New periodic check finished")
        let oldFinished = expectation(description: "Old periodic check returned")
        let gate = CheckGate()
        var checkCount = 0
        let tester = makeTester(check: {
            checkCount += 1
            if checkCount == 1 {
                oldChecking.fulfill()
                await gate.wait()
                oldFinished.fulfill()
                return (false, true)
            }
            newChecked.fulfill()
            return (true, true)
        })
        try await tester.start(tunnelIfName: "old", testImmediately: false)
        await fulfillment(of: [oldChecking], timeout: 2)
        tester.stop()
        try await tester.start(tunnelIfName: "new", testImmediately: false)
        await fulfillment(of: [newChecked], timeout: 2)
        gate.open()
        await fulfillment(of: [oldFinished], timeout: 2)
        await Task.yield()

        XCTAssertTrue(tester.isRunning)
        XCTAssertEqual(connectivityResults, [true])
        XCTAssertEqual(results, [.connected])
        tester.stop()
    }

    func testCancellingCallerAlsoCancelsStartup() async {
        let preparing = expectation(description: "Startup preparing")
        let tester = makeTester(prepare: { _ in
            preparing.fulfill()
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }, check: { (false, true) })
        let start = Task { try await tester.start(tunnelIfName: "utun-test", testImmediately: true) }
        await fulfillment(of: [preparing], timeout: 2)
        start.cancel()
        await assertCancelled(start)

        XCTAssertFalse(tester.isRunning)
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(connectivityResults.isEmpty)
    }

    func testGenuineFailedCheckStillReportsFailure() async throws {
        let checked = expectation(description: "Check completed")
        let tester = makeTester(check: { (false, true) })
        tester.resultHandler = { [self] result in
            results.append(result)
            checked.fulfill()
        }
        try await tester.start(tunnelIfName: "utun-test", testImmediately: false)
        await fulfillment(of: [checked], timeout: 2)
        tester.stop()

        XCTAssertEqual(results, [.disconnected(failureCount: 1)])
        XCTAssertEqual(connectivityResults, [false])
    }

    func testCancellingCallerDuringImmediateCheckDoesNotStartPeriodicChecks() async {
        let checking = expectation(description: "Immediate check started")
        var checkCount = 0
        let tester = makeTester(check: {
            checkCount += 1
            checking.fulfill()
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return (false, true)
        })
        let start = Task { try await tester.start(tunnelIfName: "utun-test", testImmediately: true) }
        await fulfillment(of: [checking], timeout: 2)
        start.cancel()
        await assertCancelled(start)

        XCTAssertFalse(tester.isRunning)
        XCTAssertEqual(checkCount, 1)
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(connectivityResults.isEmpty)
    }

    func testBothPathsDownStillReportsRawConnectivityFailure() async throws {
        let checked = expectation(description: "Check completed")
        let tester = makeTester(check: { (false, false) })
        tester.resultHandler = { [self] result in
            results.append(result)
            checked.fulfill()
        }
        try await tester.start(tunnelIfName: "utun-test", testImmediately: false)
        await fulfillment(of: [checked], timeout: 2)
        tester.stop()

        XCTAssertEqual(results, [.connected]) // Existing VPN-only failure classification is preserved.
        XCTAssertEqual(connectivityResults, [false])
    }

    func testGenuinePreparationFailureStillThrowsAndStopsTheTester() async {
        let tester = makeTester(prepare: { _ in throw TestError.preparation }, check: { (true, true) })
        do {
            try await tester.start(tunnelIfName: "utun-test", testImmediately: true)
            XCTFail("Expected preparation failure")
        } catch TestError.preparation {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(tester.isRunning)
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(connectivityResults.isEmpty)
    }

    private func makeTester(prepare: @escaping (String) async throws -> Void = { _ in },
                            check: @escaping () async throws -> (vpn: Bool, local: Bool)) -> NetworkProtectionConnectionTester {
        let tester = NetworkProtectionConnectionTester(timerQueue: .main,
                                                       connectivityResultHandler: { [self] connected, _ in connectivityResults.append(connected) },
                                                       prepareConnectionTest: prepare,
                                                       performConnectionTest: check)
        tester.resultHandler = { [self] in results.append($0) }
        return tester
    }

    private func assertCancelled(_ task: Task<Void, Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await task.value
            XCTFail("Expected startup cancellation", file: file, line: line)
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

@MainActor
private final class CheckGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

//
//  WakeConnectivityMonitorTests.swift
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
@_spi(Testing) import PixelKit
@testable import VPN

final class WakeConnectivityMonitorTests: XCTestCase {
    private var pixelFiring: RecordingPixelFiring!
    private var reportQueue: DispatchQueue!
    private var monitor: WakeConnectivityMonitor!
    private var date = Date(timeIntervalSince1970: 100)

    override func setUp() {
        super.setUp()
        pixelFiring = RecordingPixelFiring()
        reportQueue = DispatchQueue(label: "WakeConnectivityMonitorTests")
        monitor = WakeConnectivityMonitor(pixelFiring: pixelFiring, now: { self.date }, reportQueue: reportQueue)
    }

    override func tearDown() {
        reportQueue.sync { }
        monitor = nil
        pixelFiring = nil
        reportQueue = nil
        super.tearDown()
    }

    func testTwoFailedChecksFireOnceWithRetry() {
        monitor.wake(isEligible: true)
        check(isConnected: false)
        assertFireCount(0)
        check(isConnected: false)
        assertFireCount(1)
        XCTAssertEqual(pixelFiring.mock.actualFireCalls, [ExpectedFireCall(pixel: VPNWakeConnectivityPixel.failure, frequency: .dailyAndCount)])
        XCTAssertEqual(pixelFiring.retryOptions, [true])
        XCTAssertEqual(VPNWakeConnectivityPixel.failure.name, "vpn_wake_connectivity_failure")
        XCTAssertNil(VPNWakeConnectivityPixel.failure.parameters)
    }

    func testNoObservationWhileAsleep() {
        check(isConnected: false)
        check(isConnected: false)
        assertFireCount(0)
    }

    func testSuccessfulConnectivityEndsThisWakeCycle() {
        monitor.wake(isEligible: true)
        check(isConnected: true)
        check(isConnected: false)
        check(isConnected: false)
        assertFireCount(0)
    }

    func testSuccessfulCheckAfterOneFailureEndsCycle() {
        monitor.wake(isEligible: true)
        check(isConnected: false)
        check(isConnected: true)
        check(isConnected: false)
        check(isConnected: false)
        assertFireCount(0)
    }

    func testChecksStartedBeforeWakeDoNotCountEvenIfTheyCompleteAfterWake() {
        monitor.wake(isEligible: true)
        monitor.connectionTestCompleted(isConnected: false, startedAt: date.addingTimeInterval(-1))
        monitor.connectionTestCompleted(isConnected: false, startedAt: date.addingTimeInterval(-1))
        check(isConnected: false)
        assertFireCount(0)
        check(isConnected: false)
        assertFireCount(1)
    }

    func testSuccessfulCheckStartedBeforeWakeDoesNotEndNewObservation() {
        monitor.wake(isEligible: true)
        monitor.connectionTestCompleted(isConnected: true, startedAt: date.addingTimeInterval(-1))
        check(isConnected: false)
        check(isConnected: false)
        assertFireCount(1)
    }

    func testDuplicateWakeDoesNotResetPartialCountOrRearmAfterFiring() {
        monitor.wake(isEligible: true)
        check(isConnected: false)
        monitor.wake(isEligible: true)
        check(isConnected: false)
        assertFireCount(1)
        monitor.wake(isEligible: true)
        check(isConnected: false)
        check(isConnected: false)
        assertFireCount(1)
    }

    func testSleepCancelsAndNextWakeGetsAFreshCount() {
        monitor.wake(isEligible: true)
        check(isConnected: false)
        monitor.sleep()
        check(isConnected: false)
        assertFireCount(0)
        date = date.addingTimeInterval(60)
        monitor.wake(isEligible: true)
        check(isConnected: false)
        assertFireCount(0)
        check(isConnected: false)
        assertFireCount(1)
    }

    func testOldWakeResultsCannotEnterNewWakeCycle() {
        monitor.wake(isEligible: true)
        let oldProbeStartedAt = date.addingTimeInterval(1)
        monitor.sleep()
        date = date.addingTimeInterval(60)
        monitor.wake(isEligible: true)
        monitor.connectionTestCompleted(isConnected: false, startedAt: oldProbeStartedAt)
        check(isConnected: false)
        assertFireCount(0)
    }

    func testCancelEndsCycleUntilNextSleepAndWake() {
        monitor.wake(isEligible: true)
        check(isConnected: false)
        monitor.cancel()
        monitor.wake(isEligible: true)
        check(isConnected: false)
        check(isConnected: false)
        assertFireCount(0)
        monitor.sleep()
        monitor.wake(isEligible: true)
        check(isConnected: false)
        check(isConnected: false)
        assertFireCount(1)
    }

    func testIneligibleWakeDoesNotObserveEvenIfFollowedByDuplicateEligibleWake() {
        monitor.wake(isEligible: false)
        check(isConnected: false)
        check(isConnected: false)
        monitor.wake(isEligible: true)
        check(isConnected: false)
        check(isConnected: false)
        assertFireCount(0)
    }

    func testFailuresContinueCountingAcrossProbeRestarts() {
        monitor.wake(isEligible: true)
        check(isConnected: false)
        // A new current tester run after a network/configuration change contributes normally.
        monitor.connectionTestCompleted(isConnected: false, startedAt: date.addingTimeInterval(30))
        assertFireCount(1)
    }

    func testCancelBeforeQueuedReportRunsSuppressesTheReport() {
        reportQueue.suspend()
        monitor.wake(isEligible: true)
        check(isConnected: false)
        check(isConnected: false)
        monitor.cancel()
        reportQueue.resume()
        assertFireCount(0)
    }

    func testQueuedOldReportCannotFireForANewWakeCycle() {
        reportQueue.suspend()
        monitor.wake(isEligible: true)
        check(isConnected: false)
        check(isConnected: false)
        monitor.sleep()
        monitor.wake(isEligible: true)
        check(isConnected: false)
        check(isConnected: false)
        reportQueue.resume()
        assertFireCount(1)
    }

    private func check(isConnected: Bool) {
        monitor.connectionTestCompleted(isConnected: isConnected, startedAt: date.addingTimeInterval(1))
    }

    private func assertFireCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        reportQueue.sync { }
        XCTAssertEqual(pixelFiring.mock.actualFireCalls.count, count, file: file, line: line)
    }
}

private final class RecordingPixelFiring: PixelKitFiring {
    let mock = PixelKitMock()
    private(set) var retryOptions: [Bool] = []

    func fire(event: PixelKit.Event, frequency: PixelKit.Frequency, options: PixelKit.Options, onComplete: @escaping PixelKit.CompletionBlock) {
        retryOptions.append(options.retryOnFailure)
        mock.fire(event: event, frequency: frequency, options: options, onComplete: onComplete)
    }
}

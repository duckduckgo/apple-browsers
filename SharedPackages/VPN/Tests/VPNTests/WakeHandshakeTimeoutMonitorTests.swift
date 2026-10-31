//
//  WakeHandshakeTimeoutMonitorTests.swift
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

final class WakeHandshakeTimeoutMonitorTests: XCTestCase {
    private var pixelFiring: RecordingPixelFiring!
    private var reportQueue: DispatchQueue!
    private var monitor: WakeHandshakeTimeoutMonitor!
    private let request = "peer(test) - Sending handshake initiation"
    private let timeout = "peer(test) - Handshake did not complete after 5 seconds, retrying (try 2)"

    override func setUp() {
        super.setUp()
        pixelFiring = RecordingPixelFiring()
        reportQueue = DispatchQueue(label: "WakeHandshakeTimeoutMonitorTests")
        monitor = WakeHandshakeTimeoutMonitor(pixelFiring: pixelFiring, pathMonitor: nil, reportQueue: reportQueue)
    }

    override func tearDown() {
        reportQueue.sync { }
        monitor = nil
        pixelFiring = nil
        reportQueue = nil
        super.tearDown()
    }

    func testTwoNativeTimeoutsFireOnceWithRetryAndNoPeerParameters() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        assertFireCount(0)
        monitor.consumeLog(timeout)
        assertFireCount(1)

        XCTAssertEqual(pixelFiring.mock.actualFireCalls, [ExpectedFireCall(pixel: VPNWakeHandshakePixel.timeouts, frequency: .dailyAndCount)])
        XCTAssertEqual(pixelFiring.retryOptions, [true])
        XCTAssertEqual(VPNWakeHandshakePixel.timeouts.name, "vpn_wake_handshake_timeouts")
        XCTAssertNil(VPNWakeHandshakePixel.timeouts.parameters)
    }

    func testRequestsBeforeWakeAndTheirTimeoutsDoNotArmCounting() {
        monitor.consumeLog(request)
        monitor.wake(isEligible: true)
        monitor.consumeLog(timeout)
        monitor.consumeLog(timeout)
        assertFireCount(0)
        sendTwoTimeouts()
        assertFireCount(1)
    }

    func testNoObservationWhileAsleep() {
        sendTwoTimeouts()
        assertFireCount(0)
    }

    func testRepeatedRequestsAndRetryOrdinalResetsDoNotResetOurTimeoutCount() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        monitor.consumeLog("UDP bind has been updated")
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        assertFireCount(1)
    }

    func testSendingRequestsWithoutTimeoutsDoesNotFire() {
        monitor.wake(isEligible: true)
        for _ in 0..<10 { monitor.consumeLog(request) }
        assertFireCount(0)
    }

    func testAuthenticatedResponseOrInitiationEndsThisWakeCycle() {
        for progress in ["Received handshake response", "Received handshake initiation"] {
            monitor.sleep()
            monitor.wake(isEligible: true)
            monitor.consumeLog(request)
            monitor.consumeLog(timeout)
            monitor.consumeLog("peer(test) - " + progress)
            sendTwoTimeouts()
            assertFireCount(0)
        }
    }

    func testAuthenticatedProgressBeforeFirstPostWakeRequestEndsCycle() {
        monitor.wake(isEligible: true)
        monitor.consumeLog("peer(test) - Received handshake response")
        sendTwoTimeouts()
        assertFireCount(0)
    }

    func testInvalidResponsesAndOutgoingResponsesAreNotAuthenticatedProgress() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        monitor.consumeLog("Received invalid response message from 192.0.2.1:443")
        monitor.consumeLog("peer(test) - Sending handshake response")
        monitor.consumeLog(timeout)
        assertFireCount(1)
    }

    func testOtherPeersCannotContributeTimeoutsOrClearProgress() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout.replacingOccurrences(of: "peer(test)", with: "peer(other)"))
        monitor.consumeLog("peer(other) - Received handshake response")
        monitor.consumeLog(timeout)
        assertFireCount(0)
        monitor.consumeLog(timeout)
        assertFireCount(1)
    }

    func testNonHandshakeAndGiveUpMessagesAreNotTimeoutEvents() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog("peer(test) - Handshake did not complete after 20 attempts, giving up")
        monitor.consumeLog("peer(test) - Handshake did not complete after invalid seconds, retrying (try 2)")
        monitor.consumeLog("unrelated " + timeout)
        monitor.consumeLog(timeout)
        assertFireCount(0)
    }

    func testDuplicateWakeDoesNotResetPartialCountOrRearmAfterFiring() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        monitor.wake(isEligible: true)
        monitor.consumeLog(timeout)
        assertFireCount(1)
        monitor.wake(isEligible: true)
        sendTwoTimeouts()
        assertFireCount(1)
    }

    func testSleepCancelsAndNextWakeGetsAFreshCount() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        monitor.sleep()
        monitor.consumeLog(timeout)
        assertFireCount(0)
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        assertFireCount(0)
        monitor.consumeLog(timeout)
        assertFireCount(1)
    }

    func testCancelEndsCycleUntilNextSleepAndWake() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        monitor.cancel()
        monitor.wake(isEligible: true)
        sendTwoTimeouts()
        assertFireCount(0)
        monitor.sleep()
        monitor.wake(isEligible: true)
        sendTwoTimeouts()
        assertFireCount(1)
    }

    func testIneligibleWakeDoesNotObserveEvenIfFollowedByDuplicateEligibleWake() {
        monitor.wake(isEligible: false)
        sendTwoTimeouts()
        monitor.wake(isEligible: true)
        sendTwoTimeouts()
        assertFireCount(0)
    }

    func testInitialAndEquivalentPathNotificationsDoNotCancel() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        monitor.updatePath(isSatisfied: true, physicalInterfaces: ["pdp_ip0", "en0"])
        monitor.updatePath(isSatisfied: true, physicalInterfaces: ["en0", "pdp_ip0"])
        monitor.consumeLog(timeout)
        assertFireCount(1)
    }

    func testPhysicalInterfaceChangeCancels() {
        monitor.updatePath(isSatisfied: true, physicalInterfaces: ["pdp_ip0"])
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        monitor.updatePath(isSatisfied: true, physicalInterfaces: ["en0"])
        monitor.consumeLog(timeout)
        assertFireCount(0)
    }

    func testUnsatisfiedPathCancelsEvenOnInitialDelivery() {
        monitor.wake(isEligible: true)
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        monitor.updatePath(isSatisfied: false, physicalInterfaces: [])
        monitor.consumeLog(timeout)
        assertFireCount(0)
    }

    func testPathUpdatesDuringSleepDoNotPreventNextWakeObservation() {
        monitor.updatePath(isSatisfied: false, physicalInterfaces: [])
        monitor.updatePath(isSatisfied: true, physicalInterfaces: ["pdp_ip0"])
        monitor.wake(isEligible: true)
        sendTwoTimeouts()
        assertFireCount(1)
    }

    func testKnownUnsatisfiedPathDoesNotArmOnWake() {
        monitor.updatePath(isSatisfied: false, physicalInterfaces: [])
        monitor.wake(isEligible: true)
        sendTwoTimeouts()
        assertFireCount(0)
    }

    func testCancelBeforeQueuedReportRunsSuppressesTheReport() {
        reportQueue.suspend()
        monitor.wake(isEligible: true)
        sendTwoTimeouts()
        monitor.cancel()
        reportQueue.resume()
        assertFireCount(0)
    }

    func testQueuedOldReportCannotFireForANewWakeCycle() {
        reportQueue.suspend()
        monitor.wake(isEligible: true)
        sendTwoTimeouts()
        monitor.sleep()
        monitor.wake(isEligible: true)
        sendTwoTimeouts()
        reportQueue.resume()
        assertFireCount(1)
    }

    private func sendTwoTimeouts() {
        monitor.consumeLog(request)
        monitor.consumeLog(timeout)
        monitor.consumeLog(timeout)
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

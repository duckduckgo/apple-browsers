//
//  VPNSessionHealthInstrumentationTests.swift
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

import Foundation
import NetworkExtension
import XCTest
@_spi(Testing) import PixelKit
@testable import VPN

final class VPNSessionHealthInstrumentationTests: XCTestCase {

    private var wideEvent: WideEventMock!
    private var inputs: InstrumentationSettings!
    private var instrumentation: DefaultVPNSessionHealthInstrumentation!

    // January 1, 2024, at midnight UTC. Sessions start ten minutes into this hour.
    private let hourStart = Date(timeIntervalSince1970: 1_704_067_200)

    override func setUp() {
        super.setUp()
        wideEvent = WideEventMock()
        inputs = InstrumentationSettings(date: hourStart.addingTimeInterval(600))
        instrumentation = makeInstrumentation()
    }

    override func tearDown() {
        instrumentation = nil
        inputs = nil
        wideEvent = nil
        super.tearDown()
    }

    // MARK: - Starting and enablement

    func testPhysicalStartsPersistStartReasonExtensionTypeAndTimestamp() throws {
        let cases: [(startReason: PacketTunnelProvider.AdapterStartReason,
                     expectedReason: VPNSessionHealthWideEventData.EventStartReason)] = [
            (.manual, .physicalTunnelStartManual),
            (.onDemand, .physicalTunnelStartOnDemand)
        ]

        for (reason, expected) in cases {
            instrumentation.tunnelStarted(reason: reason)
            let data = try XCTUnwrap(wideEvent.started.last as? VPNSessionHealthWideEventData)

            XCTAssertEqual(data.startReason, expected)
            XCTAssertEqual(data.startedAt, inputs.date)
            XCTAssertEqual(data.lastObservedAt, inputs.date)
            XCTAssertEqual(data.extensionType, .system)

            instrumentation.tunnelStopped(reason: .userInitiated)
        }
    }

    func testDisabledPhysicalStartAndSubsequentCallbacksDoNotCreateEvents() {
        inputs.enabled = false
        startMonitoredSession()
        instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))
        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertTrue(wideEvent.started.isEmpty)
        XCTAssertTrue(wideEvent.updates.isEmpty)
        XCTAssertTrue(wideEvent.completions.isEmpty)
    }

    func testEnablingMidSessionWaitsForNextPhysicalStart() {
        inputs.enabled = false
        instrumentation.tunnelStarted(reason: .manual)
        inputs.enabled = true
        instrumentation.tunnelStarted(reason: .reconnected)
        instrumentation.monitoringStarted()

        XCTAssertTrue(wideEvent.started.isEmpty)

        instrumentation.tunnelStarted(reason: .manual)

        XCTAssertEqual(wideEvent.started.count, 1)
    }

    func testDisablingDoesNotDropActiveSessionOrItsRollover() throws {
        startMonitoredSession()
        inputs.enabled = false
        inputs.date = hourStart.addingTimeInterval(3_610)
        instrumentation.connectionTestCompleted(.connected)

        XCTAssertEqual(wideEvent.started.count, 2)
        XCTAssertEqual(wideEvent.completions.count, 1)

        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(wideEvent.completions.count, 2)
        XCTAssertEqual(try completedEvent(at: 1).outcome, .success)

        instrumentation.tunnelStarted(reason: .manual)

        XCTAssertEqual(wideEvent.started.count, 2)
    }

    // MARK: - Monitoring and callbacks

    func testReconnectWakeAndSnoozeEndResumeSameEvent() throws {
        startMonitoredSession()
        let originalEventID = try latestEvent().globalData.id
        for reason in [PacketTunnelProvider.AdapterStartReason.reconnected, .wake, .snoozeEnded] {
            instrumentation.deviceWentToSleep()
            instrumentation.tunnelStarted(reason: reason)

            XCTAssertEqual(try latestEvent().globalData.id, originalEventID)
            XCTAssertFalse(try latestEvent().isPaused)
        }

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertTrue(wideEvent.completions.isEmpty)
    }

    func testCallbacksWithoutPhysicalStartAreIgnored() {
        instrumentation.tunnelResumed()
        instrumentation.tunnelStarted(reason: .wake)
        instrumentation.monitoringStarted()
        instrumentation.monitoringStopped(isIntentional: false)
        instrumentation.monitoringFailedToStart()
        instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))
        instrumentation.handshakeCheckCompleted(.failureDetected)
        instrumentation.failureRecoveryStepChanged(.started)
        instrumentation.leakCheckCompleted(leakDetected: true)
        instrumentation.deviceWentToSleep()
        instrumentation.snoozeStarted()
        instrumentation.tunnelReconfigurationStarted()
        instrumentation.tunnelStopped(reason: .userInitiated)
        instrumentation.tunnelCancelledWithError()

        XCTAssertTrue(wideEvent.started.isEmpty)
        XCTAssertTrue(wideEvent.updates.isEmpty)
        XCTAssertTrue(wideEvent.completions.isEmpty)
    }

    func testEveryTransitionPersistsItsObservationTimestamp() throws {
        startMonitoredSession()
        inputs.date = hourStart.addingTimeInterval(620)
        instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))

        XCTAssertEqual(try latestEvent().lastObservedAt, inputs.date)

        inputs.date = hourStart.addingTimeInterval(630)
        instrumentation.leakCheckCompleted(leakDetected: true)

        XCTAssertEqual(try latestEvent().lastObservedAt, inputs.date)
        XCTAssertTrue(try latestEvent().leakDetected)

        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(try completedEvent().lastObservedAt, inputs.date)
    }

    func testMonitoringFailureAndRecoveryAreForwarded() throws {
        startMonitoredSession()
        instrumentation.monitoringFailedToStart()

        XCTAssertTrue(try latestEvent().monitoringInterrupted)

        instrumentation.tunnelResumed()
        instrumentation.monitoringStarted()
        instrumentation.connectionTestCompleted(.connected)
        instrumentation.handshakeCheckCompleted(.failureDetected)
        instrumentation.failureRecoveryStepChanged(.started)
        instrumentation.failureRecoveryStepChanged(.completed(.healthy))
        instrumentation.handshakeCheckCompleted(.failureRecovered)
        instrumentation.tunnelStopped(reason: .userInitiated)
        let data = try completedEvent()

        XCTAssertTrue(data.staleHandshakeRecovered)
        XCTAssertEqual(data.failureRecoverySucceeded, true)
        XCTAssertEqual(data.outcome, .failure(.staleHandshake))
    }

    func testSleepAndSnoozeClearOutageWhileReconfigurationPreservesIt() throws {
        let pauseActions = [
            instrumentation.deviceWentToSleep,
            instrumentation.snoozeStarted,
            instrumentation.tunnelReconfigurationStarted
        ]

        for pause in pauseActions {
            startMonitoredSession()
            instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))
            pause()

            XCTAssertTrue(try latestEvent().isPaused)

            instrumentation.tunnelStopped(reason: .userInitiated)
        }

        let sleepEvent = try completedEvent(at: 0)
        let snoozeEvent = try completedEvent(at: 1)
        let reconfigurationEvent = try completedEvent(at: 2)

        XCTAssertEqual(sleepEvent.outcome, .success)
        XCTAssertEqual(snoozeEvent.outcome, .success)
        XCTAssertEqual(reconfigurationEvent.outcome, .failure(.routingOutageAtUserDisable))
    }

    // MARK: - Hourly rollover

    func testRolloverSplitsOngoingOutageAtBoundaryWithoutDoubleCounting() throws {
        startMonitoredSession()
        inputs.date = hourStart.addingTimeInterval(3_570)
        instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))

        inputs.date = hourStart.addingTimeInterval(3_630)
        instrumentation.connectionTestCompleted(.reconnected(failureCount: 1))

        XCTAssertEqual(wideEvent.completions.count, 1)

        let previousHour = try completedEvent()
        let currentHour = try latestEvent()
        let boundary = hourStart.addingTimeInterval(3_600)

        XCTAssertEqual(previousHour.endedAt, boundary)
        XCTAssertEqual(previousHour.totalOutageDuration, 30)
        XCTAssertEqual(currentHour.startedAt, boundary)
        XCTAssertEqual(currentHour.totalOutageDuration, 30)
        XCTAssertFalse(currentHour.connectionTestFailureActive)
        XCTAssertEqual(currentHour.lastObservedAt, inputs.date)
    }

    func testStopAtBoundaryCompletesOldAndNewSegmentsOnlyOnce() throws {
        startMonitoredSession()
        inputs.date = hourStart.addingTimeInterval(3_600)
        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(wideEvent.completions.count, 2)
        XCTAssertEqual(try completedEvent().endReason, .rolledOver)
        XCTAssertEqual(try completedEvent(at: 1).endReason, .stoppedByUser)
        XCTAssertEqual(try completedEvent(at: 1).eventDuration(asOf: inputs.date), 0)

        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(wideEvent.completions.count, 2)
    }

    func testSleepAcrossMultipleHoursDoesNotBackfillIntermediateSegments() throws {
        startMonitoredSession()
        instrumentation.deviceWentToSleep()
        inputs.date = hourStart.addingTimeInterval(10_830)
        instrumentation.tunnelStarted(reason: .wake)

        XCTAssertEqual(wideEvent.started.count, 2)
        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(try latestEvent().startedAt, hourStart.addingTimeInterval(10_800))
        XCTAssertEqual(try latestEvent().totalOutageDuration, 0)
        XCTAssertFalse(try latestEvent().isPaused)
    }

    // MARK: - Stopping and orphan recovery

    func testStoppedEventCompletesOnceAndLateCallbacksAreIgnored() {
        startMonitoredSession()
        let updateCountBeforeStop = wideEvent.updates.count
        instrumentation.tunnelStopped(reason: .userInitiated)
        instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))
        instrumentation.handshakeCheckCompleted(.failureDetected)
        instrumentation.failureRecoveryStepChanged(.failed(NSError(domain: "test", code: 1)))
        instrumentation.tunnelCancelledWithError()
        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(wideEvent.updates.count, updateCountBeforeStop)
    }

    func testPhysicalRestartCompletesPreviousEventWithoutMisclassifyingItAsOrphan() throws {
        startMonitoredSession()
        instrumentation.tunnelStarted(reason: .onDemand)

        XCTAssertEqual(wideEvent.started.count, 2)
        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(try completedEvent().endReason, .restartedWithoutStop)
    }

    func testOrphansAreCompletedEvenWhenNewTelemetryIsDisabled() throws {
        var orphan = VPNSessionHealthWideEventData(startReason: .physicalTunnelStartManual, startedAt: hourStart, extensionType: .system)
        orphan.lastObservedAt = hourStart.addingTimeInterval(30)
        wideEvent.startFlow(orphan)
        inputs.enabled = false
        instrumentation.tunnelStarted(reason: .manual)

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(try completedEvent().endReason, .processDied)
        XCTAssertEqual(try completedEvent().endedAt, orphan.lastObservedAt)

        instrumentation.tunnelStarted(reason: .manual)

        XCTAssertEqual(wideEvent.completions.count, 1)
    }

    func testStopReasonsAreMappedToExpectedEndReasons() throws {
        var groups: [(VPNSessionHealthWideEventData.EventEndReason, [NEProviderStopReason])] = [
            (.stoppedByUser, [.userInitiated]),
            (.stoppedByFailure, [.providerFailed, .connectionFailed, .configurationFailed, .unrecoverableNetworkChange]),
            (.stoppedWithoutNetwork, [.noNetworkAvailable]),
            (.stoppedAdministratively, [.none, .providerDisabled, .authenticationCanceled, .idleTimeout, .configurationDisabled,
                                       .configurationRemoved, .superceded, .userLogout, .userSwitch, .sleep, .appUpdate])
        ]
        if #available(macOS 15.1, iOS 18.1, *) {
            groups.append((.stoppedByFailure, [.internalError]))
        }
        for (expected, reasons) in groups {
            for reason in reasons {
                instrumentation.tunnelStarted(reason: .manual)
                instrumentation.tunnelStopped(reason: reason)
                let data = try XCTUnwrap(wideEvent.completions.last?.0 as? VPNSessionHealthWideEventData)

                XCTAssertEqual(data.endReason, expected, "Stop reason: \(reason)")
            }
        }
    }

    func testCancellationCompletesWithFailureStatus() throws {
        startMonitoredSession()
        instrumentation.tunnelCancelledWithError()

        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(wideEvent.completions.first?.1, .failure)
        XCTAssertEqual(try completedEvent().endReason, .cancelledWithError)
    }

    // MARK: - Concurrent callbacks

    func testConcurrentFailureCallbacksDoNotLoseObservations() throws {
        startMonitoredSession()
        let instrumentation = try XCTUnwrap(instrumentation)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))
        }
        instrumentation.tunnelStopped(reason: .providerFailed)
        let data = try completedEvent()

        XCTAssertEqual(data.activeOutageFailedCheckCount, 100)
        XCTAssertEqual(data.connectionTestOutageCount, 1)
        XCTAssertEqual(data.outcome, .failure(.routingOutage))
    }

    func testConcurrentStopsCompleteEventOnlyOnce() throws {
        startMonitoredSession()
        let instrumentation = try XCTUnwrap(instrumentation)

        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            instrumentation.tunnelStopped(reason: .userInitiated)
        }

        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(try completedEvent().outcome, .success)
    }

    // MARK: - Helpers

    private func makeInstrumentation() -> DefaultVPNSessionHealthInstrumentation {
        let inputs = inputs!
        return DefaultVPNSessionHealthInstrumentation(
            wideEvent: wideEvent,
            extensionType: .system,
            isEnabled: { inputs.enabled },
            now: { inputs.date })
    }

    private func latestEvent(file: StaticString = #filePath, line: UInt = #line) throws -> VPNSessionHealthWideEventData {
        try XCTUnwrap((wideEvent.updates.last ?? wideEvent.started.last) as? VPNSessionHealthWideEventData,
                      "Expected a persisted session-health event", file: file, line: line)
    }

    private func completedEvent(at index: Int = 0,
                                file: StaticString = #filePath,
                                line: UInt = #line) throws -> VPNSessionHealthWideEventData {
        let completion = wideEvent.completions.enumerated().first { $0.offset == index }?.element
        return try XCTUnwrap(completion?.0 as? VPNSessionHealthWideEventData,
                             "Expected a completed session-health event at index \(index)", file: file, line: line)
    }

    private func startMonitoredSession() {
        instrumentation.tunnelStarted(reason: .manual)
        instrumentation.monitoringStarted()
        instrumentation.connectionTestCompleted(.connected)
    }
}

// Mutated only between instrumentation calls; concurrent callback tests read fixed values.
private final class InstrumentationSettings: @unchecked Sendable {
    var date: Date
    var enabled = true

    init(date: Date) {
        self.date = date
    }
}

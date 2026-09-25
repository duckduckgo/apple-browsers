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
@_spi(Testing) import WideEvent
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
            startTunnel(reason)
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
        startTunnel(.manual)
        inputs.enabled = true
        startTunnel(.reconnected)
        instrumentation.monitoringStarted()

        XCTAssertTrue(wideEvent.started.isEmpty)

        startTunnel(.manual)

        XCTAssertEqual(wideEvent.started.count, 1)
    }

    func testWhenTelemetryIsDisabledThenActiveSessionIsDiscardedOnStop() throws {
        startMonitoredSession()
        let original = try latestEvent()
        inputs.enabled = false
        inputs.date = hourStart.addingTimeInterval(3_610)
        instrumentation.connectionTestCompleted(.connected)

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertTrue(wideEvent.completions.isEmpty)
        XCTAssertTrue(wideEvent.discarded.isEmpty)
        XCTAssertEqual(try latestEvent().globalData.id, original.globalData.id)

        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertTrue(wideEvent.completions.isEmpty)
        XCTAssertEqual(wideEvent.discarded.count, 1)
        XCTAssertTrue(wideEvent.getAllFlowData(VPNSessionHealthWideEventData.self).isEmpty)
        let discarded = try XCTUnwrap(wideEvent.discarded.first as? VPNSessionHealthWideEventData)
        XCTAssertEqual(discarded.globalData.id, original.globalData.id)
        XCTAssertEqual(discarded.startedAt, original.startedAt)
        XCTAssertEqual(discarded.endedAt, inputs.date)
        XCTAssertEqual(discarded.completedOutcome(), .success)

        instrumentation.tunnelStopped(reason: .userInitiated)
        startTunnel(.manual)

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertEqual(wideEvent.discarded.count, 1)
        XCTAssertTrue(wideEvent.completions.isEmpty)
    }

    // MARK: - Monitoring and callbacks

    func testReconnectWakeAndSnoozeEndResumeSameEvent() throws {
        startMonitoredSession()
        let originalEventID = try latestEvent().globalData.id
        for reason in [PacketTunnelProvider.AdapterStartReason.reconnected, .wake, .snoozeEnded] {
            instrumentation.deviceWentToSleep()
            startTunnel(reason)

            XCTAssertEqual(try latestEvent().globalData.id, originalEventID)
            XCTAssertFalse(try latestEvent().isPaused)
        }

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertTrue(wideEvent.completions.isEmpty)
    }

    func testCallbacksWithoutPhysicalStartAreIgnored() {
        instrumentation.tunnelResumed()
        startTunnel(.wake)
        instrumentation.monitoringStarted()
        instrumentation.monitoringStopped(isIntentional: false)
        instrumentation.monitoringFailedToStart()
        instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))
        instrumentation.handshakeCheckCompleted(.failureDetected)
        instrumentation.failureRecoveryStepChanged(.started)
        instrumentation.leakDetected()
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
        instrumentation.leakDetected()

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
        XCTAssertEqual(data.completedOutcome(), .failure(.staleHandshake))
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

        XCTAssertEqual(sleepEvent.completedOutcome(), .success)
        XCTAssertEqual(snoozeEvent.completedOutcome(), .success)
        XCTAssertEqual(reconfigurationEvent.completedOutcome(), .failure(.routingOutageAtUserStop))
    }

    // MARK: - Long sessions

    func testOutageAcrossHourBoundaryRemainsInSameEvent() throws {
        startMonitoredSession()
        let original = try latestEvent()
        inputs.date = hourStart.addingTimeInterval(3_570)
        instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))

        inputs.date = hourStart.addingTimeInterval(3_630)
        instrumentation.connectionTestCompleted(.reconnected(failureCount: 1))

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertTrue(wideEvent.completions.isEmpty)
        let current = try latestEvent()
        XCTAssertEqual(current.globalData.id, original.globalData.id)
        XCTAssertEqual(current.startedAt, original.startedAt)
        XCTAssertEqual(current.totalOutageDuration, 60)
        XCTAssertFalse(current.connectionTestFailureActive)
        XCTAssertEqual(current.lastObservedAt, inputs.date)

        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(try completedEvent().totalOutageDuration, 60)
    }

    func testStopAtHourBoundaryCompletesFullSessionOnlyOnce() throws {
        startMonitoredSession()
        let original = try latestEvent()
        inputs.date = hourStart.addingTimeInterval(3_600)
        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertEqual(wideEvent.completions.count, 1)
        let completed = try completedEvent()
        XCTAssertEqual(completed.globalData.id, original.globalData.id)
        XCTAssertEqual(completed.startedAt, original.startedAt)
        XCTAssertEqual(completed.endedAt, inputs.date)
        XCTAssertEqual(completed.endReason, .stoppedByUser)
        XCTAssertEqual(completed.eventDuration(asOf: inputs.date), 3_000)

        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(wideEvent.completions.count, 1)
    }

    func testSleepAcrossMultipleHoursResumesSameEventWithoutCountingSleepAsOutage() throws {
        startMonitoredSession()
        let original = try latestEvent()
        instrumentation.connectionTestCompleted(.disconnected(failureCount: 1))
        instrumentation.deviceWentToSleep()
        inputs.date = hourStart.addingTimeInterval(10_830)
        startTunnel(.wake)

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertTrue(wideEvent.completions.isEmpty)
        let resumed = try latestEvent()
        XCTAssertEqual(resumed.globalData.id, original.globalData.id)
        XCTAssertEqual(resumed.startedAt, original.startedAt)
        XCTAssertEqual(resumed.totalOutageDuration, 0)
        XCTAssertFalse(resumed.isPaused)
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
        startTunnel(.onDemand)

        XCTAssertEqual(wideEvent.started.count, 2)
        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(try completedEvent().endReason, .restartedWithoutStop)
    }

    func testWhenPersistedEventAlreadyEndedThenRecoveryPreservesItsOutcome() throws {
        let endedAt = hourStart.addingTimeInterval(30)
        let ended = VPNSessionHealthWideEventData(startReason: .physicalTunnelStartManual,
                                                  startedAt: hourStart,
                                                  extensionType: .system)
            .markingMonitoringStarted(at: hourStart)
            .applyingConnectionTestResult(.connected, at: hourStart)
            .finalized(for: .stoppedByUser, at: endedAt).event
        wideEvent.startFlow(ended)

        startTunnel(.manual)

        XCTAssertEqual(wideEvent.completions.count, 1)
        let recovered = try completedEvent()
        XCTAssertEqual(recovered.globalData.id, ended.globalData.id)
        XCTAssertEqual(recovered.endedAt, endedAt)
        XCTAssertEqual(recovered.endReason, .stoppedByUser)
        XCTAssertEqual(recovered.completedOutcome(), .success)
        XCTAssertEqual(wideEvent.completions.first?.1, .success)
    }

    func testWhenPersistedEventIsOpenThenRecoveryReportsProcessDied() throws {
        let orphan = VPNSessionHealthWideEventData(startReason: .physicalTunnelStartManual,
                                                   startedAt: hourStart,
                                                   extensionType: .system)
        wideEvent.startFlow(orphan)

        startTunnel(.manual)

        XCTAssertEqual(wideEvent.completions.count, 1)
        let recovered = try completedEvent()
        XCTAssertEqual(recovered.endReason, .processDied)
        XCTAssertEqual(recovered.completedOutcome(), .unknown(.extensionProcessDied))
        XCTAssertEqual(wideEvent.completions.first?.1, .unknown(reason: "extension_process_died"))
    }

    func testWhenTelemetryIsDisabledThenOrphansAreDiscardedOnce() throws {
        var orphan = VPNSessionHealthWideEventData(startReason: .physicalTunnelStartManual, startedAt: hourStart, extensionType: .system)
        orphan.lastObservedAt = hourStart.addingTimeInterval(30)
        wideEvent.startFlow(orphan)
        inputs.enabled = false
        startTunnel(.manual)

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertTrue(wideEvent.completions.isEmpty)
        XCTAssertEqual(wideEvent.discarded.count, 1)
        XCTAssertTrue(wideEvent.getAllFlowData(VPNSessionHealthWideEventData.self).isEmpty)
        let discarded = try XCTUnwrap(wideEvent.discarded.first as? VPNSessionHealthWideEventData)
        XCTAssertEqual(discarded.globalData.id, orphan.globalData.id)
        XCTAssertEqual(discarded.endReason, .processDied)
        XCTAssertEqual(discarded.endedAt, orphan.lastObservedAt)

        startTunnel(.manual)

        XCTAssertTrue(wideEvent.completions.isEmpty)
        XCTAssertEqual(wideEvent.discarded.count, 1)
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
                startTunnel(.manual)
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

    // MARK: - Start attempts

    func testWhenStoppedWhileStartingThenLateStartDoesNotOpenEvent() {
        let attemptID = instrumentation.tunnelStartRequested()
        instrumentation.tunnelStopped(reason: .userInitiated)
        instrumentation.tunnelStarted(reason: .manual, attemptID: attemptID)
        instrumentation.monitoringFailedToStart()

        XCTAssertTrue(wideEvent.started.isEmpty)
        XCTAssertTrue(wideEvent.updates.isEmpty)
        XCTAssertTrue(wideEvent.getAllFlowData(VPNSessionHealthWideEventData.self).isEmpty)
    }

    func testWhenCancelledWhileStartingThenLateStartDoesNotOpenEvent() {
        let attemptID = instrumentation.tunnelStartRequested()
        instrumentation.tunnelCancelledWithError()
        instrumentation.tunnelStarted(reason: .onDemand, attemptID: attemptID)

        XCTAssertTrue(wideEvent.started.isEmpty)
        XCTAssertTrue(wideEvent.getAllFlowData(VPNSessionHealthWideEventData.self).isEmpty)
    }

    func testWhenLateStartIsIgnoredThenNextStartDoesNotRecoverOrphan() throws {
        let staleAttemptID = instrumentation.tunnelStartRequested()
        instrumentation.tunnelStopped(reason: .userInitiated)
        instrumentation.tunnelStarted(reason: .manual, attemptID: staleAttemptID)

        startMonitoredSession()
        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(wideEvent.started.count, 1)
        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(try completedEvent().endReason, .stoppedByUser)
    }

    func testWhenNewerAttemptIsRequestedThenOlderAttemptIsIgnored() throws {
        let olderAttemptID = instrumentation.tunnelStartRequested()
        let newerAttemptID = instrumentation.tunnelStartRequested()

        instrumentation.tunnelStarted(reason: .manual, attemptID: olderAttemptID)
        XCTAssertTrue(wideEvent.started.isEmpty)

        instrumentation.tunnelStarted(reason: .manual, attemptID: newerAttemptID)
        XCTAssertEqual(wideEvent.started.count, 1)
    }

    func testWhenPhysicalStartHasNoAttemptThenItIsIgnored() {
        instrumentation.tunnelStarted(reason: .manual, attemptID: nil)
        instrumentation.tunnelStarted(reason: .onDemand, attemptID: nil)

        XCTAssertTrue(wideEvent.started.isEmpty)
    }

    func testWhenStoppedThenStartedAgainThenEachSessionCompletesOnItsOwn() throws {
        startMonitoredSession()
        instrumentation.tunnelStopped(reason: .userInitiated)
        startMonitoredSession()
        instrumentation.tunnelStopped(reason: .userInitiated)

        XCTAssertEqual(wideEvent.started.count, 2)
        XCTAssertEqual(wideEvent.completions.count, 2)
        XCTAssertEqual(try completedEvent(at: 0).endReason, .stoppedByUser)
        XCTAssertEqual(try completedEvent(at: 1).endReason, .stoppedByUser)
        XCTAssertNotEqual(try completedEvent(at: 0).globalData.id, try completedEvent(at: 1).globalData.id)
    }

    func testResumesDoNotRequireAnAttempt() throws {
        startMonitoredSession()
        let originalEventID = try latestEvent().globalData.id
        instrumentation.deviceWentToSleep()
        instrumentation.tunnelStarted(reason: .wake, attemptID: nil)

        XCTAssertEqual(try latestEvent().globalData.id, originalEventID)
        XCTAssertFalse(try latestEvent().isPaused)
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
        XCTAssertEqual(data.completedOutcome(), .failure(.routingOutage))
    }

    func testConcurrentStopsCompleteEventOnlyOnce() throws {
        startMonitoredSession()
        let instrumentation = try XCTUnwrap(instrumentation)

        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            instrumentation.tunnelStopped(reason: .userInitiated)
        }

        XCTAssertEqual(wideEvent.completions.count, 1)
        XCTAssertEqual(try completedEvent().completedOutcome(), .success)
    }

    // MARK: - Helpers

    private func makeInstrumentation() -> DefaultVPNSessionHealthInstrumentation {
        let inputs = inputs!
        return DefaultVPNSessionHealthInstrumentation(
            wideEvent: wideEvent,
            extensionType: .system,
            isTelemetryEnabled: { inputs.enabled },
            now: { inputs.date })
    }

    private func latestEvent(file: StaticString = #filePath, line: UInt = #line) throws -> VPNSessionHealthWideEventData {
        try XCTUnwrap((wideEvent.updates.last ?? wideEvent.started.last) as? VPNSessionHealthWideEventData,
                      "Expected a persisted session-health event", file: file, line: line)
    }

    private func completedEvent(at index: Int = 0, file: StaticString = #filePath, line: UInt = #line) throws -> VPNSessionHealthWideEventData {
        let completion = wideEvent.completions.indices.contains(index) ? wideEvent.completions[index] : nil

        return try XCTUnwrap(completion?.0 as? VPNSessionHealthWideEventData, "Expected a completed session-health event at index \(index)", file: file, line: line)
    }

    /// Mirrors the provider: physical starts request an attempt first, resumes ignore it.
    private func startTunnel(_ reason: PacketTunnelProvider.AdapterStartReason) {
        switch reason {
        case .manual, .onDemand:
            let attemptID = instrumentation.tunnelStartRequested()
            instrumentation.tunnelStarted(reason: reason, attemptID: attemptID)
        case .reconnected, .wake, .snoozeEnded:
            instrumentation.tunnelStarted(reason: reason, attemptID: nil)
        }
    }

    private func startMonitoredSession() {
        startTunnel(.manual)
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

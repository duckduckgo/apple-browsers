//
//  VPNSessionHealthWideEventDataTests.swift
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
import XCTest
import WideEvent
@testable import VPN

final class VPNSessionHealthWideEventDataTests: XCTestCase {

    // January 1, 2024, at midnight UTC.
    private let sessionStart = Date(timeIntervalSince1970: 1_704_067_200)
    private let appVersion = "1.0.0"

    // MARK: - Payloads and persistence

    func testFrameworkLaunchSweepLeavesSessionPendingForInstrumentation() async {
        let decision = await makeEvent()
            .completionDecision(for: .appLaunch)

        guard case .keepPending = decision else {
            XCTFail("Session instrumentation owns orphan completion")
            return
        }
    }

    func testHealthyPayloadUsesExpectedKeysAndOmitsFailureOnlyParameters() {
        let data = makeMonitoredEvent()
            .finalized(for: .stoppedByUser, at: timestamp(after: 60), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)
        let parameters = data.event.jsonParameters()

        XCTAssertEqual(parameters["feature.data.ext.start_reason"] as? String, "physical_tunnel_manual_start")
        XCTAssertEqual(parameters["feature.data.ext.end_reason"] as? String, "stopped_by_user")
        XCTAssertEqual(parameters["feature.data.ext.extension_type"] as? String, "app")
        XCTAssertEqual(parameters["feature.data.ext.monitoring_coverage"] as? String, "full")
        XCTAssertEqual(parameters["feature.data.ext.connection_tester_failure_seen"] as? Bool, false)
        XCTAssertEqual(parameters["feature.data.ext.connection_tester_extended_failure_seen"] as? Bool, false)
        XCTAssertEqual(parameters["feature.data.ext.connection_tester_failure_active_at_end"] as? Bool, false)
        XCTAssertEqual(parameters["feature.data.ext.stale_handshake_seen"] as? Bool, false)
        XCTAssertEqual(parameters["feature.data.ext.failure_recovery_attempted"] as? Bool, false)
        XCTAssertEqual(parameters["feature.data.ext.stopped_by_user_with_active_failure"] as? Bool, false)
        XCTAssertEqual(parameters["feature.data.ext.ip_leak_detected"] as? Bool, false)
        XCTAssertNil(parameters["feature.data.ext.failure_reason"])
        XCTAssertNil(parameters["feature.data.ext.time_to_first_error_seconds_bucketed"])
        XCTAssertNil(parameters["feature.data.ext.stale_handshake_recovered"])
        XCTAssertNil(parameters["feature.data.ext.failure_recovery_succeeded"])
        XCTAssertEqual(VPNSessionHealthWideEventData.metadata.pixelName, "vpn_session_health")
    }

    func testFailurePayloadIncludesReasonAndBucketedFirstErrorTime() {
        let data = makeMonitoredEvent()
            .applyingHandshakeCheckResult(.failureDetected, at: timestamp(after: 65))
            .finalized(for: .stoppedAdministratively, at: timestamp(after: 90), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.failure_reason"] as? String, "stale_handshake")
        XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.time_to_first_error_seconds_bucketed"] as? String, "60")
    }

    func testCodableRoundTripPreservesPendingOutageForRecovery() throws {
        let original = makeEventWithOutage(failedChecks: 8)
            .applyingHandshakeCheckResult(.failureDetected, at: timestamp(after: 130))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VPNSessionHealthWideEventData.self, from: encoded)
        let ended = decoded.finalized(for: .stoppedAdministratively, at: timestamp(after: 150), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(decoded.globalData.id, original.globalData.id)
        XCTAssertEqual(ended.event.totalOutageDuration, 135)
        XCTAssertEqual(ended.outcome, .failure(.staleHandshake))
    }

    // MARK: - Session outcomes

    func testUnknownReasonsDistinguishMissingMonitorsFromMissingResults() {
        let neverMonitored = makeEvent().finalized(for: .stoppedByUser, at: sessionStart, processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)
        let monitorsStarted = makeEvent().markingMonitoringStarted(at: sessionStart)
        let stoppedBeforeFirstResult = monitorsStarted.finalized(for: .stoppedByUser, at: sessionStart, processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)
        let stoppedWithoutNetwork = monitorsStarted.finalized(for: .stoppedWithoutNetwork, at: sessionStart, processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(neverMonitored.outcome, .unknown(.monitorsNeverStarted))
        XCTAssertEqual(stoppedBeforeFirstResult.outcome, .unknown(.connectionTesterNeverReported))
        XCTAssertEqual(stoppedWithoutNetwork.outcome, .unknown(.osStoppedWithoutNetwork))
    }

    func testImmediateTestBeforeMonitoringStartedStillEstablishesCoverage() {
        let data = makeEvent()
            .applyingConnectionTestResult(.connected, at: sessionStart)
            .markingMonitoringStarted(at: sessionStart)

        XCTAssertEqual(data.finalized(for: .stoppedByUser, at: sessionStart, processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion).outcome, .success)
    }

    func testCancellationAndFailureStopsFailWithoutMonitorResults() {
        let cancelled = makeEvent()
            .finalized(for: .cancelledWithError, at: timestamp(after: 20), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(cancelled.outcome, .failure(.cancelledWithError))
        XCTAssertEqual(cancelled.event.timeToFirstError, 20)
        XCTAssertEqual(makeEvent().finalized(for: .stoppedByFailure, at: sessionStart, processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion).outcome, .failure(.stoppedWithFailure))
    }

    func testUserStopDuringOutageTakesPrecedenceOverOtherHealthFailures() {
        let data = makeEventWithOutage(failedChecks: 8)
            .applyingHandshakeCheckResult(.failureDetected, at: timestamp(after: 125))
            .finalized(for: .stoppedByUser, at: timestamp(after: 130), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(data.outcome, .failure(.routingOutageAtUserStop))
        XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.failure_reason"] as? String, "routing_outage_at_user_stop")
        XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.stopped_by_user_with_active_failure"] as? Bool, true)
    }

    // MARK: - Routing outages

    func testExtendedThresholdUsesChecksInCurrentOutageRatherThanCumulativeTesterCount() {
        let belowThreshold = makeEventWithOutage(failedChecks: 7)
            .finalized(for: .stoppedAdministratively, at: timestamp(after: 150), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        let atThreshold = makeEventWithOutage(failedChecks: 8)
            .finalized(for: .stoppedAdministratively, at: timestamp(after: 150), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(belowThreshold.outcome, .success)
        XCTAssertEqual(atThreshold.outcome, .failure(.routingOutage))
    }

    func testRecoveryEndsOutageAndNextFailureStartsDistinctOutage() {
        var data = makeEventWithOutage()
        data = data.applyingConnectionTestResult(.reconnected(failureCount: 101), at: timestamp(after: 45))
        data = data.applyingConnectionTestResult(.disconnected(failureCount: 1), at: timestamp(after: 60))
        let completed = data.finalized(for: .stoppedAdministratively, at: timestamp(after: 90), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(completed.event.connectionTestOutageCount, 2)
        XCTAssertEqual(completed.event.totalOutageDuration, 60)
        XCTAssertEqual(completed.event.timeToFirstError, 15)
        XCTAssertEqual(completed.outcome, .success)
    }

    func testRecoveredExtendedOutageStillFailsSession() {
        let data = makeEventWithOutage(failedChecks: 8)
            .applyingConnectionTestResult(.reconnected(failureCount: 8), at: timestamp(after: 135))
            .finalized(for: .stoppedByUser, at: timestamp(after: 150), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(data.outcome, .failure(.routingOutage))
        XCTAssertFalse(data.event.connectionTestFailureActive)
        XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.stopped_by_user_with_active_failure"] as? Bool, false)
    }

    // MARK: - Monitoring and pauses

    func testSleepAndSnoozeEndOutageWithoutReportingUserStopFailure() {
        for reason in [VPNSessionHealthWideEventData.PauseReason.sleep, .snooze] {
            let data = makeEventWithOutage()
                .markingPaused(reason, at: timestamp(after: 30))
                .finalized(for: .stoppedByUser, at: timestamp(after: 300), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

            XCTAssertEqual(data.event.totalOutageDuration, 15)
            XCTAssertFalse(data.event.connectionTestFailureActive)
            XCTAssertEqual(data.outcome, .success)
            XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.monitoring_coverage"] as? String, "full")
        }
    }

    func testReconfigurationPreservesOutageButExcludesPauseAndUnobservedResumeTime() {
        let data = makeEventWithOutage()
            .markingPaused(.reconfiguration, at: timestamp(after: 30))
            .markingResumed(at: timestamp(after: 100))
            .markingMonitoringStarted(at: timestamp(after: 110))
            .applyingConnectionTestResult(.disconnected(failureCount: 102), at: timestamp(after: 120))
            .applyingConnectionTestResult(.reconnected(failureCount: 102), at: timestamp(after: 150))

        XCTAssertEqual(data.connectionTestOutageCount, 1)
        XCTAssertEqual(data.totalOutageDuration, 45)
        XCTAssertFalse(data.connectionTestFailureActive)
    }

    func testUnintentionalStopMarksPartialCoverageAndStopsAccrual() {
        let data = makeEventWithOutage()
            .markingMonitoringStopped(at: timestamp(after: 30), isIntentional: false)
            .finalized(for: .stoppedAdministratively, at: timestamp(after: 300), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(data.event.totalOutageDuration, 15)
        XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.monitoring_coverage"] as? String, "partial")
    }

    func testStopWhilePausedDoesNotMarkCoverageInterrupted() {
        let data = makeMonitoredEvent()
            .markingPaused(.sleep, at: sessionStart)
            .markingMonitoringStopped(at: sessionStart, isIntentional: false)

        XCTAssertFalse(data.monitoringInterrupted)
    }

    func testFailedMonitoringStartMarksInterruptionEvenWhenPaused() {
        let data = makeMonitoredEvent()
            .markingPaused(.sleep, at: sessionStart)
            .markingMonitoringFailedToStart(at: sessionStart)

        XCTAssertTrue(data.monitoringInterrupted)
        XCTAssertFalse(data.connectionMonitorsActive)
    }

    // MARK: - Handshake, recovery, and leak diagnostics

    func testHandshakeRecoveryRetainsFailureDiagnosticButStopClearsActiveState() {
        let failed = makeMonitoredEvent()
            .applyingHandshakeCheckResult(.failureDetected, at: timestamp(after: 60))

        let recovered = failed
            .applyingHandshakeCheckResult(.failureRecovered, at: timestamp(after: 90))
            .finalized(for: .stoppedAdministratively, at: timestamp(after: 120), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(recovered.outcome, .failure(.staleHandshake))
        XCTAssertEqual(recovered.event.jsonParameters()["feature.data.ext.stale_handshake_recovered"] as? Bool, true)

        let stopped = failed
            .markingMonitoringStopped(at: timestamp(after: 90), isIntentional: true)

        XCTAssertTrue(stopped.staleHandshakeDetected)
        XCTAssertFalse(stopped.staleHandshakeActive)
    }

    func testNetworkPathChangeDoesNotIntroduceHandshakeFailure() {
        let data = makeMonitoredEvent()
            .applyingHandshakeCheckResult(.networkPathChanged("test"), at: sessionStart)
            .finalized(for: .stoppedAdministratively, at: sessionStart, processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(data.outcome, .success)
        XCTAssertNil(data.event.timeToFirstError)
        XCTAssertNil(data.event.jsonParameters()["feature.data.ext.stale_handshake_recovered"])
    }

    func testRecoveryAttemptHasNoOutcomeUntilCompleted() {
        let data = makeMonitoredEvent()
            .applyingFailureRecoveryStep(.started, at: sessionStart)

        XCTAssertTrue(data.failureRecoveryAttempted)
        XCTAssertNil(data.jsonParameters()["feature.data.ext.failure_recovery_succeeded"])
        for health in [FailureRecoveryStep.ServerHealth.healthy, .unhealthy] {
            let completed = data.applyingFailureRecoveryStep(.completed(health), at: sessionStart)
                .finalized(for: .stoppedAdministratively, at: sessionStart, processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

            XCTAssertEqual(completed.event.jsonParameters()["feature.data.ext.failure_recovery_succeeded"] as? Bool, true)
            XCTAssertEqual(completed.outcome, .success)
        }
    }

    func testSuccessfulRetryPreservesEarlierRecoveryFailureInSession() {
        let data = makeMonitoredEvent()
            .applyingFailureRecoveryStep(.failed(NSError(domain: "test", code: 1)), at: sessionStart)
            .applyingFailureRecoveryStep(.completed(.unhealthy), at: timestamp(after: 30))
            .finalized(for: .stoppedAdministratively, at: timestamp(after: 60), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(data.outcome, .failure(.failureRecoveryFailed))
        XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.failure_recovery_succeeded"] as? Bool, true)
    }

    func testLeakIsStickyDiagnosticAndDoesNotFailSession() {
        let data = makeMonitoredEvent()
            .markingLeakDetected()
            .markingLeakDetected()
            .finalized(for: .stoppedAdministratively, at: sessionStart, processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.ip_leak_detected"] as? Bool, true)
        XCTAssertEqual(data.outcome, .success)
    }

    // MARK: - Orphan recovery

    func testOrphanEndsAtLastObservationWithoutInventingUnobservedDuration() {
        var data = makeEventWithOutage()
        data.lastObservedAt = timestamp(after: 30)
        let ended = data.finalizedAfterOrphanRecovery(at: timestamp(after: 900), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(ended.event.endedAt, data.lastObservedAt)
        XCTAssertEqual(ended.event.totalOutageDuration, 15)
        XCTAssertEqual(ended.outcome, .unknown(.extensionProcessDied))
    }

    func testOrphanRecoveryAfterClockMovesBackDoesNotEndInTheFuture() {
        var orphan = makeEventWithOutage()
        orphan.lastObservedAt = timestamp(after: 30)
        let recoveryDate = timestamp(after: 20)

        let ended = orphan.finalizedAfterOrphanRecovery(at: recoveryDate, processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(ended.event.endedAt, recoveryDate)
    }

    func testOrphanWithKnownFailurePreservesFailureOutcome() {
        let orphan = makeEventWithOutage(failedChecks: 8)
            .finalizedAfterOrphanRecovery(at: timestamp(after: 900), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(orphan.outcome, .failure(.routingOutage))
    }

    // MARK: - Process diagnostics

    func testDurationExceedsProcessLifetimeOnlyWhenProcessStartedAfterEvent() {
        let olderProcess = makeEvent()
            .finalized(for: .stoppedByUser, at: timestamp(after: 60), processStartDate: timestamp(after: -10), processIdentifier: 123, appVersion: appVersion)
        let newerProcess = makeEvent()
            .finalized(for: .stoppedByUser, at: timestamp(after: 60), processStartDate: timestamp(after: 30), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(olderProcess.event.jsonParameters()["feature.data.ext.event_duration_exceeds_process_lifetime"] as? Bool, false)
        XCTAssertEqual(newerProcess.event.jsonParameters()["feature.data.ext.event_duration_exceeds_process_lifetime"] as? Bool, true)
    }

    func testProcessIDChangedIsReportedOnlyWhenPIDDiffers() {
        let samePID = makeEvent(sessionStartPID: 123)
            .finalized(for: .stoppedByUser, at: timestamp(after: 60), processStartDate: timestamp(after: -10), processIdentifier: 123, appVersion: appVersion)
        let differentPID = makeEvent(sessionStartPID: 123)
            .finalized(for: .stoppedByUser, at: timestamp(after: 60), processStartDate: timestamp(after: -10), processIdentifier: 456, appVersion: appVersion)

        XCTAssertNil(samePID.event.jsonParameters()["feature.data.ext.process_id_changed"])
        XCTAssertEqual(differentPID.event.jsonParameters()["feature.data.ext.process_id_changed"] as? Bool, true)
    }

    func testAppVersionChangedIsReportedOnlyWhenVersionDiffers() {
        let sameVersion = makeEvent()
            .finalized(for: .stoppedByUser, at: timestamp(after: 60), processStartDate: timestamp(after: -10), processIdentifier: 123, appVersion: appVersion)
        let differentVersion = makeEvent()
            .finalizedAfterOrphanRecovery(at: timestamp(after: 900), processStartDate: timestamp(after: 850), processIdentifier: 123, appVersion: "1.1.0")

        XCTAssertNil(sameVersion.event.jsonParameters()["feature.data.ext.app_version_changed"])
        XCTAssertEqual(differentVersion.event.jsonParameters()["feature.data.ext.app_version_changed"] as? Bool, true)
    }

    func testOrphanDiagnosticsUseBackdatedDuration() {
        var orphan = makeEvent()
        orphan.lastObservedAt = timestamp(after: 30)

        // Duration ends at the last observation (30s); the lifetime runs until recovery (50s).
        let ended = orphan.finalizedAfterOrphanRecovery(at: timestamp(after: 900), processStartDate: timestamp(after: 850), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(ended.event.eventDurationExceedsProcessLifetime, false)
    }

    func testWhenEventAlreadyEndedThenFinalizingRecordsDiagnosticsWithoutChangingEnd() {
        var ended = makeMonitoredEvent(sessionStartPID: 123)
        ended.endedAt = timestamp(after: 60)
        ended.endReason = .stoppedByUser

        let recovered = ended.finalized(for: .processDied, at: timestamp(after: 900), processStartDate: timestamp(after: 850), processIdentifier: 456, appVersion: appVersion)

        XCTAssertEqual(recovered.event.endedAt, timestamp(after: 60))
        XCTAssertEqual(recovered.event.endReason, .stoppedByUser)
        XCTAssertEqual(recovered.event.eventDurationExceedsProcessLifetime, true)
        XCTAssertEqual(recovered.event.processIDChanged, true)
    }

    // MARK: - Duration and count buckets

    func testDurationBucketsAtBoundaries() {
        let cases: [(seconds: TimeInterval, expectedBucket: String)] = [
            (0.0, "0"),
            (59.9, "0"),
            (60, "60"),
            (299, "60"),
            (300, "300"),
            (1_800, "1800"),
            (7_200, "7200"),
            (28_800, "28800"),
            (86_400, "86400"),
        ]

        for (seconds, expected) in cases {
            let data = makeEvent()
                .finalized(for: .stoppedAdministratively, at: timestamp(after: seconds), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

            XCTAssertEqual(data.event.jsonParameters()["feature.data.ext.event_duration_seconds_bucketed"] as? String,
                           expected, "Input: \(seconds) seconds")
        }
    }

    func testOutageDurationBucketsAtBoundaries() {
        let cases: [(seconds: TimeInterval, expectedBucket: String)] = [
            (0.0, "0"),
            (0.9, "0"),
            (1, "1"),
            (14.9, "1"),
            (15, "15"),
            (60, "60"),
            (300, "300"),
            (1_800, "1800"),
        ]

        for (seconds, expected) in cases {
            var data = makeEvent()
            data.totalOutageDuration = seconds

            XCTAssertEqual(data.jsonParameters()["feature.data.ext.outage_duration_seconds_bucketed"] as? String,
                           expected, "Input: \(seconds) seconds")
        }

    }

    func testOutageCountBucketsAtBoundaries() {
        let countCases = [(0, "0"), (1, "1"), (2, "2"), (3, "2"), (4, "4"), (8, "4"), (9, "9"), (100, "9")]
        for (count, expected) in countCases {
            var data = makeEvent()
            data.connectionTestOutageCount = count

            XCTAssertEqual(data.jsonParameters()["feature.data.ext.connection_tester_outage_count_bucketed"] as? String,
                           expected, "Outage count: \(count)")
        }
    }

    func testClockGoingBackwardsDoesNotProduceNegativeDurations() {
        let data = makeEventWithOutage()
            .finalized(for: .stoppedAdministratively, at: timestamp(after: -60), processStartDate: sessionStart.addingTimeInterval(-100_000), processIdentifier: 123, appVersion: appVersion)

        XCTAssertEqual(data.event.totalOutageDuration, 0)
        XCTAssertEqual(data.event.eventDuration(asOf: sessionStart), 0)
    }

    // MARK: - Event builders

    private func makeEvent(sessionStartPID: Int32? = nil) -> VPNSessionHealthWideEventData {
        VPNSessionHealthWideEventData(startReason: .physicalTunnelStartManual,
                                      startedAt: sessionStart,
                                      extensionType: .app,
                                      sessionStartPID: sessionStartPID,
                                      appData: WideEventAppData(version: appVersion))
    }

    private func makeMonitoredEvent(sessionStartPID: Int32? = nil) -> VPNSessionHealthWideEventData {
        makeEvent(sessionStartPID: sessionStartPID)
            .markingMonitoringStarted(at: sessionStart)
            .applyingConnectionTestResult(.connected, at: sessionStart)
    }

    private func makeEventWithOutage(failedChecks: Int = 1) -> VPNSessionHealthWideEventData {
        var data = makeMonitoredEvent()
        // The tester count can span monitoring restarts; the event counts its own failed checks.
        for index in 1...failedChecks {
            data = data
                .applyingConnectionTestResult(.disconnected(failureCount: 100 + index), at: timestamp(after: Double(index) * 15))
        }

        return data
    }

    private func timestamp(after seconds: TimeInterval) -> Date {
        sessionStart.addingTimeInterval(seconds)
    }
}

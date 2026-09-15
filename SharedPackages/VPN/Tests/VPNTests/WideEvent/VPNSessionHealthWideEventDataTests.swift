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
            .markingStopped(.stoppedByUser, at: timestamp(after: 60))
        let parameters = data.jsonParameters()

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
            .markingStopped(.stoppedAdministratively, at: timestamp(after: 90))

        XCTAssertEqual(data.jsonParameters()["feature.data.ext.failure_reason"] as? String, "stale_handshake")
        XCTAssertEqual(data.jsonParameters()["feature.data.ext.time_to_first_error_seconds_bucketed"] as? String, "60")
    }

    func testCodableRoundTripPreservesPendingOutageForRecovery() throws {
        let original = makeEventWithOutage(failedChecks: 8)
            .applyingHandshakeCheckResult(.failureDetected, at: timestamp(after: 130))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VPNSessionHealthWideEventData.self, from: encoded)
        let ended = decoded.markingStopped(.stoppedAdministratively, at: timestamp(after: 150))

        XCTAssertEqual(decoded.globalData.id, original.globalData.id)
        XCTAssertEqual(ended.totalOutageDuration, 135)
        XCTAssertEqual(ended.outcome, .failure(.staleHandshake))
    }

    // MARK: - Session outcomes

    func testOutcomeIsUnavailableUntilEventEnds() {
        XCTAssertNil(makeEvent().outcome)
        XCTAssertNil(makeMonitoredEvent().outcome)
        XCTAssertNil(makeEventWithOutage(failedChecks: 8).outcome)
    }

    func testUnknownReasonsDistinguishMissingMonitorsFromMissingResults() {
        let neverMonitored = makeEvent().markingStopped(.stoppedByUser, at: sessionStart)
        let monitorsStarted = makeEvent().markingMonitoringStarted(at: sessionStart)
        let stoppedBeforeFirstResult = monitorsStarted.markingStopped(.stoppedByUser, at: sessionStart)
        let stoppedWithoutNetwork = monitorsStarted.markingStopped(.stoppedWithoutNetwork, at: sessionStart)

        XCTAssertEqual(neverMonitored.outcome, .unknown(.monitorsNeverStarted))
        XCTAssertEqual(stoppedBeforeFirstResult.outcome, .unknown(.connectionTesterNeverReported))
        XCTAssertEqual(stoppedWithoutNetwork.outcome, .unknown(.osStoppedWithoutNetwork))
    }

    func testImmediateTestBeforeMonitoringStartedStillEstablishesCoverage() {
        let data = makeEvent()
            .applyingConnectionTestResult(.connected, at: sessionStart)
            .markingMonitoringStarted(at: sessionStart)

        XCTAssertEqual(data.markingStopped(.stoppedByUser, at: sessionStart).outcome, .success)
    }

    func testCancellationAndFailureStopsFailWithoutMonitorResults() {
        let cancelled = makeEvent()
            .markingCancelledWithError(at: timestamp(after: 20))

        XCTAssertEqual(cancelled.outcome, .failure(.cancelledWithError))
        XCTAssertEqual(cancelled.timeToFirstError, 20)
        XCTAssertEqual(makeEvent().markingStopped(.stoppedByFailure, at: sessionStart).outcome, .failure(.stoppedWithFailure))
    }

    func testUserStopDuringOutageTakesPrecedenceOverOtherHealthFailures() {
        let data = makeEventWithOutage(failedChecks: 8)
            .applyingHandshakeCheckResult(.failureDetected, at: timestamp(after: 125))
            .markingStopped(.stoppedByUser, at: timestamp(after: 130))

        XCTAssertEqual(data.outcome, .failure(.routingOutageAtUserStop))
        XCTAssertEqual(data.jsonParameters()["feature.data.ext.failure_reason"] as? String, "routing_outage_at_user_stop")
        XCTAssertEqual(data.jsonParameters()["feature.data.ext.stopped_by_user_with_active_failure"] as? Bool, true)
    }

    // MARK: - Routing outages

    func testExtendedThresholdUsesChecksInCurrentOutageRatherThanCumulativeTesterCount() {
        let belowThreshold = makeEventWithOutage(failedChecks: 7)
            .markingStopped(.stoppedAdministratively, at: timestamp(after: 150))

        let atThreshold = makeEventWithOutage(failedChecks: 8)
            .markingStopped(.stoppedAdministratively, at: timestamp(after: 150))

        XCTAssertEqual(belowThreshold.outcome, .success)
        XCTAssertEqual(atThreshold.outcome, .failure(.routingOutage))
    }

    func testRecoveryEndsOutageAndNextFailureStartsDistinctOutage() {
        var data = makeEventWithOutage()
        data = data.applyingConnectionTestResult(.reconnected(failureCount: 101), at: timestamp(after: 45))
        data = data.applyingConnectionTestResult(.disconnected(failureCount: 1), at: timestamp(after: 60))
        data = data.markingStopped(.stoppedAdministratively, at: timestamp(after: 90))

        XCTAssertEqual(data.connectionTestOutageCount, 2)
        XCTAssertEqual(data.totalOutageDuration, 60)
        XCTAssertEqual(data.timeToFirstError, 15)
        XCTAssertEqual(data.outcome, .success)
    }

    func testRecoveredExtendedOutageStillFailsSession() {
        let data = makeEventWithOutage(failedChecks: 8)
            .applyingConnectionTestResult(.reconnected(failureCount: 8), at: timestamp(after: 135))
            .markingStopped(.stoppedByUser, at: timestamp(after: 150))

        XCTAssertEqual(data.outcome, .failure(.routingOutage))
        XCTAssertFalse(data.connectionTestFailureActive)
        XCTAssertEqual(data.jsonParameters()["feature.data.ext.stopped_by_user_with_active_failure"] as? Bool, false)
    }

    // MARK: - Monitoring and pauses

    func testSleepAndSnoozeEndOutageWithoutReportingUserStopFailure() {
        for reason in [VPNSessionHealthWideEventData.PauseReason.sleep, .snooze] {
            let data = makeEventWithOutage()
                .markingPaused(reason, at: timestamp(after: 30))
                .markingStopped(.stoppedByUser, at: timestamp(after: 300))

            XCTAssertEqual(data.totalOutageDuration, 15)
            XCTAssertFalse(data.connectionTestFailureActive)
            XCTAssertEqual(data.outcome, .success)
            XCTAssertEqual(data.jsonParameters()["feature.data.ext.monitoring_coverage"] as? String, "full")
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
            .markingStopped(.stoppedAdministratively, at: timestamp(after: 300))

        XCTAssertEqual(data.totalOutageDuration, 15)
        XCTAssertEqual(data.jsonParameters()["feature.data.ext.monitoring_coverage"] as? String, "partial")
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
            .markingStopped(.stoppedAdministratively, at: timestamp(after: 120))

        XCTAssertEqual(recovered.outcome, .failure(.staleHandshake))
        XCTAssertEqual(recovered.jsonParameters()["feature.data.ext.stale_handshake_recovered"] as? Bool, true)

        let stopped = failed
            .markingMonitoringStopped(at: timestamp(after: 90), isIntentional: true)

        XCTAssertTrue(stopped.staleHandshakeDetected)
        XCTAssertFalse(stopped.staleHandshakeActive)
    }

    func testNetworkPathChangeDoesNotIntroduceHandshakeFailure() {
        let data = makeMonitoredEvent()
            .applyingHandshakeCheckResult(.networkPathChanged("test"), at: sessionStart)
            .markingStopped(.stoppedAdministratively, at: sessionStart)

        XCTAssertEqual(data.outcome, .success)
        XCTAssertNil(data.timeToFirstError)
        XCTAssertNil(data.jsonParameters()["feature.data.ext.stale_handshake_recovered"])
    }

    func testRecoveryAttemptHasNoOutcomeUntilCompleted() {
        let data = makeMonitoredEvent()
            .applyingFailureRecoveryStep(.started, at: sessionStart)

        XCTAssertTrue(data.failureRecoveryAttempted)
        XCTAssertNil(data.jsonParameters()["feature.data.ext.failure_recovery_succeeded"])
        for health in [FailureRecoveryStep.ServerHealth.healthy, .unhealthy] {
            let completed = data.applyingFailureRecoveryStep(.completed(health), at: sessionStart)
                .markingStopped(.stoppedAdministratively, at: sessionStart)

            XCTAssertEqual(completed.jsonParameters()["feature.data.ext.failure_recovery_succeeded"] as? Bool, true)
            XCTAssertEqual(completed.outcome, .success)
        }
    }

    func testSuccessfulRetryPreservesEarlierRecoveryFailureInSession() {
        let data = makeMonitoredEvent()
            .applyingFailureRecoveryStep(.failed(NSError(domain: "test", code: 1)), at: sessionStart)
            .applyingFailureRecoveryStep(.completed(.unhealthy), at: timestamp(after: 30))
            .markingStopped(.stoppedAdministratively, at: timestamp(after: 60))

        XCTAssertEqual(data.outcome, .failure(.failureRecoveryFailed))
        XCTAssertEqual(data.jsonParameters()["feature.data.ext.failure_recovery_succeeded"] as? Bool, true)
    }

    func testLeakIsStickyDiagnosticAndDoesNotFailSession() {
        let data = makeMonitoredEvent()
            .markingLeakDetected()
            .markingLeakDetected()
            .markingStopped(.stoppedAdministratively, at: sessionStart)

        XCTAssertEqual(data.jsonParameters()["feature.data.ext.ip_leak_detected"] as? Bool, true)
        XCTAssertEqual(data.outcome, .success)
    }

    // MARK: - Orphan recovery

    func testOrphanEndsAtLastObservationWithoutInventingUnobservedDuration() {
        var data = makeEventWithOutage()
        data.lastObservedAt = timestamp(after: 30)
        let ended = data.markingOrphanedSessionEnded(at: timestamp(after: 900))

        XCTAssertEqual(ended.endedAt, data.lastObservedAt)
        XCTAssertEqual(ended.totalOutageDuration, 15)
        XCTAssertEqual(ended.outcome, .unknown(.extensionProcessDied))
    }

    func testOrphanRecoveryAfterClockMovesBackDoesNotEndInTheFuture() {
        var orphan = makeEventWithOutage()
        orphan.lastObservedAt = timestamp(after: 30)
        let recoveryDate = timestamp(after: 20)

        let ended = orphan.markingOrphanedSessionEnded(at: recoveryDate)

        XCTAssertEqual(ended.endedAt, recoveryDate)
    }

    func testOrphanWithKnownFailurePreservesFailureOutcome() {
        let orphan = makeEventWithOutage(failedChecks: 8)
            .markingOrphanedSessionEnded(at: timestamp(after: 900))

        XCTAssertEqual(orphan.outcome, .failure(.routingOutage))
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
                .markingStopped(.stoppedAdministratively, at: timestamp(after: seconds))

            XCTAssertEqual(data.jsonParameters()["feature.data.ext.event_duration_seconds_bucketed"] as? String,
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
            .markingStopped(.stoppedAdministratively, at: timestamp(after: -60))

        XCTAssertEqual(data.totalOutageDuration, 0)
        XCTAssertEqual(data.eventDuration(asOf: sessionStart), 0)
    }

    // MARK: - Event builders

    private func makeEvent() -> VPNSessionHealthWideEventData {
        VPNSessionHealthWideEventData(startReason: .physicalTunnelStartManual, startedAt: sessionStart, extensionType: .app)
    }

    private func makeMonitoredEvent() -> VPNSessionHealthWideEventData {
        makeEvent()
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

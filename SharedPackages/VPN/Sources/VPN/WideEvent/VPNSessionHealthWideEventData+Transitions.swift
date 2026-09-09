//
//  VPNSessionHealthWideEventData+Transitions.swift
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
import WideEvent

/// # Session Health Transitions: `event + timestamp -> new event`.
///
/// Transitions return updated event values. Callers must not apply one to an event that has ended;
/// `DefaultVPNSessionHealthInstrumentation.applyTransition(_:)` is the single place that enforces it.
extension VPNSessionHealthWideEventData {

    /// Number of Connection Tester failures before an outage is considered extended.
    static let extendedFailureThreshold = PacketTunnelProvider.connectionTesterExtendedFailuresCount

    // MARK: - Monitoring

    func markingMonitoringStarted(at now: Date) -> Self {
        applying { next in
            next.connectionMonitorsActive = true
            next.monitoringStarted = true
            next.recordHealthMonitoringActivity(at: now)
        }
    }

    func markingMonitoringFailedToStart(at now: Date) -> Self {
        applying { next in
            next.markMonitoringStopped(at: now)
            next.monitoringInterrupted = true
        }
    }

    func markingMonitoringStopped(at now: Date, isIntentional: Bool) -> Self {
        applying { next in
            next.markMonitoringStopped(at: now)

            if !next.isPaused && !isIntentional {
                next.monitoringInterrupted = true
            }
        }
    }

    // MARK: - Health

    /// Counts failed checks within each outage independently of the tester's cumulative count.
    func applyingConnectionTestResult(_ result: ConnectionTestingResult, at now: Date) -> Self {
        applying { next in
            switch result {
            case .connected:
                break

            case .disconnected:
                if next.activeOutageFailedCheckCount == 0 {
                    next.connectionTestOutageCount += 1
                    next.markFirstErrorDetectedIfNeeded(at: now)
                }

                next.activeOutageFailedCheckCount += 1

                if next.activeOutageFailedCheckCount >= Self.extendedFailureThreshold {
                    next.extendedRoutingOutageDetected = true
                }

            case .reconnected:
                next.markOutageAsEnded(at: now)
            }

            next.connectionTestDidReport = true
            next.recordHealthMonitoringActivity(at: now)
        }
    }

    func applyingHandshakeCheckResult(_ result: NetworkProtectionTunnelFailureMonitor.Result, at now: Date) -> Self {
        applying { next in
            switch result {
            case .failureDetected:
                next.staleHandshakeDetected = true
                next.staleHandshakeActive = true
                next.markFirstErrorDetectedIfNeeded(at: now)

            case .failureRecovered:
                next.staleHandshakeRecovered = true
                next.staleHandshakeActive = false

            case .networkPathChanged:
                // Diagnostic noise, not a health transition.
                break
            }
        }
    }

    func applyingFailureRecoveryStep(_ step: FailureRecoveryStep, at now: Date) -> Self {
        applying { next in
            next.failureRecoveryAttempted = true

            switch step {
            case .started:
                break

            case .completed:
                next.failureRecoverySucceeded = true

            case .failed:
                next.failureRecoverySucceeded = false
                next.failureRecoveryFailed = true
                next.markFirstErrorDetectedIfNeeded(at: now)
            }
        }
    }

    func markingLeakDetected() -> Self {
        return applying { next in
            next.leakDetected = true
        }
    }

    // MARK: - Availability

    func markingPaused(_ reason: PauseReason, at now: Date) -> Self {
        applying { next in
            next.markMonitoringStopped(at: now)

            // An intentional pause ends the outage; a reassert does not.
            if reason != .reconfiguration {
                next.activeOutageFailedCheckCount = 0
            }

            next.isPaused = true
        }
    }

    func markingResumed(at now: Date) -> Self {
        applying { next in
            next.isPaused = false
            next.recordHealthMonitoringActivity(at: now)
        }
    }

    // MARK: - Termination

    /// Records a first error if needed for failure stops or user stops during an active outage.
    func markingStopped(_ endReason: EventEndReason, at now: Date) -> Self {
        applying { next in
            if endReason.isFailure || (endReason == .stoppedByUser && connectionTestFailureActive) {
                next.markFirstErrorDetectedIfNeeded(at: now)
            }

            next.markEnded(endReason, at: now)
        }
    }

    func markingCancelledWithError(at now: Date) -> Self {
        markingStopped(.cancelledWithError, at: now)
    }

    func markingStoppedForRollover(at now: Date) -> Self {
        markingStopped(.rolledOver, at: now)
    }

    func makingNextEventAfterRollover(at now: Date, globalData: WideEventGlobalData) -> Self {
        var next = Self(startReason: .rollover, startedAt: now, extensionType: extensionType, globalData: globalData)

        next.connectionMonitorsActive = connectionMonitorsActive
        next.isPaused = isPaused
        next.connectionTestDidReport = connectionTestDidReport
        next.monitoringStarted = monitoringStarted
        next.monitoringInterrupted = monitoringInterrupted && !connectionMonitorsActive

        next.activeOutageFailedCheckCount = activeOutageFailedCheckCount
        next.connectionTestOutageCount = connectionTestFailureActive ? 1 : 0
        next.extendedRoutingOutageDetected = activeOutageFailedCheckCount >= Self.extendedFailureThreshold

        next.staleHandshakeActive = staleHandshakeActive
        next.staleHandshakeDetected = staleHandshakeActive

        // Ongoing errors are present from the start of the new event.
        if connectionTestFailureActive || staleHandshakeActive {
            next.timeToFirstError = 0
        }

        next.recordHealthMonitoringActivity(at: now)
        return next
    }

    func markingOrphanedSessionEnded(at now: Date) -> Self {
        // This API is part of the Orphans Collection mechanism.
        // We'll backdate the termination event with the last observation timestamp.
        markingStopped(.processDied, at: min(now, lastObservedAt))
    }
}

// MARK: - Private

private extension VPNSessionHealthWideEventData {

    func applying(_ body: (inout Self) -> Void) -> Self {
        var next = self
        body(&next)
        return next
    }

    mutating func markMonitoringStopped(at now: Date) {
        /// Reset Monitoring Flags
        connectionMonitorsActive = false
        connectionTestDidReport = false
        staleHandshakeActive = false
        stopTrackingOutageTimeAndRefreshStats(at: now)
    }

    mutating func markOutageAsEnded(at now: Date) {
        stopTrackingOutageTimeAndRefreshStats(at: now)
        activeOutageFailedCheckCount = 0
    }

    mutating func markFirstErrorDetectedIfNeeded(at now: Date) {
        guard timeToFirstError == nil else {
            return
        }

        timeToFirstError = max(0, now.timeIntervalSince(startedAt))
    }

    mutating func recordHealthMonitoringActivity(at now: Date) {
        guard canTrackOutageTime else {
            return
        }

        healthMonitoringEverActivated = true

        if connectionTestFailureActive, outageTrackingStartedAt == nil {
            outageTrackingStartedAt = now
        }
    }

    mutating func stopTrackingOutageTimeAndRefreshStats(at now: Date) {
        guard let began = outageTrackingStartedAt else {
            return
        }

        totalOutageDuration += max(0, now.timeIntervalSince(began))
        outageTrackingStartedAt = nil
    }

    mutating func markEnded(_ reason: EventEndReason, at now: Date) {
        stopTrackingOutageTimeAndRefreshStats(at: now)

        endedAt = now
        endReason = reason
    }
}

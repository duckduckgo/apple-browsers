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
import PixelKit

/// # Session Health Transitions: `event + timestamp -> new event`.
///
/// Every transition is pure. Callers must not apply one to a segment that has ended;
/// `DefaultVPNSessionHealthInstrumentation.advance(_:)` is the single place that enforces it.
extension VPNSessionHealthWideEventData {

    /// Consecutive tester failures before an outage counts as a routing outage.
    static let extendedFailureThreshold = PacketTunnelProvider.connectionTesterExtendedFailuresCount

    // MARK: - Monitoring

    func markingMonitoringStarted(at now: Date) -> Self {
        var next = self
        next.monitoringWasEverStarted = true
        next.isMonitoring = true
        next.markAsEligibleIfPossible(at: now)
        return next
    }

    func markingMonitoringFailedToStart(at now: Date) -> Self {
        var next = markingMonitoringStopped(at: now, isIntentional: false)
        next.monitoringWasInterrupted = true
        return next
    }

    func markingMonitoringStopped(at now: Date, isIntentional: Bool) -> Self {
        var next = self
        if !isPaused && !isIntentional {
            next.monitoringWasInterrupted = true
        }
        next.isMonitoring = false
        next.connectionTestDidReport = false
        next.closeEligibleInterval(at: now)
        next.accrueOutageDuration(at: now)
        return next
    }

    // MARK: - Health

    /// Turns the tester's cumulative failure count into outage transitions. The count is
    /// not reset across a stop/start, so reading it needs the baseline it opened at.
    func applyingConnectionTestResult(_ result: ConnectionTestingResult, at now: Date) -> Self {
        var next = self

        switch result {
        case .connected:
            break

        case .disconnected(let failureCount):
            var outage = next.activeOutage ?? RoutingOutage(startedAt: now, failureBaseline: failureCount - 1)
            if next.activeOutage == nil {
                next.connectionTestFailureSeen = true
                next.connectionTestOutageCount += 1
                next.noteFirstError(at: now)
            }

            if !outage.isExtended,
               failureCount - outage.failureBaseline >= Self.extendedFailureThreshold {
                outage.isExtended = true
                next.connectionTestExtendedFailureSeen = true
                next.noteFirstError(at: now)
            }
            next.activeOutage = outage

        case .reconnected:
            next.finishOutage(at: now)
        }

        next.connectionTestDidReport = true
        next.markAsEligibleIfPossible(at: now)
        return next
    }

    func applyingHandshakeCheckResult(_ result: NetworkProtectionTunnelFailureMonitor.Result, at now: Date) -> Self {
        var next = self

        switch result {
        case .failureDetected:
            next.staleHandshakeSeen = true
            next.staleHandshakeActive = true
            next.noteFirstError(at: now)

        case .failureRecovered:
            next.staleHandshakeRecovered = true
            next.staleHandshakeActive = false

        case .networkPathChanged:
            // Diagnostic noise, not a health transition.
            break
        }

        return next
    }

    func applyingFailureRecoveryStep(_ step: FailureRecoveryStep, at now: Date) -> Self {
        var next = self
        next.failureRecoveryAttempted = true

        switch step {
        case .started:
            break

        case .completed:
            next.failureRecoverySucceeded = true

        case .failed:
            next.failureRecoverySucceeded = false
            next.noteFirstError(at: now)
            next.failureRecoveryFailedSeen = true
        }

        return next
    }

    func applyingLeakCheck(leakDetected: Bool) -> Self {
        guard leakDetected else { return self }
        var next = self
        next.leakDetected = true
        return next
    }

    // MARK: - Availability

    func pausing(_ reason: PauseReason, at now: Date) -> Self {
        var next = self
        next.closeEligibleInterval(at: now)
        next.accrueOutageDuration(at: now)

        if reason != .reconfiguration {
            // An intentional pause ends the outage; a reassert does not.
            next.activeOutage = nil
        }

        next.isPaused = true
        next.isMonitoring = false
        next.connectionTestDidReport = false
        return next
    }

    func resuming(at now: Date) -> Self {
        var next = self
        next.isPaused = false

        next.markAsEligibleIfPossible(at: now)

        return next
    }

    // MARK: - Termination

    func stopping(_ endReason: SegmentEndReason, at now: Date) -> Self {
        var next = self

        if endReason == .stoppedByFailure || (endReason == .stoppedByUser && next.connectionTestFailureActive) {
            next.noteFirstError(at: now)
        }

        next.terminate(endReason, at: now)
        return next
    }

    func cancellingWithError(at now: Date) -> Self {
        var next = self
        next.noteFirstError(at: now)
        next.terminate(.cancelledWithError, at: now)
        return next
    }

    func stopForRollover(at now: Date) -> Self {
        var next = self
        next.terminate(.rolledOver, at: now)
        return next
    }

    func startAfterRollover(at now: Date, globalData: WideEventGlobalData) -> Self {
        var next = Self(startReason: .rolloverAfter24h,
                        startedAt: now,
                        extensionType: extensionType,
                        globalData: globalData)

        next.monitoringWasEverStarted = monitoringWasEverStarted
        next.isMonitoring = isMonitoring
        next.monitoringWasInterrupted = monitoringWasInterrupted && !isMonitoring
        next.connectionTestDidReport = connectionTestDidReport
        next.isPaused = isPaused
        next.markAsEligibleIfPossible(at: now)
        next.carryOverActiveOutage(from: self, at: now)

        // The monitor won't report an unresolved failure again.
        if staleHandshakeActive {
            next = next.applyingHandshakeCheckResult(.failureDetected, at: now)
        }

        return next
    }

    func markingProcessDied(at now: Date) -> Self {
        var next = self
        next.terminate(.processDied, at: min(now, lastObservedAt))
        return next
    }
}

// MARK: - Private

private extension VPNSessionHealthWideEventData {

    mutating func carryOverActiveOutage(from previous: Self, at now: Date) {
        guard var outage = previous.activeOutage else { return }

        outage.startedAt = eligibleSince == nil ? nil : now
        outage.accumulatedDuration = 0
        activeOutage = outage
        connectionTestFailureSeen = true
        connectionTestExtendedFailureSeen = outage.isExtended
        connectionTestOutageCount = 1
        noteFirstError(at: now)
    }

    mutating func finishOutage(at now: Date) {
        accrueOutageDuration(at: now)
        activeOutage = nil
    }

    /// Accrual requires running monitors and a result from the current monitoring period.
    mutating func markAsEligibleIfPossible(at now: Date) {
        guard eligibleSince == nil,
              !isPaused,
              !hasEnded,
              isMonitoring,
              connectionTestDidReport else { return }

        hasBeenEligible = true
        eligibleSince = now
        if activeOutage != nil, activeOutage?.startedAt == nil {
            activeOutage?.startedAt = now
        }
    }

    mutating func closeEligibleInterval(at now: Date) {
        guard let since = eligibleSince else { return }
        accumulatedEligible += max(0, now.timeIntervalSince(since))
        eligibleSince = nil
    }

    /// Accrues the open outage's duration without clearing the per-outage flags.
    mutating func accrueOutageDuration(at now: Date) {
        guard var outage = activeOutage, let began = outage.startedAt else { return }
        let duration = max(0, now.timeIntervalSince(began))
        outage.accumulatedDuration += duration
        connectionTestOutageTotal += duration
        connectionTestOutageMax = max(connectionTestOutageMax, outage.accumulatedDuration)
        outage.startedAt = nil
        activeOutage = outage
    }

    mutating func noteFirstError(at now: Date) {
        guard timeToFirstError == nil else { return }
        timeToFirstError = max(0, now.timeIntervalSince(startedAt))
    }

    mutating func terminate(_ reason: SegmentEndReason, at now: Date) {
        closeEligibleInterval(at: now)
        // Preserve the active outage for terminal diagnostics.
        accrueOutageDuration(at: now)
        endedAt = now
        endReason = reason
    }
}

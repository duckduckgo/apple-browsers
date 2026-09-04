//
//  VPNSessionHealthInstrumentation.swift
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
import PixelKit

/// # Session Health Telemetry
///
/// One segment is open at a time, from a WireGuard tunnel coming up until the provider stops, cancels, or 24 eligible hours roll it over.
/// It answers one question: did an already-running VPN stay healthy, including while nominally connected but not routing.
public protocol VPNSessionHealthInstrumentation: AnyObject, Sendable {

    /// Opens a new Segment for a physical start, resumes the segment already open rather than starting one for a reconnect, a wake, or the end of a snooze.
    func tunnelStarted(reason: PacketTunnelProvider.AdapterStartReason)

    /// Resumes the segment already open for a restart that carries no start reason: the monitors coming back up after a failed reasserting configuration update.
    func tunnelResumed()

    /// Invoked once monitoring is running and a first connection test has landed.
    func monitoringStarted()

    /// Stops accrual until monitoring resumes.
    func monitoringStopped(isIntentional: Bool)

    /// Marks coverage interrupted, reported alongside the outcome so a shrinking denominator is never mistaken for improving reliability.
    func monitoringFailedToStart()

    /// Outage transitions are derived from the running failure count, so results are forwarded undigested.
    func connectionTestCompleted(_ result: ConnectionTestingResult)

    func handshakeCheckCompleted(_ result: NetworkProtectionTunnelFailureMonitor.Result)

    /// `started` records an attempt; `completed` and `failed` record its outcome, keeping "not attempted" distinct from "attempted and failed".
    func failureRecoveryStepChanged(_ step: FailureRecoveryStep)

    /// Diagnostic only: an existing security SLO owns this property.
    func leakCheckCompleted(leakDetected: Bool)

    /// Pauses eligible-time accrual: the VPN is intentionally unavailable, so the period must not count against it.
    func deviceWentToSleep()

    /// Pauses eligible-time accrual.
    func snoozeStarted()

    /// Pauses eligible-time accrual, but unlike a sleep or a snooze it leaves an open routing outage open.
    func tunnelReconfigurationStarted()

    /// Terminates the segment, and is the point at which a user switching the VPN off mid-outage is recorded as a silent failure.
    func providerStopped(reason: NEProviderStopReason)

    /// Terminates the segment as a failure.
    func providerCancelledWithError()

    /// Completes a segment left behind by a process that disappeared. Called once on launch.
    func processOrphanEvents()
}

/// Session Health Telemetry Implementation
///
/// `WideEventManaging` persists the event on every `startFlow` and `updateFlow`, and a segment orphaned by a dying process is recovered from there on the next launch.
///
/// Calls are synchronous and lock-serialized, so transitions apply in the order the tunnel produced them, from whichever isolation domain produced them.
public final class DefaultVPNSessionHealthInstrumentation: VPNSessionHealthInstrumentation, @unchecked Sendable {

    private let wideEvent: WideEventManaging
    private let extensionType: VPNConnectionWideEventData.ExtensionType

    private let isEnabled: @Sendable () -> Bool
    private let sampleRate: @Sendable () -> Float
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    private var data: VPNSessionHealthWideEventData?

    public init(wideEvent: WideEventManaging,
                extensionType: VPNConnectionWideEventData.ExtensionType,
                isEnabled: @escaping @Sendable () -> Bool,
                sampleRate: @escaping @Sendable () -> Float,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.wideEvent = wideEvent
        self.extensionType = extensionType
        self.isEnabled = isEnabled
        self.sampleRate = sampleRate
        self.now = now
    }

    // MARK: - Segment lifecycle

    public func tunnelStarted(reason: PacketTunnelProvider.AdapterStartReason) {
        switch reason {
        case .manual:
            beginSegment(reason: .physicalTunnelStartManual)
        case .onDemand:
            beginSegment(reason: .physicalTunnelStartOnDemand)
        case .reconnected, .wake, .snoozeEnded:
            advance { $0.resuming(at: $1) }
        }
    }

    public func tunnelResumed() {
        advance { $0.resuming(at: $1) }
    }

    // MARK: - Monitoring

    public func monitoringStarted() {
        advance { $0.markingMonitoringStarted(at: $1) }
    }

    public func monitoringFailedToStart() {
        advance { $0.markingMonitoringFailedToStart(at: $1) }
    }

    public func monitoringStopped(isIntentional: Bool) {
        advance { $0.markingMonitoringStopped(at: $1, isIntentional: isIntentional) }
    }

    // MARK: - Health

    public func connectionTestCompleted(_ result: ConnectionTestingResult) {
        advance { $0.applyingConnectionTestResult(result, at: $1) }
    }

    public func handshakeCheckCompleted(_ result: NetworkProtectionTunnelFailureMonitor.Result) {
        advance { $0.applyingHandshakeCheckResult(result, at: $1) }
    }

    public func failureRecoveryStepChanged(_ step: FailureRecoveryStep) {
        advance { $0.applyingFailureRecoveryStep(step, at: $1) }
    }

    public func leakCheckCompleted(leakDetected: Bool) {
        advance { event, _ in event.applyingLeakCheck(leakDetected: leakDetected) }
    }

    // MARK: - Availability

    public func deviceWentToSleep() {
        advance { $0.pausing(.sleep, at: $1) }
    }

    public func snoozeStarted() {
        advance { $0.pausing(.snooze, at: $1) }
    }

    public func tunnelReconfigurationStarted() {
        advance { $0.pausing(.reconfiguration, at: $1) }
    }

    // MARK: - Termination

    public func providerStopped(reason: NEProviderStopReason) {
        let endReason = reason.asSegmentEndReason
        advance { $0.stopping(endReason, at: $1) }
    }

    public func providerCancelledWithError() {
        advance { $0.cancellingWithError(at: $1) }
    }

    public func processOrphanEvents() {
        guard isEnabled() else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        for orphan in wideEvent.getAllFlowData(VPNSessionHealthWideEventData.self) {
            complete(orphan.markingProcessDied(at: now()))
        }
    }

    // MARK: - Private

    /// Manages State Transitions, in a Threadsafe Fashion
    private func advance(_ transition: (VPNSessionHealthWideEventData, Date) -> VPNSessionHealthWideEventData) {
        guard isEnabled() else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        guard let current = data, !current.hasEnded else {
            return
        }

        let timestamp = now()
        var next = transition(current, timestamp)
        next.lastObservedAt = timestamp
        data = next

        if next.hasEnded {
            complete(next)
            data = nil
            return
        }

        if next.eligibleDuration(asOf: timestamp) >= VPNSessionHealthWideEventData.rolloverInterval {
            complete(next.stopForRollover(at: timestamp))
            beginSegment(next.startAfterRollover(at: timestamp, globalData: WideEventGlobalData(sampleRate: sampleRate())))
            return
        }

        wideEvent.updateFlow(next)
    }

    private func beginSegment(reason: VPNSessionHealthWideEventData.SegmentStartReason) {
        guard isEnabled() else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        beginSegment(VPNSessionHealthWideEventData(startReason: reason,
                                                   startedAt: now(),
                                                   extensionType: extensionType,
                                                   globalData: WideEventGlobalData(sampleRate: sampleRate())))
    }

    private func beginSegment(_ fresh: VPNSessionHealthWideEventData) {
        data = fresh
        wideEvent.startFlow(fresh)
    }

    private func complete(_ data: VPNSessionHealthWideEventData) {
        guard let status = data.segmentOutcome?.status else {
            return
        }

        wideEvent.completeFlow(data, status: status, onComplete: { _, _ in })
    }
}

private extension NEProviderStopReason {

    var asSegmentEndReason: VPNSessionHealthWideEventData.SegmentEndReason {
        switch self {
        case .userInitiated:
            return .stoppedByUser

        case .providerFailed,
                .connectionFailed,
                .configurationFailed,
                .unrecoverableNetworkChange,
                .internalError:
            return .stoppedByFailure

        case .noNetworkAvailable:
            return .stoppedWithoutNetwork

        case .none,
                .providerDisabled,
                .authenticationCanceled,
                .idleTimeout,
                .configurationDisabled,
                .configurationRemoved,
                .superceded,
                .userLogout,
                .userSwitch,
                .sleep,
                .appUpdate:
            return .stoppedAdministratively

        @unknown default:
            return .stoppedAdministratively
        }
    }
}

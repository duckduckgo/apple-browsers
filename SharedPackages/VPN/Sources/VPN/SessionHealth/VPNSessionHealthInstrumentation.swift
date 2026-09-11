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
import os.log
import PixelKit
import WideEvent

/// # Session Health Telemetry
///
/// One event is open at a time, from a WireGuard tunnel coming up until the provider stops or cancels.
/// It answers one question: did an already-running VPN stay healthy, including while nominally connected but not routing.
public protocol VPNSessionHealthInstrumentation: AnyObject, Sendable {

    /// Opens a new event for a physical start, resumes the event already open rather than starting one for a reconnect, a wake, or the end of a snooze.
    func tunnelStarted(reason: PacketTunnelProvider.AdapterStartReason)

    /// Resumes the event already open for a restart that carries no start reason: the monitors coming back up after a failed reasserting configuration update.
    func tunnelResumed()

    /// Invoked once monitoring is running: the first connection-test result may arrive later.
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
    func leakDetected()

    /// Pauses eligible-time accrual: the VPN is intentionally unavailable, so the period must not count against it.
    func deviceWentToSleep()

    /// Pauses eligible-time accrual.
    func snoozeStarted()

    /// Pauses eligible-time accrual, but unlike a sleep or a snooze it leaves an open routing outage open.
    func tunnelReconfigurationStarted()

    /// Terminates the event, and is the point at which a user switching the VPN off mid-outage is recorded as a silent failure.
    func tunnelStopped(reason: NEProviderStopReason)

    /// Terminates the event as a failure.
    func tunnelCancelledWithError()
}

/// Session Health Telemetry Implementation
///
/// `WideEventManaging` persists the event on every `startFlow` and `updateFlow`, and an event orphaned by a dying process is recovered from there on the next launch.
///
/// Calls are synchronous and lock-serialized, so transitions apply in the order the tunnel produced them, from whichever isolation domain produced them.
public final class DefaultVPNSessionHealthInstrumentation: VPNSessionHealthInstrumentation, @unchecked Sendable {

    private let wideEvent: WideEventManaging
    private let extensionType: VPNConnectionWideEventData.ExtensionType

    private let isTelemetryEnabled: @Sendable () -> Bool
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    private var currentEvent: VPNSessionHealthWideEventData?

    public init(wideEvent: WideEventManaging,
                extensionType: VPNConnectionWideEventData.ExtensionType,
                isTelemetryEnabled: @escaping @Sendable () -> Bool,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.wideEvent = wideEvent
        self.extensionType = extensionType
        self.isTelemetryEnabled = isTelemetryEnabled
        self.now = now
        Logger.networkProtectionSessionHealth.debug("Initialized session health instrumentation")
    }

    // MARK: - Lifecycle

    public func tunnelStarted(reason: PacketTunnelProvider.AdapterStartReason) {
        Logger.networkProtectionSessionHealth.debug("tunnelStarted: reason=\(String(describing: reason), privacy: .public)")
        switch reason {
        case .manual:
            beginEvent(reason: .physicalTunnelStartManual)
        case .onDemand:
            beginEvent(reason: .physicalTunnelStartOnDemand)
        case .reconnected, .wake, .snoozeEnded:
            tunnelResumed()
        }
    }

    public func tunnelResumed() {
        Logger.networkProtectionSessionHealth.debug("tunnelResumed")
        applyTransition { $0.markingResumed(at: $1) }
    }

    // MARK: - Monitoring

    public func monitoringStarted() {
        Logger.networkProtectionSessionHealth.debug("monitoringStarted")
        applyTransition { $0.markingMonitoringStarted(at: $1) }
    }

    public func monitoringFailedToStart() {
        Logger.networkProtectionSessionHealth.debug("monitoringFailedToStart")
        applyTransition { $0.markingMonitoringFailedToStart(at: $1) }
    }

    public func monitoringStopped(isIntentional: Bool) {
        Logger.networkProtectionSessionHealth.debug("monitoringStopped: isIntentional=\(isIntentional, privacy: .public)")
        applyTransition { $0.markingMonitoringStopped(at: $1, isIntentional: isIntentional) }
    }

    // MARK: - Health

    public func connectionTestCompleted(_ result: ConnectionTestingResult) {
        Logger.networkProtectionSessionHealth.debug("connectionTestCompleted: result=\(String(describing: result), privacy: .public)")
        applyTransition { $0.applyingConnectionTestResult(result, at: $1) }
    }

    public func handshakeCheckCompleted(_ result: NetworkProtectionTunnelFailureMonitor.Result) {
        Logger.networkProtectionSessionHealth.debug("handshakeCheckCompleted: result=\(String(describing: result), privacy: .public)")
        applyTransition { $0.applyingHandshakeCheckResult(result, at: $1) }
    }

    public func failureRecoveryStepChanged(_ step: FailureRecoveryStep) {
        Logger.networkProtectionSessionHealth.debug("failureRecoveryStepChanged: step=\(String(describing: step), privacy: .public)")
        applyTransition { $0.applyingFailureRecoveryStep(step, at: $1) }
    }

    public func leakDetected() {
        Logger.networkProtectionSessionHealth.debug("leakDetected")
        applyTransition { event, _ in event.markingLeakDetected() }
    }

    // MARK: - Availability

    public func deviceWentToSleep() {
        Logger.networkProtectionSessionHealth.debug("deviceWentToSleep")
        applyTransition { $0.markingPaused(.sleep, at: $1) }
    }

    public func snoozeStarted() {
        Logger.networkProtectionSessionHealth.debug("snoozeStarted")
        applyTransition { $0.markingPaused(.snooze, at: $1) }
    }

    public func tunnelReconfigurationStarted() {
        Logger.networkProtectionSessionHealth.debug("tunnelReconfigurationStarted")
        applyTransition { $0.markingPaused(.reconfiguration, at: $1) }
    }

    // MARK: - Termination

    public func tunnelStopped(reason: NEProviderStopReason) {
        Logger.networkProtectionSessionHealth.debug("tunnelStopped: reason=\(reason.rawValue, privacy: .public)")
        applyTransition { $0.markingStopped(reason.asEventEndReason, at: $1) }
    }

    public func tunnelCancelledWithError() {
        Logger.networkProtectionSessionHealth.debug("tunnelCancelledWithError")
        applyTransition { $0.markingCancelledWithError(at: $1) }
    }
}

// MARK: - Private

private extension DefaultVPNSessionHealthInstrumentation {

    func applyTransition(_ transition: (VPNSessionHealthWideEventData, Date) -> VPNSessionHealthWideEventData) {
        lock.lock()
        defer { lock.unlock() }

        guard let previous = currentEvent, !previous.hasEnded else {
            return
        }

        let timestamp = now()
        var next = transition(previous, timestamp)
        next.lastObservedAt = timestamp

        if completeEventIfEnded(next) {
            currentEvent = nil
            return
        }

        currentEvent = next
        wideEvent.updateFlow(next)
    }

    func beginEvent(reason: VPNSessionHealthWideEventData.EventStartReason) {
        lock.lock()
        defer { lock.unlock() }

        completeEventBeforeRestartInLock()

        completeOrphanedEvents()

        guard isTelemetryEnabled() else {
            return
        }

        let nextEvent = VPNSessionHealthWideEventData(startReason: reason, startedAt: now(), extensionType: extensionType, globalData: WideEventGlobalData())
        beginEventInLock(nextEvent)
    }
}

// MARK: - Private: Non-locking Methods

private extension DefaultVPNSessionHealthInstrumentation {

    func beginEventInLock(_ fresh: VPNSessionHealthWideEventData) {
        currentEvent = fresh
        wideEvent.startFlow(fresh)
    }

    /// A physical start with an event still open means its stop was never observed. Closing it here keeps it out of the orphan sweep, which would otherwise misreport it as a dead process on a later start.
    func completeEventBeforeRestartInLock() {
        guard let previous = currentEvent else {
            return
        }

        currentEvent = nil
        completeEventIfEnded(previous.markingStopped(.restartedWithoutStop, at: now()))
    }

    func completeOrphanedEvents() {
        let orphans = wideEvent.getAllFlowData(VPNSessionHealthWideEventData.self)
        Logger.networkProtectionSessionHealth.log("Orphaned events: \(orphans.count, privacy: .public)")

        for orphan in orphans {
            Logger.networkProtectionSessionHealth.log("Recovering orphan: \(orphan.globalData.id, privacy: .public)")
            completeEventIfEnded(orphan.markingOrphanedSessionEnded(at: now()))
        }
    }

    @discardableResult
    func completeEventIfEnded(_ data: VPNSessionHealthWideEventData) -> Bool {
        guard let status = data.outcome?.status else {
            return false
        }

        guard isTelemetryEnabled() else {
            wideEvent.discardFlow(data)
            return true
        }

        Logger.networkProtectionSessionHealth.log("Completing vpn_session_health pixel: status=\(status.description, privacy: .public)")
        logPixelDetails(data)

        wideEvent.completeFlow(data, status: status) { success, error in
            if success {
                Logger.networkProtectionSessionHealth.log("vpn_session_health pixel completion succeeded")
            } else {
                Logger.networkProtectionSessionHealth.error("vpn_session_health pixel was not sent: \(String(describing: error), privacy: .public)")
            }
        }

        return true
    }

    func logPixelDetails(_ data: VPNSessionHealthWideEventData) {
        let details = PixelDetailsFormatter.prettyPrinted(data.jsonParameters())

        Logger.networkProtectionSessionHealth.log("vpn_session_health pixel details:\n\(details, privacy: .public)")
    }
}

/// Renders wide event parameters for debug logging.
private enum PixelDetailsFormatter {

    /// `isValidJSONObject` first: `data(withJSONObject:)` raises an ObjC exception Swift cannot catch.
    static func prettyPrinted(_ parameters: [String: Encodable]) -> String {
        guard JSONSerialization.isValidJSONObject(parameters),
              let jsonData = try? JSONSerialization.data(withJSONObject: parameters, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: jsonData, encoding: .utf8) else {
            return String(describing: parameters.sorted { $0.key < $1.key })
        }

        return json
    }
}

private extension NEProviderStopReason {

    var asEventEndReason: VPNSessionHealthWideEventData.EventEndReason {
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

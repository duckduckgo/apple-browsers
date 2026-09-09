//
//  VPNSessionHealthWideEventData.swift
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
import FoundationExtensions
import WideEvent

/// # Session Health Wide Pixel
public struct VPNSessionHealthWideEventData: WideEventData {

    private typealias Key = WideEventParameter.VPNSessionHealthFeature

    public static let metadata = WideEventMetadata(
        pixelName: "vpn_session_health",
        featureName: "vpn-session-health",
        mobileMetaType: "ios-vpn-session-health",
        desktopMetaType: "macos-vpn-session-health",
        version: "1.0.0")

    // MARK: - Wide event

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    /// Failures use a finite reason instead of an error payload.
    public var errorData: WideEventErrorData?

    // MARK: - Lifecycle

    public var extensionType: VPNConnectionWideEventData.ExtensionType
    public var startReason: EventStartReason
    public var startedAt: Date
    public var lastObservedAt: Date

    public var endedAt: Date?
    public var endReason: EventEndReason?

    // MARK: - Health observation

    public var isPaused = false

    public var healthMonitoringEverActivated = false

    /// Whether the tester reported during the current monitoring period; reset when monitoring stops.
    public var connectionTestDidReport = false

    public var connectionMonitorsActive = false
    public var monitoringStarted = false
    public var monitoringInterrupted = false

    // MARK: - Connection test diagnostics

    public var extendedRoutingOutageDetected = false

    /// Zero means there is no active outage.
    public var activeOutageFailedCheckCount = 0
    public var outageTrackingStartedAt: Date?

    public var connectionTestOutageCount = 0
    public var totalOutageDuration: TimeInterval = 0

    // MARK: - Other diagnostics

    /// From `NetworkProtectionTunnelFailureMonitor`; routing outages come from the tester.
    public var staleHandshakeDetected = false
    public var staleHandshakeRecovered = false
    public var staleHandshakeActive = false
    public var failureRecoveryAttempted = false
    public var failureRecoverySucceeded: Bool?
    public var failureRecoveryFailed = false
    public var leakDetected = false
    public var timeToFirstError: TimeInterval?

    // MARK: - Init

    public init(startReason: EventStartReason,
                startedAt: Date,
                extensionType: VPNConnectionWideEventData.ExtensionType,
                contextData: WideEventContextData = WideEventContextData(),
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.startReason = startReason
        self.startedAt = startedAt
        self.lastObservedAt = startedAt
        self.extensionType = extensionType
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    // MARK: - WideEventData

    /// Session-health instrumentation owns orphan recovery, so the framework's launch sweep must not race it into a second completion.
    public func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        .keepPending
    }

    public func jsonParameters() -> [String: Encodable] {
        let end = endedAt ?? startedAt

        var params: [String: Encodable] = Dictionary(compacting: [
            (Key.segmentEndReason, endReason?.rawValue),
            (Key.failureReason, hasEnded ? failureReason?.rawValue : nil),
            (Key.timeToFirstError, timeToFirstError.map(Self.durationBucket)),
            (Key.staleHandshakeRecovered, staleHandshakeDetected ? staleHandshakeRecovered : nil),
            (Key.failureRecoverySucceeded, failureRecoverySucceeded),
        ])

        params[Key.segmentStartReason] = startReason.rawValue
        params[Key.extensionType] = extensionType.rawValue
        params[Key.monitoringCoverage] = monitoringCoverage.rawValue
        params[Key.eventDuration] = Self.durationBucket(eventDuration(asOf: end))
        params[Key.connectionTestOutageCount] = Self.outageCountBucket(connectionTestOutageCount)
        params[Key.outageDuration] = Self.outageDurationBucket(totalOutageDuration)
        params[Key.connectionTestFailureSeen] = connectionTestFailureSeen
        params[Key.extendedRoutingOutageDetected] = extendedRoutingOutageDetected
        params[Key.connectionTestFailureActiveAtEnd] = connectionTestFailureActive
        params[Key.staleHandshakeDetected] = staleHandshakeDetected
        params[Key.failureRecoveryAttempted] = failureRecoveryAttempted
        params[Key.stoppedByUserWithActiveFailure] = stoppedByUserWithActiveFailure
        params[Key.ipLeakDetected] = leakDetected

        return params
    }
}

// MARK: - Derived

extension VPNSessionHealthWideEventData {

    public var hasEnded: Bool { endedAt != nil }

    public var canTrackOutageTime: Bool {
        !isPaused && !hasEnded && connectionMonitorsActive && connectionTestDidReport
    }

    public var connectionTestFailureSeen: Bool { connectionTestOutageCount > 0 }

    public var connectionTestFailureActive: Bool { activeOutageFailedCheckCount > 0 }

    public var outcome: EventOutcome? {
        guard hasEnded else {
            return nil
        }

        if let failureReason {
            return .failure(failureReason)
        }

        if endReason == .processDied {
            // A later physical start recovered this persisted orphan.
            return .unknown(.extensionProcessDied)
        }

        if healthMonitoringEverActivated {
            return .success
        }

        return .unknown(unknownReason)
    }

    public func eventDuration(asOf now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

// MARK: - Private: Error State

private extension VPNSessionHealthWideEventData {

    var failureReason: FailureReason? {
        if endReason == .cancelledWithError {
            // The provider called cancelTunnel(with:).
            return .cancelledWithError
        }

        if stoppedByUserWithActiveFailure {
            // A user-initiated stop arrived during an active tester outage.
            return .routingOutageAtUserDisable
        }

        if failureRecoveryFailed {
            // A recovery attempt failed, even if a later retry succeeded.
            return .failureRecoveryFailed
        }

        if staleHandshakeDetected {
            // The handshake monitor reported a stale handshake, even if later recovered.
            return .staleHandshake
        }

        if extendedRoutingOutageDetected {
            // One tester outage reached the extended failure threshold, even if later recovered.
            return .routingOutage
        }

        if endReason == .stoppedByFailure {
            // The OS supplied a failure-class provider stop reason.
            return .stoppedWithFailure
        }

        return nil
    }

    var unknownReason: UnknownReason {
        if !monitoringStarted {
            // No successful monitoring start was recorded or inherited from rollover.
            return .monitorsNeverStarted
        }

        if endReason == .stoppedWithoutNetwork {
            // The OS reported noNetworkAvailable before health monitoring ever activated.
            return .osStoppedWithoutNetwork
        }

        // Monitors started, but no tester report established active, unpaused coverage in this segment.
        return .connectionTesterNeverReported
    }

    var stoppedByUserWithActiveFailure: Bool {
        endReason == .stoppedByUser && connectionTestFailureActive
    }

    var monitoringCoverage: MonitoringCoverage {
        guard monitoringStarted else {
            return .neverMonitored
        }

        return monitoringInterrupted ? .partiallyMonitored : .fullyMonitored
    }
}

// MARK: - Private: Buckets

private extension VPNSessionHealthWideEventData {

    static func durationBucket(_ seconds: TimeInterval) -> String {
        bucket(seconds, thresholds: [0, 60, 300, 1_800, 7_200, 28_800, 86_400])
    }

    /// The `0` bucket also covers anything under a second.
    static func outageDurationBucket(_ seconds: TimeInterval) -> String {
        bucket(seconds, thresholds: [0, 1, 15, 60, 300, 900, 1_800, 3_600])
    }

    static func outageCountBucket(_ count: Int) -> String {
        bucket(count, thresholds: [0, 1, 2, 4, 9])
    }

    /// The lower end of the matching bucket, which is what the schema's enums hold.
    private static func bucket(_ seconds: TimeInterval, thresholds: [Int]) -> String {
        bucket(Int(max(0, seconds)), thresholds: thresholds)
    }

    private static func bucket(_ value: Int, thresholds: [Int]) -> String {
        let clamped = max(0, value)
        return String(thresholds.last { $0 <= clamped } ?? thresholds[0])
    }
}

// MARK: - Payload Types

extension VPNSessionHealthWideEventData {

    public enum EventStartReason: String, Codable, CaseIterable {
        case physicalTunnelStartManual = "physical_tunnel_manual_start"
        case physicalTunnelStartOnDemand = "physical_tunnel_on_demand_start"
        case rolloverOnTheHour = "rollover_on_the_hour"
    }

    /// Why an event ended. Exactly one applies.
    public enum EventEndReason: String, Codable, CaseIterable {
        case stoppedByUser = "stopped_by_user"
        case stoppedByFailure = "stopped_by_failure"

        /// Housekeeping stop: update, logout, user switch, sleep.
        case stoppedAdministratively = "stopped_administratively"
        case stoppedWithoutNetwork = "stopped_without_network"
        case cancelledWithError = "cancelled_with_error"

        /// A physical start arrived while an event was still open, so its stop was never observed.
        case restartedWithoutStop = "restarted_without_stop"
        case rolledOver = "rolled_over"
        case processDied = "process_died"
    }

    public enum FailureReason: String, Codable, CaseIterable {
        case cancelledWithError = "cancelled_with_error"
        case failureRecoveryFailed = "failure_recovery_failed"
        case staleHandshake = "stale_handshake"
        case routingOutage = "routing_outage"
        case routingOutageAtUserDisable = "routing_outage_at_user_disable"
        case stoppedWithFailure = "stopped_with_failure"
    }

    public enum UnknownReason: String, Codable, CaseIterable {
        case monitorsNeverStarted = "monitors_never_started"
        case connectionTesterNeverReported = "connection_tester_never_reported"
        case extensionProcessDied = "extension_process_died"
        case osStoppedWithoutNetwork = "os_stopped_without_network"
    }

    public enum MonitoringCoverage: String, Codable, CaseIterable {
        case fullyMonitored = "full"
        case partiallyMonitored = "partial"
        case neverMonitored = "none"
    }

    /// Not emitted: it only decides whether an open routing outage survives the pause.
    public enum PauseReason: String, Codable, CaseIterable {
        case sleep
        case snooze
        case reconfiguration
    }

    public enum EventOutcome: Equatable {
        case success
        case failure(FailureReason)
        case unknown(UnknownReason)

        var status: WideEventStatus {
            switch self {
            case .success: return .success
            case .failure: return .failure
            case .unknown(let reason):
                return .unknown(reason: reason.rawValue)
            }
        }
    }
}

extension VPNSessionHealthWideEventData.EventEndReason {

    /// End reasons that are failures on their own, regardless of the segment's diagnostics.
    var isFailure: Bool {
        self == .stoppedByFailure || self == .cancelledWithError
    }
}

// MARK: - Wide Event Parameters

extension WideEventParameter {

    public enum VPNSessionHealthFeature {
        static let segmentStartReason = "feature.data.ext.segment_start_reason"
        static let extensionType = "feature.data.ext.extension_type"
        static let segmentEndReason = "feature.data.ext.segment_end_reason"
        static let failureReason = "feature.data.ext.failure_reason"
        static let monitoringCoverage = "feature.data.ext.monitoring_coverage"
        static let eventDuration = "feature.data.ext.event_duration_seconds_bucketed"
        static let connectionTestFailureSeen = "feature.data.ext.connection_tester_failure_seen"
        static let extendedRoutingOutageDetected = "feature.data.ext.connection_tester_extended_failure_seen"
        static let connectionTestFailureActiveAtEnd = "feature.data.ext.connection_tester_failure_active_at_end"
        static let connectionTestOutageCount = "feature.data.ext.connection_tester_outage_count_bucketed"
        static let outageDuration = "feature.data.ext.outage_duration_seconds_bucketed"
        static let staleHandshakeDetected = "feature.data.ext.stale_handshake_seen"
        static let staleHandshakeRecovered = "feature.data.ext.stale_handshake_recovered"
        static let failureRecoveryAttempted = "feature.data.ext.failure_recovery_attempted"
        static let failureRecoverySucceeded = "feature.data.ext.failure_recovery_succeeded"
        static let stoppedByUserWithActiveFailure = "feature.data.ext.stopped_by_user_with_active_failure"
        static let timeToFirstError = "feature.data.ext.time_to_first_error_seconds_bucketed"
        static let ipLeakDetected = "feature.data.ext.ip_leak_detected"
    }
}

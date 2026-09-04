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
import PixelKit

/// # Session Health Wide Pixel
public struct VPNSessionHealthWideEventData: WideEventData {

    private typealias Key = WideEventParameter.VPNSessionHealthFeature

    public static let metadata = WideEventMetadata(
        pixelName: "vpn_session_health",
        featureName: "vpn-session-health",
        mobileMetaType: "ios-vpn-session-health",
        desktopMetaType: "macos-vpn-session-health",
        version: "1.0.0")

    /// A segment closes and reopens at this much eligible time
    public static let rolloverInterval: TimeInterval = .hours(24)

    // MARK: - Wide event

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    /// Failures use a finite reason instead of an error payload.
    public var errorData: WideEventErrorData?

    // MARK: - Lifecycle

    public var extensionType: VPNConnectionWideEventData.ExtensionType
    public var startReason: SegmentStartReason
    public var startedAt: Date
    public var lastObservedAt: Date

    public var endedAt: Date?
    public var endReason: SegmentEndReason?

    public var hasEnded: Bool { endedAt != nil }

    // MARK: - Eligibility accounting

    public var isPaused = false

    /// Set once and never cleared
    public var hasBeenEligible = false

    /// When the currently open eligible interval began. Non-`nil` means countable time is accruing right now.
    public var eligibleSince: Date?
    public var accumulatedEligible: TimeInterval = 0
    public var connectionTestDidReport = false

    /// Whether monitoring ever started during this segment.
    public var monitoringWasEverStarted = false
    public var isMonitoring = false

    /// Preserves coverage gaps across successful restarts.
    public var monitoringWasInterrupted = false

    // MARK: - Connection test diagnostics

    public var connectionTestFailureSeen = false
    public var connectionTestExtendedFailureSeen = false
    public var activeOutage: RoutingOutage?

    public var connectionTestFailureActive: Bool { activeOutage != nil }
    public var connectionTestOutageCount = 0
    public var connectionTestOutageTotal: TimeInterval = 0
    public var connectionTestOutageMax: TimeInterval = 0

    // MARK: - Other diagnostics

    /// From `NetworkProtectionTunnelFailureMonitor`; routing outages come from the tester.
    public var staleHandshakeSeen = false
    public var staleHandshakeRecovered = false
    public var staleHandshakeActive = false
    public var failureRecoveryAttempted = false
    public var failureRecoverySucceeded: Bool?
    public var failureRecoveryFailedSeen = false
    public var leakDetected = false
    public var timeToFirstError: TimeInterval?

    // MARK: - Init

    public init(startReason: SegmentStartReason,
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

    // MARK: - Derived

    /// How much of the segment the required monitors actually observed.
    public var monitoringCoverage: MonitoringCoverage {
        guard monitoringWasEverStarted else { return .neverMonitored }
        return monitoringWasInterrupted ? .partiallyMonitored : .fullyMonitored
    }

    public var segmentOutcome: SegmentOutcome? {
        guard hasEnded else { return nil }

        if let failureReason {
            return .failure(failureReason)
        }
        if endReason == .processDied {
            return .unknown(.extensionProcessDied)
        }
        if hasBeenEligible {
            return .success
        }
        return .unknown(unknownReason)
    }

    /// Total eligible time, including an interval that is still open.
    public func eligibleDuration(asOf now: Date) -> TimeInterval {
        guard let eligibleSince else { return accumulatedEligible }
        return accumulatedEligible + max(0, now.timeIntervalSince(eligibleSince))
    }

    /// Wall-clock length of the segment. Unlike `eligibleDuration`, this includes paused periods.
    public func segmentDuration(asOf now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    // MARK: - WideEventData

    /// `processOrphanEvents()` owns orphan recovery, so the framework's launch sweep must
    /// not race it into a second completion.
    public func completionDecision(
        for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        .keepPending
    }

    public func jsonParameters() -> [String: Encodable] {
        let end = endedAt ?? startedAt

        var params: [String: Encodable] = Dictionary(compacting: [
            (Key.segmentEndReason, endReason?.rawValue),
            (Key.failureReason, hasEnded ? failureReason?.rawValue : nil),
            (Key.timeToFirstError, timeToFirstError.map(Self.durationBucket)),
            // Emitted only when the antecedent happened, keeping "not attempted" and
            // "attempted and failed" distinct.
            (Key.staleHandshakeRecovered, staleHandshakeSeen ? staleHandshakeRecovered : nil),
            (Key.failureRecoverySucceeded, failureRecoverySucceeded),
        ])

        params[Key.segmentStartReason] = startReason.rawValue
        params[Key.extensionType] = extensionType.rawValue
        params[Key.monitoringCoverage] = monitoringCoverage.rawValue
        params[Key.segmentDuration] = Self.durationBucket(segmentDuration(asOf: end))
        params[Key.eligibleDuration] = Self.durationBucket(eligibleDuration(asOf: end))
        params[Key.connectionTestOutageCount] = Self.outageCountBucket(connectionTestOutageCount)
        params[Key.connectionTestOutageTotal] = Self.outageDurationBucket(connectionTestOutageTotal)
        params[Key.connectionTestOutageMax] = Self.outageDurationBucket(connectionTestOutageMax)
        params[Key.connectionTestFailureSeen] = connectionTestFailureSeen
        params[Key.connectionTestExtendedFailureSeen] = connectionTestExtendedFailureSeen
        params[Key.connectionTestFailureActiveAtEnd] = connectionTestFailureActive
        params[Key.staleHandshakeSeen] = staleHandshakeSeen
        params[Key.failureRecoveryAttempted] = failureRecoveryAttempted
        params[Key.humanStopWithActiveFailure] = humanStopWithActiveFailure
        params[Key.ipLeakDetected] = leakDetected

        return params
    }
}

// MARK: - Private

private extension VPNSessionHealthWideEventData {

    static func durationBucket(_ seconds: TimeInterval) -> String {
        bucket(seconds, thresholds: [0, 60, 300, 1_800, 7_200, 28_800, 86_400])
    }

    /// The `0` bucket also covers anything under a second.
    static func outageDurationBucket(_ seconds: TimeInterval) -> String {
        bucket(seconds, thresholds: [0, 1, 15, 60, 300, 1_800])
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

    var humanStopWithActiveFailure: Bool {
        endReason == .stoppedByUser && connectionTestFailureActive
    }

    var unknownReason: UnknownReason {
        if !monitoringWasEverStarted { return .monitorsNeverStarted }
        if endReason == .stoppedWithoutNetwork { return .osStoppedWithoutNetwork }
        return .connectionTesterNeverReported
    }

    // Order defines failure precedence.
    var failureReason: FailureReason? {
        if endReason == .cancelledWithError { return .cancelledWithError }
        if failureRecoveryFailedSeen { return .failureRecoveryFailed }
        if staleHandshakeSeen { return .staleHandshake }
        if connectionTestExtendedFailureSeen { return .routingOutage }
        if humanStopWithActiveFailure { return .routingOutageAtUserDisable }
        if endReason == .stoppedByFailure { return .stoppedWithFailure }
        return nil
    }

}

// MARK: - Payload Types

extension VPNSessionHealthWideEventData {

    public enum SegmentStartReason: String, Codable, CaseIterable {
        case physicalTunnelStartManual = "physical_tunnel_manual_start"
        case physicalTunnelStartOnDemand = "physical_tunnel_on_demand_start"
        case rolloverAfter24h = "rollover_after_24h"
    }

    /// Why a segment ended. Exactly one applies.
    public enum SegmentEndReason: String, Codable, CaseIterable {
        case stoppedByUser = "stopped_by_user"
        case stoppedByFailure = "stopped_by_failure"

        /// Housekeeping stop: update, logout, user switch, sleep.
        case stoppedAdministratively = "stopped_administratively"
        case stoppedWithoutNetwork = "stopped_without_network"
        case cancelledWithError = "cancelled_with_error"
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

    public struct RoutingOutage: Codable {
        public var startedAt: Date?
        public var failureBaseline: Int
        public var isExtended = false
        public var accumulatedDuration: TimeInterval = 0
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

    public enum SegmentOutcome: Equatable {
        case success
        case failure(FailureReason)
        case unknown(UnknownReason)

        var status: WideEventStatus {
            switch self {
            case .success: return .success
            case .failure: return .failure
            case .unknown(let reason): return .unknown(reason: reason.rawValue)
            }
        }
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
        static let segmentDuration = "feature.data.ext.segment_duration_seconds_bucketed"
        static let eligibleDuration = "feature.data.ext.eligible_duration_seconds_bucketed"
        static let connectionTestFailureSeen = "feature.data.ext.connection_tester_failure_seen"
        static let connectionTestExtendedFailureSeen = "feature.data.ext.connection_tester_extended_failure_seen"
        static let connectionTestFailureActiveAtEnd = "feature.data.ext.connection_tester_failure_active_at_end"
        static let connectionTestOutageCount = "feature.data.ext.connection_tester_outage_count_bucketed"
        static let connectionTestOutageTotal = "feature.data.ext.connection_tester_outage_total_seconds_bucketed"
        static let connectionTestOutageMax = "feature.data.ext.connection_tester_outage_max_seconds_bucketed"
        static let staleHandshakeSeen = "feature.data.ext.stale_handshake_seen"
        static let staleHandshakeRecovered = "feature.data.ext.stale_handshake_recovered"
        static let failureRecoveryAttempted = "feature.data.ext.failure_recovery_attempted"
        static let failureRecoverySucceeded = "feature.data.ext.failure_recovery_succeeded"
        static let humanStopWithActiveFailure = "feature.data.ext.human_stop_with_active_failure"
        static let timeToFirstError = "feature.data.ext.time_to_first_error_seconds_bucketed"
        static let ipLeakDetected = "feature.data.ext.ip_leak_detected"
    }
}

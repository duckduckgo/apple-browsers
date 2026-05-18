//
//  VPNLeakCheckService.swift
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

import Common
import Foundation
import Network
import os.log
import PixelKit

private enum LeakCheckIPError: Error, CustomNSError {
    case malformedObservedIP
    case malformedEgressIP

    static var errorDomain: String { "VPNLeakCheckIPError" }

    var errorCode: Int {
        switch self {
        case .malformedObservedIP: return 1
        case .malformedEgressIP: return 2
        }
    }
}

private enum LeakCheckStatusReason {
    static let checkInterrupted = "check_interrupted"
}

public actor VPNLeakCheckService {

    public typealias TunnelInterfaceProvider = @Sendable () async -> NWInterface?
    public typealias EgressInfoProvider = @Sendable () async -> LeakCheckEgressInfo?
    public typealias TunnelPathGenerationProvider = @Sendable () async -> UInt64

    private let configuration: LeakCheckConfiguration
    private let egressInfo: EgressInfoProvider
    private let tunnelInterface: TunnelInterfaceProvider
    private let tunnelPathGeneration: TunnelPathGenerationProvider
    private let httpClient: LeakCheckHTTPClient
    private let stunClient: LeakCheckSTUNClient
    private let wideEvent: WideEventManaging

    private var currentCheck: Task<Void, Never>?
    private var currentCheckID: UInt64 = 0
    private var lastCompletionDate: Date?
    private var periodicTask: Task<Void, Never>?
    private var scheduledCheck: Task<Void, Never>?
    private var scheduledCheckID: UInt64 = 0
    private var isStopped = false

    /// The service resolves both the tunnel `NWInterface` and the egress info live at the start of
    /// every check via `tunnelInterface` and `egressInfo`. This avoids caching stale values from
    /// initialization time — for example, if a rekey has selected a different server underneath,
    /// the next check picks up the new server automatically without anyone having to push an
    /// update.
    ///
    /// When either provider returns nil, the check is skipped entirely — no wide event is fired.
    /// Running without a tunnel-pinned interface, or without a reference IP to compare against,
    /// can't distinguish "tunnel is healthy" from "tunnel is leaking", so the result would be
    /// meaningless either way.
    public init(
        configuration: LeakCheckConfiguration = .default,
        egressInfo: @escaping EgressInfoProvider,
        tunnelInterface: @escaping TunnelInterfaceProvider,
        tunnelPathGeneration: @escaping TunnelPathGenerationProvider = { 0 },
        httpClient: LeakCheckHTTPClient,
        stunClient: LeakCheckSTUNClient,
        wideEvent: WideEventManaging
    ) {
        self.configuration = configuration
        self.egressInfo = egressInfo
        self.tunnelInterface = tunnelInterface
        self.tunnelPathGeneration = tunnelPathGeneration
        self.httpClient = httpClient
        self.stunClient = stunClient
        self.wideEvent = wideEvent
    }

    public func start() {
        Logger.networkProtectionIPLeakCheck.log("🟢 Starting leak check service")
        schedulePeriodic()
    }

    public func stop() {
        Logger.networkProtectionIPLeakCheck.log("🔴 Stopping leak check service")
        isStopped = true
        periodicTask?.cancel()
        periodicTask = nil
        scheduledCheck?.cancel()
        scheduledCheck = nil
        if let task = currentCheck {
            task.cancel()
            currentCheck = nil
            for data in wideEvent.getAllFlowData(VPNIPLeakCheckWideEventData.self) {
                wideEvent.discardFlow(data)
            }
        }
    }

    /// Schedules a leak check that runs after the trigger's natural delay:
    /// `debounceDelay` for tunnel path changes, immediate for `.periodic`.
    ///
    /// The latest schedule wins: a pending scheduled check is cancelled and replaced. This collapses
    /// rapid bursts (e.g. manual start → reconnect) into a single check using the freshest trigger,
    /// and ensures `stop()` can cancel a pending check before it fires.
    public func scheduleCheck(trigger: LeakCheckTrigger) {
        guard !isStopped else {
            Logger.networkProtectionIPLeakCheck.log("Skipping scheduled leak check — service stopped (trigger: \(trigger.rawValue, privacy: .public))")
            return
        }

        guard trigger != .periodic else {
            guard scheduledCheck == nil else {
                Logger.networkProtectionIPLeakCheck.log("Skipping periodic leak check — tunnel path check pending")
                return
            }
            Task { [weak self] in
                await self?.runCheck(trigger: trigger)
            }
            return
        }

        scheduledCheck?.cancel()
        currentCheck?.cancel()
        currentCheck = nil
        scheduledCheckID &+= 1
        let checkID = scheduledCheckID

        let delay = configuration.debounceDelay
        scheduledCheck = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(interval: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.runCheck(trigger: trigger)
            await self?.clearScheduledCheck(id: checkID)
        }
    }

    private func clearScheduledCheck(id: UInt64) {
        guard scheduledCheckID == id else { return }
        scheduledCheck = nil
    }

    public static func completeAllPendingFlows(wideEvent: WideEventManaging) {
        let pending = wideEvent.getAllFlowData(VPNIPLeakCheckWideEventData.self)
        if !pending.isEmpty {
            Logger.networkProtectionIPLeakCheck.log("Completing \(pending.count, privacy: .public) pending leak check flow(s) as interrupted")
        }
        for data in pending {
            wideEvent.completeFlow(
                data,
                status: .unknown(reason: LeakCheckStatusReason.checkInterrupted),
                onComplete: { _, _ in }
            )
        }
    }

    public func runCheck(trigger: LeakCheckTrigger, bypassCooldown: Bool = false) async {
        guard !isStopped else {
            Logger.networkProtectionIPLeakCheck.log("Skipping leak check — service stopped (trigger: \(trigger.rawValue, privacy: .public))")
            return
        }
        guard trigger != .periodic || bypassCooldown || scheduledCheck == nil else {
            Logger.networkProtectionIPLeakCheck.log("Skipping periodic leak check — tunnel path check pending")
            return
        }
        guard currentCheck == nil else {
            Logger.networkProtectionIPLeakCheck.log("Skipping leak check — already in flight (trigger: \(trigger.rawValue, privacy: .public))")
            return
        }
        // `.reassert` and `.rekey` both signal a tunnel path change (failure recovery /
        // reconfiguration in the first case, server reselection in the second). They bypass
        // cooldown so the new path always gets validated once the debounce window elapses,
        // even if a recent check just completed.
        if !bypassCooldown,
           trigger != .reassert,
           trigger != .rekey,
           let last = lastCompletionDate,
           Date().timeIntervalSince(last) < configuration.cooldown {
            Logger.networkProtectionIPLeakCheck.log("Skipping leak check — cooldown active (trigger: \(trigger.rawValue, privacy: .public))")
            return
        }
        currentCheckID &+= 1
        let checkID = currentCheckID
        let task = Task { await executeCheck(trigger: trigger, id: checkID) }
        currentCheck = task
        await task.value
    }

    private func executeCheck(trigger: LeakCheckTrigger, id: UInt64) async {
        defer {
            if currentCheckID == id {
                currentCheck = nil
                if !Task.isCancelled {
                    lastCompletionDate = Date()
                }
            }
        }

        if trigger != .periodic {
            schedulePeriodic()
        }

        Logger.networkProtectionIPLeakCheck.log("🟢 Starting leak check (trigger: \(trigger.rawValue, privacy: .public))")

        let pathGenerationSnapshot = await tunnelPathGeneration()
        guard let egressInfoSnapshot = await egressInfo() else {
            Logger.networkProtectionIPLeakCheck.log("🔴 Skipping leak check — egress info unavailable (trigger: \(trigger.rawValue, privacy: .public))")
            return
        }
        guard let tunnelInterfaceSnapshot = await tunnelInterface() else {
            Logger.networkProtectionIPLeakCheck.log("🔴 Skipping leak check — tunnel interface unavailable (trigger: \(trigger.rawValue, privacy: .public))")
            return
        }
        Logger.networkProtectionIPLeakCheck.debug("Resolved tunnel interface for leak check: \(tunnelInterfaceSnapshot.name, privacy: .public)")

        let data = VPNIPLeakCheckWideEventData(trigger: trigger)
        data.egressServerName = egressInfoSnapshot.name
        wideEvent.startFlow(data)

        let egressIPSnapshot = egressInfoSnapshot.ipAddress
        let startDate = Date()
        let results = await runAllLeakTests(tunnelInterface: tunnelInterfaceSnapshot)

        data.latencyMsBucketed = bucketedLatency(Date().timeIntervalSince(startDate))

        if Task.isCancelled {
            Logger.networkProtectionIPLeakCheck.log("🔴 Leak check cancelled — discarding flow (trigger: \(trigger.rawValue, privacy: .public))")
            wideEvent.discardFlow(data)
            return
        }

        guard await tunnelPathGeneration() == pathGenerationSnapshot else {
            Logger.networkProtectionIPLeakCheck.log("🔴 Leak check interrupted by tunnel path change (trigger: \(trigger.rawValue, privacy: .public))")
            data.statusReason = LeakCheckStatusReason.checkInterrupted
            wideEvent.completeFlow(data, status: .unknown(reason: LeakCheckStatusReason.checkInterrupted), onComplete: { _, _ in })
            return
        }

        Logger.networkProtectionIPLeakCheck.debug(
            "IP comparison — expected: \(egressIPSnapshot, privacy: .public), got ipv4[http: \(Self.describeIP(results.ipv4Http), privacy: .public), https: \(Self.describeIP(results.ipv4Https), privacy: .public), stun: \(Self.describeIP(results.ipv4Stun), privacy: .public)], ipv6[http: \(Self.describeIP(results.ipv6Http), privacy: .public), https: \(Self.describeIP(results.ipv6Https), privacy: .public), stun: \(Self.describeIP(results.ipv6Stun), privacy: .public)]"
        )

        data.ipv4Http = classifyIPv4(results.ipv4Http, egressIP: egressIPSnapshot)
        data.ipv4Https = classifyIPv4(results.ipv4Https, egressIP: egressIPSnapshot)
        data.ipv4Stun = classifyIPv4(results.ipv4Stun, egressIP: egressIPSnapshot)
        data.ipv6Http = classifyIPv6(results.ipv6Http)
        data.ipv6Https = classifyIPv6(results.ipv6Https)
        data.ipv6Stun = classifyIPv6(results.ipv6Stun)

        let ipv4Tests: [LeakCheckPerTestResult?] = [data.ipv4Http, data.ipv4Https, data.ipv4Stun]
        if ipv4Tests.contains(where: { $0?.status == .leak }),
           let leakedIP = firstLeakedIPv4(from: [results.ipv4Http, results.ipv4Https, results.ipv4Stun], egressIP: egressIPSnapshot) {
            data.ipv4LeakIPType = IPAddressClassifier.classify(leakedIP)
        }
        let ipv6Tests: [LeakCheckPerTestResult?] = [data.ipv6Http, data.ipv6Https, data.ipv6Stun]
        if ipv6Tests.contains(where: { $0?.status == .leak }),
           let leakedIP = firstSuccessfulIP(from: [results.ipv6Http, results.ipv6Https, results.ipv6Stun]) {
            data.ipv6LeakIPType = IPAddressClassifier.classify(leakedIP)
        }

        let status = determineStatus(data: data)
        if case .unknown(let reason) = status {
            data.statusReason = reason
        }

        Logger.networkProtectionIPLeakCheck.log(
            "🟢 Leak check complete (trigger: \(trigger.rawValue, privacy: .public), status: \(Self.describeStatus(status), privacy: .public), latency: \(data.latencyMsBucketed ?? 0, privacy: .public)ms, \(Self.describeResults(data), privacy: .public))"
        )
        wideEvent.completeFlow(data, status: status, onComplete: { _, _ in })
    }

    private static func describeStatus(_ status: WideEventStatus) -> String {
        switch status {
        case .success: return "SUCCESS"
        case .failure: return "FAILURE"
        case .cancelled: return "CANCELLED"
        case .unknown(let reason): return "UNKNOWN(\(reason))"
        }
    }

    private static func describeIP(_ result: Result<String, Error>) -> String {
        switch result {
        case .success(let ip): return ip
        case .failure(let error): return "error(\(error))"
        }
    }

    private static func describeResults(_ data: VPNIPLeakCheckWideEventData) -> String {
        func describe(_ result: LeakCheckPerTestResult?) -> String {
            guard let result = result else { return "-" }
            return result.status.rawValue
        }

        var parts: [String] = []
        parts.append("ipv4: [http: \(describe(data.ipv4Http)), https: \(describe(data.ipv4Https)), stun: \(describe(data.ipv4Stun))]")
        if let leak = data.ipv4LeakIPType { parts.append("ipv4_leak_type: \(leak.rawValue)") }
        parts.append("ipv6: [http: \(describe(data.ipv6Http)), https: \(describe(data.ipv6Https)), stun: \(describe(data.ipv6Stun))]")
        if let leak = data.ipv6LeakIPType { parts.append("ipv6_leak_type: \(leak.rawValue)") }
        return parts.joined(separator: ", ")
    }

    private struct LeakTestResults {
        var ipv4Http: Result<String, Error>
        var ipv4Https: Result<String, Error>
        var ipv4Stun: Result<String, Error>
        var ipv6Http: Result<String, Error>
        var ipv6Https: Result<String, Error>
        var ipv6Stun: Result<String, Error>
    }

    private func runAllLeakTests(tunnelInterface: NWInterface?) async -> LeakTestResults {
        let cfg = configuration
        let http = httpClient
        let stun = stunClient
        let iface = tunnelInterface

        async let v4Http  = Self.runLeakTest { try await http.fetchIP(host: cfg.host, port: cfg.httpPort, usesTLS: false, ipVersion: .v4, timeout: cfg.httpTimeout, requiredInterface: iface) }
        async let v4Https = Self.runLeakTest { try await http.fetchIP(host: cfg.host, port: cfg.httpsPort, usesTLS: true, ipVersion: .v4, timeout: cfg.httpTimeout, requiredInterface: iface) }
        async let v4Stun  = Self.runLeakTest { try await stun.fetchIP(host: cfg.host, port: cfg.stunPort, ipVersion: .v4, timeout: cfg.stunTimeout, requiredInterface: iface) }
        async let v6Http  = Self.runLeakTest { try await http.fetchIP(host: cfg.host, port: cfg.httpPort, usesTLS: false, ipVersion: .v6, timeout: cfg.httpTimeout, requiredInterface: iface) }
        async let v6Https = Self.runLeakTest { try await http.fetchIP(host: cfg.host, port: cfg.httpsPort, usesTLS: true, ipVersion: .v6, timeout: cfg.httpTimeout, requiredInterface: iface) }
        async let v6Stun  = Self.runLeakTest { try await stun.fetchIP(host: cfg.host, port: cfg.stunPort, ipVersion: .v6, timeout: cfg.stunTimeout, requiredInterface: iface) }

        return await LeakTestResults(
            ipv4Http: v4Http, ipv4Https: v4Https, ipv4Stun: v4Stun,
            ipv6Http: v6Http, ipv6Https: v6Https, ipv6Stun: v6Stun
        )
    }

    private static func runLeakTest(_ operation: @Sendable () async throws -> String) async -> Result<String, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    private func classifyIPv4(_ result: Result<String, Error>, egressIP: String) -> LeakCheckPerTestResult {
        switch result {
        case .success(let ip):
            guard let matches = Self.ipv4OctetMatches(ip, egressIP) else {
                let error: LeakCheckIPError = IPv4Address(ip) == nil ? .malformedObservedIP : .malformedEgressIP
                return .error(error)
            }
            if matches.octet1 && matches.octet2 && matches.octet3 {
                return .success
            }
            return .leak(
                octet1Matched: matches.octet1,
                octet2Matched: matches.octet2,
                octet3Matched: matches.octet3,
                octet4Matched: matches.octet4
            )
        case .failure(let error):
            return .error(error)
        }
    }

    /// Returns `nil` if either string is not a parseable IPv4 address; otherwise reports per-octet equality.
    private static func ipv4OctetMatches(_ lhs: String, _ rhs: String) -> (octet1: Bool, octet2: Bool, octet3: Bool, octet4: Bool)? {
        guard let lhsAddr = IPv4Address(lhs), let rhsAddr = IPv4Address(rhs) else { return nil }
        let lhsBytes = [UInt8](lhsAddr.rawValue)
        let rhsBytes = [UInt8](rhsAddr.rawValue)
        guard lhsBytes.count == 4, rhsBytes.count == 4 else { return nil }
        return (
            lhsBytes[0] == rhsBytes[0],
            lhsBytes[1] == rhsBytes[1],
            lhsBytes[2] == rhsBytes[2],
            lhsBytes[3] == rhsBytes[3]
        )
    }

    private func classifyIPv6(_ result: Result<String, Error>) -> LeakCheckPerTestResult {
        switch result {
        case .success:
            return .leak
        case .failure(let error):
            return isExpectedIPv6ConnectionFailure(error) ? .success : .error(error)
        }
    }

    private func isExpectedIPv6ConnectionFailure(_ error: Error) -> Bool {
        if error is CancellationError { return true }

        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let code):
                let expected: [POSIXErrorCode] = [.EHOSTUNREACH, .ENETUNREACH, .ENETDOWN, .ECONNREFUSED, .ETIMEDOUT, .EADDRNOTAVAIL, .ENOTCONN]
                return expected.contains(code)
            case .dns:
                return true
            case .tls:
                return false
            case .wifiAware:
                return false
            @unknown default:
                return false
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost,
                    .cannotConnectToHost,
                    .timedOut,
                    .networkConnectionLost,
                    .notConnectedToInternet,
                    .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func firstLeakedIPv4(from results: [Result<String, Error>], egressIP: String) -> String? {
        for result in results {
            if case .success(let ip) = result,
               let matches = Self.ipv4OctetMatches(ip, egressIP),
               !(matches.octet1 && matches.octet2 && matches.octet3) {
                return ip
            }
        }
        return nil
    }

    private func firstSuccessfulIP(from results: [Result<String, Error>]) -> String? {
        for result in results {
            if case .success(let ip) = result { return ip }
        }
        return nil
    }

    private func bucketedLatency(_ seconds: TimeInterval) -> Int {
        let ms = max(0, Int(seconds * 1000))
        let rounded = ((ms + 499) / 500) * 500
        return min(max(rounded, 500), 5_000)
    }

    private func schedulePeriodic() {
        periodicTask?.cancel()
        let interval = configuration.periodicInterval
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(interval: interval)
                if Task.isCancelled { return }
                await self?.runCheck(trigger: .periodic)
            }
        }
    }

    private func determineStatus(data: VPNIPLeakCheckWideEventData) -> WideEventStatus {
        let tests: [LeakCheckPerTestResult?] = [
            data.ipv4Http, data.ipv4Https, data.ipv4Stun,
            data.ipv6Http, data.ipv6Https, data.ipv6Stun
        ]
        if tests.contains(where: { $0?.status == .leak }) {
            return .failure
        }
        if tests.contains(where: { $0?.status == .error }) {
            return .unknown(reason: "checks_errored")
        }
        return .success
    }

    /// A rekey that lands on the same server can't have changed the egress path, so we skip the
    /// leak check and let the periodic timer handle routine validation. Only force an immediate
    /// check when the server (or its IP) actually changed. A `nil` postRekey means WireGuard
    /// dropped state out from under us — the service would skip the check anyway.
    public nonisolated static func shouldScheduleCheckAfterRekey(preRekey: LeakCheckEgressInfo?,
                                                                 postRekey: LeakCheckEgressInfo?) -> Bool {
        guard let postRekey else { return false }
        return preRekey != postRekey
    }
}

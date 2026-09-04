//
//  NetworkProtectionTunnelFailureMonitor.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Combine
import ConcurrencyExtensions
import Foundation
import Network
import NetworkExtension
import os.log

public actor NetworkProtectionTunnelFailureMonitor: TunnelFailureMonitoring {
    public enum Result: Equatable {
        case failureDetected
        case failureRecovered
        case networkPathChanged(String)

        var threshold: TimeInterval {
            switch self {
            case .failureDetected: // WG handshakes happen every 2 mins, this means we'd miss 2+ handshakes
                return .minutes(5)
            case .failureRecovered:
                return .minutes(2) // WG handshakes happen every 2 mins
            case .networkPathChanged:
                return -1
            }
        }
    }

    private static let pathQueue = DispatchQueue(
        label: "com.duckduckgo.NetworkProtectionTunnelFailureMonitor.pathQueue")

    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    public var isStarted: Bool {
        task?.isCancelled == false
    }

    private let handshakeReporter: HandshakeReporting
    private let pathMonitorProvider: () -> PathMonitoring
    private let monitoringInterval: TimeInterval

    /// `nil` in production. Tests set it so the background timer cannot consume the deliberate first-check skip.
    private let initialDelay: TimeInterval?

    private var pathMonitor: PathMonitoring?
    private var callback: ((Result) -> Void)?

    private var failureReported = false
    private var firstCheckSkipped = false

    // MARK: - Init & deinit

    init(handshakeReporter: HandshakeReporting,
         pathMonitorProvider: @escaping () -> PathMonitoring = { PathMonitor() },
         monitoringInterval: TimeInterval = .minutes(1),
         initialDelay: TimeInterval? = nil) {
        self.handshakeReporter = handshakeReporter
        self.pathMonitorProvider = pathMonitorProvider
        self.monitoringInterval = monitoringInterval
        self.initialDelay = initialDelay

        Logger.networkProtectionMemory.debug("[+] \(String(describing: self), privacy: .public)")
    }

    deinit {
        task?.cancel()
        pathMonitor?.cancel()

        Logger.networkProtectionMemory.debug("[-] \(String(describing: self), privacy: .public)")
    }

    // MARK: - Start/Stop monitoring

    public func start(callback: @escaping (Result) -> Void) {
        Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Starting tunnel failure monitor")

        failureReported = false
        firstCheckSkipped = false
        self.callback = callback

        let monitor = pathMonitorProvider()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { [weak self] in
                await self?.reportPathChange()
            }
        }
        monitor.start(queue: Self.pathQueue)
        pathMonitor = monitor

        task = Task.periodic(delay: initialDelay, interval: monitoringInterval) { [weak self] in
            await self?.checkHandshakes()
        }
    }

    public func stop() {
        Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Stopping tunnel failure monitor")

        pathMonitor?.pathUpdateHandler = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        callback = nil

        task?.cancel() // Just making extra sure in case it's detached
        task = nil
    }

    // MARK: - Handshake monitor

    private func reportPathChange() {
        guard let description = pathMonitor?.currentPathSnapshot?.anonymousDescription else {
            return
        }
        callback?(.networkPathChanged(description))
    }

    /// Internal so tests drive checks directly rather than sleeping on `monitoringInterval`.
    func checkHandshakes() async {
        guard firstCheckSkipped else {
            // Avoid running the first tunnel failure check after startup to avoid reading the first handshake after sleep, which will almost always
            // be out of date. In normal operation, the first check will frequently be 0 as WireGuard hasn't had the chance to handshake yet.
            Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Skipping first tunnel failure check")
            firstCheckSkipped = true
            return
        }

        let mostRecentHandshake = (try? await handshakeReporter.getMostRecentHandshake()) ?? 0

        guard mostRecentHandshake > 0 else {
            Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Got handshake timestamp at or below 0, skipping check")
            return
        }

        let difference = Date().timeIntervalSince1970 - mostRecentHandshake
        Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Last handshake: \(difference, privacy: .public) seconds ago")

        if difference > Result.failureDetected.threshold, isReachable {
            if failureReported {
                Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Tunnel failure already reported")
            } else {
                Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Tunnel failure reported")
                callback?(.failureDetected)
                failureReported = true
            }
        } else if difference <= Result.failureRecovered.threshold, failureReported {
            Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Tunnel recovered from failure")
            callback?(.failureRecovered)
            failureReported = false
        }
    }

    private var isReachable: Bool {
        pathMonitor?.currentPathSnapshot?.isReachable ?? false
    }
}

extension Network.NWPath {

    /// Helper enum to identify known interfaces
    ///
    public enum KnownInterface: CaseIterable {
        case utun
        case ipsec
        case dns
        case unidentified

        var prefix: String {
            switch self {
            case .utun:
                return "utun"
            case .ipsec:
                return "ipsec"
            case .dns:
                return "dns"
            case .unidentified:
                return "unidentified"
            }
        }

        static func identify(_ interface: NWInterface) -> KnownInterface {
            allCases.first { knownInterface in
                interface.name.hasPrefix(knownInterface.prefix)
            } ?? .unidentified
        }
    }

    /// Counts of the known interface families backing this path.
    ///
    private var interfaceCounts: (utun: Int, ipsec: Int, dns: Int, unidentified: Int) {
        var dnsCount = 0
        var ipsecCount = 0
        var utunCount = 0
        var unidentifiedCount = 0

        availableInterfaces.map(KnownInterface.identify).forEach { knownInterface in
            switch knownInterface {
            case .dns:
                dnsCount += 1
            case .ipsec:
                ipsecCount += 1
            case .utun:
                utunCount += 1
            case .unidentified:
                unidentifiedCount += 1
            }
        }

        return (utunCount, ipsecCount, dnsCount, unidentifiedCount)
    }

    /// A description that's safe from a privacy standpoint.
    ///
    /// Ref: https://app.asana.com/0/0/1206712493935053/1206712516729780/f
    ///
    public var anonymousDescription: String {
        var description = "NWPath("

        description += "status: \(status), "

        if #available(iOS 14.2, *), case .unsatisfied = status {
            description += "unsatisfiedReason: \(unsatisfiedReason), "
        }

        let counts = interfaceCounts

        description += "mainInterfaceType: \(String(describing: availableInterfaces.first?.type)), "
        description += "utunInterfaceCount: \(counts.utun), "
        description += "ipsecInterfaceCount: \(counts.ipsec), "
        description += "dnsInterfaceCount: \(counts.dns)), "
        description += "unidentifiedInterfaceCount: \(counts.unidentified)), "
        description += "isConstrained: \(isConstrained ? "true" : "false"), "
        description += "isExpensive: \(isExpensive ? "true" : "false")"
        description += ")"

        return description
    }

    /// A privacy-safe, structured view of this path holding the same anonymized fields as `anonymousDescription`.
    ///
    public var anonymousPathInfo: NetworkProtectionNetworkPathInfo {
        let counts = interfaceCounts

        var unsatisfiedReasonDescription: String?
        if #available(iOS 14.2, *), case .unsatisfied = status {
            unsatisfiedReasonDescription = String(describing: unsatisfiedReason)
        }

        return NetworkProtectionNetworkPathInfo(
            status: String(describing: status),
            unsatisfiedReason: unsatisfiedReasonDescription,
            mainInterfaceType: availableInterfaces.first.map { String(describing: $0.type) },
            utunInterfaceCount: counts.utun,
            ipsecInterfaceCount: counts.ipsec,
            dnsInterfaceCount: counts.dns,
            unidentifiedInterfaceCount: counts.unidentified,
            isConstrained: isConstrained,
            isExpensive: isExpensive
        )
    }
}

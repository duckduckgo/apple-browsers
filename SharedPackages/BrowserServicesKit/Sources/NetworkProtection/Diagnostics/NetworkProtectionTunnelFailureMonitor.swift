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

import Foundation
import Network
import NetworkExtension
import os.log
import Combine

public actor NetworkProtectionTunnelFailureMonitor {
    public enum Result {
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

    private static let monitoringInterval: TimeInterval = .minutes(1)

    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    var isStarted: Bool {
        task?.isCancelled == false
    }

    private let handshakeReporter: HandshakeReporting

    private let networkMonitor = NWPathMonitor()

    private var failureReported = false
    private var firstCheckSkipped = false

    // MARK: - Init & deinit

    init(handshakeReporter: HandshakeReporting) {
        self.handshakeReporter = handshakeReporter
        self.networkMonitor.start(queue: .global())

        Logger.networkProtectionMemory.debug("[+] \(String(describing: self), privacy: .public)")
    }

    deinit {
        task?.cancel()
        networkMonitor.cancel()

        Logger.networkProtectionMemory.debug("[-] \(String(describing: self), privacy: .public)")
    }

    // MARK: - Start/Stop monitoring

    func start(callback: @escaping (Result) -> Void) {
        Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Starting tunnel failure monitor")

        failureReported = false
        firstCheckSkipped = false

        networkMonitor.pathUpdateHandler = { path in
            callback(.networkPathChanged(path.anonymousDescription))
        }

        task = Task.periodic(interval: Self.monitoringInterval) { [weak self] in
            await self?.monitorHandshakes(callback: callback)
        }
    }

    func stop() {
        Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Stopping tunnel failure monitor")

        networkMonitor.cancel()
        networkMonitor.pathUpdateHandler = nil

        task?.cancel() // Just making extra sure in case it's detached
        task = nil
    }

    // MARK: - Handshake monitor

    private func monitorHandshakes(callback: @escaping (Result) -> Void) async {
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

        if difference > Result.failureDetected.threshold, isConnected {
            if failureReported {
                Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Tunnel failure already reported")
            } else {
                Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Tunnel failure reported")
                callback(.failureDetected)
                failureReported = true
            }
        } else if difference <= Result.failureRecovered.threshold, failureReported {
            Logger.networkProtectionTunnelFailureMonitor.log("⚫️ Tunnel recovered from failure")
            callback(.failureRecovered)
            failureReported = false
        }
    }

    private var isConnected: Bool {
        let path = networkMonitor.currentPath
        let connectionType = NetworkConnectionType(nwPath: path)

        return [.wifi, .eth, .cellular].contains(connectionType) && path.status == .satisfied
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

        description += "mainInterfaceType: \(String(describing: availableInterfaces.first?.type)), "
        description += "utunInterfaceCount: \(utunCount), "
        description += "ipsecInterfaceCount: \(ipsecCount), "
        description += "dnsInterfaceCount: \(dnsCount)), "
        description += "unidentifiedInterfaceCount: \(unidentifiedCount)), "
        description += "isConstrained: \(isConstrained ? "true" : "false"), "
        description += "isExpensive: \(isExpensive ? "true" : "false")"
        description += ")"

        return description
    }
}

//
//  NetworkSignalsProvider.swift
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
import Network

public protocol NetworkSignalsProviding {
    /// Returns `nil` when collecting network signals is disabled.
    func currentSignals() async -> NetworkSignals?
}

public struct NetworkPathState: Equatable, Sendable {
    public let networkType: NetworkSignals.NetworkType
    public let isConstrained: Bool

    public init(networkType: NetworkSignals.NetworkType, isConstrained: Bool) {
        self.networkType = networkType
        self.isConstrained = isConstrained
    }
}

public protocol NetworkPathProviding: AnyObject {
    var currentPathState: NetworkPathState { get }
}

public protocol VPNConnectivityIssuesProviding {
    func isExperiencingVPNConnectivityIssues() async -> Bool
}

public final class NetworkSignalsProvider: NetworkSignalsProviding {

    private let pathProvider: NetworkPathProviding
    private let vpnConnectivityIssuesProvider: VPNConnectivityIssuesProviding
    private let isEnabledProvider: () -> Bool

    public init(pathProvider: NetworkPathProviding,
                vpnConnectivityIssuesProvider: VPNConnectivityIssuesProviding,
                isEnabledProvider: @escaping () -> Bool) {
        self.pathProvider = pathProvider
        self.vpnConnectivityIssuesProvider = vpnConnectivityIssuesProvider
        self.isEnabledProvider = isEnabledProvider
    }

    public func currentSignals() async -> NetworkSignals? {
        guard isEnabledProvider() else {
            return nil
        }

        let pathState = pathProvider.currentPathState
        let hasVPNConnectivityIssues = await vpnConnectivityIssuesProvider.isExperiencingVPNConnectivityIssues()

        return NetworkSignals(networkType: pathState.networkType,
                              isLowDataModeEnabled: pathState.isConstrained,
                              hasVPNConnectivityIssues: hasVPNConnectivityIssues)
    }
}

public final class NetworkPathMonitor: NetworkPathProviding {

    private let queue: DispatchQueue
    private let monitor: NWPathMonitor

    public init(monitor: NWPathMonitor = NWPathMonitor(), queue: DispatchQueue? = nil) {
        let targetqQueue = queue ?? DispatchQueue(label: "com.duckduckgo.network-signals.path-monitor")

        self.queue = targetqQueue
        self.monitor = monitor

        monitor.start(queue: targetqQueue)
    }

    deinit {
        monitor.cancel()
    }

    public var currentPathState: NetworkPathState {
        let path = monitor.currentPath
        return NetworkPathState(networkType: networkType(for: path), isConstrained: path.isConstrained)
    }

    private func networkType(for path: NWPath) -> NetworkSignals.NetworkType {
        guard path.status == .satisfied else {
            return .unavailable
        }

        if path.usesInterfaceType(.wiredEthernet) {
            return .wired
        }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        }

        if path.usesInterfaceType(.cellular) {
            return .cellular
        }

        return .unknown
    }
}

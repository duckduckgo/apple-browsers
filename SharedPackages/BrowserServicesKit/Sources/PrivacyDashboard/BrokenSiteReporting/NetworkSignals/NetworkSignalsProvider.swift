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

public protocol NetworkSignalsProviding {
    /// Starts collecting ping quality without waiting for the lookup to complete; `nil` when no ping is started.
    @discardableResult
    func prefetchSignals() -> Task<Void, Never>?

    /// Returns `nil` when collecting network signals is disabled.
    func currentSignals() async -> NetworkSignals?
}

public protocol VPNConnectivityIssuesProviding {
    func isExperiencingVPNConnectivityIssues() async -> Bool
}

public protocol PingQualityProviding: Sendable {
    associatedtype Quality: RawRepresentable where Quality.RawValue == String

    func currentPingQuality() async -> Quality
}

public final class NetworkSignalsProvider: NetworkSignalsProviding {

    public static let pingHost = "duckduckgo.com"
    public static let lookupTimeout: TimeInterval = 1

    private let pathProvider: NetworkPathProviding
    private let vpnConnectivityIssuesProvider: VPNConnectivityIssuesProviding
    private let pingQualityProvider: any PingQualityProviding
    private let isEnabledProvider: () -> Bool
    private let pingLock = NSLock()
    private var prefetchedPingQuality: PingQuality = .unknown

    public init(pathProvider: NetworkPathProviding,
                vpnConnectivityIssuesProvider: VPNConnectivityIssuesProviding,
                pingQualityProvider: any PingQualityProviding,
                isEnabledProvider: @escaping () -> Bool) {
        self.pathProvider = pathProvider
        self.vpnConnectivityIssuesProvider = vpnConnectivityIssuesProvider
        self.pingQualityProvider = pingQualityProvider
        self.isEnabledProvider = isEnabledProvider
    }

    @discardableResult
    public func prefetchSignals() -> Task<Void, Never>? {
        pingLock.withLock { prefetchedPingQuality = .unknown }

        guard isEnabledProvider(), pathProvider.currentPathState.isNetworkAvailable else {
            return nil
        }

        return Task { [weak self] in
            await self?.refreshPingQuality()
        }
    }

    /// Uses the prefetched ping quality, if any, rather than waiting for a new ping.
    public func currentSignals() async -> NetworkSignals? {
        guard isEnabledProvider() else {
            return nil
        }

        let pathState = pathProvider.currentPathState
        let pingQuality = pingLock.withLock { prefetchedPingQuality }
        let hasVPNConnectivityIssues = await vpnConnectivityIssuesProvider.isExperiencingVPNConnectivityIssues()

        return NetworkSignals(isNetworkAvailable: pathState.isNetworkAvailable,
                              networkType: pathState.networkType,
                              isLowDataModeEnabled: pathState.isConstrained,
                              hasVPNConnectivityIssues: hasVPNConnectivityIssues,
                              pingQuality: pingQuality)
    }
}

private extension NetworkSignalsProvider {

    func refreshPingQuality() async {
        let quality = await pingQualityProvider.currentPingQuality()
        let pingQuality = PingQuality(rawValue: quality.rawValue) ?? .unknown

        pingLock.withLock { prefetchedPingQuality = pingQuality }
    }
}

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

    private let pathProvider: NetworkPathProviding
    private let vpnConnectivityIssuesProvider: VPNConnectivityIssuesProviding
    private let pingQualityProvider: any PingQualityProviding
    private let isEnabledProvider: () -> Bool

    public init(pathProvider: NetworkPathProviding,
                vpnConnectivityIssuesProvider: VPNConnectivityIssuesProviding,
                pingQualityProvider: any PingQualityProviding,
                isEnabledProvider: @escaping () -> Bool) {
        self.pathProvider = pathProvider
        self.vpnConnectivityIssuesProvider = vpnConnectivityIssuesProvider
        self.pingQualityProvider = pingQualityProvider
        self.isEnabledProvider = isEnabledProvider
    }

    public func currentSignals() async -> NetworkSignals? {
        guard isEnabledProvider() else {
            return nil
        }

        let pathState = pathProvider.currentPathState

        async let pingQuality = pingQuality(networkType: pathState.networkType)
        async let hasVPNConnectivityIssues = vpnConnectivityIssuesProvider.isExperiencingVPNConnectivityIssues()

        return await NetworkSignals(networkType: pathState.networkType,
                                    isLowDataModeEnabled: pathState.isConstrained,
                                    hasVPNConnectivityIssues: hasVPNConnectivityIssues,
                                    pingQuality: pingQuality)
    }

    /// Skips the ping when there is no network, since it could only time out.
    private func pingQuality(networkType: NetworkSignals.NetworkType) async -> PingQuality {
        guard networkType != .unavailable else {
            return .unknown
        }

        let quality = await pingQualityProvider.currentPingQuality()
        return PingQuality(rawValue: quality.rawValue) ?? .unknown
    }
}

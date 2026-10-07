//
//  NetworkSignals.swift
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

public struct NetworkSignals: Equatable, Sendable {

    public enum NetworkType: String, Sendable {
        case wifi
        case cellular
        case wired
        case unknown
    }

    public let isNetworkAvailable: Bool
    public let networkType: NetworkType
    public let isLowDataModeEnabled: Bool
    public let hasVPNConnectivityIssues: Bool
    public let pingQuality: PingQuality

    public init(isNetworkAvailable: Bool, networkType: NetworkType, isLowDataModeEnabled: Bool, hasVPNConnectivityIssues: Bool, pingQuality: PingQuality) {
        self.isNetworkAvailable = isNetworkAvailable
        self.networkType = networkType
        self.isLowDataModeEnabled = isLowDataModeEnabled
        self.hasVPNConnectivityIssues = hasVPNConnectivityIssues
        self.pingQuality = pingQuality
    }
}

/// Round-trip latency bucket; raw values match the VPN's `ConnectionQuality`.
public enum PingQuality: String, Sendable {
    case excellent
    case good
    case moderate
    case poor
    case terrible
    case unknown
}

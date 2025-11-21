//
//  LatencyMonitoring.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Protocol abstraction for latency monitoring functionality.
///
/// This protocol defines the interface for monitoring VPN connection latency
/// by periodically measuring ping times to the VPN server.
///
public protocol LatencyMonitoring: Actor {

    /// Indicates whether the monitor is currently running.
    var isStarted: Bool { get }

    /// Starts monitoring latency to the specified server.
    ///
    /// - Parameters:
    ///   - serverIP: The IPv4 address of the server to monitor
    ///   - callback: Called with latency measurements and quality assessments
    func start(serverIP: IPv4Address,
               callback: @escaping (NetworkProtectionLatencyMonitor.Result) -> Void)

    /// Stops monitoring latency.
    func stop()
}

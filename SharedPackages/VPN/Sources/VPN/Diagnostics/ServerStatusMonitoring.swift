//
//  ServerStatusMonitoring.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

/// Protocol abstraction for server status monitoring functionality.
///
/// This protocol defines the interface for monitoring VPN server status
/// and detecting when server migration is required.
///
protocol ServerStatusMonitoring: Actor {

    /// Indicates whether the monitor is currently running.
    var isStarted: Bool { get }

    /// Starts monitoring the status of the specified server.
    ///
    /// - Parameters:
    ///   - serverName: The name of the server to monitor
    ///   - callback: Called when server status changes or migration is needed
    func start(serverName: String,
               callback: @escaping (NetworkProtectionServerStatusMonitor.ServerStatusResult) -> Void)

    /// Stops monitoring server status.
    func stop()
}

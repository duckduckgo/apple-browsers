//
//  TunnelFailureMonitoring.swift
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

/// Protocol abstraction for tunnel failure monitoring functionality.
///
/// This protocol defines the interface for monitoring tunnel health by checking
/// WireGuard handshakes and detecting connection failures.
///
public protocol TunnelFailureMonitoring: Actor {

    /// Indicates whether the monitor is currently running.
    var isStarted: Bool { get }

    /// Starts monitoring tunnel failures.
    ///
    /// - Parameter callback: Called when a tunnel failure is detected or recovered
    func start(callback: @escaping (NetworkProtectionTunnelFailureMonitor.Result) -> Void)

    /// Stops monitoring tunnel failures.
    func stop()
}

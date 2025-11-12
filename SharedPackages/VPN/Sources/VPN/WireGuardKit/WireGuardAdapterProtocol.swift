//
//  WireGuardAdapterProtocol.swift
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

/// Protocol abstraction for WireGuard adapter functionality.
///
/// This protocol defines the interface for managing a WireGuard tunnel adapter,
/// including starting, stopping, updating configuration, and monitoring connection state.
///
protocol WireGuardAdapterProtocol: AnyObject, HandshakeReporting {

    /// The name of the tunnel interface, if available.
    var interfaceName: String? { get }

    /// Starts the WireGuard tunnel with the specified configuration.
    ///
    /// - Parameters:
    ///   - tunnelConfiguration: The tunnel configuration to use
    ///   - completionHandler: Called when the operation completes, with an error if it failed
    func start(tunnelConfiguration: TunnelConfiguration,
               completionHandler: @escaping (WireGuardAdapterError?) -> Void)

    /// Stops the WireGuard tunnel.
    ///
    /// - Parameter completionHandler: Called when the operation completes, with an error if it failed
    func stop(completionHandler: @escaping (WireGuardAdapterError?) -> Void)

    /// Updates the tunnel configuration and optionally reasserts the connection.
    ///
    /// - Parameters:
    ///   - tunnelConfiguration: The new tunnel configuration
    ///   - reassert: Whether to reassert the connection after updating
    ///   - completionHandler: Called when the operation completes, with an error if it failed
    func update(tunnelConfiguration: TunnelConfiguration,
                reassert: Bool,
                completionHandler: @escaping (WireGuardAdapterError?) -> Void)

    /// Retrieves the number of bytes transmitted and received.
    ///
    /// - Returns: A tuple containing received (rx) and transmitted (tx) byte counts
    /// - Throws: An error if the operation fails
    func getBytesTransmitted() async throws -> (rx: UInt64, tx: UInt64)

    /// Retrieves the current runtime configuration.
    ///
    /// - Parameter completionHandler: Called with the configuration string, or nil if unavailable
    func getRuntimeConfiguration(completionHandler: @escaping (String?) -> Void)

    /// Puts the adapter into snooze mode, temporarily pausing the tunnel.
    ///
    /// - Parameter completionHandler: Called when the operation completes, with an error if it failed
    func snooze(completionHandler: @escaping (WireGuardAdapterError?) -> Void)
}

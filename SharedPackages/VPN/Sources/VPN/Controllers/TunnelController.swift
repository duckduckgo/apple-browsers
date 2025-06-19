//
//  TunnelController.swift
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
import NetworkExtension

/// This protocol offers an interface to control the tunnel.
///
public protocol TunnelController {

    // MARK: - Starting & Stopping the VPN

    /// Starts the VPN connection used for Network Protection
    ///
    func start() async

    /// Stops the VPN connection used for Network Protection
    ///
    func stop() async

    /// Sends a command to the adapter
    ///
    func command(_ command: VPNCommand) async throws

    /// Whether the tunnel is connected
    ///
    var isConnected: Bool { get async }
}

/// A convenience tunnel session provider protocol.
///
/// This should eventually be unified onto `TunnelController`, so that all these requests can be made
/// directly or through IPC, but this protocol is added to avoid having to tackle that right now..
///
public protocol TunnelSessionProvider {
    func activeSession() async -> NETunnelProviderSession?
}

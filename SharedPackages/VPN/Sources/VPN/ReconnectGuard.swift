//
//  ReconnectGuard.swift
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

/// Persists the failed-shutdown guard independently of subscription credentials.
struct ReconnectGuard {
    private static let blockedKey = "com.duckduckgo.vpn.reconnectBlocked"
    let defaults: UserDefaults
    /// Startup history belongs to the current provider instance and is never persisted.
    private(set) var hasStartedSuccessfully = false

    var canReconnect: Bool {
        get { !defaults.bool(forKey: Self.blockedKey) }
        nonmutating set { defaults.set(!newValue, forKey: Self.blockedKey) }
    }

    func validate(startupMethod: StartupOptions.StartupMethod) throws {
        // A system restart can arrive without options and look like a system-initiated start.
        guard canReconnect || startupMethod == .manualByMainApp else {
            throw PacketTunnelProvider.TunnelError.reconnectBlocked
        }
    }

    mutating func startSucceeded(startupMethod: StartupOptions.StartupMethod) {
        hasStartedSuccessfully = true
        if startupMethod == .manualByMainApp {
            canReconnect = true
        }
    }
}

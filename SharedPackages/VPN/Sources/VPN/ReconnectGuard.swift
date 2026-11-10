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
    private let defaults: UserDefaults
    /// Startup history belongs to the current provider instance and is never persisted.
    private(set) var hasStartedSuccessfully = false

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private var isAutomaticReconnectBlocked: Bool {
        get { defaults.bool(forKey: Self.blockedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.blockedKey) }
    }

    /// Validates the start and immediately enables automatic reconnects when it is allowed.
    func runStartValidation(startupMethod: StartupOptions.StartupMethod) throws {
        // A system restart can arrive without options and look like a system-initiated start.
        guard !isAutomaticReconnectBlocked || startupMethod == .manualByMainApp else {
            throw PacketTunnelProvider.TunnelError.reconnectBlocked
        }
        isAutomaticReconnectBlocked = false
    }

    func blockAutomaticReconnect() {
        isAutomaticReconnectBlocked = true
    }

    mutating func didStartSuccessfully() {
        hasStartedSuccessfully = true
    }
}

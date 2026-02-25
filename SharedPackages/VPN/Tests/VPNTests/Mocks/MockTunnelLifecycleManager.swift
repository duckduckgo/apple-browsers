//
//  MockTunnelLifecycleManager.swift
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
@testable import VPN

@MainActor
final class MockTunnelLifecycleManager: TunnelLifecycleManaging {

    private(set) var cancelTunnelCalled = false
    private(set) var cancelTunnelError: Error?

    private(set) var updateTunnelConfigurationCalled = false
    private(set) var lastUpdateMethod: PacketTunnelProvider.TunnelUpdateMethod?
    private(set) var lastReassert: Bool?

    private(set) var restartAdapterCalled = false

    private(set) var resetRegistrationKeyCalled = false

    private(set) var removeTokenCalled = false

    private(set) var handleAccessRevokedCalled = false
    private(set) var handleAccessRevokedError: Error?

    func cancelTunnel(with error: Error) async {
        cancelTunnelCalled = true
        cancelTunnelError = error
    }

    func updateTunnelConfiguration(updateMethod: PacketTunnelProvider.TunnelUpdateMethod, reassert: Bool) async throws {
        updateTunnelConfigurationCalled = true
        lastUpdateMethod = updateMethod
        lastReassert = reassert
    }

    func restartAdapter() async throws {
        restartAdapterCalled = true
    }

    func resetRegistrationKey() {
        resetRegistrationKeyCalled = true
    }

    func removeToken() async throws {
        removeTokenCalled = true
    }

    func handleAccessRevoked(dueTo error: Error) async {
        handleAccessRevokedCalled = true
        handleAccessRevokedError = error
    }
}

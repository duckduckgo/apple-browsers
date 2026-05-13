//
//  KeyRotator.swift
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

import Common
import Foundation
import os.log

@MainActor
final class KeyRotator {

    private var keyStore: NetworkProtectionKeyStore
    private let settings: VPNSettings
    private let events: EventMapping<PacketTunnelProvider.Event>

    private weak var tunnelLifecycle: (any TunnelLifecycleManaging)?

    init(keyStore: NetworkProtectionKeyStore,
         settings: VPNSettings,
         events: EventMapping<PacketTunnelProvider.Event>,
         tunnelLifecycle: any TunnelLifecycleManaging) {

        self.keyStore = keyStore
        self.settings = settings
        self.events = events
        self.tunnelLifecycle = tunnelLifecycle
    }

    func rekey() async throws {
        // Intentional: KeyExpirationTester's canRekey closure also fires .userBecameActive
        // before invoking rekey. Both fires are preserved to match pre-refactor behavior.
        events.fire(.userBecameActive)

        guard !settings.disableRekeying else {
            Logger.networkProtectionKeyManagement.log("Rekeying disabled")
            return
        }

        events.fire(.rekeyAttempt(.begin))

        guard let tunnelLifecycle else {
            return
        }

        do {
            try await tunnelLifecycle.performRekey()
            events.fire(.rekeyAttempt(.success))
        } catch {
            events.fire(.rekeyAttempt(.failure(error)))
            if case PacketTunnelProvider.TunnelError.vpnAccessRevoked = error {
                await tunnelLifecycle.handleAccessRevoked(dueTo: error)
            }
            throw error
        }
    }

    func resetRegistrationKey() {
        Logger.networkProtectionKeyManagement.log("Resetting the current registration key")
        keyStore.resetCurrentKeyPair()
    }
}

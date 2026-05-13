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

/// Owns the VPN registration-keypair lifecycle: triggering rotation and resetting the
/// stored pair. The class doesn't perform the cryptographic swap itself — it coordinates
/// the work and delegates the actual rotation to the injected `rotateKey` closure
/// (typically the provider's tunnel reconfiguration with `regenerateKey: true`).
///
/// In scope:
/// - `rekey()`: gate on `VPNSettings.disableRekeying`, fire `.rekeyAttempt` telemetry,
///   invoke the `rotateKey` closure to do the work.
/// - `resetRegistrationKey()`: clear the locally-cached keypair via `keyStore`, so the
///   next config request regenerates one. Used in response to signals like subscription
///   changes that should invalidate the stored pair.
///
/// Out of scope:
/// - Performing the actual rotation (the `rotateKey` closure does that).
/// - Subscription / access-revoked routing — the caller's rekey closure wraps `rekey()`
///   with `subscriptionAccessErrorHandler` for that.
/// - Leak-check scheduling around rekey — handled in the caller's closure.
/// - Deciding *when* to rekey — `KeyExpirationTester` owns that.
@MainActor
final class KeyRotator {

    private let keyStore: NetworkProtectionKeyStore
    private let settings: VPNSettings
    private let events: EventMapping<PacketTunnelProvider.Event>
    private let rotateKey: @MainActor () async throws -> Void

    init(keyStore: NetworkProtectionKeyStore,
         settings: VPNSettings,
         events: EventMapping<PacketTunnelProvider.Event>,
         rotateKey: @escaping @MainActor () async throws -> Void) {

        self.keyStore = keyStore
        self.settings = settings
        self.events = events
        self.rotateKey = rotateKey
    }

    func rekey() async throws {
        guard !settings.disableRekeying else {
            Logger.networkProtectionKeyManagement.log("Rekeying disabled")
            return
        }

        events.fire(.rekeyAttempt(.begin))

        do {
            try await rotateKey()
            events.fire(.rekeyAttempt(.success))
        } catch {
            events.fire(.rekeyAttempt(.failure(error)))
            throw error
        }
    }

    func resetRegistrationKey() {
        Logger.networkProtectionKeyManagement.log("Resetting the current registration key")
        keyStore.resetCurrentKeyPair()
    }
}

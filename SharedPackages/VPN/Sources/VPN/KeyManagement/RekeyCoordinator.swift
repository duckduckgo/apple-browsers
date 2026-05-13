//
//  RekeyCoordinator.swift
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

/// Coordinates the rekey lifecycle without performing the rotation itself.
///
/// In scope:
/// - Gating on `VPNSettings.disableRekeying` (short-circuits when the user has opted out).
/// - Firing `.rekeyAttempt(.begin/.success/.failure)` telemetry around the operation.
/// - Delegating the actual key regeneration to the injected `performRekey` closure
///   (the caller — typically the packet tunnel provider — owns the WireGuard
///   tunnel-reconfiguration plumbing).
/// - Clearing the locally-cached registration keypair via `resetRegistrationKey()`
///   so the next config request regenerates one.
///
/// Out of scope:
/// - Performing the rotation itself (the closure does that).
/// - Subscription / access-revoked routing — the caller's rekey closure wraps
///   `rekey()` with `subscriptionAccessErrorHandler` for that.
/// - Leak-check scheduling around rekey — also handled in the caller's closure.
/// - Deciding *when* to rekey — `KeyExpirationTester` owns that.
@MainActor
final class RekeyCoordinator {

    private let keyStore: NetworkProtectionKeyStore
    private let settings: VPNSettings
    private let events: EventMapping<PacketTunnelProvider.Event>
    private let performRekey: @MainActor () async throws -> Void

    init(keyStore: NetworkProtectionKeyStore,
         settings: VPNSettings,
         events: EventMapping<PacketTunnelProvider.Event>,
         performRekey: @escaping @MainActor () async throws -> Void) {

        self.keyStore = keyStore
        self.settings = settings
        self.events = events
        self.performRekey = performRekey
    }

    func rekey() async throws {
        guard !settings.disableRekeying else {
            Logger.networkProtectionKeyManagement.log("Rekeying disabled")
            return
        }

        events.fire(.rekeyAttempt(.begin))

        do {
            try await performRekey()
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

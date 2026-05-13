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

// MARK: - Dependency Protocols

@MainActor
protocol TunnelEgressProviding: AnyObject {
    func currentEgressInfo() -> LeakCheckEgressInfo?
}

@MainActor
protocol TunnelReconfiguring: AnyObject {
    func updateTunnelConfiguration(updateMethod: PacketTunnelProvider.TunnelUpdateMethod,
                                   reassert: Bool,
                                   regenerateKey: Bool) async throws
}

// MARK: - KeyRotator

@MainActor
final class KeyRotator {

    private var keyStore: NetworkProtectionKeyStore
    private let settings: VPNSettings
    private let events: EventMapping<PacketTunnelProvider.Event>
    private let scheduleLeakCheckAfterRekey: @MainActor () async -> Void

    private weak var tunnelState: (any TunnelStateProviding)?
    private weak var tunnelLifecycle: (any TunnelLifecycleManaging)?
    private weak var tunnelEgress: (any TunnelEgressProviding)?
    private weak var tunnelReconfigurer: (any TunnelReconfiguring)?

    init(keyStore: NetworkProtectionKeyStore,
         settings: VPNSettings,
         events: EventMapping<PacketTunnelProvider.Event>,
         tunnelState: any TunnelStateProviding,
         tunnelLifecycle: any TunnelLifecycleManaging,
         tunnelEgress: any TunnelEgressProviding,
         tunnelReconfigurer: any TunnelReconfiguring,
         scheduleLeakCheckAfterRekey: @escaping @MainActor () async -> Void) {

        self.keyStore = keyStore
        self.settings = settings
        self.events = events
        self.tunnelState = tunnelState
        self.tunnelLifecycle = tunnelLifecycle
        self.tunnelEgress = tunnelEgress
        self.tunnelReconfigurer = tunnelReconfigurer
        self.scheduleLeakCheckAfterRekey = scheduleLeakCheckAfterRekey
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

        guard let tunnelState, let tunnelReconfigurer else {
            return
        }

        let preRekeyEgress = tunnelEgress?.currentEgressInfo()

        do {
            try await tunnelReconfigurer.updateTunnelConfiguration(
                updateMethod: .selectServer(tunnelState.currentServerSelectionMethod),
                reassert: false,
                regenerateKey: true)

            let postRekeyEgress = tunnelEgress?.currentEgressInfo()
            if Self.shouldScheduleLeakCheck(preRekeyEgress: preRekeyEgress, postRekeyEgress: postRekeyEgress) {
                await scheduleLeakCheckAfterRekey()
            }

            events.fire(.rekeyAttempt(.success))
        } catch {
            events.fire(.rekeyAttempt(.failure(error)))
            if case PacketTunnelProvider.TunnelError.vpnAccessRevoked = error {
                await tunnelLifecycle?.handleAccessRevoked(dueTo: error)
            }
            throw error
        }
    }

    func resetRegistrationKey() {
        Logger.networkProtectionKeyManagement.log("Resetting the current registration key")
        keyStore.resetCurrentKeyPair()
    }

    /// A rekey that lands on the same server can't have changed the egress path, so we skip the
    /// leak check and let the periodic timer handle routine validation. We only force an immediate
    /// check when the server (or its IP) actually changed. A `nil` postRekeyEgress means WireGuard
    /// dropped state out from under us — the leak service would skip the check anyway.
    static func shouldScheduleLeakCheck(preRekeyEgress: LeakCheckEgressInfo?,
                                        postRekeyEgress: LeakCheckEgressInfo?) -> Bool {
        guard let postRekeyEgress else { return false }
        return preRekeyEgress != postRekeyEgress
    }
}

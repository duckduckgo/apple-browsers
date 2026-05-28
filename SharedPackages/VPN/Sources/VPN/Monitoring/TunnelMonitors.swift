//
//  TunnelMonitors.swift
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
import FoundationExtensions
import Foundation
import os.log

/// Groups the tunnel's monitors behind one start/stop so the subsystem can be
/// exercised without `NEPacketTunnelProvider`. Wires preconditions and routes
/// signals out via injected hooks; the caller decides *when* monitoring runs
/// and *how* to act on each signal.
@MainActor
protocol TunnelMonitoring: AnyObject {
    func start(testImmediately: Bool) async throws
    func stop() async
}

@MainActor
final class TunnelMonitors: TunnelMonitoring {

    private let tunnelFailureMonitor: TunnelFailureMonitoring
    private let latencyMonitor: LatencyMonitoring
    private let entitlementMonitor: EntitlementMonitoring
    private let serverStatusMonitor: ServerStatusMonitoring
    private let keyExpirationTester: KeyExpirationTesting
    private let connectionTester: ConnectionTesting
    private let failureRecoveryHandler: FailureRecoveryHandling

    private weak var tunnelState: (any TunnelStateProviding)?

    private let settings: VPNSettings
    private let events: EventMapping<PacketTunnelProvider.Event>
    private let entitlementCheck: (() async -> Result<Bool, Error>)?
    private let isConnectionTesterEnabled: @MainActor () -> Bool

    private let onReconfigureForMigration: @MainActor () async throws -> Void
    private let onConnectionTestResult: @MainActor (ConnectionTestingResult) -> Void
    private let onFailureRecoveryConfigUpdate: @MainActor (NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult) async throws -> Void
    private let onAccessRevoked: @MainActor () async -> Void

    init(
        tunnelFailureMonitor: TunnelFailureMonitoring,
        latencyMonitor: LatencyMonitoring,
        entitlementMonitor: EntitlementMonitoring,
        serverStatusMonitor: ServerStatusMonitoring,
        keyExpirationTester: KeyExpirationTesting,
        connectionTester: ConnectionTesting,
        failureRecoveryHandler: FailureRecoveryHandling,
        tunnelState: any TunnelStateProviding,
        settings: VPNSettings,
        events: EventMapping<PacketTunnelProvider.Event>,
        entitlementCheck: (() async -> Result<Bool, Error>)?,
        isConnectionTesterEnabled: @escaping @MainActor () -> Bool,
        onReconfigureForMigration: @escaping @MainActor () async throws -> Void,
        onConnectionTestResult: @escaping @MainActor (ConnectionTestingResult) -> Void,
        onFailureRecoveryConfigUpdate: @escaping @MainActor (NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult) async throws -> Void,
        onAccessRevoked: @escaping @MainActor () async -> Void
    ) {
        self.tunnelFailureMonitor = tunnelFailureMonitor
        self.latencyMonitor = latencyMonitor
        self.entitlementMonitor = entitlementMonitor
        self.serverStatusMonitor = serverStatusMonitor
        self.keyExpirationTester = keyExpirationTester
        self.connectionTester = connectionTester
        self.failureRecoveryHandler = failureRecoveryHandler
        self.tunnelState = tunnelState
        self.settings = settings
        self.events = events
        self.entitlementCheck = entitlementCheck
        self.isConnectionTesterEnabled = isConnectionTesterEnabled
        self.onReconfigureForMigration = onReconfigureForMigration
        self.onConnectionTestResult = onConnectionTestResult
        self.onFailureRecoveryConfigUpdate = onFailureRecoveryConfigUpdate
        self.onAccessRevoked = onAccessRevoked

        self.connectionTester.resultHandler = { @MainActor [weak self] result in
            self?.onConnectionTestResult(result)
        }
    }

    // MARK: - TunnelMonitoring

    func start(testImmediately: Bool) async throws {
        await startTunnelFailureMonitor()
        await startLatencyMonitor()
        await startEntitlementMonitor()
        await startServerStatusMonitor()
        await keyExpirationTester.start(testImmediately: testImmediately)

        do {
            try await startConnectionTester(testImmediately: testImmediately)
        } catch {
            Logger.networkProtection.error("🔴 Connection Tester error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func stop() async {
        connectionTester.stop()
        await keyExpirationTester.stop()
        await tunnelFailureMonitor.stop()
        await latencyMonitor.stop()
        await entitlementMonitor.stop()
        await serverStatusMonitor.stop()
    }

    // MARK: - Tunnel Failure Monitor

    private func startTunnelFailureMonitor() async {
        if await tunnelFailureMonitor.isStarted {
            await tunnelFailureMonitor.stop()
        }

        await tunnelFailureMonitor.start { [weak self] result in
            guard let self else { return }

            events.fire(.reportTunnelFailure(result: result))

            switch result {
            case .failureDetected:
                startServerFailureRecovery()
            case .failureRecovered:
                Task {
                    await self.failureRecoveryHandler.stop()
                }
            case .networkPathChanged: break
            }
        }
    }

    private func startServerFailureRecovery() {
        Task { [weak self] in
            guard let self,
                  let server = self.tunnelState?.lastSelectedServer else {
                return
            }
            let excludeLocalNetworks = self.tunnelState?.excludeLocalNetworks ?? false
            await self.failureRecoveryHandler.attemptRecovery(
                to: server,
                excludeLocalNetworks: excludeLocalNetworks,
                dnsSettings: self.settings.dnsSettings) { [weak self] generateConfigResult in

                try await self?.onFailureRecoveryConfigUpdate(generateConfigResult)
                self?.events.fire(.failureRecoveryAttempt(.completed(.unhealthy)))
            }
        }
    }

    // MARK: - Latency Monitor

    private func startLatencyMonitor() async {
        guard let ip = tunnelState?.lastSelectedServerInfo?.ipv4 else {
            await latencyMonitor.stop()
            return
        }
        if await latencyMonitor.isStarted {
            await latencyMonitor.stop()
        }

        if await isEntitlementInvalid() {
            return
        }

        await latencyMonitor.start(serverIP: ip) { [weak self] result in
            guard let self else { return }

            switch result {
            case .error:
                self.events.fire(.reportLatency(result: .error, location: self.settings.selectedLocation))
            case .quality(let quality):
                self.events.fire(.reportLatency(result: .quality(quality), location: self.settings.selectedLocation))
            }
        }
    }

    // MARK: - Entitlement Monitor

    private func startEntitlementMonitor() async {
        if await entitlementMonitor.isStarted {
            await entitlementMonitor.stop()
        }

        guard let entitlementCheck else {
            Logger.networkProtection.fault("Expected entitlement check but didn't find one")
            assertionFailure("Expected entitlement check but didn't find one")
            return
        }

        await entitlementMonitor.start(entitlementCheck: entitlementCheck) { [weak self] result in
            switch result {
            case .invalidEntitlement:
                await self?.onAccessRevoked()
            case .validEntitlement, .error:
                break
            }
        }
    }

    private func isEntitlementInvalid() async -> Bool {
        guard let entitlementCheck, case .success(false) = await entitlementCheck() else { return false }
        return true
    }

    // MARK: - Server Status Monitor

    private func startServerStatusMonitor() async {
        guard let serverName = tunnelState?.lastSelectedServerInfo?.name else {
            await serverStatusMonitor.stop()
            return
        }

        if await serverStatusMonitor.isStarted {
            await serverStatusMonitor.stop()
        }

        await serverStatusMonitor.start(serverName: serverName) { [weak self] status in
            guard status.shouldMigrate else { return }
            Task { [weak self] in
                guard let self else { return }

                self.events.fire(.serverMigrationAttempt(.begin))

                do {
                    try await self.onReconfigureForMigration()
                    self.events.fire(.serverMigrationAttempt(.success))
                } catch {
                    self.events.fire(.serverMigrationAttempt(.failure(error)))
                }
            }
        }
    }

    // MARK: - Connection Tester

    private func startConnectionTester(testImmediately: Bool) async throws {
        guard isConnectionTesterEnabled() else {
            Logger.networkProtectionConnectionTester.log("The connection tester is disabled")
            return
        }

        guard let interfaceName = tunnelState?.tunnelInterfaceName else {
            throw PacketTunnelProvider.ConnectionTesterError.couldNotRetrieveInterfaceNameFromAdapter
        }

        do {
            try await connectionTester.start(tunnelIfName: interfaceName, testImmediately: testImmediately)
        } catch {
            switch error {
            case NetworkProtectionConnectionTester.TesterError.couldNotFindInterface:
                Logger.networkProtectionConnectionTester.log("Printing current proposed utun: \(String(reflecting: self.tunnelState?.tunnelInterfaceName), privacy: .public)")
            default:
                break
            }

            throw PacketTunnelProvider.ConnectionTesterError.testerFailedToStart(internalError: error)
        }
    }
}

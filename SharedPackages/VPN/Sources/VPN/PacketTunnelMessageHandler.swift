//
//  PacketTunnelMessageHandler.swift
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

protocol TunnelStateProviding: AnyObject {
    @MainActor var connectionStatus: ConnectionStatus { get }
    @MainActor var currentServerSelectionMethod: NetworkProtectionServerSelectionMethod { get }
    @MainActor var lastSelectedServerInfo: NetworkProtectionServerInfo? { get }
}

protocol TunnelLifecycleManaging: AnyObject {
    @MainActor func cancelTunnel(with error: Error) async
    @MainActor func updateTunnelConfiguration(updateMethod: PacketTunnelProvider.TunnelUpdateMethod, reassert: Bool) async throws
    @MainActor func restartAdapter() async throws
    @MainActor func resetRegistrationKey()
    @MainActor func removeToken() async throws
    @MainActor func handleAccessRevoked(dueTo error: Error) async
}

protocol SnoozeManaging: AnyObject {
    @MainActor func startSnooze(duration: TimeInterval) async
    @MainActor func cancelSnooze() async
}

// MARK: - PacketTunnelMessageHandler

@MainActor
final class PacketTunnelMessageHandler {

    private var keyStore: NetworkProtectionKeyStore
    private let keyExpirationTester: KeyExpirationTesting
    private let controllerErrorStore: NetworkProtectionTunnelErrorStore
    private let adapter: WireGuardAdapterProtocol
    private let tunnelHealth: NetworkProtectionTunnelHealthStore
    private let notificationsPresenter: VPNNotificationsPresenting
    private let connectionTester: ConnectionTesting
    private let settings: VPNSettings
    private let debugEvents: EventMapping<NetworkProtectionError>

    private weak var tunnelState: (any TunnelStateProviding)?
    private weak var tunnelLifecycle: (any TunnelLifecycleManaging)?
    private weak var snoozeManager: (any SnoozeManaging)?

    init(keyStore: NetworkProtectionKeyStore,
         keyExpirationTester: KeyExpirationTesting,
         controllerErrorStore: NetworkProtectionTunnelErrorStore,
         adapter: WireGuardAdapterProtocol,
         tunnelHealth: NetworkProtectionTunnelHealthStore,
         notificationsPresenter: VPNNotificationsPresenting,
         connectionTester: ConnectionTesting,
         settings: VPNSettings,
         debugEvents: EventMapping<NetworkProtectionError>,
         tunnelState: any TunnelStateProviding,
         tunnelLifecycle: any TunnelLifecycleManaging,
         snoozeManager: any SnoozeManaging) {

        self.keyStore = keyStore
        self.keyExpirationTester = keyExpirationTester
        self.controllerErrorStore = controllerErrorStore
        self.adapter = adapter
        self.tunnelHealth = tunnelHealth
        self.notificationsPresenter = notificationsPresenter
        self.connectionTester = connectionTester
        self.settings = settings
        self.debugEvents = debugEvents
        self.tunnelState = tunnelState
        self.tunnelLifecycle = tunnelLifecycle
        self.snoozeManager = snoozeManager
    }

    // MARK: - Message Routing

    func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let message = ExtensionMessage(rawValue: messageData) else {
            Logger.networkProtectionIPC.error("🔴 Received unknown app message")
            completionHandler?(nil)
            return
        }

        if message != .getDataVolume {
            Logger.networkProtectionIPC.log("⚪️ Received app message: \(String(describing: message), privacy: .public)")
        }

        switch message {
        case .request(let request):
            handleRequest(request, completionHandler: completionHandler)
        case .expireRegistrationKey:
            handleExpireRegistrationKey(completionHandler: completionHandler)
        case .getLastErrorMessage:
            handleGetLastErrorMessage(completionHandler: completionHandler)
        case .getRuntimeConfiguration:
            handleGetRuntimeConfiguration(completionHandler: completionHandler)
        case .isHavingConnectivityIssues:
            handleIsHavingConnectivityIssues(completionHandler: completionHandler)
        case .setSelectedServer(let serverName):
            handleSetSelectedServer(serverName, completionHandler: completionHandler)
        case .getServerLocation:
            handleGetServerLocation(completionHandler: completionHandler)
        case .getServerAddress:
            handleGetServerAddress(completionHandler: completionHandler)
        case .setKeyValidity(let keyValidity):
            handleSetKeyValidity(keyValidity, completionHandler: completionHandler)
        case .resetAllState:
            handleResetAllState(completionHandler: completionHandler)
        case .triggerTestNotification:
            handleSendTestNotification(completionHandler: completionHandler)
        case .setExcludedRoutes:
            // No longer supported, will remove, but keeping the enum to prevent ABI issues
            completionHandler?(nil)
        case .setIncludedRoutes:
            // No longer supported, will remove, but keeping the enum to prevent ABI issues
            completionHandler?(nil)
        case .simulateTunnelFailure:
            simulateTunnelFailure(completionHandler: completionHandler)
        case .simulateTunnelFatalError:
            simulateTunnelFatalError(completionHandler: completionHandler)
        case .simulateTunnelMemoryOveruse:
            simulateTunnelMemoryOveruse(completionHandler: completionHandler)
        case .simulateConnectionInterruption:
            simulateConnectionInterruption(completionHandler: completionHandler)
        case .getDataVolume:
            getDataVolume(completionHandler: completionHandler)
        case .startSnooze(let duration):
            startSnooze(duration, completionHandler: completionHandler)
        case .cancelSnooze:
            cancelSnooze(completionHandler: completionHandler)
        }

        if message != .getDataVolume {
            Logger.networkProtectionIPC.log("⚪️ Message handled: \(String(describing: message), privacy: .public)")
        }
    }

    // MARK: - Request Handling

    private func handleRequest(_ request: ExtensionRequest, completionHandler: ((Data?) -> Void)? = nil) {
        Logger.networkProtectionIPC.log("⚪️ Handling app request: \(String(describing: request), privacy: .public)")
        switch request {
        case .changeTunnelSetting(let change):
            handleSettingChangeAppRequest(change, completionHandler: completionHandler)
            completionHandler?(nil)
        case .command(let command):
            handle(command, completionHandler: completionHandler)
        }
    }

    private func handleSettingChangeAppRequest(_ change: VPNSettings.Change, completionHandler: ((Data?) -> Void)? = nil) {
        settings.apply(change: change)
    }

    private func handle(_ command: VPNCommand, completionHandler: ((Data?) -> Void)? = nil) {
        switch command {
        case .removeSystemExtension:
            // Since the system extension is being removed we may as well reset all state
            handleResetAllState(completionHandler: completionHandler)
        case .expireRegistrationKey:
            handleExpireRegistrationKey(completionHandler: completionHandler)
        case .sendTestNotification:
            handleSendTestNotification(completionHandler: completionHandler)
        case .simulateSubscriptionExpirationInTunnel:
            Task { [weak self] in
                await self?.tunnelLifecycle?.handleAccessRevoked(dueTo: PacketTunnelProvider.TunnelError.simulateSubscriptionExpiration)
                completionHandler?(nil)
            }
        case .removeVPNConfiguration:
            // Since the VPN configuration is being removed we may as well reset all state
            handleResetAllState(completionHandler: completionHandler)
        case .restartAdapter:
            handleRestartAdapter(completionHandler: completionHandler)
        case .uninstallVPN:
            // Since the VPN configuration is being removed we may as well reset all state
            handleResetAllState(completionHandler: completionHandler)
        case .quitAgent:
            // No-op since this is intended for the agent app
            break
        case .createLogSnapshot:
            if #available(macOS 12.0, iOS 15.0, *) {
                handleCreateLogSnapshot(completionHandler: completionHandler)
            }
        }
    }

    // MARK: - Individual Handlers

    private func handleExpireRegistrationKey(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            keyStore.currentExpirationDate = Date()
            await keyExpirationTester.rekeyIfExpired()
            completionHandler?(nil)
        }
    }

    private func handleGetLastErrorMessage(completionHandler: ((Data?) -> Void)? = nil) {
        let response = controllerErrorStore.lastErrorMessage.map(ExtensionMessageString.init)
        completionHandler?(response?.rawValue)
    }

    private func handleGetRuntimeConfiguration(completionHandler: ((Data?) -> Void)? = nil) {
        adapter.getRuntimeConfiguration { settings in
            let response = settings.map(ExtensionMessageString.init)
            completionHandler?(response?.rawValue)
        }
    }

    private func handleIsHavingConnectivityIssues(completionHandler: ((Data?) -> Void)? = nil) {
        let response = ExtensionMessageBool(tunnelHealth.isHavingConnectivityIssues)
        completionHandler?(response.rawValue)
    }

    private func handleSetSelectedServer(_ serverName: String?, completionHandler: ((Data?) -> Void)? = nil) {
        Task { [weak self] in
            guard let self else {
                completionHandler?(nil)
                return
            }

            guard let serverName else {
                if case .endpoint = settings.selectedServer {
                    settings.selectedServer = .automatic

                    if case .connected = tunnelState?.connectionStatus,
                       let currentMethod = tunnelState?.currentServerSelectionMethod {
                        try? await tunnelLifecycle?.updateTunnelConfiguration(
                            updateMethod: .selectServer(currentMethod),
                            reassert: true)
                    }
                }
                completionHandler?(nil)
                return
            }

            guard settings.selectedServer.stringValue != serverName else {
                completionHandler?(nil)
                return
            }

            settings.selectedServer = .endpoint(serverName)
            if case .connected = tunnelState?.connectionStatus {
                try? await tunnelLifecycle?.updateTunnelConfiguration(
                    updateMethod: .selectServer(.preferredServer(serverName: serverName)),
                    reassert: true)
            }
            completionHandler?(nil)
        }
    }

    private func handleGetServerLocation(completionHandler: ((Data?) -> Void)? = nil) {
        guard let attributes = tunnelState?.lastSelectedServerInfo?.attributes else {
            completionHandler?(nil)
            return
        }

        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(attributes), let encodedJSONString = String(data: encoded, encoding: .utf8) else {
            assertionFailure("Failed to encode server attributes")
            completionHandler?(nil)
            return
        }

        completionHandler?(ExtensionMessageString(encodedJSONString).rawValue)
    }

    private func handleGetServerAddress(completionHandler: ((Data?) -> Void)? = nil) {
        let response = tunnelState?.lastSelectedServerInfo?.endpoint.map { ExtensionMessageString($0.host.hostWithoutPort) }
        completionHandler?(response?.rawValue)
    }

    private func handleSetKeyValidity(_ keyValidity: TimeInterval?, completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            await keyExpirationTester.setKeyValidity(keyValidity)
            completionHandler?(nil)
        }
    }

    private func handleResetAllState(completionHandler: ((Data?) -> Void)? = nil) {
        tunnelLifecycle?.resetRegistrationKey()
        Task { [weak self] in
#if os(macOS)
            try? await self?.tunnelLifecycle?.removeToken()
#endif

            completionHandler?(nil)
            await self?.tunnelLifecycle?.cancelTunnel(with: PacketTunnelProvider.TunnelError.appRequestedCancellation)
        }
    }

    private func handleRestartAdapter(completionHandler: ((Data?) -> Void)? = nil) {
        Task { [weak self] in
            do {
                try await self?.tunnelLifecycle?.restartAdapter()
                completionHandler?(nil)
            } catch {
                completionHandler?(nil)
            }
        }
    }

    private func handleSendTestNotification(completionHandler: ((Data?) -> Void)? = nil) {
        notificationsPresenter.showTestNotification()
        completionHandler?(nil)
    }

    // Used for the iOS debug menu by DuckDuckGo VPN developers
    @available(macOS 12.0, iOS 15.0, *)
    private func handleCreateLogSnapshot(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            do {
                let logCollector = NetworkProtectionDebugLogCollector()
                let logFileURL = try await logCollector.createLogSnapshot()
                let response = ExtensionMessageString(logFileURL.path)
                completionHandler?(response.rawValue)
            } catch {
                let errorResponse = ExtensionMessageString("Error: \(error.localizedDescription)")
                completionHandler?(errorResponse.rawValue)
            }
        }
    }

    private func simulateTunnelFailure(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            Logger.networkProtection.log("Simulating tunnel failure")

            adapter.stop { [weak self] error in
                if let error {
                    self?.debugEvents.fire(error.networkProtectionError)
                    Logger.networkProtection.error("🔴 Failed to stop WireGuard adapter: \(error.localizedDescription, privacy: .public)")
                }

                completionHandler?(error.map { ExtensionMessageString($0.localizedDescription).rawValue })
            }
        }
    }

    private func simulateTunnelFatalError(completionHandler: ((Data?) -> Void)? = nil) {
        completionHandler?(nil)
        fatalError("Simulated PacketTunnelProvider crash")
    }

    private func simulateTunnelMemoryOveruse(completionHandler: ((Data?) -> Void)? = nil) {
        completionHandler?(nil)
        var array = [String]()
        while true {
            array.append("Crash")
        }
    }

    private func simulateConnectionInterruption(completionHandler: ((Data?) -> Void)? = nil) {
        connectionTester.failNextTest()
        completionHandler?(nil)
    }

    private func getDataVolume(completionHandler: ((Data?) -> Void)? = nil) {
        Task {
            guard let (received, sent) = try? await adapter.getBytesTransmitted() else {
                completionHandler?(nil)
                return
            }

            let string = "\(received),\(sent)"
            completionHandler?(ExtensionMessageString(string).rawValue)
        }
    }

    private func startSnooze(_ duration: TimeInterval, completionHandler: ((Data?) -> Void)? = nil) {
        Task { [weak self] in
            await self?.snoozeManager?.startSnooze(duration: duration)
            completionHandler?(nil)
        }
    }

    private func cancelSnooze(completionHandler: ((Data?) -> Void)? = nil) {
        Task { [weak self] in
            await self?.snoozeManager?.cancelSnooze()
            completionHandler?(nil)
        }
    }
}

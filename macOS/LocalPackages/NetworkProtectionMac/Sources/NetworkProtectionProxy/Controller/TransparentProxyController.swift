//
//  TransparentProxyController.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation
import NetworkExtension
import VPN
import os.log
import PixelKit
import SystemExtensions
import VPNAppState
import VPNExtensionManagement

/// Controller for ``TransparentProxyProvider``
///
@MainActor
public final class TransparentProxyController {

    public enum StartError: Error {
        case attemptToStartWithoutBackingActiveFeatures
        case couldNotRetrieveProtocolConfiguration
        case couldNotEncodeSettingsSnapshot
        case failedToLoadConfiguration(_ error: Error)
        case failedToSaveConfiguration(_ error: Error)
        case failedToStartProvider(_ error: Error)
    }

    public typealias ManagerSetupCallback = (_ manager: NETransparentProxyManager) async -> Void

    /// Dry mode means this won't really do anything to start or stop the proxy.
    ///
    /// This is useful for testing.
    ///
    private let dryMode: Bool

    /// The proxy extension resolver.
    ///
    private let extensionResolver: VPNExtensionResolving

    /// The event handler
    ///
    private let eventHandler: TransparentProxyControllerEventHandling

    /// Callback to set up a ``NETransparentProxyManager``.
    ///
    public let setup: ManagerSetupCallback

    private var internalManager: NETransparentProxyManager?
    private let vpnAppState: VPNAppState
    public let settings: TransparentProxySettings
    private let notificationCenter: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializers

    /// Default initializer.
    ///
    /// - Parameters:
    ///     - extensionResolver: the proxy extension resolver.
    ///     - settings: the settings to use for this proxy.
    ///     - dryMode: whether this class is initialized in dry mode.
    ///     - setup: a callback that will be called whenever a ``NETransparentProxyManager`` needs
    ///         to be setup.
    ///
    public init(extensionResolver: VPNExtensionResolving,
                vpnAppState: VPNAppState,
                settings: TransparentProxySettings,
                notificationCenter: NotificationCenter = .default,
                dryMode: Bool = false,
                eventHandler: TransparentProxyControllerEventHandler,
                setup: @escaping ManagerSetupCallback) {

        self.dryMode = dryMode
        self.extensionResolver = extensionResolver
        self.notificationCenter = notificationCenter
        self.vpnAppState = vpnAppState
        self.settings = settings
        self.setup = setup
        self.eventHandler = eventHandler

        subscribeToProviderConfigurationChanges()
        subscribeToSettingsChanges()
    }

    // MARK: - Relay Settings Changes

    private func subscribeToProviderConfigurationChanges() {
        notificationCenter.publisher(for: .NEVPNConfigurationChange)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                self.reloadProviderConfiguration()
            }
            .store(in: &cancellables)
    }

    private func reloadProviderConfiguration() {
        Task { @MainActor in
            try? await self.manager?.loadFromPreferences()
        }
    }

    private func subscribeToSettingsChanges() {
        settings.changePublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: relay(_:))
            .store(in: &cancellables)
    }

    private func relay(_ change: TransparentProxySettings.Change) {
        Task { @MainActor in
            guard let session = await session else {
                return
            }

            switch session.status {
            case .connected, .connecting, .reasserting:
                break
            default:
                return
            }

            try TransparentProxySession(session).send(.changeSetting(change, responseHandler: {
                // no-op
            }))
        }
    }

    // MARK: - Setting up NETransparentProxyManager

    /// Loads the proxy configuration.
    ///
    public var manager: NETransparentProxyManager? {
        get async {
            if let internalManager {
                return internalManager
            }

            let extensionID = await extensionResolver.activeExtensionBundleID

            let manager = try? await NETransparentProxyManager.loadAllFromPreferences().first { manager in
                (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionID
            }
            internalManager = manager
            return manager
        }
    }

    /// Loads an existing configuration or creates a new one, if one doesn't exist.
    ///
    /// - Returns a properly configured `NETransparentProxyManager`.
    ///
    public func loadOrMakeManager() async throws -> NETransparentProxyManager {
        let manager = await manager ?? {
            let manager = NETransparentProxyManager()
            internalManager = manager
            return manager
        }()

        try await setupAndSave(manager)
        return manager
    }

    @MainActor
    private func setupAndSave(_ manager: NETransparentProxyManager) async throws {
        await setup(manager)
        try setupAdditionalProviderConfiguration(manager)

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }

    private func setupAdditionalProviderConfiguration(_ manager: NETransparentProxyManager) throws {
        guard let providerProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            throw StartError.couldNotRetrieveProtocolConfiguration
        }

        var providerConfiguration = providerProtocol.providerConfiguration ?? [String: Any]()

        guard let encodedSettings = try? JSONEncoder().encode(settings.snapshot()),
              let encodedSettingsString = String(data: encodedSettings, encoding: .utf8) else {

            throw StartError.couldNotEncodeSettingsSnapshot
        }

        providerConfiguration[TransparentProxySettingsSnapshot.key] = encodedSettingsString as NSString
        providerProtocol.providerConfiguration = providerConfiguration

    }

    // MARK: - Connection & Session

    /// Checks whether a connection is the one being used by this proxy, not loading our configuration from settings.
    ///
    /// Not loading the connection from settings can be good in some circumstances, as it triggers a status updates.  This is particularly
    /// useful when we're comparing the connection from an event triggered by a status update, so the proxy won't enter an infinite
    /// loop of updating status > loading config > updating status > etc.
    ///
    public func isUsingConnection(_ connection: NEVPNConnection) -> Bool {
        internalManager?.connection === connection
    }

    public var connection: NEVPNConnection? {
        get async {
            await manager?.connection
        }
    }

    public var session: NETunnelProviderSession? {
        get async {
            guard let manager = await manager,
                  let session = manager.connection as? NETunnelProviderSession else {

                // The active connection is not running, so there's no session, this is acceptable
                return nil
            }

            return session
        }
    }

    // MARK: - Connection

    public var status: NEVPNStatus {
        get async {
            await connection?.status ?? .disconnected
        }
    }

    // MARK: - Start & stop the proxy

    public var isRequiredForActiveFeatures: Bool {
        vpnAppState.isUsingSystemExtension
        && (settings.appRoutingRules.count > 0 || settings.excludedDomains.count > 0)
    }

    public func start() async throws {
        guard isRequiredForActiveFeatures else {
            let error = StartError.attemptToStartWithoutBackingActiveFeatures
            eventHandler.handle(event: .startAttempt(.prevented(error)))
            throw error
        }

        eventHandler.handle(event: .startAttempt(.begin))

        let manager: NETransparentProxyManager

        do {
            manager = try await loadOrMakeManager()
            try manager.connection.startVPNTunnel(options: [:])

            eventHandler.handle(event: .startAttempt(.success))
        } catch {
            let error = StartError.failedToStartProvider(error)
            eventHandler.handle(event: .startAttempt(.failure(error)))
            throw error
        }
    }

    public func stop() async {
        await connection?.stopVPNTunnel()
        eventHandler.handle(event: .stopped)
    }
}

// MARK: - Events & Pixels

extension TransparentProxyController {

    public enum Event {
        case startAttempt(_ step: StartAttemptStep)
        case stopped
    }

    public enum StartAttemptStep: PixelKitEvent {
        /// Abnormal attempt to start the proxy when it wasn't needed
        case prevented(_ error: Error)

        /// Attempt to start the proxy begins
        case begin

        /// Attempt to start the proxy succeeds
        case success

        /// Attempt to start the proxy fails
        case failure(_ error: Error)

        public var name: String {
            switch self {
            case .prevented:
                return "vpn_proxy_controller_start_prevented"

            case .begin:
                return "vpn_proxy_controller_start_attempt"

            case .success:
                return "vpn_proxy_controller_start_success"

            case .failure:
                return "vpn_proxy_controller_start_failure"
            }
        }

        public var parameters: [String: String]? {
            return nil
        }

    }
}

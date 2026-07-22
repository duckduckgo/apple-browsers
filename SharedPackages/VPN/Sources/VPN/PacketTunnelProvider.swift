//
//  PacketTunnelProvider.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import Combine
import Common
import ConcurrencyExtensions
import Foundation
import FoundationExtensions
import Network
import NetworkExtension
import os.log
import PixelKit
import UserNotifications

open class PacketTunnelProvider: NEPacketTunnelProvider {

    public enum Event {
        case userBecameActive
        case connectionTesterStatusChange(_ status: ConnectionTesterStatus, server: String)
        case reportConnectionAttempt(attempt: ConnectionAttempt, source: ConnectionAttemptSource)
        case tunnelStartAttempt(_ step: TunnelStartAttemptStep)
        case tunnelStopAttempt(_ step: TunnelStopAttemptStep)
        case tunnelUpdateAttempt(_ step: TunnelUpdateAttemptStep)
        case tunnelWakeAttempt(_ step: TunnelWakeAttemptStep)
        case tunnelStartOnDemandWithoutAccessToken(_ error: Error)
        case reportTunnelFailure(result: NetworkProtectionTunnelFailureMonitor.Result)
        case reportLatency(result: NetworkProtectionLatencyMonitor.Result, location: VPNSettings.SelectedLocation)
        case rekeyAttempt(_ step: RekeyAttemptStep)
        case failureRecoveryAttempt(_ step: FailureRecoveryStep)
        case serverMigrationAttempt(_ step: ServerMigrationAttemptStep)

        case adapterEndTemporaryShutdownStateAttemptFailure(Error)
        case adapterEndTemporaryShutdownStateRecoverySuccess
        case adapterEndTemporaryShutdownStateRecoveryFailure(Error)

        case connectionFailureLoopDetected(_ error: Error)
    }

    public enum AttemptStep: CustomDebugStringConvertible {
        case begin
        case success
        case failure(_ error: Error)

        public var debugDescription: String {
            switch self {
            case .begin:
                "Begin"
            case .success:
                "Success"
            case .failure(let error):
                "Failure \(error.localizedDescription)"
            }
        }
    }

    public typealias TunnelStartAttemptStep = AttemptStep
    public typealias TunnelStopAttemptStep = AttemptStep
    public typealias TunnelUpdateAttemptStep = AttemptStep
    public typealias TunnelWakeAttemptStep = AttemptStep
    public typealias RekeyAttemptStep = AttemptStep
    public typealias ServerMigrationAttemptStep = AttemptStep

    public enum ConnectionAttempt: CustomDebugStringConvertible {
        case connecting
        case success
        case failure

        public var debugDescription: String {
            switch self {
            case .connecting:
                "Connecting"
            case .success:
                "Success"
            case .failure:
                "Failure"
            }
        }
    }

    public enum ConnectionAttemptSource: String {
        case start
        case rekey
        case serverChange
        case locationChange
        case adapterRestart
        case failureRecovery
        case serverMigration

        /// Whether attempts from this source should be recorded in the connection-attempt SLO.
        public var isConnectionAttempt: Bool {
            switch self {
            case .start, .serverChange, .locationChange,
                 .adapterRestart, .failureRecovery, .serverMigration:
                return true
            case .rekey:
                return false
            }
        }

        var preservesFailureRecoveryDuringReassertUpdate: Bool {
            self == .failureRecovery
        }
    }

    public enum ConnectionTesterStatus {
        case failed(duration: Duration)
        case recovered(duration: Duration, failureCount: Int)

        public enum Duration: String {
            case immediate
            case extended
        }
    }

    // MARK: - Error Handling

    public enum TunnelError: LocalizedError, CustomNSError, SilentErrorConvertible {
        // Tunnel Setup Errors - 0+
        case startingTunnelWithoutAuthToken(internalError: Error?)
        case couldNotGenerateTunnelConfiguration(internalError: Error)
        case simulateTunnelFailureError
        case settingsMissing
        case simulateSubscriptionExpiration
        case tokenReset

        // Subscription Errors - 100+
        case vpnAccessRevoked(_ underlyingError: Error)
        case vpnAccessRevokedDetectedByMonitorCheck

        // State Reset - 200+
        case appRequestedCancellation

        /// Integer error codes for `TunnelError`, used as the single source of truth
        /// for serialization across the XPC / process boundary.
        public enum Code: Int, CaseIterable {
            // Tunnel Setup Errors - 0+
            case startingTunnelWithoutAuthToken = 0
            case couldNotGenerateTunnelConfiguration = 1
            case simulateTunnelFailureError = 2
            case settingsMissing = 3
            case simulateSubscriptionExpiration = 4
            case tokenReset = 5
            // Subscription Errors - 100+
            case vpnAccessRevoked = 100
            case vpnAccessRevokedDetectedByMonitorCheck = 101
            // State Reset - 200+
            case appRequestedCancellation = 200
        }

        public var errorDescription: String? {
            switch self {
            case .startingTunnelWithoutAuthToken(let internalError):
                return "Missing auth token at startup: \(internalError.debugDescription)"
            case .vpnAccessRevoked, .vpnAccessRevokedDetectedByMonitorCheck:
                return "VPN disconnected due to expired subscription"
            case .couldNotGenerateTunnelConfiguration(let internalError):
                return "Failed to generate a tunnel configuration: \(internalError.localizedDescription)"
            case .simulateTunnelFailureError:
                return "Simulated a tunnel error as requested"
            case .settingsMissing:
                return "VPN settings are missing or invalid"
            case .simulateSubscriptionExpiration:
                return nil
            case .tokenReset:
                return "Abnormal situation caused the token to be reset"
            case .appRequestedCancellation:
                return nil
            }
        }

        /// The `Code` for this error — exhaustive switch ensures new cases are not forgotten.
        public var code: Code {
            switch self {
            case .startingTunnelWithoutAuthToken: return .startingTunnelWithoutAuthToken
            case .couldNotGenerateTunnelConfiguration: return .couldNotGenerateTunnelConfiguration
            case .simulateTunnelFailureError: return .simulateTunnelFailureError
            case .settingsMissing: return .settingsMissing
            case .simulateSubscriptionExpiration: return .simulateSubscriptionExpiration
            case .tokenReset: return .tokenReset
            case .vpnAccessRevoked: return .vpnAccessRevoked
            case .vpnAccessRevokedDetectedByMonitorCheck: return .vpnAccessRevokedDetectedByMonitorCheck
            case .appRequestedCancellation: return .appRequestedCancellation
            }
        }

        public var errorCode: Int { code.rawValue }

        public var errorUserInfo: [String: Any] {
            switch self {
            case .simulateTunnelFailureError,
                    .settingsMissing,
                    .vpnAccessRevokedDetectedByMonitorCheck,
                    .simulateSubscriptionExpiration,
                    .tokenReset,
                    .appRequestedCancellation:
                return [:]
            case .couldNotGenerateTunnelConfiguration(let underlyingError),
                    .vpnAccessRevoked(let underlyingError):
                return [NSUnderlyingErrorKey: underlyingError]
            case .startingTunnelWithoutAuthToken(let underlyingError):
                if let underlyingError {
                    return [NSUnderlyingErrorKey: underlyingError]
                } else {
                    return [:]
                }
            }
        }

        public var asSilentError: KnownFailure.SilentError? {
            guard case .couldNotGenerateTunnelConfiguration(let internalError) = self,
                  let clientError = internalError as? NetworkProtectionClientError,
                  case .failedToFetchRegisteredServers = clientError else {
                return nil
            }

            return .registeredServerFetchingFailed
        }
    }

    // MARK: - WireGuard

    private let wireGuardAdapterEventHandler: WireGuardAdapterEventHandling
    private var adapter: WireGuardAdapterProtocol!
    private var messageHandler: PacketTunnelMessageHandler!

    // MARK: - Timers Support

    private let timerQueue = DispatchQueue(label: "com.duckduckgo.network-protection.PacketTunnelProvider.timerQueue")

    // MARK: - Status

    @MainActor
    public override var reasserting: Bool {
        get {
            super.reasserting
        }
        set {
            if newValue {
                connectionStatus = .reasserting
            } else {
                connectionStatus = .connected(connectedDate: Date())
            }

            super.reasserting = newValue
        }
    }

    @MainActor
    public var connectionStatus: ConnectionStatus = .default {
        didSet {
            guard connectionStatus != oldValue else {
                return
            }

            if case .connected = connectionStatus {
                self.notificationsPresenter.showConnectedNotification(
                    serverLocation: lastSelectedServerInfo?.serverLocation,
                    snoozeEnded: snoozeJustEnded
                )

                if !isEnforceRoutesActive {
                    self.notificationsPresenter.showStrictRoutingReminderNotification()
                }

                snoozeJustEnded = false
            }

            handleConnectionStatusChange(old: oldValue, new: connectionStatus)
        }
    }

    public var isKillSwitchEnabled: Bool {
        guard #available(macOS 11.0, iOS 14.2, *) else { return false }
        return self.protocolConfiguration.enforceRoutes || self.protocolConfiguration.includeAllNetworks
    }

    /// Whether strict routing is actually applied to this tunnel session.
    ///
    /// Inside the tunnel, the applied truth lives on `protocolConfiguration` (bound to the NECP session
    /// at creation time), not on `settings.enforceRoutes` — the latter is user intent for the *next*
    /// session and can be stale here (e.g. the macOS system extension can't read the app's defaults, and
    /// system/on-demand starts don't deliver a settings snapshot). Read this, not `settings`, for
    /// routing-dependent behavior in the extension.
    public var isEnforceRoutesActive: Bool {
        guard #available(macOS 11.0, iOS 14.2, *) else { return false }
        return self.protocolConfiguration.enforceRoutes
    }

    // MARK: - Tunnel Settings

    public let settings: VPNSettings

    // MARK: - User Defaults

    private let defaults: UserDefaults

    // MARK: - Server Selection

    private let serverSelectionResolver: VPNServerSelectionResolving

    @MainActor
    var lastSelectedServer: NetworkProtectionServer? {
        didSet {
            if lastSelectedServer != oldValue {
                bumpTunnelPathGeneration()
            }
            lastSelectedServerInfoPublisher.send(lastSelectedServer?.serverInfo)
        }
    }

    @MainActor
    private var tunnelPathGeneration: UInt64 = 0

    @MainActor
    public var lastSelectedServerInfo: NetworkProtectionServerInfo? {
        lastSelectedServer?.serverInfo
    }

    public let lastSelectedServerInfoPublisher = CurrentValueSubject<NetworkProtectionServerInfo?, Never>(nil)

    // MARK: - User Notifications

    private let notificationsPresenter: VPNNotificationsPresenting

    // MARK: - Registration Key

    private var keyStore: NetworkProtectionKeyStore

    public let tokenHandlerProvider: any SubscriptionTokenHandling

    private var keyRotator: KeyRotator!

    @MainActor
    func resetRegistrationKey() {
        keyRotator.resetRegistrationKey()
    }

    private func subscriptionAccessErrorHandler(_ error: Error) async {
        switch error {
        case TunnelError.vpnAccessRevoked:
            await handleAccessRevoked(dueTo: error)
        default:
            break
        }
    }

    // MARK: - Bandwidth Analyzer

    /// Updates the bandwidth analyzer with the latest data from the WireGuard Adapter
    ///
    public func updateBandwidthAnalyzer() async {
        guard let (rx, tx) = try? await adapter.getBytesTransmitted() else {
            await self.bandwidthAnalyzer.preventIdle()
            return
        }

        await bandwidthAnalyzer.record(rxBytes: rx, txBytes: tx)
    }

    // MARK: - Connection tester

    private static let connectionTesterExtendedFailuresCount = 8
    private var isConnectionTesterEnabled: Bool = true

    @MainActor
    private var keyExpirationTester: KeyExpirationTesting!

    private var tunnelFailureMonitor: TunnelFailureMonitoring!

    public let latencyMonitor: LatencyMonitoring
    public let entitlementMonitor: EntitlementMonitoring

    private var lastTestFailed = false
    private let bandwidthAnalyzer: BandwidthAnalyzing
    private let tunnelHealth: NetworkProtectionTunnelHealthStore
    private let controllerErrorStore: NetworkProtectionTunnelErrorStore
    private let knownFailureStore: NetworkProtectionKnownFailureStore
    private let errorStateReset: VPNErrorStateReset
    private let snoozeTimingStore: NetworkProtectionSnoozeTimingStore
    private let wireGuardInterface: WireGuardGoInterface
    private let deviceManager: NetworkProtectionDeviceManagement
    public let serverStatusMonitor: ServerStatusMonitoring

    // MARK: - WideEvent

    private var wideEvent: WideEventManaging
    private var connectionWideEventData: VPNConnectionWideEventData?
    private let connectionTunnelTimeoutInterval: TimeInterval = .minutes(15)
    private var leakCheckService: VPNLeakCheckService?

    // MARK: - Connection Tester

    private let connectionTester: ConnectionTesting

    // MARK: - Monitors

    private var tunnelMonitors: TunnelMonitors!

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializers

    private let keychainType: KeychainType
    private let debugEvents: EventMapping<NetworkProtectionError>
    private let providerEvents: EventMapping<Event>
    public let entitlementCheck: (() async -> Result<Bool, Error>)?
    public let loopDetector: ConnectionFailureLoopDetector
    private let heartbeatStore: TunnelHeartbeatStore?
    private var heartbeatTask: Task<Never, Error>? {
        willSet { heartbeatTask?.cancel() }
    }
    private static let heartbeatInterval: TimeInterval = 15

    @MainActor
    public init(notificationsPresenter: VPNNotificationsPresenting,
                tunnelHealthStore: NetworkProtectionTunnelHealthStore,
                controllerErrorStore: NetworkProtectionTunnelErrorStore,
                knownFailureStore: NetworkProtectionKnownFailureStore = NetworkProtectionKnownFailureStore(),
                snoozeTimingStore: NetworkProtectionSnoozeTimingStore,
                wireGuardInterface: WireGuardGoInterface,
                keychainType: KeychainType,
                keyStore: NetworkProtectionKeyStore? = nil,
                tokenHandlerProvider: any SubscriptionTokenHandling,
                debugEvents: EventMapping<NetworkProtectionError>,
                providerEvents: EventMapping<Event>,
                settings: VPNSettings,
                defaults: UserDefaults,
                wideEvent: WideEventManaging? = nil,
                bandwidthAnalyzer: BandwidthAnalyzing? = nil,
                latencyMonitor: LatencyMonitoring = NetworkProtectionLatencyMonitor(),
                entitlementMonitor: EntitlementMonitoring = NetworkProtectionEntitlementMonitor(),
                deviceManager: NetworkProtectionDeviceManagement? = nil,
                serverStatusMonitor: ServerStatusMonitoring? = nil,
                serverSelectionResolver: VPNServerSelectionResolving? = nil,
                connectionTester: ConnectionTesting? = nil,
                adapter: WireGuardAdapterProtocol? = nil,
                keyExpirationTester: KeyExpirationTesting? = nil,
                tunnelFailureMonitor: TunnelFailureMonitoring? = nil,
                failureRecoveryHandler: FailureRecoveryHandling? = nil,
                entitlementCheck: (() async -> Result<Bool, Error>)?,
                loopDetector: ConnectionFailureLoopDetector,
                heartbeatStore: TunnelHeartbeatStore? = nil) {
        Logger.networkProtectionMemory.log("[+] PacketTunnelProvider")

        self.notificationsPresenter = notificationsPresenter
        self.keychainType = keychainType
        self.tokenHandlerProvider = tokenHandlerProvider
        self.debugEvents = debugEvents
        self.providerEvents = providerEvents
        self.tunnelHealth = tunnelHealthStore
        self.controllerErrorStore = controllerErrorStore
        self.knownFailureStore = knownFailureStore
        self.errorStateReset = VPNErrorStateReset(errorMessageStore: controllerErrorStore,
                                                  knownFailureStore: knownFailureStore)
        self.snoozeTimingStore = snoozeTimingStore
        self.wireGuardInterface = wireGuardInterface
        self.settings = settings
        self.defaults = defaults
        self.bandwidthAnalyzer = bandwidthAnalyzer ?? NetworkProtectionConnectionBandwidthAnalyzer()
        self.latencyMonitor = latencyMonitor
        self.entitlementMonitor = entitlementMonitor
        self.entitlementCheck = entitlementCheck
        self.loopDetector = loopDetector
        self.heartbeatStore = heartbeatStore

        self.wideEvent = wideEvent ?? WideEvent(featureFlagProvider: WideEventFeatureFlagProvider(settings: settings))

        let keyStore = keyStore ?? NetworkProtectionKeychainKeyStore(
            keychainType: keychainType,
            errorEvents: debugEvents
        )
        self.keyStore = keyStore

        self.deviceManager = deviceManager ?? NetworkProtectionDeviceManager(
            environment: settings.selectedEnvironment,
            tokenHandler: tokenHandlerProvider,
            keyStore: keyStore,
            errorEvents: debugEvents
        )

        self.serverStatusMonitor = serverStatusMonitor ?? NetworkProtectionServerStatusMonitor(
            networkClient: NetworkProtectionBackendClient(environment: settings.selectedEnvironment),
            tokenHandler: tokenHandlerProvider
        )

        self.serverSelectionResolver = serverSelectionResolver ?? {
            let locationRepository = NetworkProtectionLocationListCompositeRepository(
                environment: settings.selectedEnvironment,
                tokenHandler: tokenHandlerProvider,
                errorEvents: debugEvents
            )
            return VPNServerSelectionResolver(locationListRepository: locationRepository, vpnSettings: settings)
        }()

        self.wireGuardAdapterEventHandler = WireGuardAdapterEventHandler(
            providerEvents: providerEvents,
            settings: settings,
            notificationsPresenter: notificationsPresenter
        )

        self.connectionTester = connectionTester ?? NetworkProtectionConnectionTester(timerQueue: timerQueue)

        super.init()

        self.adapter = adapter ?? WireGuardAdapter(
            with: self,
            wireGuardInterface: wireGuardInterface,
            eventHandler: wireGuardAdapterEventHandler
        ) { logLevel, message in
            if logLevel == .error {
                Logger.networkProtectionWireGuard.error("🔴 Received error from adapter: \(message, privacy: .public)")
            } else {
                Logger.networkProtectionWireGuard.log("Received message from adapter: \(message, privacy: .public)")
            }
        }

        self.keyRotator = KeyRotator(
            keyStore: keyStore,
            settings: settings,
            events: providerEvents,
            rotateKey: { @MainActor [weak self] in
                // Provider deinit mid-rekey: surface as failure rather than silently succeeding,
                // so .rekeyAttempt(.success) is never fired for a rekey that didn't run.
                guard let self else { throw CancellationError() }
                try await self.updateTunnelConfiguration(
                    updateMethod: .selectServer(self.currentServerSelectionMethod),
                    reassert: false,
                    regenerateKey: true,
                    attemptSource: .rekey)
            }
        )

        self.keyExpirationTester = keyExpirationTester ?? KeyExpirationTester(
            keyStore: keyStore,
            settings: settings
        ) { @MainActor [weak self] in
            guard let self else { return false }
            self.providerEvents.fire(.userBecameActive)
            await self.updateBandwidthAnalyzer()
            return await self.bandwidthAnalyzer.isConnectionIdle()
        } rekey: { @MainActor [weak self] in
            guard let self else { return }
            let preRekeyEgress = self.currentEgressInfo()
            do {
                try await self.keyRotator.rekey()
            } catch {
                await self.subscriptionAccessErrorHandler(error)
                throw error
            }
            let postRekeyEgress = self.currentEgressInfo()
            if VPNLeakCheckService.shouldScheduleCheckAfterRekey(preRekey: preRekeyEgress, postRekey: postRekeyEgress) {
                await self.leakCheckService?.scheduleCheck(trigger: .rekey)
            }
        }

        self.tunnelFailureMonitor = tunnelFailureMonitor ?? NetworkProtectionTunnelFailureMonitor(
            handshakeReporter: self.adapter
        )

        let resolvedFailureRecoveryHandler = failureRecoveryHandler ?? FailureRecoveryHandler(
            deviceManager: self.deviceManager,
            reassertingControl: self,
            eventHandler: { [weak self] step in
                self?.providerEvents.fire(.failureRecoveryAttempt(step))
            }
        )

        self.tunnelMonitors = TunnelMonitors(
            tunnelFailureMonitor: self.tunnelFailureMonitor,
            latencyMonitor: self.latencyMonitor,
            entitlementMonitor: self.entitlementMonitor,
            serverStatusMonitor: self.serverStatusMonitor,
            keyExpirationTester: self.keyExpirationTester,
            connectionTester: self.connectionTester,
            failureRecoveryHandler: resolvedFailureRecoveryHandler,
            tunnelState: self,
            settings: self.settings,
            events: self.providerEvents,
            entitlementCheck: self.entitlementCheck,
            isConnectionTesterEnabled: { [weak self] in
                self?.isConnectionTesterEnabled ?? true
            },
            onReconfigureForMigration: { @MainActor [weak self] in
                guard let self else { throw CancellationError() }
                try await self.updateTunnelConfiguration(
                    updateMethod: .selectServer(self.currentServerSelectionMethod),
                    reassert: true,
                    regenerateKey: true,
                    attemptSource: .serverMigration)
            },
            onConnectionTestResult: { @MainActor [weak self] result in
                self?.handleConnectionTestResult(result)
            },
            onFailureRecoveryConfigUpdate: { @MainActor [weak self] result in
                try await self?.handleFailureRecoveryConfigUpdate(result: result)
            },
            onAccessRevoked: { @MainActor [weak self] in
                await self?.handleAccessRevoked(dueTo: TunnelError.vpnAccessRevokedDetectedByMonitorCheck)
            }
        )

        self.messageHandler = PacketTunnelMessageHandler(
            keyStore: self.keyStore,
            keyExpirationTester: self.keyExpirationTester,
            controllerErrorStore: self.controllerErrorStore,
            adapter: self.adapter,
            tunnelHealth: self.tunnelHealth,
            notificationsPresenter: self.notificationsPresenter,
            connectionTester: self.connectionTester,
            settings: self.settings,
            debugEvents: self.debugEvents,
            tunnelState: self,
            tunnelLifecycle: self,
            snoozeManager: self,
            leakCheckController: self
        )

        Logger.networkProtectionMemory.log("[+] PacketTunnelProvider initialized")

        observeSettingChanges()
    }

    deinit {
        Logger.networkProtectionMemory.log("[-] PacketTunnelProvider")
    }

    private var tunnelProviderProtocol: NETunnelProviderProtocol? {
        protocolConfiguration as? NETunnelProviderProtocol
    }

    private func runDebugSimulations(options: StartupOptions) throws {
        if options.simulateError {
            throw TunnelError.simulateTunnelFailureError
        }

        if options.simulateCrash {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval.seconds(2)) {
                fatalError("Simulated PacketTunnelProvider crash")
            }

            return
        }

        if options.simulateMemoryCrash {
            Task {
                var array = [String]()
                while true {
                    array.append("Crash")
                }
            }

            return
        }
    }

    open func load(options: StartupOptions) async throws {
        Logger.networkProtection.log("Loading startup options")
        loadKeyValidity(from: options)
        loadTesterEnabled(from: options)
    }

    open func loadVendorOptions(from provider: NETunnelProviderProtocol?) throws {
        // no-op, but can be overridden by subclasses
    }

    /// Called after the token check passes on iOS, indicating that protected data is available.
    open func loadProtectedResources() async {
        // no-op, but can be overridden by subclasses
    }

    private func loadKeyValidity(from options: StartupOptions) {
        switch options.vpnSettings {
        case .set(let settingsSnapshot):
            if case .custom(let validity) = settingsSnapshot.registrationKeyValidity {
                Task { @MainActor in
                    await keyExpirationTester.setKeyValidity(validity)
                }
            } else {
                Task { @MainActor in
                    await keyExpirationTester.setKeyValidity(nil)
                }
            }
        case .useExisting:
            break
        case .reset:
            Task { @MainActor in
                await keyExpirationTester.setKeyValidity(nil)
            }
        }
    }

    private func loadTesterEnabled(from options: StartupOptions) {
        switch options.enableTester {
        case .set(let value):
            isConnectionTesterEnabled = value
        case .useExisting:
            break
        case .reset:
            isConnectionTesterEnabled = true
        }
    }

    // MARK: - Observing Changes

    private func observeSettingChanges() {
        settings.changePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }

                Logger.networkProtection.log("🔵 Settings changed: \(String(describing: change), privacy: .public)")

                Task { @MainActor in
                    do {
                        try await self.handleSettingsChange(change)
                    } catch {
                        await self.subscriptionAccessErrorHandler(error)
                        throw error
                    }
                }
            }.store(in: &cancellables)
    }

    @MainActor
    private func handleConnectionTestResult(_ result: NetworkProtectionConnectionTester.Result) {
        let serverName = lastSelectedServerInfo?.name ?? "Unknown"

        switch result {
        case .connected:
            self.clearResolvedIssueState()

        case .reconnected(let failureCount):
            providerEvents.fire(
                .connectionTesterStatusChange(
                    .recovered(duration: .immediate, failureCount: failureCount),
                    server: serverName))

            if failureCount >= Self.connectionTesterExtendedFailuresCount {
                providerEvents.fire(
                    .connectionTesterStatusChange(
                        .recovered(duration: .extended, failureCount: failureCount),
                        server: serverName))
            }

            self.clearResolvedIssueState()

        case .disconnected(let failureCount):
            if failureCount == 1 {
                providerEvents.fire(
                    .connectionTesterStatusChange(
                        .failed(duration: .immediate),
                        server: serverName))
            } else if failureCount == 8 {
                providerEvents.fire(
                    .connectionTesterStatusChange(
                        .failed(duration: .extended),
                        server: serverName))
            }

            self.tunnelHealth.isHavingConnectivityIssues = true

            Task {
                await self.bandwidthAnalyzer.reset()
            }
        }
    }

    @MainActor
    open func handleConnectionStatusChange(old: ConnectionStatus, new: ConnectionStatus) {
        Logger.networkProtectionPixel.debug("⚫️ Connection Status Change: \(old.description, privacy: .public) -> \(new.description, privacy: .public)")
    }

    // MARK: - Overrideable Connection Events

    open func prepareToConnect(using provider: NETunnelProviderProtocol?) {
        // no-op: abstract method to be overridden in subclass
    }

    // MARK: - Tunnel Start

    @MainActor
    open override func startTunnel(options: [String: NSObject]? = nil) async throws {
        do {
            try await startTunnelInternal(options: options)
        } catch {
            throw error.sanitizedForXPC()
        }
    }

    @MainActor
    private func startTunnelInternal(options: [String: NSObject]? = nil) async throws {
        Logger.networkProtection.log("🚀 Starting tunnel")

        // It's important to have this as soon as possible since it helps setup PixelKit
        prepareToConnect(using: tunnelProviderProtocol)

        let startupOptions = StartupOptions(options: options ?? [:])
        Logger.networkProtection.log("Starting tunnel with options: \(startupOptions.description, privacy: .public)")
        setupAndStartConnectionWideEvent(with: startupOptions.startupMethod)

        // Reset snooze if the VPN is restarting.
        self.snoozeTimingStore.reset()

        do {
            try await load(options: startupOptions)
            Logger.networkProtection.log("🟢 Startup options loaded correctly")

#if os(iOS)
            do {
                _ = try await tokenHandlerProvider.getToken()
            } catch {
                throw TunnelError.startingTunnelWithoutAuthToken(internalError: error)
            }

            // Load resources that require the device to be unlocked.
            // At this point, the token check has passed, so protected data is available.
            await loadProtectedResources()
#endif
        } catch {
            if startupOptions.startupMethod == .automaticOnDemand {
                if loopDetector.connectionFailed(isOnDemand: true) {
                    providerEvents.fire(.connectionFailureLoopDetected(error))
                }

                // If the VPN was started by on-demand without the basic prerequisites for
                // it to work we skip firing pixels.  This should only be possible if the
                // manual start attempt that preceded failed, or if the subscription has
                // expired.  In either case it should be enough to record the manual failures
                // for these prerequisited to avoid flooding our metrics.
                providerEvents.fire(.tunnelStartOnDemandWithoutAccessToken(error))
                Logger.networkProtection.log("Going to sleep...")
                try? await Task.sleep(interval: .seconds(15))
                Logger.networkProtection.log("Waking up...")
            } else {
                loopDetector.connectionFailed(isOnDemand: false)

                // If the VPN was started manually without the basic prerequisites we always
                // want to know as this should not be possible.
                providerEvents.fire(.tunnelStartAttempt(.begin))
                providerEvents.fire(.reportConnectionAttempt(attempt: .connecting, source: .start))
                providerEvents.fire(.tunnelStartAttempt(.failure(error)))
                providerEvents.fire(.reportConnectionAttempt(attempt: .failure, source: .start))
            }

            Logger.networkProtection.error("🔴 Stopping VPN due to no auth token")
            completeAndCleanupConnectionWideEvent(with: error, description: error.contextualizedDescription())
            throw error
        }

        do {
            providerEvents.fire(.tunnelStartAttempt(.begin))
            providerEvents.fire(.reportConnectionAttempt(attempt: .connecting, source: .start))
            connectionStatus = .connecting
            resetIssueStateOnTunnelStart(startupOptions)

            try runDebugSimulations(options: startupOptions)
            try await startTunnel(onDemand: startupOptions.startupMethod == .automaticOnDemand)

            providerEvents.fire(.tunnelStartAttempt(.success))
            providerEvents.fire(.reportConnectionAttempt(attempt: .success, source: .start))
            loopDetector.connectionSucceeded()
            startHeartbeat()
            completeAndCleanupConnectionWideEvent()
        } catch {
            if loopDetector.connectionFailed(isOnDemand: startupOptions.startupMethod == .automaticOnDemand) {
                providerEvents.fire(.connectionFailureLoopDetected(error))
            }

            Logger.networkProtection.error("🔴 Failed to start tunnel \(error.localizedDescription, privacy: .public)")

            await subscriptionAccessErrorHandler(error)

            if startupOptions.startupMethod == .automaticOnDemand {
                // We add a delay when the VPN is started by
                // on-demand and there's an error, to avoid frenetic ON/OFF
                // cycling.
                Logger.networkProtection.log("Going to sleep...")
                try? await Task.sleep(interval: .seconds(15))
                Logger.networkProtection.log("Waking up...")
            }

            let errorDescription = (error as? LocalizedError)?.localizedDescription ?? String(describing: error)

            self.controllerErrorStore.lastErrorMessage = errorDescription
            self.connectionStatus = .disconnected
            self.knownFailureStore.lastKnownFailure = KnownFailure(error)

            providerEvents.fire(.tunnelStartAttempt(.failure(error)))
            providerEvents.fire(.reportConnectionAttempt(attempt: .failure, source: .start))
            completeAndCleanupConnectionWideEvent(with: error, description: error.contextualizedDescription())
            throw error
        }
    }

    var currentServerSelectionMethod: NetworkProtectionServerSelectionMethod {
        var serverSelectionMethod: NetworkProtectionServerSelectionMethod

        switch settings.selectedLocation {
        case .nearest:
            serverSelectionMethod = .automatic
        case .location(let networkProtectionSelectedLocation):
            serverSelectionMethod = .preferredLocation(networkProtectionSelectedLocation)
        }

        switch settings.selectedServer {
        case .automatic:
            break
        case .endpoint(let string):
            // Selecting a specific server will override locations setting
            // Only available in debug
            serverSelectionMethod = .preferredServer(serverName: string)
        }

        return serverSelectionMethod
    }

    private func startTunnel(onDemand: Bool) async throws {
        do {
            Logger.networkProtection.log("Generating tunnel config")
            Logger.networkProtection.log("Server selection method: \(self.currentServerSelectionMethod.debugDescription, privacy: .public)")
            Logger.networkProtection.log("DNS server: \(String(describing: self.settings.dnsSettings), privacy: .public)")
            let tunnelConfiguration = try await generateTunnelConfiguration(
                serverSelectionMethod: currentServerSelectionMethod,
                dnsSettings: settings.dnsSettings,
                regenerateKey: true)

            try await startTunnel(with: tunnelConfiguration, onDemand: onDemand)
            Logger.networkProtection.log("Done generating tunnel config")
        } catch {
            Logger.networkProtection.error("Failed to start tunnel on demand: \(error.localizedDescription, privacy: .public)")
            controllerErrorStore.lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func startTunnel(with tunnelConfiguration: TunnelConfiguration, onDemand: Bool) async throws {

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            adapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] error in
                if let error {
                    self?.debugEvents.fire(error.networkProtectionError)
                    continuation.resume(throwing: error)
                    return
                }

                Task { @MainActor [weak self] in
                    // It's important to call this completion handler before running the tester
                    // as if we don't, the tester will just fail.  It seems like the connection
                    // won't fully work until the completion handler is called.
                    continuation.resume()

                    guard let self else { return }

                    do {
                        let startReason: AdapterStartReason = onDemand ? .onDemand : .manual
                        try await self.handleAdapterStarted(startReason: startReason)

                        // Enable Connect on Demand when manually enabling the tunnel on iOS 17.0+.
#if os(iOS)
                        if #available(iOS 17.0, *), startReason == .manual {
                            try? await updateConnectOnDemand(enabled: true)
                            Logger.networkProtection.log("Enabled Connect on Demand due to user-initiated startup")
                        }
#endif
                    } catch {
                        Logger.networkProtection.log("Connection Tester failed to start... will run without it: \(error, privacy: .public)")
                        return
                    }
                }
            }
        }
    }

    // MARK: - Tunnel Stop

    @MainActor
    open override func stopTunnel(with reason: NEProviderStopReason) async {
        providerEvents.fire(.tunnelStopAttempt(.begin))
        stopHeartbeat()

        Logger.networkProtection.log("🛑 Stopping tunnel with reason \(String(describing: reason), privacy: .public)")

        do {
            try await stopTunnel()
            providerEvents.fire(.tunnelStopAttempt(.success))

            // Disable Connect on Demand when disabling the tunnel from iOS settings on iOS 17.0+.
            if #available(iOS 17.0, *), case .userInitiated = reason {
                try? await updateConnectOnDemand(enabled: false)
                Logger.networkProtection.log("Disabled Connect on Demand due to user-initiated shutdown")
            }
        } catch {
            providerEvents.fire(.tunnelStopAttempt(.failure(error)))
        }

        if case .userInitiated = reason {
            // If the user shut down the VPN deliberately, end snooze mode early.
            self.snoozeTimingStore.reset()
            loopDetector.reset()
        }

        if case .superceded = reason {
            self.notificationsPresenter.showSupersededNotification()
        }
    }

    /// Do not cancel, directly... call this method so that the adapter and tester are stopped too.
    @MainActor
    func cancelTunnel(with stopError: Error) async {
        providerEvents.fire(.tunnelStopAttempt(.begin))
        stopHeartbeat()

        Logger.networkProtection.error("Stopping tunnel with error \(stopError.localizedDescription, privacy: .public)")

        do {
            try await stopTunnel()
            providerEvents.fire(.tunnelStopAttempt(.success))
        } catch {
            providerEvents.fire(.tunnelStopAttempt(.failure(error)))
        }

        cancelTunnelWithError(stopError)
    }

    // MARK: - Tunnel Stop: Support Methods

    /// Do not call this directly, call `cancelTunnel(with:)` instead.
    ///
    @MainActor
    private func stopTunnel() async throws {
        connectionStatus = .disconnecting

        await stopMonitors()
        if let service = leakCheckService {
            await service.stop()
            leakCheckService = nil
        }
        try await stopAdapter()
    }

    @MainActor
    private func stopAdapter() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            adapter.stop { [weak self] error in
                if let error {
                    self?.debugEvents.fire(error.networkProtectionError)

                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume()
            }
        }
    }

    // MARK: - Fix Issues Management

    /// Resets the issue state when startup up the tunnel manually.
    ///
    /// When the tunnel is started by on-demand the issue state should not be cleared until the tester
    /// reports a working connection (see `clearResolvedIssueState()`).
    ///
    private func resetIssueStateOnTunnelStart(_ startupOptions: StartupOptions) {
        guard startupOptions.startupMethod != .automaticOnDemand else {
            return
        }

        clearResolvedIssueState()
    }

    /// Clears the issue state once a working connection is confirmed (and on manual start).
    ///
    /// On-demand starts skip `resetIssueStateOnTunnelStart`, so without this a failed start's error
    /// lingers in the stores and resurfaces when the tunnel later disconnects.
    ///
    private func clearResolvedIssueState() {
        tunnelHealth.isHavingConnectivityIssues = false
        errorStateReset.clear()
    }

    // MARK: - Tunnel Configuration

    enum TunnelUpdateMethod {
        case selectServer(_ method: NetworkProtectionServerSelectionMethod)
        case useConfiguration(_ configuration: TunnelConfiguration)
    }

    @MainActor
    func updateTunnelConfiguration(updateMethod: TunnelUpdateMethod,
                                   reassert: Bool,
                                   regenerateKey: Bool = false,
                                   attemptSource: ConnectionAttemptSource) async throws {

        providerEvents.fire(.tunnelUpdateAttempt(.begin))
        bumpTunnelPathGeneration()

        if attemptSource.isConnectionAttempt {
            providerEvents.fire(.reportConnectionAttempt(attempt: .connecting, source: attemptSource))
        }

        try await TunnelConfigurationUpdateOperation.run(
            reassert: reassert,
            generateTunnelConfiguration: {
                switch updateMethod {
                case .selectServer(let serverSelectionMethod):
                    return try await generateTunnelConfiguration(
                        serverSelectionMethod: serverSelectionMethod,
                        dnsSettings: settings.dnsSettings,
                        regenerateKey: regenerateKey)

                case .useConfiguration(let newTunnelConfiguration):
                    return newTunnelConfiguration
                }
            },
            stopMonitors: { [weak self] in
                await self?.stopMonitorsForReconfiguration(preservingFailureRecovery: attemptSource.preservesFailureRecoveryDuringReassertUpdate)
            },
            updateAdapterConfiguration: { [weak self] tunnelConfiguration in
                guard let self else { throw CancellationError() }
                try await self.updateAdapterConfiguration(tunnelConfiguration: tunnelConfiguration, reassert: reassert)
            },
            handleAdapterStarted: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.handleAdapterStarted(startReason: .reconnected)
            },
            handleFailure: { [weak self] error in
                guard let self else { return false }
                return await self.handleTunnelConfigurationUpdateFailure(error, attemptSource: attemptSource)
            },
            restartMonitorsAfterFailure: { [weak self] in
                await self?.restartMonitorsAfterFailedReassert()
            }
        )

        providerEvents.fire(.tunnelUpdateAttempt(.success))
        if attemptSource.isConnectionAttempt {
            providerEvents.fire(.reportConnectionAttempt(attempt: .success, source: attemptSource))
        }
    }

    @MainActor
    private func handleTunnelConfigurationUpdateFailure(_ error: Error, attemptSource: ConnectionAttemptSource) async -> Bool {
        providerEvents.fire(.tunnelUpdateAttempt(.failure(error)))
        if attemptSource.isConnectionAttempt {
            providerEvents.fire(.reportConnectionAttempt(attempt: .failure, source: attemptSource))
        }

        switch error {
        case WireGuardAdapterError.setWireguardConfig:
            await cancelTunnel(with: error)
            return true
        default:
            return false
        }
    }

    @MainActor
    private func restartMonitorsAfterFailedReassert() async {
        do {
            try await startMonitors(testImmediately: true)
        } catch {
            Logger.networkProtection.error("Failed to restart monitors after failed reassert update: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func updateAdapterConfiguration(tunnelConfiguration: TunnelConfiguration, reassert: Bool) async throws {

        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self = self else {
                continuation.resume()
                return
            }

            self.adapter.update(tunnelConfiguration: tunnelConfiguration, reassert: reassert) { [weak self] error in

                if let error = error {
                    self?.debugEvents.fire(error.networkProtectionError)

                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume()
            }
        }
    }

    @MainActor
    private func generateTunnelConfiguration(serverSelectionMethod: NetworkProtectionServerSelectionMethod,
                                             dnsSettings: NetworkProtectionDNSSettings,
                                             regenerateKey: Bool) async throws -> TunnelConfiguration {

        let configurationResult: NetworkProtectionDeviceManager.GenerateTunnelConfigurationResult
        let resolvedServerSelectionMethod = await serverSelectionResolver.resolvedServerSelectionMethod()

        do {
            configurationResult = try await deviceManager.generateTunnelConfiguration(
                resolvedSelectionMethod: resolvedServerSelectionMethod,
                excludeLocalNetworks: settings.excludeLocalNetworks,
                excludeCGNAT: settings.excludeCGNAT,
                dnsSettings: dnsSettings,
                regenerateKey: regenerateKey
            )
        } catch {
            switch error {
            case NetworkProtectionError.vpnAccessRevoked:
                throw TunnelError.vpnAccessRevoked(error)
            default:
                throw TunnelError.couldNotGenerateTunnelConfiguration(internalError: error)
            }
        }

        let newSelectedServer = configurationResult.server
        self.lastSelectedServer = newSelectedServer

        Logger.networkProtection.log("⚪️ Generated tunnel configuration for server at location: \(newSelectedServer.serverInfo.serverLocation, privacy: .public) (preferred server is \(newSelectedServer.serverInfo.name, privacy: .public))")

        return configurationResult.tunnelConfiguration
    }

    @available(iOS 17.0, *)
    private func updateConnectOnDemand(enabled: Bool) async throws {
        Logger.networkProtectionIPC.log("Updating Connect on Demand to \(enabled)")
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let manager = managers.first {
            manager.isOnDemandEnabled = enabled
            try await manager.saveToPreferences()
        }
    }

    // MARK: - App Messages

    @MainActor public override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        messageHandler.handleAppMessage(messageData, completionHandler: completionHandler)
    }

    @MainActor
    private func handleSettingsChange(_ change: VPNSettings.Change) async throws {
        switch change {
        case .setSelectedServer(let selectedServer):
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            switch selectedServer {
            case .automatic:
                serverSelectionMethod = .automatic
            case .endpoint(let serverName):
                serverSelectionMethod = .preferredServer(serverName: serverName)
            }

            if case .connected = connectionStatus {
                try? await updateTunnelConfiguration(
                    updateMethod: .selectServer(serverSelectionMethod),
                    reassert: true,
                    attemptSource: .serverChange)
            }
        case .setSelectedLocation(let selectedLocation):
            let serverSelectionMethod: NetworkProtectionServerSelectionMethod

            switch selectedLocation {
            case .nearest:
                serverSelectionMethod = .automatic
            case .location(let location):
                serverSelectionMethod = .preferredLocation(location)
            }

            if case .connected = connectionStatus {
                try? await updateTunnelConfiguration(
                    updateMethod: .selectServer(serverSelectionMethod),
                    reassert: true,
                    attemptSource: .locationChange)
            }
        case .setConnectOnLogin,
                .setDNSSettings,
                .setEnforceRoutes,
                .setExcludeLocalNetworks,
                .setExcludeCGNAT,
                .setExcludeAPNs,
                .setExcludeCellularServices,
                .setExcludeDeviceCommunication,
                .setIncludeAllNetworks,
                .setNotifyStatusChanges,
                .setRegistrationKeyValidity,
                .setSelectedEnvironment,
                .setShowInMenuBar,
                .setDisableRekeying:
            // Intentional no-op
            // Some of these don't require further action
            // Some may require an adapter restart, but it's best if that's taken care of by
            // the app that's coordinating the updates.
            //
            // enforceRoutes specifically is bound to the NECP session at creation time, so a
            // network-settings re-push here can't change it. The controller re-saves the protocol
            // and fully restarts the tunnel when this setting changes instead.
            break
        }
    }

    private func handleRestartAdapter() async throws {
        let tunnelConfiguration = try await generateTunnelConfiguration(
            serverSelectionMethod: currentServerSelectionMethod,
            dnsSettings: settings.dnsSettings,
            regenerateKey: false)

        try await updateTunnelConfiguration(updateMethod: .useConfiguration(tunnelConfiguration),
                                            reassert: false,
                                            regenerateKey: false,
                                            attemptSource: .adapterRestart)
    }

    /// Disables on-demand if the OS supports it.
    ///
    /// iOS 17+ supports it, but macOS does not - to the best of our knowledge.  Still, we encourage calling this method
    /// in macOS too in case this feature is ever implemented.
    ///
    @MainActor
    public func disableOnDemandIfSupportedByOS() async throws {
        enum DisableOnDemandError: LocalizedError {
            case notSupportedByOS

            func localizedDescription(in locale: Locale = .current) -> String {
                switch self {
                case .notSupportedByOS:
                    return "Disabling on-demand is not supported by the OS"
                }
            }
        }

        Logger.networkProtection.log("🔴 Disabling Connect On Demand and shutting down the tunnel")
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()

        guard let manager = managers.first else {
            throw DisableOnDemandError.notSupportedByOS
        }

        manager.isOnDemandEnabled = false
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }

    // MARK: - Adapter start completion handling

    private enum AdapterStartReason {
        case manual
        case onDemand
        case reconnected
        case wake
        case snoozeEnded
    }

    /// Called when the adapter reports that the tunnel was successfully started.
    ///
    @MainActor
    private func handleAdapterStarted(startReason: AdapterStartReason) async throws {
        if startReason != .reconnected && startReason != .wake {
            connectionStatus = .connected(connectedDate: Date())
        }

        Logger.networkProtection.log("⚪️ Tunnel interface is \(self.adapter.interfaceName ?? "unknown", privacy: .public)")

        // These cases only make sense in the context of a connection that had trouble
        // and is being fixed, so we want to test the connection immediately.
        let testImmediately = startReason == .reconnected || startReason == .onDemand
        try await startMonitors(testImmediately: testImmediately)

        await scheduleLeakCheck(for: startReason)
    }

    @MainActor
    private func scheduleLeakCheck(for startReason: AdapterStartReason) async {
        switch startReason {
        case .manual, .onDemand, .snoozeEnded:
            if leakCheckService == nil {
                let service = VPNLeakCheckService(
                    configuration: .default,
                    egressInfo: { [weak self] in
                        await self?.currentEgressInfo()
                    },
                    tunnelInterface: { [weak self] in
                        guard let self else { return .unavailable }
                        // Read the utun name live per check: the service outlives rekeys/reconnects/wake,
                        // any of which can rebind the tunnel to a new utun. A stale name makes the
                        // older-OS fallback (no `virtualInterface`) pin probes to the wrong interface → false leak.
                        let currentInterfaceName = await self.tunnelInterfaceName
                        return await self.resolveTunnelInterface(fallbackInterfaceName: currentInterfaceName)
                    },
                    tunnelPathGeneration: { [weak self] in
                        guard let self else { return 0 }
                        return await self.tunnelPathGeneration
                    },
                    httpClient: DefaultLeakCheckHTTPClient(),
                    stunClient: DefaultLeakCheckSTUNClient(),
                    wideEvent: wideEvent
                )
                leakCheckService = service
                await service.start()
            }
            await leakCheckService?.scheduleCheck(trigger: .tunnelStart)
        case .reconnected:
            await leakCheckService?.scheduleCheck(trigger: .reassert)
        case .wake:
            break
        }
    }

    /// Resolves the current egress info from `lastSelectedServerInfo` on the main actor. The leak
    /// check service calls this at the start of every check so the reference IP stays in sync with
    /// whichever server WireGuard is currently connected to — including changes made by `rekey()`,
    /// `handleRestartAdapter()`, or any future code path that mutates `lastSelectedServer` without
    /// going through `handleAdapterStarted`.
    @MainActor
    private func currentEgressInfo() -> LeakCheckEgressInfo? {
        guard let info = lastSelectedServerInfo,
              let ip = info.ipv4?.debugDescription else {
            return nil
        }
        return LeakCheckEgressInfo(ipAddress: ip, name: info.name)
    }

    @MainActor
    private func bumpTunnelPathGeneration() {
        tunnelPathGeneration &+= 1
    }

    // MARK: - Failure Recovery

    @MainActor
    private func handleFailureRecoveryConfigUpdate(result: NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult) async throws {
        self.lastSelectedServer = result.server
        try await updateTunnelConfiguration(updateMethod: .useConfiguration(result.tunnelConfiguration), reassert: true, attemptSource: .failureRecovery)
    }

    @MainActor
    func handleAccessRevoked(dueTo error: Error) async {
        defaults.enableEntitlementMessaging()
        notificationsPresenter.showEntitlementNotification()

        // We add a delay here so the notification has a chance to show up
        try? await Task.sleep(interval: .seconds(5))

        do {
            try await shutdown(dueTo: error)
        } catch {
            // If we can't cleanly shut the tunneldown, we'll do our best to
            // shut it down even if the process keeps running.

            // We don't want to be firing monitoring pixels for failures from this point onward...
            await stopMonitors()

            // If the extension process restarts we don't want it to attempt to reconnect
            try? await self.tokenHandlerProvider.removeToken()

            // We show some visual indication that something's off, so the user can chose to
            // manually stop the VPN.
            reasserting = true
        }
    }

    /// Tries to shut down the tunnel disabling on-demand.
    ///
    /// Not all OS versions support disabling on-demand, so this method will throw an error in that case
    /// to allow the caller to decide what to do next.
    ///
    @MainActor
    private func shutdown(dueTo error: Error) async throws {
        Logger.networkProtection.log("Shutting down due to: \(error.localizedDescription, privacy: .public)")

        do {
            try await disableOnDemandIfSupportedByOS()
            await cancelTunnel(with: error)
        } catch {
            Logger.networkProtection.debug("Shutdown cancelled, probably because the OS does not support disabling on-demand: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @MainActor
    public func startMonitors(testImmediately: Bool) async throws {
        try await tunnelMonitors.start(testImmediately: testImmediately)
    }

    @MainActor
    public func stopMonitors() async {
        await tunnelMonitors.stop()
    }

    /// Stops the monitors during a reasserting config update. Failure recovery
    /// is preserved only for the update it drives itself; other reassert updates
    /// supersede any in-flight recovery.
    @MainActor
    private func stopMonitorsForReconfiguration(preservingFailureRecovery: Bool) async {
        await tunnelMonitors.stop(includingFailureRecovery: !preservingFailureRecovery)
    }

    // MARK: - Connection Tester

    enum ConnectionTesterError: CustomNSError {
        case couldNotRetrieveInterfaceNameFromAdapter
        case testerFailedToStart(internalError: Error)

        var errorCode: Int {
            switch self {
            case .couldNotRetrieveInterfaceNameFromAdapter: return 0
            case .testerFailedToStart: return 1
            }
        }

        var errorUserInfo: [String: Any] {
            switch self {
            case .couldNotRetrieveInterfaceNameFromAdapter:
                return [:]
            case .testerFailedToStart(let internalError):
                return [NSUnderlyingErrorKey: internalError as NSError]
            }
        }
    }

    // MARK: - Computer sleeping

    @MainActor
    public override func sleep() async {
        Logger.networkProtectionSleep.log("Sleep")
        stopHeartbeat()
        await stopMonitors()
    }

    @MainActor
    public override func wake() {
        Logger.networkProtectionSleep.log("Wake up")

        // macOS can launch the extension due to calls to `sendProviderMessage`, so there's
        // a chance this is being called when the VPN isn't really meant to be connected or
        // running.  We want to avoid firing pixels or handling adapter changes when this is
        // the case.
        guard connectionStatus != .disconnected else {
            return
        }

        Task {
            providerEvents.fire(.tunnelWakeAttempt(.begin))

            do {
                try await handleAdapterStarted(startReason: .wake)
                Logger.networkProtectionConnectionTester.log("🟢 Wake success")
                providerEvents.fire(.tunnelWakeAttempt(.success))
                startHeartbeat()
            } catch {
                Logger.networkProtection.error("🔴 Wake error: \(error.localizedDescription, privacy: .public)")
                providerEvents.fire(.tunnelWakeAttempt(.failure(error)))
            }
        }
    }

    // MARK: - Tunnel heartbeat

    private func startHeartbeat() {
        guard let heartbeatStore else { return }
        heartbeatTask = Task.periodic(interval: Self.heartbeatInterval) { [weak heartbeatStore] in
            heartbeatStore?.recordHeartbeat()
        }
    }

    private func stopHeartbeat() {
        heartbeatTask = nil
    }

    // MARK: - Snooze

    private var snoozeTimerTask: Task<Never, Error>? {
        willSet {
            snoozeTimerTask?.cancel()
        }
    }

    private var snoozeRequestProcessing: Bool = false
    private var snoozeJustEnded: Bool = false

    @MainActor
    func startSnooze(duration: TimeInterval) async {
        if snoozeRequestProcessing {
            Logger.networkProtection.log("Rejecting start snooze request due to existing request processing")
            return
        }

        snoozeRequestProcessing = true
        Logger.networkProtection.log("Starting snooze mode with duration: \(duration, privacy: .public)")

        await stopMonitors()

        self.adapter.snooze { [weak self] error in
            guard let self else {
                assertionFailure("Failed to get strong self")
                return
            }

            if error == nil {
                self.connectionStatus = .snoozing
                self.snoozeTimingStore.activeTiming = .init(startDate: Date(), duration: duration)
                self.notificationsPresenter.showSnoozingNotification(duration: duration)

                snoozeTimerTask = Task.periodic(interval: .seconds(1)) { [weak self] in
                    guard let self else { return }

                    if self.snoozeTimingStore.hasExpired {
                        Task.detached {
                            Logger.networkProtection.log("Snooze mode timer expired, canceling snooze now...")
                            await self.cancelSnooze()
                        }
                    }
                }
            } else {
                self.snoozeTimingStore.reset()
            }

            self.snoozeRequestProcessing = false
        }
    }

    @MainActor
    func cancelSnooze() async {
        if snoozeRequestProcessing {
            Logger.networkProtection.log("Rejecting cancel snooze request due to existing request processing")
            return
        }

        snoozeRequestProcessing = true
        defer {
            snoozeRequestProcessing = false
        }

        snoozeTimerTask?.cancel()
        snoozeTimerTask = nil

        guard connectionStatus == .snoozing, snoozeTimingStore.activeTiming != nil else {
            Logger.networkProtection.error("Failed to cancel snooze mode as it was not active")
            return
        }

        Logger.networkProtection.log("Canceling snooze mode")

        snoozeJustEnded = true
        try? await startTunnel(onDemand: false)
        snoozeTimingStore.reset()
    }

    // MARK: - Error Validation

    enum InvalidDiagnosticError: Error, CustomNSError {
        case errorWithInvalidUnderlyingError(Error)

        var errorCode: Int {
            switch self {
            case .errorWithInvalidUnderlyingError(let error):
                return (error as NSError).code
            }
        }

        var localizedDescription: String {
            switch self {
            case .errorWithInvalidUnderlyingError(let error):
                return "Error '\(type(of: error))', message: \(error.localizedDescription)"
            }
        }

        var errorUserInfo: [String: Any] {
            switch self {
            case .errorWithInvalidUnderlyingError(let error):
                let newError = NSError(domain: (error as NSError).domain, code: (error as NSError).code)
                return [NSUnderlyingErrorKey: newError]
            }
        }
    }
}

private struct WideEventFeatureFlagProvider: WideEventFeatureFlagProviding {
    let settings: VPNSettings

    func isEnabled(_ flag: WideEventFeatureFlag) -> Bool {
        // There are no flags defined currently, but please replace this with a switch statement when a new flag is added.
        return true
    }
}

extension WireGuardAdapterError: LocalizedError, CustomDebugStringConvertible {

    public var errorDescription: String? {
        switch self {
        case .cannotLocateTunnelFileDescriptor:
            return "Starting tunnel failed: could not determine file descriptor"

        case .dnsResolution(let dnsErrors):
            let hostnamesWithDnsResolutionFailure = dnsErrors.map { $0.address }
                .joined(separator: ", ")
            return "DNS resolution failed for the following hostnames: \(hostnamesWithDnsResolutionFailure)"

        case .setNetworkSettings(let error):
            return "Starting tunnel failed with setTunnelNetworkSettings returning: \(error.localizedDescription)"

        case .startWireGuardBackend(let errorCode):
            return "Starting tunnel failed with wgTurnOn returning: \(errorCode)"

        case .setWireguardConfig(let errorCode):
            return "Update tunnel failed with wgSetConfig returning: \(errorCode)"

        case .invalidState:
            return "Starting tunnel failed with invalid error"
        }
    }

    public var debugDescription: String {
        errorDescription!
    }
}

// MARK: - WideEvent

extension PacketTunnelProvider {

    func setupAndStartConnectionWideEvent(with startupMethod: StartupOptions.StartupMethod) {
        completeAllPendingVPNConnectionPixels()
        VPNLeakCheckService.completeAllPendingFlows(wideEvent: wideEvent)
        // Already measured
        guard startupMethod != .manualByMainApp else { return }
        let data = VPNConnectionWideEventData(
            extensionType: .unknown,
            startupMethod: startupMethod == .automaticOnDemand ? .automaticOnDemand : .manualByTheSystem,
            // User cannot onboard during this flow
            isSetup: .no,
            onboardingStatus: .completed,
            contextData: WideEventContextData(name: (startupMethod == .automaticOnDemand ? NetworkProtectionFunnelOrigin.others : NetworkProtectionFunnelOrigin.systemSettings).rawValue)
        )
        self.connectionWideEventData = data
        self.connectionWideEventData?.overallDuration = WideEvent.MeasuredInterval.startingNow()
        self.connectionWideEventData?.tunnelStartDuration = WideEvent.MeasuredInterval.startingNow()
        wideEvent.startFlow(data)
    }

    func completeAndCleanupConnectionWideEvent(with error: Error? = nil, description: String? = nil) {
        guard let data = self.connectionWideEventData else { return }
        data.tunnelStartDuration?.complete()
        data.overallDuration?.complete()
        if let error {
            data.errorData = .init(error: error, description: description)
            wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
        } else {
            wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
        }
        self.connectionWideEventData = nil
    }

    func completeAllPendingVPNConnectionPixels() {
        let pending = wideEvent.getAllFlowData(VPNConnectionWideEventData.self)
        for data in pending {
            guard let start = data.overallDuration?.start, data.overallDuration?.end == nil else {
                wideEvent.completeFlow(data, status: .unknown(reason: VPNConnectionWideEventData.StatusReason.partialData.rawValue), onComplete: { _, _ in })
                continue
            }

            let timeoutDate = start.addingTimeInterval(connectionTunnelTimeoutInterval)
            let reason: VPNConnectionWideEventData.StatusReason = Date() >= timeoutDate ? .timeout : .retried
            wideEvent.completeFlow(data, status: .unknown(reason: reason.rawValue), onComplete: { _, _ in })
        }
    }
}

// MARK: - TunnelStateProviding

extension PacketTunnelProvider: TunnelStateProviding {
    // connectionStatus — already public var @MainActor
    // currentServerSelectionMethod — already internal var @MainActor
    // lastSelectedServer — already internal var @MainActor
    // lastSelectedServerInfo — already public var @MainActor

    var tunnelInterfaceName: String? {
        adapter.interfaceName
    }

    var excludeLocalNetworks: Bool {
        protocolConfiguration.excludeLocalNetworks
    }
}

// MARK: - TunnelLifecycleManaging

extension PacketTunnelProvider: TunnelLifecycleManaging {
    // cancelTunnel(with:) — already internal @MainActor
    // resetRegistrationKey() — already internal @MainActor
    // handleAccessRevoked(dueTo:) — already internal @MainActor

    func updateTunnelConfiguration(updateMethod: TunnelUpdateMethod, reassert: Bool, attemptSource: ConnectionAttemptSource) async throws {
        try await updateTunnelConfiguration(updateMethod: updateMethod, reassert: reassert, regenerateKey: false, attemptSource: attemptSource)
    }

    func restartAdapter() async throws {
        try await handleRestartAdapter()
    }

    func removeToken() async throws {
        try await tokenHandlerProvider.removeToken()
    }
}

// MARK: - SnoozeManaging

extension PacketTunnelProvider: SnoozeManaging {
    // startSnooze(duration:) — already internal @MainActor
    // cancelSnooze() — already internal @MainActor
}

extension PacketTunnelProvider: LeakCheckControlling {
    func triggerLeakCheckFromDebugMenu() async {
        Logger.networkProtectionIPLeakCheck.log("Debug-triggered leak check requested")
        await leakCheckService?.runCheck(trigger: .periodic, bypassCooldown: true)
    }
}

// MARK: - Error Description Helper

private extension Error {
    func contextualizedDescription() -> String? {
        return (self as? PacketTunnelProvider.TunnelError)?.errorDescription
    }
}

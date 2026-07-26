//
//  NetworkProtectionTunnelController.swift
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

import PrivacyConfig
import Combine
import SwiftUI
import Common
import FoundationExtensions
import FeatureFlags
import Foundation
import NetworkExtension
import VPN
import NetworkProtectionProxy
import NetworkProtectionUI
import Networking
import PixelKit
import os.log
import Subscription
import SystemExtensionManager
import SystemExtensions
import VPNAppState

typealias NetworkProtectionStatusChangeHandler = (VPN.ConnectionStatus) -> Void
typealias NetworkProtectionConfigChangeHandler = () -> Void

/// The `NETunnelProviderManager` surface the tunnel controller needs in order to start, configure and
/// stop the VPN.
///
/// Exists so the start flow can be exercised in a test. `NETunnelProviderManager` reads and writes the
/// user's real VPN configuration, and `NEVPNConnection` cannot be instantiated at all, so without this
/// every start attempt would touch system preferences.
protocol VPNTunnelManaging: AnyObject {
    var isEnabled: Bool { get set }
    var localizedDescription: String? { get set }
    var protocolConfiguration: NEVPNProtocol? { get set }
    var onDemandRules: [NEOnDemandRule]? { get set }
    var isOnDemandEnabled: Bool { get set }

    /// Kept separate from ``vpnConnection`` because a test double has to be able to report a status
    /// without supplying an `NEVPNConnection`, which it cannot construct.
    var connectionStatus: NEVPNStatus { get }
    var vpnConnection: NEVPNConnection? { get }
    var providerSession: NETunnelProviderSession? { get }

    func loadFromPreferences() async throws
    func saveToPreferences() async throws
    func removeFromPreferences() async throws
    func startTunnel(options: [String: NSObject]?) throws
    func stopTunnel()

    /// Waits until the tunnel reaches a terminal startup state, throwing a
    /// `VPNStartupMonitor.StartupError` if it disconnects silently or never confirms a connection.
    func waitForStartSuccess() async throws
}

extension NETunnelProviderManager: VPNTunnelManaging {

    var connectionStatus: NEVPNStatus {
        connection.status
    }

    var vpnConnection: NEVPNConnection? {
        connection
    }

    var providerSession: NETunnelProviderSession? {
        connection as? NETunnelProviderSession
    }

    func startTunnel(options: [String: NSObject]?) throws {
        try connection.startVPNTunnel(options: options)
    }

    func stopTunnel() {
        connection.stopVPNTunnel()
    }

    func waitForStartSuccess() async throws {
        try await VPNStartupMonitor().waitForStartSuccess(self)
    }
}

/// Provides the tunnel managers the controller operates on.
protocol VPNTunnelManagerStore {
    func loadAllManagers() async throws -> [any VPNTunnelManaging]
    func makeManager() -> any VPNTunnelManaging
}

struct SystemVPNTunnelManagerStore: VPNTunnelManagerStore {

    func loadAllManagers() async throws -> [any VPNTunnelManaging] {
        try await NETunnelProviderManager.loadAllFromPreferences()
    }

    func makeManager() -> any VPNTunnelManaging {
        NETunnelProviderManager()
    }
}

final class NetworkProtectionTunnelController: TunnelController, TunnelSessionProvider {

    // MARK: - Configuration

    let settings: VPNSettings
    let vpnAppState: VPNAppState
    let defaults: UserDefaults
    let wideEvent: WideEventManaging
    private let featureFlagger: FeatureFlagger

    // MARK: - Combine Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Debug Helpers

    /// Debug simulation options to aid with testing NetP.
    ///
    /// This is static because we want these options to be shared across all instances of `NetworkProtectionProvider`.
    ///
    static var simulationOptions = NetworkProtectionSimulationOptions()

    /// Stores the last controller error for the purpose of updating the UI as needed.
    ///
    private let controllerErrorStore: NetworkProtectionControllerErrorStore

    private let knownFailureStore = NetworkProtectionKnownFailureStore()

    // MARK: - Subscriptions

    private let subscriptionManager: any SubscriptionManager

    // MARK: - Extensions Support

    private let availableExtensions: VPNExtensionResolver.AvailableExtensions
    lazy var extensionResolver: VPNExtensionResolver = {
        VPNExtensionResolver(availableExtensions: availableExtensions, featureFlagger: featureFlagger, isConfigurationInstalled: { [weak self] extensionBundleID in
            await self?.isConfigurationInstalled(extensionBundleID: extensionBundleID) ?? true
        })
    }()

    private let networkExtensionController: NetworkExtensionControlling

    private let tunnelManagerStore: VPNTunnelManagerStore

    // MARK: - Notification Center

    private let notificationCenter: NotificationCenter

    /// The tunnel manager
    ///
    /// We're keeping a reference to this because we don't want to be calling `loadAllFromPreferences` more than
    /// once.
    ///
    /// For reference read: https://app.asana.com/0/1203137811378537/1206513608690551/f
    ///
    private var internalManager: (any VPNTunnelManaging)?

    /// Simply clears the internal manager so the VPN manager is reloaded next time it's requested.
    ///
    @MainActor
    private func clearInternalManager() {
        internalManager = nil
    }

    /// The last known VPN status.
    ///
    /// Should not be used for checking the current status.
    ///
    private var previousStatus: NEVPNStatus = .invalid

    // MARK: - User Defaults

    /// These are read and written directly against ``defaults`` instead of through `@UserDefaultsWrapper`,
    /// whose suite is fixed at declaration time and therefore can't be redirected. The key strings match the
    /// wrapper's, so the stored representation is unchanged and stays compatible with the main app, which
    /// writes the wide event start times through `NetworkProtectionIPCTunnelController`.
    private enum DefaultsKey {
        static let onboardingStatusRawValue = "networkProtectionOnboardingStatusRawValue"
        static let vpnConnectionWideEventBrowserStartTime = "vpnConnectionWideEventBrowserStartTime"
        static let vpnConnectionWideEventOverallStartTime = "vpnConnectionWideEventOverallStartTime"
    }

    private(set) var onboardingStatusRawValue: OnboardingStatus.RawValue {
        get {
            defaults.string(forKey: DefaultsKey.onboardingStatusRawValue) ?? OnboardingStatus.default.rawValue
        }
        set {
            defaults.set(newValue, forKey: DefaultsKey.onboardingStatusRawValue)
            syncWideEventOnboardingStatus()
        }
    }

    private var vpnConnectionWideEventBrowserStartTime: Date? {
        get {
            defaults.object(forKey: DefaultsKey.vpnConnectionWideEventBrowserStartTime) as? Date
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: DefaultsKey.vpnConnectionWideEventBrowserStartTime)
                return
            }
            defaults.set(newValue, forKey: DefaultsKey.vpnConnectionWideEventBrowserStartTime)
        }
    }

    private var vpnConnectionWideEventOverallStartTime: Date? {
        get {
            defaults.object(forKey: DefaultsKey.vpnConnectionWideEventOverallStartTime) as? Date
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: DefaultsKey.vpnConnectionWideEventOverallStartTime)
                return
            }
            defaults.set(newValue, forKey: DefaultsKey.vpnConnectionWideEventOverallStartTime)
        }
    }

    // MARK: - Wide Event

    private var connectionWideEventData: VPNConnectionWideEventData?
    private let connectionControllerTimeoutInterval: TimeInterval = .hours(24)

    // MARK: - Tunnel Manager

    /// Loads the configuration matching our ``extensionID``.
    ///
    @MainActor
    public var manager: (any VPNTunnelManaging)? {
        get async {
            if let internalManager {
                return internalManager
            }

            let extensionBundleID = await extensionResolver.activeExtensionBundleID

            let manager = (try? await tunnelManagerStore.loadAllManagers())?.first { manager in
                (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionBundleID
            }
            internalManager = manager
            return manager
        }
    }

    @MainActor
    private func loadOrMakeTunnelManager() async throws -> any VPNTunnelManaging {
        let tunnelManager = await manager ?? {
            let manager = tunnelManagerStore.makeManager()
            internalManager = manager
            return manager
        }()

        try await setupAndSave(tunnelManager)
        return tunnelManager
    }

    @MainActor
    private func setupAndSave(_ tunnelManager: any VPNTunnelManaging) async throws {
        await setup(tunnelManager)
        try await tunnelManager.saveToPreferences()
        try await tunnelManager.loadFromPreferences()
    }

    // MARK: - Initialization

    /// Default initializer
    ///
    /// - Parameters:
    ///         - notificationCenter: (meant for testing) the notification center that this object will use.
    ///
    init(availableExtensions: VPNExtensionResolver.AvailableExtensions,
         networkExtensionController: NetworkExtensionControlling,
         featureFlagger: FeatureFlagger,
         settings: VPNSettings,
         defaults: UserDefaults,
         wideEvent: WideEventManaging,
         notificationCenter: NotificationCenter = .default,
         subscriptionManager: any SubscriptionManager,
         vpnAppState: VPNAppState,
         tunnelManagerStore: VPNTunnelManagerStore = SystemVPNTunnelManagerStore(),
         controllerErrorStore: NetworkProtectionControllerErrorStore = NetworkProtectionControllerErrorStore()) {

        self.availableExtensions = availableExtensions
        self.featureFlagger = featureFlagger
        self.networkExtensionController = networkExtensionController
        self.tunnelManagerStore = tunnelManagerStore
        self.controllerErrorStore = controllerErrorStore
        self.notificationCenter = notificationCenter
        self.settings = settings
        self.defaults = defaults
        self.wideEvent = wideEvent
        self.subscriptionManager = subscriptionManager
        self.vpnAppState = vpnAppState
        subscribeToSettingsChanges()
        subscribeToStatusChanges()
        subscribeToConfigurationChanges()
    }

    // MARK: - Observing Status Changes

    private func subscribeToStatusChanges() {
        notificationCenter.publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] status in
                self?.handleStatusChange(status)
            }
            .store(in: &cancellables)
    }

    private func handleStatusChange(_ notification: Notification) {
        Logger.networkProtection.log("VPN handle status change: \(notification.debugDescription, privacy: .public)")
        guard let session = (notification.object as? NETunnelProviderSession),
              session.status != previousStatus else {
            return
        }

        Task { @MainActor in
            previousStatus = session.status

            if session.status == .invalid {
                clearInternalManager()
            }
        }
    }

    // MARK: - Observing Configuation Changes

    private func subscribeToConfigurationChanges() {
        notificationCenter.publisher(for: .NEVPNConfigurationChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }

                Task { @MainActor in
                    guard let manager = await self.manager else {
                        return
                    }

                    do {
                        try await manager.loadFromPreferences()

                        if manager.connectionStatus == .invalid {
                            self.clearInternalManager()
                        }
                    } catch {
                        self.clearInternalManager()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Subscriptions

    private func subscribeToSettingsChanges() {
        settings.changePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }

                Task {
                    // Offer the extension a chance to handle the settings change
                    try? await self.relaySettingsChange(change)

                    // Handle the settings change right in the controller
                    try? await self.handleSettingsChange(change)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Handling Settings Changes

    /// This is where the tunnel owner has a chance to handle the settings change locally.
    ///
    /// The extension can also handle these changes so not everything needs to be handled here.
    ///
    private func handleSettingsChange(_ change: VPNSettings.Change) async throws {
        switch change {
        case .setIncludeAllNetworks(let includeAllNetworks):
            try await handleSetIncludeAllNetworks(includeAllNetworks)
        case .setEnforceRoutes(let enforceRoutes):
            try await handleSetEnforceRoutes(enforceRoutes)
        case .setExcludeLocalNetworks(let excludeLocalNetworks):
            try await handleSetExcludeLocalNetworks(excludeLocalNetworks)
        case .setConnectOnLogin,
                .setExcludeCGNAT,
                .setExcludeAPNs,
                .setExcludeCellularServices,
                .setExcludeDeviceCommunication,
                .setNotifyStatusChanges,
                .setRegistrationKeyValidity,
                .setSelectedServer,
                .setSelectedEnvironment,
                .setSelectedLocation,
                .setDNSSettings,
                .setShowInMenuBar,
                .setDisableRekeying:
            // Intentional no-op as this is handled by the extension or the agent's app delegate
            break
        }
    }

    private func handleSetIncludeAllNetworks(_ includeAllNetworks: Bool) async throws {
        guard let tunnelManager = await manager,
              tunnelManager.protocolConfiguration?.includeAllNetworks == !includeAllNetworks else {
            return
        }

        try await setupAndSave(tunnelManager)
    }

    private func handleSetEnforceRoutes(_ enforceRoutes: Bool) async throws {
        guard let tunnelManager = await manager,
              tunnelManager.protocolConfiguration?.enforceRoutes == !enforceRoutes else {
            return
        }

        try await setupAndSave(tunnelManager)

        // enforceRoutes is bound to the NECP session when it's created, so re-saving the protocol
        // only affects the next connection. If a tunnel is currently up, fully restart it so the
        // new value takes effect now rather than on the next manual connect.
        if await isConnected {
            await restart(trigger: .settingsChangeRestart)
        }
    }

    private func handleSetExcludeLocalNetworks(_ excludeLocalNetworks: Bool) async throws {
        guard let tunnelManager = await manager else {
            return
        }

        try await setupAndSave(tunnelManager)
    }

    private func relaySettingsChange(_ change: VPNSettings.Change) async throws {
        guard await isConnected,
              let session = await session else {
            return
        }

        let errorMessage: ExtensionMessageString? = try await session.sendProviderRequest(.changeTunnelSetting(change))
        if let errorMessage {
            throw TunnelFailureError(errorDescription: errorMessage.value)
        }
    }

    // MARK: - Debug Command support

    func relay(_ command: VPNCommand) async throws {
        guard await isConnected,
              let session = await session else {
            return
        }

        let errorMessage: ExtensionMessageString? = try await session.sendProviderRequest(.command(command))
        if let errorMessage {
            throw TunnelFailureError(errorDescription: errorMessage.value)
        }
    }

    // MARK: - Tunnel Configuration

    /// Setups the tunnel manager if it's not set up already.
    ///
    @MainActor
    private func setup(_ tunnelManager: any VPNTunnelManaging) async {
        Logger.networkProtection.log("Setting up tunnel manager")

        // Scrub a stale enforceRoutes value before it reaches the protocol config, so it can't
        // persist after the Strict routing flag is withdrawn. This is the authoritative reset: it
        // runs on every connect, regardless of whether the user ever opens VPN settings.
        settings.resetEnforceRoutesIfUnavailable(
            strictRoutingAvailable: featureFlagger.isFeatureOn(.vpnStrictRoutingToggle))

        if tunnelManager.localizedDescription == nil {
            tunnelManager.localizedDescription = UserText.networkProtectionTunnelName
        }

        if !tunnelManager.isEnabled {
            tunnelManager.isEnabled = true
        }

        let extensionBundleID = await extensionResolver.activeExtensionBundleID

        tunnelManager.protocolConfiguration = {
            let protocolConfiguration = tunnelManager.protocolConfiguration as? NETunnelProviderProtocol ?? NETunnelProviderProtocol()
            protocolConfiguration.serverAddress = "127.0.0.1" // Dummy address... the NetP service will take care of grabbing a real server
            protocolConfiguration.providerBundleIdentifier = extensionBundleID
            protocolConfiguration.providerConfiguration = [
                NetworkProtectionOptionKey.defaultPixelHeaders: APIRequest.Headers().httpHeaders
            ]

            // always-on
            protocolConfiguration.disconnectOnSleep = false

            protocolConfiguration.enforceRoutes = settings.enforceRoutes
            protocolConfiguration.includeAllNetworks = settings.includeAllNetworks
            protocolConfiguration.excludeLocalNetworks = settings.excludeLocalNetworks

            if #available(macOS 13.3, *) {
                protocolConfiguration.excludeAPNs = settings.excludeAPNs
                protocolConfiguration.excludeCellularServices = settings.excludeCellularServices
            }

            if #available(macOS 14.4, *) {
                protocolConfiguration.excludeDeviceCommunication = settings.excludeDeviceCommunication
            }

            return protocolConfiguration
        }()
    }

    // MARK: - Connection & Session

    public var connection: NEVPNConnection? {
        get async {
            await manager?.vpnConnection
        }
    }

    @MainActor
    public func activeSession() async -> NETunnelProviderSession? {
        await session
    }

    @MainActor
    public var session: NETunnelProviderSession? {
        get async {
            guard let manager = await manager,
                  let session = manager.providerSession else {

                // The active connection is not running, so there's no session, this is acceptable
                return nil
            }

            return session
        }
    }

    // MARK: - Connection

    public var status: NEVPNStatus {
        get async {
            await manager?.connectionStatus ?? .disconnected
        }
    }

    // MARK: - Connection Status Querying

    /// Queries the VPN to know if it's connected.
    ///
    /// - Returns: `true` if the VPN is connected, connecting or reasserting, and `false` otherwise.
    ///
    var isConnected: Bool {
        get async {
            switch await manager?.connectionStatus {
            case .connected, .connecting, .reasserting:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Activate System Extension

    /// Checks if the specified configuration is installed.
    ///
    /// We first check if ``internalManager`` exists, and if it does exist we assume it represents the only installed configuration.
    /// We do this because it's best to avoid calling `loadAllFromPreferences` excessively as it triggers VPN status updates when we do.
    /// If it doesn't exist, we load all configurations and check if the one with the specified extension bundle ID exists.
    ///
    func isConfigurationInstalled(extensionBundleID: String) async -> Bool {

        guard let internalManager,
              let configuration = internalManager.protocolConfiguration as? NETunnelProviderProtocol,
              internalManager.connectionStatus != .invalid else {

            guard let allConfigurations = try? await tunnelManagerStore.loadAllManagers() else {
                return false
            }

            return allConfigurations.contains { manager in
                (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionBundleID
            }
        }

        return configuration.providerBundleIdentifier == extensionBundleID
    }

    @MainActor
    func refreshSystemState() async {
        let usesSystemExtension = await extensionResolver.isUsingSystemExtension
        let extensionBundleID = await extensionResolver.activeExtensionBundleID

        let systemExtensionState: SystemExtensionActivationState = if usesSystemExtension {
            await networkExtensionController.systemExtensionActivationState()
        } else {
            .enabled
        }

        let vpnConfigurationState = await vpnConfigurationState(extensionBundleID: extensionBundleID)
        let existingStatus = OnboardingStatus(rawValue: onboardingStatusRawValue) ?? .default

        let resolvedStatus = NetworkProtectionSystemStateResolver.resolvedOnboardingStatus(
            usesSystemExtension: usesSystemExtension,
            systemExtensionState: systemExtensionState,
            vpnConfigurationState: vpnConfigurationState,
            existingStatus: existingStatus
        )

        guard resolvedStatus.rawValue != onboardingStatusRawValue else {
            return
        }

        onboardingStatusRawValue = resolvedStatus.rawValue
    }

    @MainActor
    private func vpnConfigurationState(extensionBundleID: String) async -> NetworkProtectionVPNConfigurationState {
        guard let manager = await manager else {
            return .missingOrInvalid
        }

        do {
            try await manager.loadFromPreferences()
        } catch {
            Logger.networkProtection.error("""
            VPN system state refresh failed to load active tunnel manager from preferences
              expectedExtensionBundleID: \(extensionBundleID, privacy: .public)
              description: \(error.localizedDescription, privacy: .public)
            """)
            clearInternalManager()
            return .missingOrInvalid
        }

        guard let configuration = manager.protocolConfiguration as? NETunnelProviderProtocol,
              configuration.providerBundleIdentifier == extensionBundleID,
              manager.connectionStatus != .invalid else {

            clearInternalManager()
            return .missingOrInvalid
        }

        return manager.isEnabled ? .installedAndEnabled : .installedButDisabled
    }

    /// Ensures that the system extension is activated if necessary.
    ///
    private func activateSystemExtension(waitingForUserApproval: @escaping () -> Void) async throws {

        PixelKit.fire(
            NetworkProtectionPixelEvent.networkProtectionSystemExtensionActivationAttempt,
            frequency: .dailyAndCount,
            includeAppVersionParameter: true)

        do {
            try await networkExtensionController.activateSystemExtension(waitingForUserApproval: waitingForUserApproval)

            PixelKit.fire(
                NetworkProtectionPixelEvent.networkProtectionSystemExtensionActivationSuccess,
                frequency: .dailyAndCount,
                includeAppVersionParameter: true)
        } catch is CancellationError {
            throw StartError.cancelled(step: .systemExtensionActivation)
        } catch {
            switch error {
            case OSSystemExtensionError.requestSuperseded:
                // Even if the installation request is superseded we want to show the message that tells the user
                // to go to System Settings to allow the extension
                controllerErrorStore.lastErrorMessage = UserText.networkProtectionSystemSettings
            case SystemExtensionRequestError.requestTimedOut:
                controllerErrorStore.lastErrorMessage = UserText.networkProtectionSystemSettings
            case SystemExtensionRequestError.unknownRequestResult:
                controllerErrorStore.lastErrorMessage = UserText.networkProtectionUnknownActivationError
            case OSSystemExtensionError.extensionNotFound,
                SystemExtensionRequestError.willActivateAfterReboot:
                controllerErrorStore.lastErrorMessage = UserText.networkProtectionPleaseReboot
            default:
                controllerErrorStore.lastErrorMessage = error.localizedDescription
            }

            PixelKit.fire(
                NetworkProtectionPixelEvent.networkProtectionSystemExtensionActivationFailure(error),
                frequency: .dailyAndCount,
                includeAppVersionParameter: true
            )

            throw error
        }
    }

    // MARK: - Starting & Stopping the VPN

    enum StartError: LocalizedError, CustomNSError {
        case cancelled(step: CancellationStep)
        case noAuthToken
        case connectionStatusInvalid
        case simulateControllerFailureError
        case startTunnelFailure(_ error: Error)
        case failedToFetchAuthToken(_ error: Error)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return nil
            case .noAuthToken:
                return "You need a subscription to start the VPN"
            case .connectionStatusInvalid:
#if DEBUG
                return "[DEBUG] Connection status invalid"
#else
                return "An unexpected error occurred, please try again"
#endif
            case .simulateControllerFailureError:
                return "Simulated a controller error as requested"
            case .startTunnelFailure(let error),
                    .failedToFetchAuthToken(let error):
                return error.localizedDescription
            }
        }

        var errorCode: Int {
            switch self {
            case .cancelled: return 0
                // MARK: Setup errors
            case .noAuthToken: return 1
            case .connectionStatusInvalid: return 2
            case .simulateControllerFailureError: return 4
                // MARK: Actual connection attempt issues
            case .startTunnelFailure: return 100
                // MARK: Auth errors
            case .failedToFetchAuthToken: return 201
            }
        }

        var errorUserInfo: [String: Any] {
            switch self {
            case .cancelled,
                    .noAuthToken,
                    .connectionStatusInvalid,
                    .simulateControllerFailureError:
                return [:]
            case .startTunnelFailure(let error),
                    .failedToFetchAuthToken(let error):
                return [NSUnderlyingErrorKey: error]
            }
        }

        public var caseDescription: String {
            switch self {
            case .cancelled(let step):
                return "cancelled(\(step.rawValue))"
            case .noAuthToken:
                return "noAuthToken"
            case .connectionStatusInvalid:
                return "connectionStatusInvalid"
            case .simulateControllerFailureError:
                return "simulateControllerFailureError"
            case .startTunnelFailure:
                return "startTunnelFailure"
            case .failedToFetchAuthToken:
                return "failedToFetchAuthToken"
            }
        }
    }

    /// What a single VPN enable attempt actually ended up doing.
    ///
    /// Distinct from ``StartError``: several situations that currently throw are not failures from the
    /// user's point of view, and two that currently return normally are not successes. Naming them here
    /// means the decision about how each is reported lives in exactly one place, ``report(_:trigger:)``.
    enum StartOutcome {
        /// The tunnel was started and the startup monitor confirmed a connection.
        case connected

        /// The tunnel connected, but its on-demand rule could not be saved afterwards.
        case connectedWithoutOnDemand(Error)

        /// Activation completed while the extension still awaits the user's approval, so the start was
        /// paused and System Settings was opened. No tunnel was started.
        case awaitingExtensionApproval

        /// A start arrived while the tunnel was already connected, so it was stopped to allow recovery.
        case stoppedBecauseAlreadyConnected

        /// The token the extension needs was obtained, but the follow-up refresh that branches the app's
        /// token from the extension's failed.
        case tokenBranchRefreshFailed(Error)

        /// The user was shown the system extension approval prompt and did not answer it in time.
        case approvalPromptTimedOut(Error)

        /// The start was cancelled at a known step.
        case cancelled(step: CancellationStep)

        /// Any other failure. The reported error's domain and code already separate auth failures,
        /// tunnel start failures and unusable configurations, so they do not need their own cases.
        case failed(Error)

        /// Stable wire value for the `outcome` pixel parameter. These strings are duplicated in the
        /// `vpnStartOutcome` enum in the pixel definitions, so treat them as an external contract.
        var name: String {
            switch self {
            case .connected: return "connected"
            case .connectedWithoutOnDemand: return "connected_without_on_demand"
            case .awaitingExtensionApproval: return "awaiting_extension_approval"
            case .stoppedBecauseAlreadyConnected: return "stopped_because_already_connected"
            case .tokenBranchRefreshFailed: return "token_branch_refresh_failed"
            case .approvalPromptTimedOut: return "approval_prompt_timed_out"
            case .cancelled: return "cancelled"
            case .failed: return "failed"
            }
        }
    }

    /// What caused a start attempt. Only ``userInitiated`` belongs in a "user enables the VPN" metric.
    ///
    /// A different axis from `VPNConnectionWideEventData.ScreenSource`, which records which in-app surface
    /// a user came from. Neither replaces the other.
    enum StartTrigger: String {
        case userInitiated = "user_initiated"
        case connectOnLogin = "connect_on_login"
        case appUpdateRestart = "app_update_restart"
        case settingsChangeRestart = "settings_change_restart"
    }

    /// `TunnelController` conformance. That protocol is shared with iOS, so it stays parameterless and
    /// forwards the only trigger a protocol caller can represent.
    @MainActor
    func start() async {
        await start(trigger: .userInitiated)
    }

    /// Starts the VPN connection
    ///
    /// Handles all the top level error management logic.
    ///
    @MainActor
    func start(trigger: StartTrigger) async {
        Logger.networkProtection.log("🚀 Start VPN")
        await refreshSystemState()
        setupAndStartConnectionWideEvent()
        VPNOperationErrorRecorder().beginRecordingControllerStart()
        PixelKit.fire(NetworkProtectionPixelEvent.networkProtectionControllerStartAttempt,
                      frequency: .legacyDailyAndCount,
                      withAdditionalParameters: [PixelKit.Parameters.vpnStartTrigger: trigger.rawValue])

        controllerErrorStore.lastErrorMessage = nil

        let outcome: StartOutcome

        do {
            outcome = try await start(isFirstAttempt: true)
        } catch {
            outcome = Self.outcome(from: error)
        }

        report(outcome, trigger: trigger)
    }

    /// Maps a thrown error onto the outcome it represents. The only place errors become outcomes.
    private static func outcome(from error: Error) -> StartOutcome {
        switch error {
        case is CancellationError:
            return .cancelled(step: .unknown)
        case StartError.cancelled(let step):
            return .cancelled(step: step)
        case let branchFailure as TokenBranchRefreshFailure:
            return .tokenBranchRefreshFailed(branchFailure.underlyingError)
        case SystemExtensionRequestError.requestTimedOut:
            return .approvalPromptTimedOut(error)
        default:
            return .failed(error)
        }
    }

    /// The single place an enable attempt's outcome becomes a signal.
    ///
    /// This mapping intentionally reproduces the reporting that existed before this function did, including
    /// six outcomes reported as the wrong thing. Those are marked MISREPORTED. Correcting one is a change to
    /// one branch here, plus the test that pins it.
    @MainActor
    private func report(_ outcome: StartOutcome, trigger: StartTrigger) {
        let sharedParameters = [
            PixelKit.Parameters.vpnStartOutcome: outcome.name,
            PixelKit.Parameters.vpnStartTrigger: trigger.rawValue
        ]

        switch outcome {
        case .connected:
            fireStartSuccess(with: sharedParameters)
            completeAndCleanupConnectionWideEvent(status: .success)

        case .awaitingExtensionApproval:
            // MISREPORTED: no tunnel was started, the user still has to approve the extension.
            fireStartSuccess(with: sharedParameters)
            completeAndCleanupAtStepWithPartialSuccess()

        case .stoppedBecauseAlreadyConnected:
            // MISREPORTED: the VPN was turned off, not on.
            fireStartSuccess(with: sharedParameters)
            completeAndCleanupConnectionWideEvent(status: .success)

        case .connectedWithoutOnDemand(let error):
            // MISREPORTED: the tunnel is up and confirmed; only its on-demand rule is missing.
            let reportedError = StartError.startTunnelFailure(error)
            recordOperationFailure(reportedError)
            fireStartFailure(reportedError, with: sharedParameters)
            completeAndCleanupConnectionWideEvent(status: .failure, error: reportedError, description: reportedError.caseDescription)

        case .tokenBranchRefreshFailed(let error):
            // MISREPORTED: the token the extension needs was already in hand.
            // The original error is reported, so the domain and code stay SubscriptionManagerError / 12001.
            recordOperationFailure(error)
            fireStartFailure(error, with: sharedParameters)
            completeAndCleanupConnectionWideEvent(status: .failure, error: error, description: error.contextualizedDescription())

        case .approvalPromptTimedOut(let error):
            // MISREPORTED: the user walked away from an approval prompt, which isn't a product failure.
            recordOperationFailure(error)
            fireStartFailure(error, with: sharedParameters)
            completeAndCleanupConnectionWideEvent(status: .failure, error: error, description: error.contextualizedDescription())

        case .cancelled(let step):
            let reportedError = StartError.cancelled(step: step)
            recordOperationFailure(reportedError)
            PixelKit.fire(
                NetworkProtectionPixelEvent.networkProtectionControllerStartCancelled(step: step),
                frequency: .legacyDailyAndCount,
                withAdditionalParameters: sharedParameters,
                includeAppVersionParameter: true
            )
            completeAndCleanupConnectionWideEvent(status: .cancelled, error: reportedError, description: reportedError.contextualizedDescription())

        case .failed(let error):
            Logger.networkProtection.error("Controller start tunnel failure: \(error, privacy: .public)")
            recordOperationFailure(error)
            fireStartFailure(error, with: sharedParameters)
            completeAndCleanupConnectionWideEvent(status: .failure, error: error, description: error.contextualizedDescription())
        }
    }

    /// Note this fires even for outcomes where no tunnel was started. It should be read as "the controller
    /// completed a start attempt without raising an error", which is what it has always meant. The outcome
    /// parameter is what distinguishes a confirmed connection from the rest.
    private func fireStartSuccess(with parameters: [String: String]) {
        PixelKit.fire(
            NetworkProtectionPixelEvent.networkProtectionControllerStartSuccess,
            frequency: .legacyDailyAndCount,
            withAdditionalParameters: parameters
        )
        Logger.networkProtection.log("Controller start tunnel success")
    }

    private func fireStartFailure(_ error: Error, with parameters: [String: String]) {
        PixelKit.fire(
            NetworkProtectionPixelEvent.networkProtectionControllerStartFailure(error),
            frequency: .legacyDailyAndCount,
            withAdditionalParameters: parameters,
            includeAppVersionParameter: true
        )

        // Always keep the first error message shown, as it's the more actionable one: system extension
        // activation may already have written something the user can act on.
        if controllerErrorStore.lastErrorMessage == nil {
            controllerErrorStore.lastErrorMessage = error.localizedDescription
        }
    }

    /// Written for every error-derived outcome, cancellations included, matching the behaviour this
    /// replaced. Whether a cancellation should be remembered as a known failure is a separate question.
    private func recordOperationFailure(_ error: Error) {
        VPNOperationErrorRecorder().recordControllerStartFailure(error)
        knownFailureStore.lastKnownFailure = KnownFailure(error)
    }

    @MainActor
    private func start(isFirstAttempt: Bool) async throws -> StartOutcome {
        self.connectionWideEventData?.controllerStartDuration = WideEvent.MeasuredInterval.startingNow()
        if await extensionResolver.isUsingSystemExtension {
            self.connectionWideEventData?.extensionType = .system
            try await activateSystemExtension { [weak self] in
                // If we're waiting for user approval we wanna make sure the
                // onboarding step is set correctly.  This can be useful to
                // help prevent the value from being de-synchronized.
                self?.onboardingStatusRawValue = OnboardingStatus.isOnboarding(step: .userNeedsToAllowExtension).rawValue
            }

            self.controllerErrorStore.lastErrorMessage = nil

            // If activation leaves us on the system extension onboarding step, verify
            // the real system state before deciding whether to advance. Activation may
            // complete even when the user has manually disabled the extension.
            if onboardingStatusRawValue == OnboardingStatus.isOnboarding(step: .userNeedsToAllowExtension).rawValue {
                await refreshSystemState()

                let refreshedStatus = OnboardingStatus(rawValue: onboardingStatusRawValue) ?? .default
                guard NetworkProtectionSystemStateResolver.shouldContinueStartingTunnel(afterSystemExtensionActivation: refreshedStatus) else {
                    Logger.networkProtection.info("""
                    Pausing VPN start after system extension activation
                      refreshedOnboardingStatus: \(refreshedStatus.rawValue, privacy: .public)
                    """)
                    networkExtensionController.openSystemExtensionSettings()
                    return .awaitingExtensionApproval
                }
            }
        } else {
            self.connectionWideEventData?.extensionType = .app
        }

        let tunnelManager: any VPNTunnelManaging

        do {
            tunnelManager = try await loadOrMakeTunnelManager()
        } catch {
            if case NEVPNError.configurationReadWriteFailed = error {
                onboardingStatusRawValue = OnboardingStatus.isOnboarding(step: .userNeedsToAllowVPNConfiguration).rawValue
                recordStepFailure(.controllerStart, with: error, description: StartError.cancelled(step: .tunnelManagerLoad).caseDescription)
                throw StartError.cancelled(step: .tunnelManagerLoad)
            }

            recordStepFailure(.controllerStart, with: error, description: error.contextualizedDescription())
            throw error
        }
        onboardingStatusRawValue = OnboardingStatus.completed.rawValue

        switch tunnelManager.connectionStatus {
        case .invalid:
            // This means the VPN isn't configured, so let's drop our cached
            // manager and try again

            guard isFirstAttempt else {
                recordStepFailure(.controllerStart, with: StartError.connectionStatusInvalid, description: StartError.connectionStatusInvalid.caseDescription)
                throw StartError.connectionStatusInvalid
            }

            clearInternalManager()
            resetControllerStartWideEventMeasurement()
            return try await start(isFirstAttempt: false)
        case .connected:
            Logger.networkProtection.error("Start requested while already connected - stopping VPN to allow recovery")
            await stop()
            return .stoppedBecauseAlreadyConnected
        default:
            self.connectionWideEventData?.controllerStartDuration?.complete()
            return try await start(tunnelManager)
        }
    }

    @MainActor
    private func start(_ tunnelManager: any VPNTunnelManaging) async throws -> StartOutcome {
        settings.updateExcludeCGNAT(isFeatureEnabled: featureFlagger.isFeatureOn(.vpnExcludeCGNATToggle))

        let options = try await prepareStartupOptions()

        if Self.simulationOptions.isEnabled(.controllerFailure) {
            Self.simulationOptions.setEnabled(false, option: .controllerFailure)
            throw StartError.simulateControllerFailureError
        }

        do {
            Logger.networkProtection.log("🚀 Starting NetworkProtectionTunnelController, options: \(options, privacy: .public)")
            self.connectionWideEventData?.tunnelStartDuration = WideEvent.MeasuredInterval.startingNow()
            try tunnelManager.startTunnel(options: options)
            try await tunnelManager.waitForStartSuccess()
        } catch is CancellationError {
            Logger.networkProtection.log("VPN tunnel start cancelled")
            throw StartError.cancelled(step: .tunnelConnection)
        } catch {
            Logger.networkProtection.fault("🔴 Failed to start VPN tunnel: \(error, privacy: .public)")
            recordStepFailure(.tunnelStart, with: error, description: StartError.startTunnelFailure(error).caseDescription)
            throw StartError.startTunnelFailure(error)
        }

        var outcome = StartOutcome.connected

        // The tunnel is up and confirmed by this point. Failing to persist the on-demand rule leaves the
        // user with a working VPN, so it gets its own outcome even though it's still reported as a tunnel
        // start failure.
        do {
            try await self.enableOnDemand(tunnelManager: tunnelManager)
            self.connectionWideEventData?.tunnelStartDuration?.complete()
        } catch is CancellationError {
            Logger.networkProtection.log("VPN tunnel start cancelled")
            throw StartError.cancelled(step: .tunnelConnection)
        } catch {
            Logger.networkProtection.fault("🔴 Failed to enable VPN on-demand: \(error, privacy: .public)")
            recordStepFailure(.tunnelStart, with: error, description: StartError.startTunnelFailure(error).caseDescription)
            outcome = .connectedWithoutOnDemand(error)
        }

        // Gated on a confirmed connection so that an on-demand failure suppresses this exactly as the
        // previous single-throw structure did, leaving first-enable attribution unchanged.
        if case .connected = outcome {
            PixelKit.fire(
                NetworkProtectionPixelEvent.networkProtectionNewUser,
                frequency: .uniqueByName,
                includeAppVersionParameter: true) { [weak self] fired, error in
                    guard let self, error == nil, fired else { return }
                    self.defaults.vpnFirstEnabled = try? PixelKit.pixelLastFireDate(event: NetworkProtectionPixelEvent.networkProtectionNewUser, frequency: .uniqueByName)
                }
        }

        return outcome
    }

    /// Marks a failure of the post-fetch token branching refresh, so the top-level handler doesn't have to
    /// infer it from which layer happened to wrap the error. Carries the original error, which is what gets
    /// reported, so the pixel's domain and code are unchanged.
    struct TokenBranchRefreshFailure: Error {
        let underlyingError: Error
    }

    func prepareStartupOptions() async throws -> [String: NSObject] {
        Logger.networkProtection.log("Preparing startup options")
        var options = [String: NSObject]()
        options[NetworkProtectionOptionKey.activationAttemptId] = UUID().uuidString as NSString
        self.connectionWideEventData?.oauthDuration = WideEvent.MeasuredInterval.startingNow()
        let tokenContainer = try await fetchTokenContainer()
        options[NetworkProtectionOptionKey.tokenContainer] = tokenContainer.data

        // It’s important to force refresh the token here to immediately branch the token used by the main app
        // from the one sent to the system extension.
        // See discussion https://app.asana.com/0/1199230911884351/1208785842165508/f
        do {
            try await subscriptionManager.getTokenContainer(policy: .localForceRefresh)
        } catch {
            throw TokenBranchRefreshFailure(underlyingError: error)
        }
        self.connectionWideEventData?.oauthDuration?.complete()

        // Encode entire VPN settings as one unit
        let settingsSnapshot = VPNSettingsSnapshot(from: settings)
        if let data = try? JSONEncoder().encode(settingsSnapshot) {
            options[NetworkProtectionOptionKey.settings] = NSData(data: data)
        }

        if Self.simulationOptions.isEnabled(.tunnelFailure) {
            Self.simulationOptions.setEnabled(false, option: .tunnelFailure)
            options[NetworkProtectionOptionKey.tunnelFailureSimulation] = NSNumber(value: true)
        }

        if Self.simulationOptions.isEnabled(.crashFatalError) {
            Self.simulationOptions.setEnabled(false, option: .crashFatalError)
            options[NetworkProtectionOptionKey.tunnelFatalErrorCrashSimulation] = NSNumber(value: true)
        }

        return options
    }

    /// Stops the VPN connection
    ///
    @MainActor
    func stop() async {
        Logger.networkProtection.log("🛑 Stop VPN")
        await stop(disableOnDemand: true)
    }

    @MainActor
    func stop(disableOnDemand: Bool) async {
        guard let manager = await manager else {
            return
        }

        await stop(tunnelManager: manager, disableOnDemand: disableOnDemand)
    }

    @MainActor
    private func stop(tunnelManager: any VPNTunnelManaging, disableOnDemand: Bool) async {
        if disableOnDemand {
            try? await self.disableOnDemand(tunnelManager: tunnelManager)
        }

        switch tunnelManager.connectionStatus {
        case .connected, .connecting, .reasserting:
            tunnelManager.stopTunnel()
        default:
            break
        }
    }

    func command(_ command: VPNCommand) async throws {
        try await sendProviderMessageToActiveSession(.request(.command(command)))
    }

    /// Restarts the tunnel.
    ///
    @MainActor
    func restart(trigger: StartTrigger) async {
        guard let internalManager else {
            // This is a temporary thing because we know this method works well
            // in case we need to roll back auth v2
            await stop(disableOnDemand: false)
            return
        }

        await stop(disableOnDemand: true)
        await start(trigger: trigger)
        try? await enableOnDemand(tunnelManager: internalManager)
    }

    // MARK: - On Demand & Kill Switch

    @MainActor
    func enableOnDemand(tunnelManager: any VPNTunnelManaging) async throws {
        try await tunnelManager.loadFromPreferences()

        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any

        tunnelManager.onDemandRules = [rule]
        tunnelManager.isOnDemandEnabled = true

        try await tunnelManager.saveToPreferences()
    }

    @MainActor
    func disableOnDemand(tunnelManager: any VPNTunnelManaging) async throws {
        try await tunnelManager.loadFromPreferences()

        guard tunnelManager.connectionStatus != .invalid else {
            // An invalid connection status means the VPN isn't really configured
            // so we don't want to save changed because that would re-create the VPN
            // configuration.
            clearInternalManager()
            return
        }

        tunnelManager.isOnDemandEnabled = false

        try await tunnelManager.saveToPreferences()
    }

    struct TunnelFailureError: LocalizedError {
        let errorDescription: String?
    }

    @MainActor
    func toggleShouldSimulateTunnelFailure() async throws {
        if Self.simulationOptions.isEnabled(.tunnelFailure) {
            Self.simulationOptions.setEnabled(false, option: .tunnelFailure)
        } else {
            Self.simulationOptions.setEnabled(true, option: .tunnelFailure)
            try await sendProviderMessageToActiveSession(.simulateTunnelFailure)
        }
    }

    @MainActor
    func toggleShouldSimulateTunnelFatalError() async throws {
        if Self.simulationOptions.isEnabled(.crashFatalError) {
            Self.simulationOptions.setEnabled(false, option: .crashFatalError)
        } else {
            Self.simulationOptions.setEnabled(true, option: .crashFatalError)
            try await sendProviderMessageToActiveSession(.simulateTunnelFatalError)
        }
    }

    @MainActor
    func toggleShouldSimulateConnectionInterruption() async throws {
        if Self.simulationOptions.isEnabled(.connectionInterruption) {
            Self.simulationOptions.setEnabled(false, option: .connectionInterruption)
        } else {
            Self.simulationOptions.setEnabled(true, option: .connectionInterruption)
            try await sendProviderMessageToActiveSession(.simulateConnectionInterruption)
        }
    }

    @MainActor
    private func sendProviderRequestToActiveSession(_ request: ExtensionRequest) async throws {
        try await sendProviderMessageToActiveSession(.request(request))
    }

    @MainActor
    private func sendProviderMessageToActiveSession(_ message: ExtensionMessage) async throws {
        guard await isConnected,
              let session = await session else {
            return
        }

        let errorMessage: ExtensionMessageString? = try await session.sendProviderMessage(message)
        if let errorMessage {
            throw TunnelFailureError(errorDescription: errorMessage.value)
        }
    }

    private func fetchTokenContainer() async throws -> TokenContainer {
        do {
            let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
            Logger.networkProtection.log("🟢 TunnelController found token container")
            return tokenContainer
        } catch {
            switch error {
            case SubscriptionManagerError.noTokenAvailable:
                Logger.networkProtection.fault("🔴 TunnelController found no token container")
                throw StartError.noAuthToken
            default:
                Logger.networkProtection.fault("🔴 TunnelController failed to fetch token container: \(error.localizedDescription)")
                throw StartError.failedToFetchAuthToken(error)
            }
        }
    }

    private static func adaptAccessTokenForVPN(_ token: String) -> String {
        "ddg:\(token)"
    }
}

// MARK: - Wide Event

private extension NetworkProtectionTunnelController {

    func setupAndStartConnectionWideEvent() {
        completeAllPendingVPNConnectionPixels()
        let data = VPNConnectionWideEventData(
            extensionType: .unknown,
            startupMethod: .manualByMainApp,
            isSetup: onboardingStatusRawValue == OnboardingStatus.completed.rawValue ? .no : .yes,
            onboardingStatus: .init(from: onboardingStatusRawValue),
            contextData: WideEventContextData(name: NetworkProtectionFunnelOrigin.agent.rawValue)
        )
        self.connectionWideEventData = data
        syncWideEventOnboardingStatus()
        prefillBrowserStartDataIfAvailable()
        wideEvent.startFlow(data)
        if data.overallDuration == nil {
            data.overallDuration = WideEvent.MeasuredInterval.startingNow()
        }
    }

    func prefillBrowserStartDataIfAvailable() {
        guard let data = connectionWideEventData else { return }
        guard let vpnConnectionWideEventBrowserStartTime, let vpnConnectionWideEventOverallStartTime else { return }
        data.contextData = WideEventContextData(name: NetworkProtectionFunnelOrigin.appSettings.rawValue)
        data.browserStartDuration = WideEvent.MeasuredInterval(start: vpnConnectionWideEventBrowserStartTime)
        data.browserStartDuration?.complete()
        data.overallDuration = WideEvent.MeasuredInterval(start: vpnConnectionWideEventOverallStartTime)
        self.vpnConnectionWideEventBrowserStartTime = nil
        self.vpnConnectionWideEventOverallStartTime = nil
    }

    func resetControllerStartWideEventMeasurement() {
        connectionWideEventData?.controllerStartDuration = nil
    }

    /// Records that a step errored, without completing the flow. The top-level start handler completes the
    /// wide event once, so cancellations and failures are classified in a single place.
    func recordStepFailure(_ step: VPNConnectionWideEventData.Step, with error: Error, description: String? = nil) {
        connectionWideEventData?[keyPath: step.errorPath] = .init(error: error, description: description)
        connectionWideEventData?[keyPath: step.durationPath]?.complete()
    }

    func completeAndCleanupAtStepWithPartialSuccess(_ step: VPNConnectionWideEventData.Step = .controllerStart) {
        connectionWideEventData?[keyPath: step.durationPath]?.complete()
        completeAndCleanupConnectionWideEvent(status: .success(reason: VPNConnectionWideEventData.StatusReason.partialData.rawValue))
    }

    func completeAndCleanupConnectionWideEvent(status: WideEventStatus, error: Error? = nil, description: String? = nil) {
        guard let data = connectionWideEventData else { return }
        data.overallDuration?.complete()
        if let error {
            data.errorData = .init(error: error, description: description)
        }
        wideEvent.completeFlow(data, status: status, onComplete: { _, _ in })
        connectionWideEventData = nil
    }

    func completeAllPendingVPNConnectionPixels() {
        let pending = wideEvent.getAllFlowData(VPNConnectionWideEventData.self)
        for data in pending {
            guard let start = data.overallDuration?.start, data.overallDuration?.end == nil else {
                wideEvent.completeFlow(data, status: .unknown(reason: VPNConnectionWideEventData.StatusReason.partialData.rawValue), onComplete: { _, _ in })
                continue
            }

            let timeoutDate = start.addingTimeInterval(connectionControllerTimeoutInterval)
            let reason: VPNConnectionWideEventData.StatusReason = Date() >= timeoutDate ? .timeout : .retried
            wideEvent.completeFlow(data, status: .unknown(reason: reason.rawValue), onComplete: { _, _ in })
        }
    }

    func syncWideEventOnboardingStatus() {
        connectionWideEventData?.onboardingStatus = .init(from: onboardingStatusRawValue)
    }
}

fileprivate extension VPNConnectionWideEventData.MacOSOnboardingStatus {
    init(from rawValue: OnboardingStatus.RawValue) {
        if rawValue == OnboardingStatus.completed.rawValue {
            self = .completed
            return
        }
        if rawValue == OnboardingStatus.isOnboarding(step: .userNeedsToAllowExtension).rawValue {
            self = .needsToAllowExtension
            return
        }
        if rawValue == OnboardingStatus.isOnboarding(step: .userNeedsToAllowVPNConfiguration).rawValue {
            self = .needsToAllowVPNConfiguration
            return
        }
        self = .unknown
    }
}

// MARK: - Error Description Helper

private extension Error {
    func contextualizedDescription() -> String? {
        return (self as? NetworkProtectionTunnelController.StartError)?.caseDescription
    }
}

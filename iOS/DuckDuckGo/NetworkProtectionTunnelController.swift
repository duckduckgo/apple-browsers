//
//  NetworkProtectionTunnelController.swift
//  DuckDuckGo
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
import Common
import FoundationExtensions
import Core
import Foundation
import NetworkExtension
import VPN
import Subscription
import PixelKit

enum VPNConfigurationRemovalReason: String {
    case didBecomeActiveCheck
    case entitlementCheck
    case signedOut
    case debugMenu
}

final class NetworkProtectionTunnelController: VPNConnectionContextProvidingTunnelController, TunnelSessionProvider {
    static var shouldSimulateFailure: Bool = false

    private let featureFlagger: FeatureFlagger
    private var internalManager: NETunnelProviderManager?
    private let debugFeatures = NetworkProtectionDebugFeatures()
    private let tokenHandler: any SubscriptionTokenHandling
    private let errorStore = NetworkProtectionTunnelErrorStore()
    private let snoozeTimingStore = NetworkProtectionSnoozeTimingStore(userDefaults: .networkProtectionGroupDefaults)
    private let notificationCenter: NotificationCenter = .default
    private var previousStatus: NEVPNStatus = .invalid
    private let persistentPixel: PersistentPixelFiring
    private let settings: VPNSettings
    private lazy var startupMonitor = VPNStartupMonitor()
    private var cancellables = Set<AnyCancellable>()

    /// Carries user-facing messages for controller-side (pre-session) start failures.
    ///
    /// The status view surfaces connection errors through the tunnel session, but failures that abort
    /// before the session is created (e.g. a missing auth token) never reach that observer. This subject
    /// gives those pre-session failures a channel to the UI; `nil` means "no error to show".
    private let controllerErrorSubject = CurrentValueSubject<String?, Never>(nil)
    var controllerErrorPublisher: AnyPublisher<String?, Never> {
        controllerErrorSubject.eraseToAnyPublisher()
    }

    // Wide Event
    private let wideEvent: WideEventManaging
    private var connectionWideEventData: VPNConnectionWideEventData?
    private let freeTrialConversionService: FreeTrialConversionInstrumentationService

    // MARK: - Manager, Session, & Connection

    /// The tunnel manager: will try to load if it its not loaded yet, but if one can't be loaded from preferences,
    /// a new one will not be created.  This is useful for querying the connection state and information without triggering
    /// a VPN-access popup to the user.
    ///
    @MainActor var tunnelManager: NETunnelProviderManager? {
        get async {
            if let internalManager {
                return internalManager
            }

            let loadedManager = try? await NETunnelProviderManager.loadAllFromPreferences().first
            internalManager = loadedManager
            return loadedManager
        }
    }

    public var connection: NEVPNConnection? {
        get async {
            await tunnelManager?.connection
        }
    }

    public func activeSession() async -> NETunnelProviderSession? {
        await session
    }

    public var session: NETunnelProviderSession? {
        get async {
            guard let manager = await tunnelManager, let session = manager.connection as? NETunnelProviderSession else {
                return nil
            }

            return session
        }
    }

    // MARK: - Starting & Stopping the VPN

    enum StartError: LocalizedError, CustomNSError {
        case simulateControllerFailureError
        case loadFromPreferencesFailed(Error)
        case saveToPreferencesFailed(Error)
        case startVPNFailed(Error)
        case failedToFetchAuthToken(Error)
        case configSystemPermissionsDenied(Error)
        case noAuthToken

        public var errorCode: Int {
            switch self {
            case .simulateControllerFailureError: 0
            case .loadFromPreferencesFailed: 1
            case .saveToPreferencesFailed: 2
            case .startVPNFailed: 3
            case .failedToFetchAuthToken: 4
            case .configSystemPermissionsDenied: 5
            case .noAuthToken: 6
            }
        }

        public var errorUserInfo: [String: Any] {
            switch self {
            case .noAuthToken,
                    .simulateControllerFailureError:
                return [:]
            case
                    .loadFromPreferencesFailed(let error),
                    .saveToPreferencesFailed(let error),
                    .startVPNFailed(let error),
                    .failedToFetchAuthToken(let error),
                    .configSystemPermissionsDenied(let error):
                return [NSUnderlyingErrorKey: error]
            }
        }
        
        public var caseDescription: String {
            switch self {
                case .simulateControllerFailureError:
                    return "simulateControllerFailureError"
                case .loadFromPreferencesFailed:
                    return "loadFromPreferencesFailed"
                case .saveToPreferencesFailed:
                    return "saveToPreferencesFailed"
                case .startVPNFailed:
                    return "startVPNFailed"
                case .failedToFetchAuthToken:
                    return "failedToFetchAuthToken"
                case .configSystemPermissionsDenied:
                    return "configSystemPermissionsDenied"
                case .noAuthToken:
                    return "noAuthToken"
                }
        }
    }

    // MARK: - Initializers

    init(tokenHandler: any SubscriptionTokenHandling,
         featureFlagger: FeatureFlagger,
         persistentPixel: PersistentPixelFiring,
         settings: VPNSettings,
         wideEvent: WideEventManaging,
         freeTrialConversionService: FreeTrialConversionInstrumentationService
    ) {

        self.featureFlagger = featureFlagger
        self.persistentPixel = persistentPixel
        self.settings = settings
        self.tokenHandler = tokenHandler
        self.wideEvent = wideEvent
        self.freeTrialConversionService = freeTrialConversionService

        subscribeToSnoozeTimingChanges()
        subscribeToStatusChanges()
        subscribeToConfigurationChanges()
        subscribeToSettingsChanges()
    }

    /// Starts the VPN connection used for Network Protection
    ///
    func start() async {
        await start(with: nil)
    }

    func start(entryContext: VPNConnectionWideEventData.EntryContext) async {
        await start(with: entryContext)
    }

    private func start(with entryContext: VPNConnectionWideEventData.EntryContext?) async {
        setupAndStartConnectionWideEvent(entryContext: entryContext)
        controllerErrorSubject.send(nil)
        persistentPixel.fire(
            pixel: .networkProtectionControllerStartAttempt,
            error: nil,
            includedParameters: [.appVersion],
            withAdditionalParameters: [:],
            onComplete: { _ in })

        do {
            try await startWithError()
            completeAndCleanupConnectionWideEvent()

            persistentPixel.fire(
                pixel: .networkProtectionControllerStartSuccess,
                error: nil,
                includedParameters: [.appVersion],
                withAdditionalParameters: [:],
                onComplete: { _ in })
        } catch {
            if let message = userFacingControllerErrorMessage(for: error) {
                controllerErrorSubject.send(message)
            }

            completeAndCleanupConnectionWideEvent(with: error, description: error.contextualizedDescription())
            if case StartError.configSystemPermissionsDenied = error {
                return
            }

            persistentPixel.fire(
                pixel: .networkProtectionControllerStartFailure,
                error: error,
                includedParameters: [.appVersion],
                withAdditionalParameters: [:],
                onComplete: { _ in })

            #if DEBUG
            errorStore.lastErrorMessage = error.localizedDescription
            #endif
        }
    }

    /// Maps a start failure to the user-facing message the status view should show, reusing the existing
    /// `VPNConnectionError` copy. Returns `nil` for failures the user should not see a banner for:
    /// `configSystemPermissionsDenied` (the user deliberately declined the system prompt) and
    /// `startVPNFailed` (which happens after the tunnel session exists, so the session-based error
    /// observer already surfaces it).
    private func userFacingControllerErrorMessage(for error: Error) -> String? {
        guard let startError = error as? StartError else {
            return nil
        }

        let connectionError: VPNConnectionError
        switch startError {
        case .noAuthToken, .failedToFetchAuthToken:
            connectionError = .authenticationFailed
        case .loadFromPreferencesFailed, .saveToPreferencesFailed, .simulateControllerFailureError:
            connectionError = .connectionFailed
        case .configSystemPermissionsDenied, .startVPNFailed:
            return nil
        }

        return connectionError.localizedMessage
    }

    func stop() async {
        guard let tunnelManager = await self.tunnelManager else {
            return
        }

        do {
            try await disableOnDemand(tunnelManager: tunnelManager)
        } catch {
            #if DEBUG
            errorStore.lastErrorMessage = error.localizedDescription
            #endif
        }

        tunnelManager.connection.stopVPNTunnel()
    }

    func restart() async {
        guard let internalManager else {
            await stop()
            return
        }

        await stop()
        await startupMonitor.waitForStop(internalManager)
        await start()
        try? await enableOnDemand(tunnelManager: internalManager)
    }

    func command(_ command: VPNCommand) async throws {
        guard let activeSession = await AppDependencyProvider.shared.networkProtectionTunnelController.activeSession(),
            activeSession.status == .connected else {

            return
        }

        try? await activeSession.sendProviderRequest(.command(command))
    }

    func removeVPN(reason: VPNConfigurationRemovalReason) async {
        do {
            try await tunnelManager?.removeFromPreferences()

            DailyPixel.fireDailyAndCount(pixel: .networkProtectionVPNConfigurationRemoved,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                                         withAdditionalParameters: [PixelParameters.reason: reason.rawValue])
        } catch {
            DailyPixel.fireDailyAndCount(pixel: .networkProtectionVPNConfigurationRemovalFailed,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                                         error: error,
                                         withAdditionalParameters: [PixelParameters.reason: reason.rawValue])
        }
    }

    // MARK: - Connection Status Querying

    var isInstalled: Bool {
        get async {
            return await self.tunnelManager != nil
        }
    }

    /// Queries Network Protection to know if its VPN is connected.
    ///
    /// - Returns: `true` if the VPN is connected, connecting or reasserting, and `false` otherwise.
    ///
    var isConnected: Bool {
        get async {
            guard let tunnelManager = await self.tunnelManager else {
                return false
            }

            switch tunnelManager.connection.status {
            case .connected, .connecting, .reasserting:
                return true
            default:
                return false
            }
        }
    }

    private func startWithError() async throws {
        let tunnelManager: NETunnelProviderManager

        do {
            self.connectionWideEventData?.controllerStartDuration = WideEvent.MeasuredInterval.startingNow()
            tunnelManager = try await loadOrMakeTunnelManager()
            self.connectionWideEventData?.controllerStartDuration?.complete()
        } catch {
            completeAtStepWithFailure(.controllerStart, with: error, description: error.contextualizedDescription())
            throw error
        }

        switch tunnelManager.connection.status {
        case .invalid:
            clearInternalManager()
            resetControllerStartWideEventMeasurement()
            try await startWithError()
        case .connected:
            Logger.networkProtection.error("Start requested while already connected - stopping VPN to allow recovery")
            await stop()
        default:
            try await start(tunnelManager)
        }
    }

    private func clearInternalManager() {
        internalManager = nil
    }

    private func start(_ tunnelManager: NETunnelProviderManager) async throws {
        settings.updateExcludeCGNAT(isFeatureEnabled: featureFlagger.isFeatureOn(.vpnExcludeCGNATToggle))

        var options = [String: NSObject]()

        if Self.shouldSimulateFailure {
            Self.shouldSimulateFailure = false
            throw StartError.simulateControllerFailureError
        }

        options["activationAttemptId"] = UUID().uuidString as NSString

        
        do {
            self.connectionWideEventData?.oauthDuration = WideEvent.MeasuredInterval.startingNow()
            try await tokenHandler.getToken()
            self.connectionWideEventData?.oauthDuration?.complete()
        } catch {
            switch error {
            case SubscriptionManagerError.noTokenAvailable:
                completeAtStepWithFailure(.oauth, with: error, description: error.contextualizedDescription())
                throw StartError.noAuthToken
            default:
                completeAtStepWithFailure(.oauth, with: error, description: error.contextualizedDescription())
                throw StartError.failedToFetchAuthToken(error)
            }
        }

        do {
            self.connectionWideEventData?.tunnelStartDuration = WideEvent.MeasuredInterval.startingNow()
            try tunnelManager.connection.startVPNTunnel(options: options)
            try await startupMonitor.waitForStartSuccess(tunnelManager)
            UniquePixel.fire(pixel: .networkProtectionNewUser, includedParameters: [.appVersion]) { error in
                guard error != nil else { return }
                UserDefaults.networkProtectionGroupDefaults.vpnFirstEnabled = Pixel.Event.networkProtectionNewUser.lastFireDate(
                    uniquePixelStorage: UniquePixel.storage
                )
            }
            self.connectionWideEventData?.tunnelStartDuration?.complete()
            freeTrialConversionService.markVPNActivated()
        } catch {
            completeAtStepWithFailure(.tunnelStart, with: error, description: error.contextualizedDescription())
            Pixel.fire(pixel: .networkProtectionActivationRequestFailed, error: error)
            throw StartError.startVPNFailed(error)
        }
    }

    private func loadOrMakeTunnelManager() async throws -> NETunnelProviderManager {
        guard let tunnelManager = await tunnelManager else {
            connectionWideEventData?.isSetup = .yes
            let tunnelManager = NETunnelProviderManager()
            try await setupAndSave(tunnelManager)
            internalManager = tunnelManager
            return tunnelManager
        }
        
        connectionWideEventData?.isSetup = .no
        try await setupAndSave(tunnelManager)
        return tunnelManager
    }

    @MainActor
    private func setupAndSave(_ tunnelManager: NETunnelProviderManager) async throws {
        setup(tunnelManager)

        do {
            try await tunnelManager.saveToPreferences()
        } catch {
            let nsError = error as NSError
            if nsError.code == NEVPNError.Code.configurationReadWriteFailed.rawValue,
               nsError.localizedDescription == "permission denied" {
                // This is a user denying the system permissions prompt to add the config
                // Maybe we should fire another pixel here, but not a start failure as this is an imaginable scenario
                // The code could be caused by a number of problems so I'm using the localizedDescription to catch that case
                throw StartError.configSystemPermissionsDenied(error)
            }
            throw StartError.saveToPreferencesFailed(error)
        }

        do {
            try await tunnelManager.loadFromPreferences()
        } catch {
            throw StartError.loadFromPreferencesFailed(error)
        }
    }

    @MainActor
    private func setup(_ tunnelManager: NETunnelProviderManager) {
        // Scrub a stale enforceRoutes value before it reaches the protocol config, so it can't
        // persist after the Strict routing flag is withdrawn. This is the authoritative reset: it
        // runs on every connect, regardless of whether the user ever opens VPN settings.
        settings.resetEnforceRoutesIfUnavailable(
            strictRoutingAvailable: featureFlagger.isFeatureOn(.vpnStrictRoutingToggle))

        tunnelManager.applyDuckDuckGoConfiguration(from: settings)
    }

    // MARK: - Observing Configuration Changes

    private func subscribeToConfigurationChanges() {
        notificationCenter.publisher(for: .NEVPNConfigurationChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    guard let manager = self.internalManager else {
                        return
                    }

                    do {
                        try await manager.loadFromPreferences()

                        if manager.connection.status == .invalid {
                            self.clearInternalManager()
                        }
                    } catch {
                        self.clearInternalManager()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Handling Settings Changes

    private func subscribeToSettingsChanges() {
        settings.changePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                Task {
                    // Handle the settings change right in the controller
                    try? await self.handleSettingsChange(change)
                }
            }
            .store(in: &cancellables)
    }

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
            // Intentional no-op as this is handled by the extension or applied on the next connect
            break
        }
    }

    private func handleSetIncludeAllNetworks(_ includeAllNetworks: Bool) async throws {
        guard let tunnelManager = await tunnelManager,
              tunnelManager.protocolConfiguration?.includeAllNetworks == !includeAllNetworks else {
            return
        }

        try await setupAndSave(tunnelManager)
    }

    private func handleSetEnforceRoutes(_ enforceRoutes: Bool) async throws {
        guard let tunnelManager = await tunnelManager,
              tunnelManager.protocolConfiguration?.enforceRoutes == !enforceRoutes else {
            return
        }

        try await setupAndSave(tunnelManager)

        // enforceRoutes is bound to the NECP session when it's created, so re-saving the protocol
        // only affects the next connection. If a tunnel is currently up, fully restart it so the
        // new value takes effect now rather than on the next connect.
        if await isConnected {
            await restart()
        }
    }

    private func handleSetExcludeLocalNetworks(_ excludeLocalNetworks: Bool) async throws {
        guard let tunnelManager = await tunnelManager else {
            return
        }

        try await setupAndSave(tunnelManager)
    }

    // MARK: - Observing Status Changes

    private func subscribeToStatusChanges() {
        notificationCenter.publisher(for: .NEVPNStatusDidChange)
            .sink { [weak self] value in
                self?.handleStatusChange(value)
            }
            .store(in: &cancellables)
    }

    private func handleStatusChange(_ notification: Notification) {
        guard !debugFeatures.alwaysOnDisabled,
              let session = (notification.object as? NETunnelProviderSession),
              session.status != previousStatus,
              let manager = session.manager as? NETunnelProviderManager else {
            return
        }

        Task { @MainActor in
            previousStatus = session.status

            switch session.status {
            case .connected:
                try await enableOnDemand(tunnelManager: manager)
            default:
                break
            }

        }
    }

    private func subscribeToSnoozeTimingChanges() {
        snoozeTimingStore.snoozeTimingChangedSubject
            .sink {
                NotificationCenter.default.post(name: .VPNSnoozeRefreshed, object: nil)
            }
            .store(in: &cancellables)
    }

    // MARK: - On Demand

    @MainActor
    func enableOnDemand(tunnelManager: NETunnelProviderManager) async throws {
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any

        tunnelManager.onDemandRules = [rule]
        tunnelManager.isOnDemandEnabled = true

        try await tunnelManager.saveToPreferences()
    }

    @MainActor
    func disableOnDemand(tunnelManager: NETunnelProviderManager) async throws {
        tunnelManager.isOnDemandEnabled = false

        try await tunnelManager.saveToPreferences()
    }
}

// MARK: Wide Event Helpers

private extension NetworkProtectionTunnelController {
    
    func setupAndStartConnectionWideEvent(entryContext: VPNConnectionWideEventData.EntryContext?) {
        let data = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
            entryContext: entryContext,
            contextData: WideEventContextData(name: NetworkProtectionFunnelOrigin.appSettings.rawValue)
        )
        self.connectionWideEventData = data
        wideEvent.startFlow(data)
        self.connectionWideEventData?.overallDuration = WideEvent.MeasuredInterval.startingNow()
    }
    
    func resetControllerStartWideEventMeasurement() {
        self.connectionWideEventData?.controllerStartDuration = nil
    }

    func completeAtStepWithFailure(
        _ step: VPNConnectionWideEventData.Step,
        with error: Error,
        description: String? = nil
    ) {
        self.connectionWideEventData?[keyPath: step.errorPath] = .init(error: error, description: description)
        self.connectionWideEventData?[keyPath: step.durationPath]?.complete()
        completeAndCleanupConnectionWideEvent(with: error, description: description)
    }

    func completeAndCleanupConnectionWideEvent(with error: Error? = nil, description: String? = nil) {
        guard let data = self.connectionWideEventData else { return }
        data.overallDuration?.complete()
        if let error {
            data.errorData = .init(error: error, description: description)
            wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
        } else {
            wideEvent.completeFlow(data, status: .success, onComplete: { _, _ in })
        }
        self.connectionWideEventData = nil
    }
}

// MARK: - Error Description Helper

private extension Error {
    func contextualizedDescription() -> String? {
        return (self as? NetworkProtectionTunnelController.StartError)?.caseDescription
    }
}

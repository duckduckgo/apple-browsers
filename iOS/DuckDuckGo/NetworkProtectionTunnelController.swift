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

final class NetworkProtectionTunnelController: TunnelController, TunnelSessionProvider {
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
    private var cancellables = Set<AnyCancellable>()
    
    // Wide Event
    private let wideEvent: WideEventManaging
    private var connectionWideEventData: VPNConnectionWideEventData?

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
         wideEvent: WideEventManaging
    ) {

        self.featureFlagger = featureFlagger
        self.persistentPixel = persistentPixel
        self.settings = settings
        self.tokenHandler = tokenHandler
        self.wideEvent = wideEvent

        subscribeToSnoozeTimingChanges()
        subscribeToStatusChanges()
        subscribeToConfigurationChanges()
    }

    /// Starts the VPN connection used for Network Protection
    ///
    func start() async {
        setupAndStartConnectionWideEvent()
        persistentPixel.fire(
            pixel: .networkProtectionControllerStartAttempt,
            error: nil,
            includedParameters: [.appVersion, .atb],
            withAdditionalParameters: [:],
            onComplete: { _ in })

        do {
            try await startWithError()
            completeAndCleanupConnectionWideEvent()

            persistentPixel.fire(
                pixel: .networkProtectionControllerStartSuccess,
                error: nil,
                includedParameters: [.appVersion, .atb],
                withAdditionalParameters: [:],
                onComplete: { _ in })
        } catch {
            // Top level catch-all
            completeAndCleanupConnectionWideEvent(with: error, description: error.contextualizedDescription())
            if case StartError.configSystemPermissionsDenied = error {
                return
            }

            persistentPixel.fire(
                pixel: .networkProtectionControllerStartFailure,
                error: error,
                includedParameters: [.appVersion, .atb],
                withAdditionalParameters: [:],
                onComplete: { _ in })

            #if DEBUG
            errorStore.lastErrorMessage = error.localizedDescription
            #endif
        }
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
            UniquePixel.fire(pixel: .networkProtectionNewUser, includedParameters: [.appVersion, .atb]) { error in
                guard error != nil else { return }
                UserDefaults.networkProtectionGroupDefaults.vpnFirstEnabled = Pixel.Event.networkProtectionNewUser.lastFireDate(
                    uniquePixelStorage: UniquePixel.storage
                )
            }
            self.connectionWideEventData?.tunnelStartDuration?.complete()
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

    /// Setups the tunnel manager if it's not set up already.
    ///
    @MainActor
    private func setup(_ tunnelManager: NETunnelProviderManager) {
        tunnelManager.localizedDescription = "DuckDuckGo VPN"
        tunnelManager.isEnabled = true

        tunnelManager.protocolConfiguration = {
            let protocolConfiguration = NETunnelProviderProtocol()
            protocolConfiguration.serverAddress = "127.0.0.1" // Dummy address... the NetP service will take care of grabbing a real server

            protocolConfiguration.providerConfiguration = [:]

            // always-on
            protocolConfiguration.disconnectOnSleep = false

            // Enforce routes
            protocolConfiguration.enforceRoutes = true

            // We will control excluded networks through includedRoutes / excludedRoutes
            protocolConfiguration.excludeLocalNetworks = false

            #if DEBUG
            if #available(iOS 17.4, *) {
                // This is useful to ensure debugging is never blocked by the VPN
                protocolConfiguration.excludeDeviceCommunication = true
            }
            #endif

            return protocolConfiguration
        }()

        // reconnect on reboot
        tunnelManager.onDemandRules = [NEOnDemandRuleConnect()]
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
    
    func setupAndStartConnectionWideEvent() {
        let data = VPNConnectionWideEventData(
            extensionType: .app,
            startupMethod: .manualByMainApp,
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

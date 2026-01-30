//
//  MacPacketTunnelProvider.swift
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

import Combine
import Common
import Foundation
import NetworkExtension
import Networking
import os.log
import PixelKit
import Subscription
import VPN
import WireGuard

final class MacPacketTunnelProvider: PacketTunnelProvider {

    static var isAppex: Bool {
#if NETP_SYSTEM_EXTENSION
        false
#else
        true
#endif
    }

    static var subscriptionsAppGroup: String? {
        isAppex ? Bundle.main.appGroup(bundle: .subs) : nil
    }

    // MARK: - Error Reporting

    private static func networkProtectionDebugEvents(controllerErrorStore: NetworkProtectionTunnelErrorStore) -> EventMapping<NetworkProtectionError> {
        return EventMapping { event, _, _, _ in
            let domainEvent: NetworkProtectionPixelEvent
#if DEBUG
            // Makes sure we see the error in the yellow NetP alert.
            controllerErrorStore.lastErrorMessage = "[Debug] Error event: \(event.localizedDescription)"
#endif
            switch event {
            case .noServerRegistrationInfo:
                domainEvent = .networkProtectionTunnelConfigurationNoServerRegistrationInfo
            case .couldNotSelectClosestServer:
                domainEvent = .networkProtectionTunnelConfigurationCouldNotSelectClosestServer
            case .couldNotGetPeerPublicKey:
                domainEvent = .networkProtectionTunnelConfigurationCouldNotGetPeerPublicKey
            case .couldNotGetPeerHostName:
                domainEvent = .networkProtectionTunnelConfigurationCouldNotGetPeerHostName
            case .couldNotGetInterfaceAddressRange:
                domainEvent = .networkProtectionTunnelConfigurationCouldNotGetInterfaceAddressRange
            case .failedToFetchServerList(let eventError):
                domainEvent = .networkProtectionClientFailedToFetchServerList(eventError)
            case .failedToParseServerListResponse:
                domainEvent = .networkProtectionClientFailedToParseServerListResponse
            case .failedToEncodeRegisterKeyRequest:
                domainEvent = .networkProtectionClientFailedToEncodeRegisterKeyRequest
            case .failedToFetchRegisteredServers(let eventError):
                domainEvent = .networkProtectionClientFailedToFetchRegisteredServers(eventError)
            case .failedToParseRegisteredServersResponse:
                domainEvent = .networkProtectionClientFailedToParseRegisteredServersResponse
            case .invalidAuthToken:
                domainEvent = .networkProtectionClientInvalidAuthToken
            case .serverListInconsistency:
                return
            case .failedToCastKeychainValueToData(let field):
                domainEvent = .networkProtectionKeychainErrorFailedToCastKeychainValueToData(field: field)
            case .keychainReadError(let field, let status):
                domainEvent = .networkProtectionKeychainReadError(field: field, status: status)
            case .keychainWriteError(let field, let status):
                domainEvent = .networkProtectionKeychainWriteError(field: field, status: status)
            case .keychainUpdateError(let field, let status):
                domainEvent = .networkProtectionKeychainUpdateError(field: field, status: status)
            case .keychainDeleteError(let status):
                domainEvent = .networkProtectionKeychainDeleteError(status: status)
            case .wireGuardCannotLocateTunnelFileDescriptor:
                domainEvent = .networkProtectionWireguardErrorCannotLocateTunnelFileDescriptor
            case .wireGuardInvalidState(let reason):
                domainEvent = .networkProtectionWireguardErrorInvalidState(reason: reason)
            case .wireGuardDnsResolution:
                domainEvent = .networkProtectionWireguardErrorFailedDNSResolution
            case .wireGuardSetNetworkSettings(let error):
                domainEvent = .networkProtectionWireguardErrorCannotSetNetworkSettings(error)
            case .startWireGuardBackend(let error):
                domainEvent = .networkProtectionWireguardErrorCannotStartWireguardBackend(error)
            case .setWireguardConfig(let error):
                domainEvent = .networkProtectionWireguardErrorCannotSetWireguardConfig(error)
            case .noAuthTokenFound:
                domainEvent = .networkProtectionNoAuthTokenFoundError
            case .vpnAccessRevoked(let error):
                domainEvent = .networkProtectionVPNAccessRevoked(error)
            case .failedToFetchServerStatus(let error):
                domainEvent = .networkProtectionClientFailedToFetchServerStatus(error)
            case .failedToParseServerStatusResponse(let error):
                domainEvent = .networkProtectionClientFailedToParseServerStatusResponse(error)
            case .unhandledError(function: let function, line: let line, error: let error):
                domainEvent = .networkProtectionUnhandledError(function: function, line: line, error: error)
            case .failedToFetchLocationList,
                    .failedToParseLocationListResponse:
                // Needs Privacy triage for macOS Geoswitching pixels
                return
            case .unmanagedSubscriptionError(let error):
                domainEvent = .networkProtectionUnmanagedSubscriptionError(error)
            }

            PixelKit.fire(domainEvent, frequency: .legacyDailyAndCount, includeAppVersionParameter: true)
        }
    }

    private let notificationCenter: NetworkProtectionNotificationCenter = DistributedNotificationCenter.default()
    private let wideEvent: WideEventManaging

    // MARK: - PacketTunnelProvider.Event reporting

    private static var packetTunnelProviderEvents: EventMapping<PacketTunnelProvider.Event> = .init { event, _, _, _ in

#if NETP_SYSTEM_EXTENSION
        let defaults = UserDefaults.standard
#else
        let defaults = UserDefaults.netP
#endif
        switch event {
        case .userBecameActive:
            PixelKit.fire(
                NetworkProtectionPixelEvent.networkProtectionActiveUser,
                frequency: .legacyDailyNoSuffix,
                withAdditionalParameters: [PixelKit.Parameters.vpnCohort: PixelKit.cohort(from: defaults.vpnFirstEnabled)],
                includeAppVersionParameter: true)
        case .connectionTesterStatusChange(let status, let server):
            switch status {
            case .failed(let duration):
                Logger.networkProtectionConnectionTester.error("🔴 Connection tester (\(duration.rawValue, privacy: .public) - \(server, privacy: .public)) failure")
            case .recovered(let duration, let failureCount):
                Logger.networkProtectionConnectionTester.log("🟢 Connection tester (\(duration.rawValue, privacy: .public) - \(server, privacy: .public)) recovery (after \(String(failureCount), privacy: .public) failures)")
            }

            switch status {
            case .failed(let duration):
                let pixel: NetworkProtectionPixelEvent = {
                    switch duration {
                    case .immediate:
                        return .networkProtectionConnectionTesterFailureDetected(server: server)
                    case .extended:
                        return .networkProtectionConnectionTesterExtendedFailureDetected(server: server)
                    }
                }()

                PixelKit.fire(
                    pixel,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .recovered(let duration, let failureCount):
                let pixel: NetworkProtectionPixelEvent = {
                    switch duration {
                    case .immediate:
                        return .networkProtectionConnectionTesterFailureRecovered(server: server, failureCount: failureCount)
                    case .extended:
                        return .networkProtectionConnectionTesterExtendedFailureRecovered(server: server, failureCount: failureCount)
                    }
                }()

                PixelKit.fire(
                    pixel,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            }
        case .reportConnectionAttempt(attempt: let attempt):
            switch attempt {
            case .connecting:
                Logger.networkProtection.log("🔵 Connection attempt detected")
            case .failure:
                Logger.networkProtection.error("🔴 Connection attempt failed")
            case .success:
                Logger.networkProtection.log("🟢 Connection attempt successful")
            }

            switch attempt {
            case .connecting:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionEnableAttemptConnecting,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .success:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionEnableAttemptSuccess,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .failure:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionEnableAttemptFailure,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            }
        case .reportTunnelFailure(result: let result):
            switch result {
            case .failureDetected:
                Logger.networkProtectionTunnelFailureMonitor.error("🔴 Tunnel failure detected")
            case .failureRecovered:
                Logger.networkProtectionTunnelFailureMonitor.log("🟢 Tunnel failure recovered")
            case .networkPathChanged:
                Logger.networkProtectionTunnelFailureMonitor.log("🔵 Tunnel recovery detected path change")
            }

            switch result {
            case .failureDetected:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelFailureDetected,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .failureRecovered:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelFailureRecovered,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .networkPathChanged:
                break
            }
        case .reportLatency(let result, let location):
            switch result {
            case .error:
                Logger.networkProtectionLatencyMonitor.error("🔴 There was an error logging the latency")
            case .quality(let quality):
                Logger.networkProtectionLatencyMonitor.log("Connection quality is: \(quality.rawValue, privacy: .public)")
            }

            switch result {
            case .error:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionLatencyError,
                    frequency: .legacyDailyNoSuffix,
                    includeAppVersionParameter: true)
            case .quality(let quality):
                guard quality != .unknown else { return }
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionLatency(quality: quality),
                    frequency: .legacyDailyAndCount,
                    withAdditionalParameters: ["location": location.stringValue],
                    includeAppVersionParameter: true)
            }
        case .rekeyAttempt(let step):
            switch step {
            case .begin:
                Logger.networkProtection.log("🔵 Rekey attempt begins")
            case .failure(let error):
                Logger.networkProtection.error("🔴 Rekey attempt failed with error: \(error.localizedDescription, privacy: .public)")
            case .success:
                Logger.networkProtection.log("🟢 Rekey attempt succeeded")
            }

            switch step {
            case .begin:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionRekeyAttempt,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .failure(let error):
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionRekeyFailure(error),
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .success:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionRekeyCompleted,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            }
        case .tunnelStartAttempt(let step):
            switch step {
            case .begin:
                Logger.networkProtection.log("🔵 Tunnel Start attempt begins")
            case .failure(let error):
                Logger.networkProtection.error("🔴 Tunnel Start attempt failed with error: \(error.localizedDescription, privacy: .public)")
            case .success:
                Logger.networkProtection.log("🟢 Tunnel Start attempt succeeded")
            }

            switch step {
            case .begin:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelStartAttempt,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .failure(let error):
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelStartFailure(error),
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .success:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelStartSuccess,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            }
        case .tunnelStopAttempt(let step):
            switch step {
            case .begin:
                Logger.networkProtection.log("🔵 Tunnel Stop attempt begins")
            case .failure(let error):
                Logger.networkProtection.error("🔴 Tunnel Stop attempt failed with error: \(error.localizedDescription, privacy: .public)")
            case .success:
                Logger.networkProtection.log("🟢 Tunnel Stop attempt succeeded")
            }

            switch step {
            case .begin:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelStopAttempt,
                    frequency: .standard,
                    includeAppVersionParameter: true)
            case .failure(let error):
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelStopFailure(error),
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .success:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelStopSuccess,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            }
        case .tunnelUpdateAttempt(let step):
            switch step {
            case .begin:
                Logger.networkProtection.log("🔵 Tunnel Update attempt begins")
            case .failure(let error):
                Logger.networkProtection.error("🔴 Tunnel Update attempt failed with error: \(error.localizedDescription, privacy: .public)")
            case .success:
                Logger.networkProtection.log("🟢 Tunnel Update attempt succeeded")
            }

            switch step {
            case .begin:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelUpdateAttempt,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .failure(let error):
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelUpdateFailure(error),
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .success:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelUpdateSuccess,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            }
        case .tunnelWakeAttempt(let step):
            switch step {
            case .begin:
                Logger.networkProtection.log("🔵 Tunnel Wake attempt begins")
            case .failure(let error):
                Logger.networkProtection.error("🔴 Tunnel Wake attempt failed with error: \(error.localizedDescription, privacy: .public)")
            case .success:
                Logger.networkProtection.log("🟢 Tunnel Wake attempt succeeded")
            }

            switch step {
            case .begin, .success: break
            case .failure(let error):
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionTunnelWakeFailure(error),
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            }
        case .failureRecoveryAttempt(let step):
            switch step {
            case .started:
                Logger.networkProtectionTunnelFailureMonitor.log("🔵 Failure Recovery attempt started")
            case .failed(let error):
                Logger.networkProtectionTunnelFailureMonitor.error("🔴 Failure Recovery attempt failed with error: \(error.localizedDescription, privacy: .public)")
            case .completed(let health):
                switch health {
                case .healthy:
                    Logger.networkProtectionTunnelFailureMonitor.log("🟢 Failure Recovery attempt completed")
                case .unhealthy:
                    Logger.networkProtectionTunnelFailureMonitor.error("🔴 Failure Recovery attempt ended as unhealthy")
                }
            }

            switch step {
            case .started:
                PixelKit.fire(
                    VPNFailureRecoveryPixel.vpnFailureRecoveryStarted,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true
                )
            case .completed(.healthy):
                PixelKit.fire(
                    VPNFailureRecoveryPixel.vpnFailureRecoveryCompletedHealthy,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true
                )
            case .completed(.unhealthy):
                PixelKit.fire(
                    VPNFailureRecoveryPixel.vpnFailureRecoveryCompletedUnhealthy,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true
                )
            case .failed(let error):
                PixelKit.fire(
                    VPNFailureRecoveryPixel.vpnFailureRecoveryFailed(error),
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true
                )
            }
        case .serverMigrationAttempt(let step):
            switch step {
            case .begin:
                Logger.networkProtection.log("🔵 Server Migration attempt begins")
            case .failure(let error):
                Logger.networkProtection.error("🔴 Server Migration attempt failed with error: \(error.localizedDescription, privacy: .public)")
            case .success:
                Logger.networkProtection.log("🟢 Server Migration attempt succeeded")
            }

            switch step {
            case .begin:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionServerMigrationAttempt,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .failure(let error):
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionServerMigrationFailure(error),
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            case .success:
                PixelKit.fire(
                    NetworkProtectionPixelEvent.networkProtectionServerMigrationSuccess,
                    frequency: .legacyDailyAndCount,
                    includeAppVersionParameter: true)
            }
        case .tunnelStartOnDemandWithoutAccessToken:
            Logger.networkProtection.error("🔴 Starting tunnel without an auth token")

            PixelKit.fire(
                NetworkProtectionPixelEvent.networkProtectionTunnelStartAttemptOnDemandWithoutAccessToken,
                frequency: .legacyDailyAndCount,
                includeAppVersionParameter: true)
        case .adapterEndTemporaryShutdownStateAttemptFailure(let error):
            PixelKit.fire(NetworkProtectionPixelEvent.networkProtectionAdapterEndTemporaryShutdownStateAttemptFailure(error),
                          frequency: PixelKit.Frequency.dailyAndCount,
                          includeAppVersionParameter: true)
        case .adapterEndTemporaryShutdownStateRecoverySuccess:
            PixelKit.fire(NetworkProtectionPixelEvent.networkProtectionAdapterEndTemporaryShutdownStateRecoverySuccess,
                          frequency: PixelKit.Frequency.dailyAndCount,
                          includeAppVersionParameter: true)
        case .adapterEndTemporaryShutdownStateRecoveryFailure(let error):
            PixelKit.fire(NetworkProtectionPixelEvent.networkProtectionAdapterEndTemporaryShutdownStateRecoveryFailure(error),
                          frequency: PixelKit.Frequency.dailyAndCount,
                          includeAppVersionParameter: true)
        }
    }

    static var tokenServiceName: String {
#if NETP_SYSTEM_EXTENSION
        "\(Bundle.main.bundleIdentifier!).authToken"
#else
        NetworkProtectionKeychainTokenStore.Defaults.tokenStoreService
#endif
    }

    static var tokenContainerServiceName: String {
#if NETP_SYSTEM_EXTENSION
        "\(Bundle.main.bundleIdentifier!).authTokenContainer"
#else
        NetworkProtectionKeychainTokenStore.Defaults.tokenStoreService
#endif
    }

    // MARK: - Initialization

    let subscriptionManager: DefaultSubscriptionManager
    let tokenStorage: NetworkProtectionKeychainTokenStore

    @MainActor @objc public init() {
        Logger.networkProtection.log("[+] MacPacketTunnelProvider")
#if NETP_SYSTEM_EXTENSION
        let defaults = UserDefaults.standard
#else
        let defaults = UserDefaults.netP
#endif

        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let trimmedOSVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        APIRequest.Headers.setUserAgent(UserAgent.duckDuckGoUserAgent(systemVersion: trimmedOSVersion))
        NetworkProtectionLastVersionRunStore(userDefaults: defaults).lastExtensionVersionRun = AppVersion.shared.versionAndBuildNumber
        let settings = VPNSettings(defaults: defaults) // Note, settings here is not yet populated with the startup options
        self.wideEvent = WideEvent(featureFlagProvider: WideEventFeatureFlagProvider(settings: settings))

        // MARK: - Subscription configuration

        // Align Subscription environment to the VPN environment
        var subscriptionEnvironment = SubscriptionEnvironment.default
        switch settings.selectedEnvironment {
        case .production:
            subscriptionEnvironment.serviceEnvironment = .production
        case .staging:
            subscriptionEnvironment.serviceEnvironment = .staging
        }
        // The SysExt doesn't care about the purchase platform because the only operations executed here are about the Auth token. No purchase or
        // platforms-related operations are performed.
        subscriptionEnvironment.purchasePlatform = .stripe
        Logger.networkProtection.debug("Subscription ServiceEnvironment: \(subscriptionEnvironment.serviceEnvironment.rawValue, privacy: .public)")

        let notificationCenter: NetworkProtectionNotificationCenter = DistributedNotificationCenter.default()
        let controllerErrorStore = NetworkProtectionTunnelErrorStore(notificationCenter: notificationCenter)
        let debugEvents = Self.networkProtectionDebugEvents(controllerErrorStore: controllerErrorStore)

        // MARK: - Subscription
        let subscriptionUserDefaults = UserDefaults(suiteName: MacPacketTunnelProvider.subscriptionsAppGroup)!
        let authService = DefaultOAuthService(baseURL: subscriptionEnvironment.authEnvironment.url,
                                              apiService: APIServiceFactory.makeAPIServiceForAuthV2(withUserAgent: UserAgent.duckDuckGoUserAgent()))
        let tokenStore = NetworkProtectionKeychainTokenStore(keychainType: Bundle.keychainType,
                                                                 serviceName: Self.tokenContainerServiceName,
                                                                 errorEventsHandler: debugEvents)
        let authClient = DefaultOAuthClient(tokensStorage: tokenStore,
                                            authService: authService,
                                            refreshEventMapping: AuthV2TokenRefreshWideEventData.authV2RefreshEventMapping(wideEvent: self.wideEvent, isFeatureEnabled: { true }))

        let subscriptionEndpointService = DefaultSubscriptionEndpointService(apiService: APIServiceFactory.makeAPIServiceForSubscription(withUserAgent: UserAgent.duckDuckGoUserAgent()),
                                                                                 baseURL: subscriptionEnvironment.serviceEnvironment.url)
        let pixelHandler = SubscriptionPixelHandler(source: .systemExtension)
        let subscriptionManager = DefaultSubscriptionManager(oAuthClient: authClient,
                                                               userDefaults: subscriptionUserDefaults,
                                                               subscriptionEndpointService: subscriptionEndpointService,
                                                               subscriptionEnvironment: subscriptionEnvironment,
                                                               pixelHandler: pixelHandler,
                                                               initForPurchase: false,
                                                               wideEvent: self.wideEvent,
                                                               isAuthV2WideEventEnabled: { return subscriptionEnvironment.serviceEnvironment == .production })

        let entitlementsCheck: (() async -> Result<Bool, Error>) = {
            Logger.networkProtection.log("Subscription Entitlements check...")
            do {
                let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
                let isNetworkProtectionEnabled = tokenContainer.decodedAccessToken.hasEntitlement(.networkProtection)
                Logger.networkProtection.log("NetworkProtectionEnabled if: \( isNetworkProtectionEnabled ? "Enabled" : "Disabled", privacy: .public)")
                return .success(isNetworkProtectionEnabled)
            } catch {
                return .failure(error)
            }
        }

        self.tokenStorage = tokenStore
        self.subscriptionManager = subscriptionManager

        // MARK: -

        let tunnelHealthStore = NetworkProtectionTunnelHealthStore(notificationCenter: notificationCenter)
        let notificationsPresenter = NetworkProtectionNotificationsPresenterFactory().make(settings: settings, defaults: defaults)

        super.init(notificationsPresenter: notificationsPresenter,
                   tunnelHealthStore: tunnelHealthStore,
                   controllerErrorStore: controllerErrorStore,
                   snoozeTimingStore: NetworkProtectionSnoozeTimingStore(userDefaults: .netP),
                   wireGuardInterface: DefaultWireGuardInterface(),
                   keychainType: Bundle.keychainType,
                   tokenHandlerProvider: subscriptionManager,
                   debugEvents: debugEvents,
                   providerEvents: Self.packetTunnelProviderEvents,
                   settings: settings,
                   defaults: defaults,
                   wideEvent: wideEvent,
                   entitlementCheck: entitlementsCheck)

        setupPixels()
        Logger.networkProtection.log("[+] MacPacketTunnelProvider Initialised")
    }

    deinit {
        Logger.networkProtectionMemory.log("[-] MacPacketTunnelProvider")
    }

    public override func load(options: StartupOptions) async throws {
        try await super.load(options: options)

        // macOS-specific options
        try loadVPNSettings(from: options)
        try await loadTokenContainer(from: options)
    }

    private func loadVPNSettings(from options: StartupOptions) throws {
        switch options.vpnSettings {
        case .set(let settingsSnapshot):
            settingsSnapshot.applyTo(settings)
        case .useExisting:
            break
        case .reset:
            // VPN settings are required - if we're in reset case, it means they were missing or invalid
            throw TunnelError.settingsMissing
        }
    }

    private func loadTokenContainer(from options: StartupOptions) async throws {
        let tokenHandler = tokenHandlerProvider
        Logger.networkProtection.log("Load token container")
        switch options.tokenContainer {
        case .set(let newTokenContainer):
            Logger.networkProtection.log("Set new token container")
            do {
                try await tokenHandler.adoptToken(newTokenContainer)
            } catch {
                Logger.networkProtection.fault("Error adopting token container: \(error, privacy: .public)")
                throw TunnelError.startingTunnelWithoutAuthToken(internalError: error)
            }
        case .useExisting:
            Logger.networkProtection.log("Use existing token container")
            do {
                try await tokenHandler.getToken()
            } catch {
                Logger.networkProtection.fault("Error loading token container: \(error, privacy: .public)")
                throw TunnelError.startingTunnelWithoutAuthToken(internalError: error)
            }
        case .reset:
            Logger.networkProtection.log("Reset token")
            // This case should in theory not be possible, but it's ideal to have this in place
            // in case an error in the controller on the client side allows it.
            try await tokenHandler.removeToken()
            throw TunnelError.tokenReset
        }
    }

    enum ConfigurationError: Error {
        case missingProviderConfiguration
        case missingPixelHeaders
    }

    public override func loadVendorOptions(from provider: NETunnelProviderProtocol?) throws {
        try super.loadVendorOptions(from: provider)

        guard let vendorOptions = provider?.providerConfiguration else {
            Logger.networkProtection.log("🔵 Provider is nil, or providerConfiguration is not set")
            throw ConfigurationError.missingProviderConfiguration
        }

        try loadDefaultPixelHeaders(from: vendorOptions)
    }

    private func loadDefaultPixelHeaders(from options: [String: Any]) throws {
        guard let defaultPixelHeaders = options[NetworkProtectionOptionKey.defaultPixelHeaders] as? [String: String] else {
            Logger.networkProtection.log("🔵 Pixel options are not set")
            throw ConfigurationError.missingPixelHeaders
        }

        setupPixels(defaultHeaders: defaultPixelHeaders)
    }

    // MARK: - Override-able Connection Events

    override func prepareToConnect(using provider: NETunnelProviderProtocol?) {
        Logger.networkProtection.log("Preparing to connect...")
        super.prepareToConnect(using: provider)
        guard PixelKit.shared == nil, let options = provider?.providerConfiguration else { return }
        try? loadDefaultPixelHeaders(from: options)
    }

    // MARK: - Start

    @MainActor
    override func startTunnel(options: [String: NSObject]? = nil) async throws {

        try await super.startTunnel(options: options)
    }

    // MARK: - Pixels

    private func setupPixels(defaultHeaders: [String: String] = [:]) {
        let source: String

#if NETP_SYSTEM_EXTENSION && !APPSTORE
        source = "vpnSystemExtension"
#elseif NETP_SYSTEM_EXTENSION && APPSTORE
        source = "vpnSystemExtensionAppStore"
#else
        source = "vpnAppExtension"
#endif

        let userAgent = UserAgent.duckDuckGoUserAgent()

        PixelKit.setUp(dryRun: PixelKitConfig.isDryRun(isProductionBuild: BuildFlags.isProductionBuild),
                       appVersion: AppVersion.shared.versionNumber,
                       source: source,
                       defaultHeaders: defaultHeaders,
                       defaults: .netP) { (pixelName: String, headers: [String: String], parameters: [String: String], _, _, onComplete: @escaping PixelKit.CompletionBlock) in

            let url = URL.pixelUrl(forPixelNamed: pixelName)
            let apiHeaders = APIRequest.Headers(userAgent: userAgent, additionalHeaders: headers)
            let configuration = APIRequest.Configuration(url: url, method: .get, queryParameters: parameters, headers: apiHeaders)
            let request = APIRequest(configuration: configuration)

            request.fetch { _, error in
                onComplete(error == nil, error)
            }
        }
    }

}

private struct WideEventFeatureFlagProvider: WideEventFeatureFlagProviding {
    let settings: VPNSettings

    func isEnabled(_ flag: WideEventFeatureFlag) -> Bool {
        switch flag {
        case .postEndpoint:
#if DEBUG || REVIEW || ALPHA
            return false
#else
            return settings.wideEventPostEndpointEnabled
#endif
        }
    }
}

final class DefaultWireGuardInterface: WireGuardGoInterface {
    func turnOn(settings: UnsafePointer<CChar>, handle: Int32) -> Int32 {
        wgTurnOn(settings, handle)
    }

    func turnOff(handle: Int32) {
        wgTurnOff(handle)
    }

    func getConfig(handle: Int32) -> UnsafeMutablePointer<CChar>? {
        return wgGetConfig(handle)
    }

    func setConfig(handle: Int32, config: String) -> Int64 {
        return wgSetConfig(handle, config)
    }

    func bumpSockets(handle: Int32) {
        wgBumpSockets(handle)
    }

    func disableSomeRoamingForBrokenMobileSemantics(handle: Int32) {
        wgDisableSomeRoamingForBrokenMobileSemantics(handle)
    }

    func setLogger(context: UnsafeMutableRawPointer?, logFunction: (@convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void)?) {
        wgSetLogger(context, logFunction)
    }
}

//
//  NetworkProtectionPacketTunnelProvider.swift
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

import BrowserServicesKit
import Combine
import Common
import DDGError
import FoundationExtensions
import Configuration
import Core
import Foundation
import UIKit
import NetworkExtension
import Networking
import os.log
import Persistence
import PixelKit
import Subscription
import VPN
import WidgetKit
import WireGuard
import PrivacyConfig

final class NetworkProtectionPacketTunnelProvider: PacketTunnelProvider {

    private static let persistentPixel: PersistentPixelFiring = PersistentPixel()
    private var cancellables = Set<AnyCancellable>()
    private let subscriptionManager: (any SubscriptionManager)?
    private let configurationStore = ConfigurationStore()
    private let configurationManager: ConfigurationManager
    private let wideEvent: WideEventManaging

    // MARK: - PacketTunnelProvider.Event reporting

    private static func packetTunnelProviderEvents(loopDetector: ConnectionFailureLoopDetector) -> EventMapping<PacketTunnelProvider.Event> { .init { event, _, _, _ in
        let defaults = UserDefaults.networkProtectionGroupDefaults

        switch event {
        case .userBecameActive:
            PixelKit.fire(Pixel.Event.networkProtectionActiveUser,
                          frequency: .legacyDailyNoSuffix,
                          options: .parameters([PixelParameters.vpnCohort: PixelKit.cohort(from: defaults.vpnFirstEnabled)]))

            persistentPixel.sendQueuedPixels { error in
                Logger.networkProtection.error("Failed to send queued pixels, with error: \(error)")
            }
        case .connectionTesterStatusChange(let status, let server):
            switch status {
            case .failed(let duration):
                Logger.networkProtectionConnectionTester.error("🔴 Connection tester (\(duration.rawValue, privacy: .public) - \(server, privacy: .public)) failure")
            case .recovered(let duration, let failureCount):
                Logger.networkProtectionConnectionTester.log("🟢 Connection tester (\(duration.rawValue, privacy: .public) - \(server, privacy: .public)) recovery (after \(String(failureCount), privacy: .public) failures)")
            }

            switch status {
            case .failed(let duration):
                let pixel: Pixel.Event = {
                    switch duration {
                    case .immediate:
                        return .networkProtectionConnectionTesterFailureDetected
                    case .extended:
                        return .networkProtectionConnectionTesterExtendedFailureDetected
                    }
                }()

                PixelKit.fire(pixel,
                              frequency: .legacyDailyAndCount,
                              options: .parameters([PixelParameters.server: server]))
            case .recovered(let duration, let failureCount):
                let pixel: Pixel.Event = {
                    switch duration {
                    case .immediate:
                        return .networkProtectionConnectionTesterFailureRecovered(failureCount: failureCount)
                    case .extended:
                        return .networkProtectionConnectionTesterExtendedFailureRecovered(failureCount: failureCount)
                    }
                }()

                PixelKit.fire(pixel,
                              frequency: .legacyDailyAndCount,
                              options: .parameters([
                                                PixelParameters.count: String(failureCount),
                                                PixelParameters.server: server
                                             ]))
            }
        case .reportConnectionAttempt(attempt: let attempt, source: let source):
            switch attempt {
            case .connecting:
                Logger.networkProtection.log("🔵 Connection attempt detected")
            case .failure:
                Logger.networkProtection.error("🔴 Connection attempt failed")
            case .success:
                Logger.networkProtection.log("🟢 Connection attempt successful")
            }

            let sourceParameters = ["source": source.rawValue]

            switch attempt {
            case .connecting:
                if loopDetector.connectionLoopDetected { return }
                PixelKit.fire(Pixel.Event.networkProtectionEnableAttemptConnecting,
                              frequency: .legacyDailyAndCount,
                              options: .parameters(sourceParameters))
            case .success:
                let versionStore = NetworkProtectionLastVersionRunStore(userDefaults: .networkProtectionGroupDefaults)
                versionStore.lastExtensionVersionRun = AppVersion.shared.versionAndBuildNumber

                PixelKit.fire(Pixel.Event.networkProtectionEnableAttemptSuccess,
                              frequency: .legacyDailyAndCount,
                              options: .parameters(sourceParameters))
            case .failure:
                if loopDetector.connectionLoopDetected { return }
                PixelKit.fire(Pixel.Event.networkProtectionEnableAttemptFailure,
                              frequency: .legacyDailyAndCount,
                              options: .parameters(sourceParameters))
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
                PixelKit.fire(Pixel.Event.networkProtectionTunnelFailureDetected,
                              frequency: .legacyDailyAndCount)
            case .failureRecovered:
                PixelKit.fire(Pixel.Event.networkProtectionTunnelFailureRecovered,
                              frequency: .legacyDailyAndCount)
            case .networkPathChanged(let newPath):
                defaults.updateNetworkPath(with: newPath)
            }
        case .reportLatency(result: let result, location: let location):
            switch result {
            case .error:
                Logger.networkProtectionLatencyMonitor.error("🔴 There was an error logging the latency")
            case .quality(let quality):
                Logger.networkProtectionLatencyMonitor.log("Connection quality is: \(quality.rawValue, privacy: .public)")
            }

            switch result {
            case .error:
                PixelKit.fire(Pixel.Event.networkProtectionLatencyError, frequency: .legacyDailyNoSuffix)
            case .quality(let quality):
                guard quality != .unknown else { return }
                PixelKit.fire(Pixel.Event.networkProtectionLatency(quality: quality.rawValue),
                              frequency: .legacyDailyAndCount,
                              options: .parameters(["location": location.stringValue]))
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
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionRekeyAttempt,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: nil,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
            case .failure(let error):
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionRekeyFailure,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: error,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
            case .success:
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionRekeyCompleted,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: nil,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
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
                if loopDetector.connectionLoopDetected { return }
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionTunnelStartAttempt,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: nil,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
            case .failure(let error):
                if loopDetector.connectionLoopDetected { return }
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionTunnelStartFailure,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: error,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
            case .success:
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionTunnelStartSuccess,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: nil,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
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
                PixelKit.fire(Pixel.Event.networkProtectionTunnelStopAttempt)
            case .failure(let error):
                PixelKit.fire(Pixel.Event.networkProtectionTunnelStopFailure.withError(error),
                              frequency: .legacyDailyAndCount)
            case .success:
                PixelKit.fire(Pixel.Event.networkProtectionTunnelStopSuccess,
                              frequency: .legacyDailyAndCount)
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
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionTunnelUpdateAttempt,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: nil,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
            case .failure(let error):
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionTunnelUpdateFailure,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: error,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
            case .success:
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionTunnelUpdateSuccess,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: nil,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
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
                PixelKit.fire(Pixel.Event.networkProtectionTunnelWakeFailure.withError(error),
                              frequency: .legacyDailyAndCount)
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
                PixelKit.fire(Pixel.Event.networkProtectionFailureRecoveryStarted,
                              frequency: .legacyDailyAndCount)
            case .completed(.healthy):
                PixelKit.fire(Pixel.Event.networkProtectionFailureRecoveryCompletedHealthy,
                              frequency: .legacyDailyAndCount)
            case .completed(.unhealthy):
                PixelKit.fire(Pixel.Event.networkProtectionFailureRecoveryCompletedUnhealthy,
                              frequency: .legacyDailyAndCount)
            case .failed(let error):
                PixelKit.fire(Pixel.Event.networkProtectionFailureRecoveryFailed.withError(error),
                              frequency: .legacyDailyAndCount)
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
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionServerMigrationAttempt,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: nil,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
            case .failure(let error):
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionServerMigrationAttemptFailure,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: error,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
            case .success:
                persistentPixel.fireDailyAndCount(
                    pixel: .networkProtectionServerMigrationAttemptSuccess,
                    pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                    error: nil,
                    withAdditionalParameters: [:],
                    includedParameters: [.appVersion]) { _ in }
            }
        case .tunnelStartOnDemandWithoutAccessToken(let error):
            Logger.networkProtection.error("🔴 Starting tunnel without an auth token")
            if loopDetector.connectionLoopDetected { return }
            PixelKit.fire(Pixel.Event.networkProtectionTunnelStartAttemptOnDemandWithoutAccessToken.withError(error),
                          frequency: .legacyDailyAndCount)
        case .adapterEndTemporaryShutdownStateAttemptFailure(let error):
            PixelKit.fire(Pixel.Event.networkProtectionAdapterEndTemporaryShutdownStateAttemptFailure.withError(error), frequency: .dailyAndCount)
        case .adapterEndTemporaryShutdownStateRecoverySuccess:
            PixelKit.fire(Pixel.Event.networkProtectionAdapterEndTemporaryShutdownStateRecoverySuccess, frequency: .dailyAndCount)
        case .adapterEndTemporaryShutdownStateRecoveryFailure(let error):
            PixelKit.fire(Pixel.Event.networkProtectionAdapterEndTemporaryShutdownStateRecoveryFailure.withError(error), frequency: .dailyAndCount)
        case .connectionFailureLoopDetected(let error):
            persistentPixel.fireDailyAndCount(
                pixel: .networkProtectionConnectionFailureLoopDetected,
                pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                error: error,
                withAdditionalParameters: [:],
                includedParameters: [.appVersion]) { _ in }
        }
    } }

    // MARK: - Error Reporting

    private static func networkProtectionDebugEvents(controllerErrorStore: NetworkProtectionTunnelErrorStore) -> EventMapping<NetworkProtectionError> {
        return EventMapping { event, _, _, _ in
            let pixelEvent: Pixel.Event
            var pixelError: Error?
            var params: [String: String] = [:]

#if DEBUG
            // Makes sure we see the error in the yellow NetP alert.
            controllerErrorStore.lastErrorMessage = "[Debug] Error event: \(event.localizedDescription)"
#endif
            switch event {
            case .noServerRegistrationInfo:
                pixelEvent = .networkProtectionTunnelConfigurationNoServerRegistrationInfo
            case .couldNotSelectClosestServer:
                pixelEvent = .networkProtectionTunnelConfigurationCouldNotSelectClosestServer
            case .couldNotGetPeerPublicKey:
                pixelEvent = .networkProtectionTunnelConfigurationCouldNotGetPeerPublicKey
            case .couldNotGetPeerHostName:
                pixelEvent = .networkProtectionTunnelConfigurationCouldNotGetPeerHostName
            case .couldNotGetInterfaceAddressRange:
                pixelEvent = .networkProtectionTunnelConfigurationCouldNotGetInterfaceAddressRange
            case .failedToFetchServerList(let eventError):
                pixelEvent = .networkProtectionClientFailedToFetchServerList
                pixelError = eventError
            case .failedToParseServerListResponse:
                pixelEvent = .networkProtectionClientFailedToParseServerListResponse
            case .failedToEncodeRegisterKeyRequest:
                pixelEvent = .networkProtectionClientFailedToEncodeRegisterKeyRequest
            case .failedToFetchRegisteredServers(let eventError):
                pixelEvent = .networkProtectionClientFailedToFetchRegisteredServers
                pixelError = eventError
            case .failedToParseRegisteredServersResponse:
                pixelEvent = .networkProtectionClientFailedToParseRegisteredServersResponse
            case .invalidAuthToken:
                pixelEvent = .networkProtectionClientInvalidAuthToken
            case .vpnAccessRevoked(let error):
                pixelEvent = .networkProtectionVPNAccessRevoked
                pixelError = error
            case .unmanagedSubscriptionError(let error):
                pixelEvent = .networkProtectionUnmanagedSubscriptionError
                pixelError = error
            case .serverListInconsistency:
                return
            case .failedToCastKeychainValueToData(let field):
                pixelEvent = .networkProtectionKeychainErrorFailedToCastKeychainValueToData
                params[PixelParameters.keychainFieldName] = field
            case .keychainReadError(let field, let status):
                pixelEvent = .networkProtectionKeychainReadError
                params[PixelParameters.keychainFieldName] = field
                params[PixelParameters.keychainErrorCode] = String(status)
            case .keychainWriteError(let field, let status):
                pixelEvent = .networkProtectionKeychainWriteError
                params[PixelParameters.keychainFieldName] = field
                params[PixelParameters.keychainErrorCode] = String(status)
            case .keychainUpdateError(let field, let status):
                pixelEvent = .networkProtectionKeychainUpdateError
                params[PixelParameters.keychainFieldName] = field
                params[PixelParameters.keychainErrorCode] = String(status)
            case .keychainDeleteError(let status): // TODO: Check whether field needed here
                pixelEvent = .networkProtectionKeychainDeleteError
                params[PixelParameters.keychainErrorCode] = String(status)
            case .wireGuardCannotLocateTunnelFileDescriptor:
                pixelEvent = .networkProtectionWireguardErrorCannotLocateTunnelFileDescriptor
            case .wireGuardInvalidState(reason: let reason):
                pixelEvent = .networkProtectionWireguardErrorInvalidState
                params[PixelParameters.reason] = reason
            case .wireGuardDnsResolution:
                pixelEvent = .networkProtectionWireguardErrorFailedDNSResolution
            case .wireGuardSetNetworkSettings(let error):
                pixelEvent = .networkProtectionWireguardErrorCannotSetNetworkSettings
                pixelError = error
            case .startWireGuardBackend(let error):
                pixelEvent = .networkProtectionWireguardErrorCannotStartWireguardBackend
                pixelError = error
            case .setWireguardConfig(let error):
                pixelEvent = .networkProtectionWireguardErrorCannotSetWireguardConfig
                pixelError = error
            case .noAuthTokenFound:
                pixelEvent = .networkProtectionNoAccessTokenFoundError
            case .vpnAccessRevoked:
                return
            case .unhandledError(function: let function, line: let line, error: let error):
                pixelEvent = .networkProtectionUnhandledError
                params[PixelParameters.function] = function
                params[PixelParameters.line] = String(line)
                pixelError = error
            case .failedToFetchLocationList:
                return
            case .failedToParseLocationListResponse:
                return
            case .failedToFetchServerStatus(let error):
                pixelEvent = .networkProtectionClientFailedToFetchServerStatus
                pixelError = error
            case .failedToParseServerStatusResponse(let error):
                pixelEvent = .networkProtectionClientFailedToParseServerStatusResponse
                pixelError = error
            }
            PixelKit.fire(pixelEvent.withError(pixelError),
                          frequency: .legacyDailyAndCount,
                          options: .parameters(params))
        }
    }

    public override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        switch reason {
        case .appUpdate, .userInitiated:
            break
        default:
            PixelKit.fire(Pixel.Event.networkProtectionDisconnected,
                          frequency: .legacyDailyAndCount,
                          options: .parameters([PixelParameters.reason: String(reason.rawValue)]))
        }
        super.stopTunnel(with: reason, completionHandler: completionHandler)
    }

    @MainActor
    @objc init() {
        APIRequest.Headers.setUserAgent(DefaultUserAgentManager.duckDuckGoUserAgent)
        Self.configurePixelStorage()

        let settings = VPNSettings(defaults: .networkProtectionGroupDefaults)

        configurationManager = ConfigurationManager(fetcher: ConfigurationFetcher(store: configurationStore, configurationURLProvider: VPNAgentConfigurationURLProvider(), eventMapping: ConfigurationManager.configurationDebugEvents), store: configurationStore)
        configurationManager.start()
        let privacyConfigurationManager = VPNPrivacyConfigurationManager.shared
        // Privacy configuration is loaded in loadProtectedResources() after the device is confirmed unlocked.
        // Until then, embedded config is used as fallback.

        let featureFlagger = DefaultFeatureFlagger(
            internalUserDecider: privacyConfigurationManager.internalUserDecider,
            privacyConfigManager: privacyConfigurationManager,
            experimentManager: nil
        )

        let netPGroupID = "\(Global.groupIdPrefix).netp"
        let vpnContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: netPGroupID)

        let loopDetectorStore = vpnContainerURL.map {
            Self.makeUnprotectedFileStore(containerURL: $0, name: "vpn-loop-detector", fallback: UserDefaults.networkProtectionGroupDefaults)
        } ?? UserDefaults.networkProtectionGroupDefaults

        let loopDetector = ConnectionFailureLoopDetector(store: loopDetectorStore)

        self.wideEvent = WideEvent(useMockRequests: {
#if DEBUG || REVIEW || ALPHA
            true
#else
            false
#endif
        }(),
                                   featureFlagProvider: WideEventFeatureFlagProvider(featureFlagger: featureFlagger))

        // Align Subscription environment to the VPN environment
        var subscriptionEnvironment = SubscriptionEnvironment.default
        switch settings.selectedEnvironment {
        case .production:
            subscriptionEnvironment.serviceEnvironment = .production
        case .staging:
            subscriptionEnvironment.serviceEnvironment = .staging
        }

        // MARK: - Configure Subscription

        var tokenHandler: any SubscriptionTokenHandling
        var entitlementsCheck: (() async -> Result<Bool, Error>)
        Logger.networkProtection.log("Configure Subscription")
        let authEnvironment: OAuthEnvironment = subscriptionEnvironment.serviceEnvironment == .production ? .production : .staging
        let authService = DefaultOAuthService(baseURL: authEnvironment.url,
                                              apiService: APIServiceFactory.makeAPIServiceForAuthV2(withUserAgent: DefaultUserAgentManager.duckDuckGoUserAgent))

        let pixelHandler = SubscriptionPixelHandler(source: .systemExtension, pixelKit: PixelKit.shared)
        // keychain storage
        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        let keychainType: KeychainType = .dataProtection(.named(subscriptionAppGroup))
        let keychainManager = KeychainManager(attributes: SubscriptionTokenKeychainStorage.defaultAttributes(keychainType: keychainType), pixelHandler: pixelHandler)
        let tokenStorage = SubscriptionTokenKeychainStorage(keychainManager: keychainManager,
                                                            userDefaults: UserDefaults.standard) { accessType, error in
            let parameters = [PixelParameters.subscriptionKeychainAccessType: accessType.rawValue,
                              PixelParameters.subscriptionKeychainError: error.localizedDescription,
                              PixelParameters.source: KeychainErrorSource.vpn.rawValue,
                              PixelParameters.authVersion: KeychainErrorAuthVersion.v2.rawValue]
            PixelKit.fire(Pixel.Event.subscriptionKeychainAccessError,
                          frequency: .legacyDailyAndCount,
                          options: .parameters(parameters))
        }

        let isAuthV2WideEventEnabled = {
#if DEBUG
            return true
#else
            return authEnvironment == .production
#endif
        }
        let authV2RefreshInstrumentation = DefaultAuthV2TokenRefreshInstrumentation(wideEvent: wideEvent,
                                                                                    isFeatureEnabled: isAuthV2WideEventEnabled,
                                                                                    shouldSuppressFailure: {
                                                                                        loopDetector.shouldSuppressCurrentAttemptTelemetry
                                                                                    })
        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            authService: authService,
                                            refreshEventMapping: authV2RefreshInstrumentation.eventMapping)

        let subscriptionEndpointService = DefaultSubscriptionEndpointService(apiService: APIServiceFactory.makeAPIServiceForSubscription(withUserAgent: DefaultUserAgentManager.duckDuckGoUserAgent),
                                                                             baseURL: subscriptionEnvironment.serviceEnvironment.url)
        let storePurchaseManager = DefaultStorePurchaseManager(subscriptionFeatureMappingCache: subscriptionEndpointService)
        let subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                             oAuthClient: authClient,
                                                             userDefaults: UserDefaults.standard,
                                                             subscriptionEndpointService: subscriptionEndpointService,
                                                             subscriptionEnvironment: subscriptionEnvironment,
                                                             pixelHandler: pixelHandler,
                                                             initForPurchase: false,
                                                             wideEvent: wideEvent,
                                                             isAuthV2WideEventEnabled: isAuthV2WideEventEnabled,
                                                             authV2TokenRefreshInstrumentation: authV2RefreshInstrumentation)
        entitlementsCheck = {
            Logger.networkProtection.log("Subscription Entitlements check...")
            do {
                let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
                let isNetworkProtectionEnabled = tokenContainer.decodedAccessToken.hasEntitlement(.networkProtection)
                Logger.networkProtection.log("NetworkProtectionEnabled if: \( isNetworkProtectionEnabled ? "Enabled" : "Disabled", privacy: .public)")
                return .success(isNetworkProtectionEnabled)
            } catch {
                Logger.networkProtection.error("Subscription Entitlements check failed: \(error.localizedDescription)")
                return .failure(error)
            }
        }
        tokenHandler = subscriptionManager
        self.subscriptionManager = subscriptionManager

        // MARK: -

        let errorStore = NetworkProtectionTunnelErrorStore()
        let notificationsPresenter = NetworkProtectionUNNotificationPresenter()

        let notificationsPresenterDecorator = VPNNotificationsPresenterTogglableDecorator(
            settings: settings,
            defaults: .networkProtectionGroupDefaults,
            wrappee: notificationsPresenter
        )
        notificationsPresenter.requestAuthorization()
        super.init(notificationsPresenter: notificationsPresenterDecorator,
                   tunnelHealthStore: NetworkProtectionTunnelHealthStore(),
                   controllerErrorStore: errorStore,
                   snoozeTimingStore: NetworkProtectionSnoozeTimingStore(userDefaults: .networkProtectionGroupDefaults),
                   wireGuardInterface: DefaultWireGuardInterface(),
                   keychainType: .dataProtection(.unspecified),
                   tokenHandlerProvider: tokenHandler,
                   debugEvents: Self.networkProtectionDebugEvents(controllerErrorStore: errorStore),
                   providerEvents: Self.packetTunnelProviderEvents(loopDetector: loopDetector),
                   settings: settings,
                   defaults: .networkProtectionGroupDefaults,
                   wideEvent: wideEvent,
                   entitlementCheck: entitlementsCheck,
                   loopDetector: loopDetector)
        startMonitoringMemoryPressureEvents()
        observeServerChanges()
        APIRequest.Headers.setUserAgent(DefaultUserAgentManager.duckDuckGoUserAgent)
    }

    deinit {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private let memoryPressureQueue = DispatchQueue(label: "com.duckduckgo.mobile.ios.NetworkExtension.memoryPressure")

    private func startMonitoringMemoryPressureEvents() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: memoryPressureQueue)

        source.setEventHandler { [weak source] in
            guard let source else { return }

            let event = source.data

            if event.contains(.warning) {
                Logger.networkProtectionMemory.warning("Received memory pressure warning")
                PixelKit.fire(Pixel.Event.networkProtectionMemoryWarning, frequency: .legacyDailyNoSuffix)
            } else if event.contains(.critical) {
                Logger.networkProtectionMemory.warning("Received memory pressure critical warning")
                PixelKit.fire(Pixel.Event.networkProtectionMemoryCritical, frequency: .legacyDailyNoSuffix)
            }
        }

        self.memoryPressureSource = source
        source.activate()
    }

    private func observeServerChanges() {
        lastSelectedServerInfoPublisher.sink { server in
            let location = server?.attributes.city ?? "Unknown Location"
            UserDefaults.networkProtectionGroupDefaults.set(location, forKey: NetworkProtectionUserDefaultKeys.lastSelectedServerCity)
        }
        .store(in: &cancellables)
    }

    private static func makeUnprotectedFileStore(containerURL: URL, name: String, fallback: ThrowingKeyValueStoring) -> ThrowingKeyValueStoring {
        guard let fileStore = try? KeyValueFileStore(
            location: containerURL,
            name: name,
            writeOptions: [.atomic, .noFileProtection]
        ) else {
            return fallback
        }
        return fileStore
    }

    /// - Returns: the file store PixelKit's `defaults` was set up with, or `nil` when it fell back
    ///   to `UserDefaults.networkProtectionGroupDefaults`.
    private static func setupPixelKit(vpnFileStoreDirectory: URL?) -> KeyValueFileStore? {
        let pixelKitFileStore: KeyValueFileStore? = vpnFileStoreDirectory.flatMap {
            try? KeyValueFileStore(
                location: $0,
                name: "pixelkit",
                writeOptions: [.atomic, .noFileProtection]
            )
        }
        let pixelKitDefaults: ThrowingKeyValueStoring = pixelKitFileStore ?? UserDefaults.networkProtectionGroupDefaults

        // Configuring PixelKit
        PixelKit.setUp(
            dryRun: PixelKitConfig.isDryRun(isProductionBuild: BuildFlags.isProductionBuild),
            appVersion: AppVersion.shared.versionNumber,
            source: (UIDevice.current.userInterfaceIdiom == .pad ? PixelKit.Source.iPadOS : PixelKit.Source.iOS).rawValue,
            session: "ios-vpn-tunnel",
            defaultHeaders: [:],
            defaults: pixelKitDefaults
        ) { (pixelName: String, headers: [String: String], parameters: [String: String], _, _, onComplete: @escaping PixelKit.CompletionBlock) in
            let url = URL.pixelUrl(forPixelNamed: pixelName)
            // `PixelKit.Options.userAgent` arrives under this key, and overrides the pixel one.
            let apiHeaders = APIRequestV2.HeadersV2(userAgent: headers[PixelKit.Header.userAgent] ?? PixelUserAgent.default,
                                                    additionalHeaders: headers)
            guard let request = APIRequestV2(url: url, method: .get, queryItems: parameters.toQueryItems(), headers: apiHeaders) else {
                onComplete(false, nil)
                return
            }

            Task {
                do {
                    _ = try await DefaultAPIService().fetch(request: request)
                    onComplete(true, nil)
                } catch {
                    onComplete(false, error)
                }
            }
        }

        return pixelKitFileStore
    }

    private static func configurePixelStorage() {
        do {
            let vpnFileStoreDirectory = try Self.vpnFileStoreDirectory()
            let pixelKitStore = Self.setupPixelKit(vpnFileStoreDirectory: vpnFileStoreDirectory)
            let legacyStores = Self.configureDailyPixelFileStore(vpnFileStoreDirectory: vpnFileStoreDirectory)

            // The tunnel keeps its legacy daily and once-ever pixel state in its own app-group
            // files, not in the suites the browser migrates, so it runs its own migration here
            // against whichever store PixelKit actually ended up using. Without it every VPN daily
            // pixel fires once extra and every VPN once-ever pixel fires a second time on the
            // release that migrates.
            let destination: ThrowingKeyValueStoring = pixelKitStore ?? UserDefaults.networkProtectionGroupDefaults
            LegacyPixelStateMigration(
                destination: destination,
                dailyStore: legacyStores.daily.map(KeyValueFileStoreLegacyPixelStore.init),
                uniqueStore: legacyStores.unique.map(KeyValueFileStoreLegacyPixelStore.init),
                debounceStore: nil,
                completionFlagStore: destination
            ).run()
        } catch {
            _ = Self.setupPixelKit(vpnFileStoreDirectory: nil)
            PixelKit.fire(Pixel.Event.networkProtectionPixelStorageSetupFailure.withError(error))
        }
    }

    enum VPNFileStoreError: DDGError {
        case containerURLNotFound
        case directoryCreationFailed(underlying: Error?)

        static var errorDomain: String { "com.duckduckgo.vpnFileStore" }

        var errorCode: Int {
            switch self {
            case .containerURLNotFound: return 1
            case .directoryCreationFailed: return 2
            }
        }

        var underlyingError: Error? {
            switch self {
            case .containerURLNotFound: return nil
            case .directoryCreationFailed(let underlying): return underlying
            }
        }

        var description: String {
            switch self {
            case .containerURLNotFound: return "App group container URL not found"
            case .directoryCreationFailed: return "Failed to create VPN file store directory"
            }
        }

        static func == (lhs: VPNFileStoreError, rhs: VPNFileStoreError) -> Bool {
            lhs.errorCode == rhs.errorCode
        }
    }

    private static func vpnFileStoreDirectory() throws -> URL {
        let vpnGroupName = "\(Global.groupIdPrefix).netp"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: vpnGroupName) else {
            throw VPNFileStoreError.containerURLNotFound
        }

        let directory = containerURL.appendingPathComponent("vpn", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw VPNFileStoreError.directoryCreationFailed(underlying: error)
        }
        return directory
    }

    private static func configureDailyPixelFileStore(vpnFileStoreDirectory: URL?) -> (daily: KeyValueFileStore?, unique: KeyValueFileStore?) {
        guard let vpnFileStoreDirectory else { return (daily: nil, unique: nil) }

        let dailyPixelFileStore = try? KeyValueFileStore(
            location: vpnFileStoreDirectory,
            name: "daily-pixel",
            writeOptions: [.atomic, .noFileProtection]
        )
        if let dailyPixelFileStore {
            DailyPixel.storage = dailyPixelFileStore
        }

        let uniquePixelFileStore = try? KeyValueFileStore(
            location: vpnFileStoreDirectory,
            name: "unique-pixel",
            writeOptions: [.atomic, .noFileProtection]
        )
        if let uniquePixelFileStore {
            UniquePixel.storage = uniquePixelFileStore
        }

        return (daily: dailyPixelFileStore, unique: uniquePixelFileStore)
    }

    private let activationDateStore = DefaultVPNActivationDateStore()

    public override func handleConnectionStatusChange(old: ConnectionStatus, new: ConnectionStatus) {
        super.handleConnectionStatusChange(old: old, new: new)

        activationDateStore.setActivationDateIfNecessary()
        activationDateStore.updateLastActiveDate()

        VPNReloadStatusWidgets()
    }

    public override func loadProtectedResources() async {
        // Load cached privacy configuration now that the device is confirmed unlocked.
        // This is deferred from init() because the config file may be protected by iOS data protection
        // and inaccessible when Connect on Demand starts the VPN before the user unlocks after reboot.
        VPNPrivacyConfigurationManager.shared.reload(
            etag: configurationStore.loadEtag(for: .privacyConfiguration),
            data: configurationStore.loadData(for: .privacyConfiguration)
        )
    }
}

private struct WideEventFeatureFlagProvider: WideEventFeatureFlagProviding {
    let featureFlagger: FeatureFlagger

    func isEnabled(_ flag: WideEventFeatureFlag) -> Bool {
        // There are no flags defined currently, but please replace this with a switch statement when a new flag is added.
        return true
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

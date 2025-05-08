//
//  AppDependencyProvider.swift
//  DuckDuckGo
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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

import Foundation
import Core
import BrowserServicesKit
import DDGSync
import Bookmarks
import Subscription
import Common
import NetworkProtection
import RemoteMessaging
import PageRefreshMonitor
import PixelKit
import PixelExperimentKit
import Networking

protocol DependencyProvider {

    var appSettings: AppSettings { get }
    var variantManager: VariantManager { get }
    var internalUserDecider: InternalUserDecider { get }
    var featureFlagger: FeatureFlagger { get }
    var storageCache: StorageCache { get }
    var downloadManager: DownloadManager { get }
    var autofillLoginSession: AutofillLoginSession { get }
    var autofillNeverPromptWebsitesManager: AutofillNeverPromptWebsitesManager { get }
    var configurationManager: ConfigurationManager { get }
    var configurationStore: ConfigurationStore { get }
    var pageRefreshMonitor: PageRefreshMonitor { get }
    var vpnFeatureVisibility: DefaultNetworkProtectionVisibility { get }
    var networkProtectionKeychainTokenStore: NetworkProtectionKeychainTokenStore { get }
    var networkProtectionTunnelController: NetworkProtectionTunnelController { get }
    var connectionObserver: ConnectionStatusObserver { get }
    var serverInfoObserver: ConnectionServerInfoObserver { get }
    var vpnSettings: VPNSettings { get }
    var persistentPixel: PersistentPixelFiring { get }

    // Subscription
    var subscriptionAuthV1toV2Bridge: any SubscriptionAuthV1toV2Bridge { get }
    var subscriptionManager: (any SubscriptionManager)? { get }
    var subscriptionManagerV2: (any SubscriptionManagerV2)? { get }
    var isAuthV2Enabled: Bool { get }
}

/// Provides dependencies for objects that are not directly instantiated
/// through `init` call (e.g. ViewControllers created from Storyboards).
final class AppDependencyProvider: DependencyProvider {

    static var shared: DependencyProvider = AppDependencyProvider()
    let appSettings: AppSettings = AppUserDefaults()
    let variantManager: VariantManager = DefaultVariantManager()
    let internalUserDecider: InternalUserDecider = ContentBlocking.shared.privacyConfigurationManager.internalUserDecider
    let featureFlagger: FeatureFlagger

    let storageCache = StorageCache()
    let downloadManager = DownloadManager()
    let autofillLoginSession = AutofillLoginSession()
    lazy var autofillNeverPromptWebsitesManager = AutofillNeverPromptWebsitesManager()

    let configurationManager: ConfigurationManager
    let configurationStore = ConfigurationStore()

    let pageRefreshMonitor = PageRefreshMonitor(onDidDetectRefreshPattern: PageRefreshMonitor.onDidDetectRefreshPattern)

    // Subscription
    let subscriptionAuthV1toV2Bridge: any SubscriptionAuthV1toV2Bridge
    var subscriptionManager: (any SubscriptionManager)?
    var subscriptionManagerV2: (any SubscriptionManagerV2)?
    let isAuthV2Enabled: Bool
    
    let vpnFeatureVisibility: DefaultNetworkProtectionVisibility
    let networkProtectionKeychainTokenStore: NetworkProtectionKeychainTokenStore
    let networkProtectionTunnelController: NetworkProtectionTunnelController

    let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)

    let connectionObserver: ConnectionStatusObserver = ConnectionStatusObserverThroughSession()
    let serverInfoObserver: ConnectionServerInfoObserver = ConnectionServerInfoObserverThroughSession()
    let vpnSettings = VPNSettings(defaults: .networkProtectionGroupDefaults)
    let persistentPixel: PersistentPixelFiring = PersistentPixel()

    private init() {
        let featureFlaggerOverrides = FeatureFlagLocalOverrides(keyValueStore: UserDefaults(suiteName: FeatureFlag.localOverrideStoreName)!,
                                                                actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>()
        )
        let experimentManager = ExperimentCohortsManager(store: ExperimentsDataStore(), fireCohortAssigned: PixelKit.fireExperimentEnrollmentPixel(subfeatureID:experiment:))
        featureFlagger = DefaultFeatureFlagger(internalUserDecider: internalUserDecider,
                                               privacyConfigManager: ContentBlocking.shared.privacyConfigurationManager,
                                               localOverrides: featureFlaggerOverrides,
                                               experimentManager: experimentManager,
                                               for: FeatureFlag.self)
        configurationManager = ConfigurationManager(store: configurationStore)

        // Configure Subscription

        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
        let subscriptionEnvironment = DefaultSubscriptionManager.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)
        var tokenHandler: any SubscriptionTokenHandling
        var accessTokenProvider: () async -> String?
        var authenticationStateProvider: (any SubscriptionAuthenticationStateProvider)!

        let tokenStorageV2 = SubscriptionTokenKeychainStorageV2(keychainType: .dataProtection(.named(subscriptionAppGroup))) { accessType, error in

            let parameters = [PixelParameters.privacyProKeychainAccessType: accessType.rawValue,
                              PixelParameters.privacyProKeychainError: error.localizedDescription,
                              PixelParameters.source: KeychainErrorSource.browser.rawValue,
                              PixelParameters.authVersion: KeychainErrorAuthVersion.v2.rawValue]
            DailyPixel.fireDailyAndCount(pixel: .privacyProKeychainAccessError,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                                         withAdditionalParameters: parameters)
        }
        self.isAuthV2Enabled = featureFlagger.isFeatureOn(.privacyProAuthV2)
        vpnSettings.isAuthV2Enabled = self.isAuthV2Enabled
        if !isAuthV2Enabled {
            // V1
            Logger.subscription.debug("Configuring Subscription V1")
            vpnSettings.alignTo(subscriptionEnvironment: subscriptionEnvironment)

            let entitlementsCache = UserDefaultsCache<[Entitlement]>(userDefaults: subscriptionUserDefaults,
                                                                     key: UserDefaultsCacheKey.subscriptionEntitlements,
                                                                     settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))
            let accessTokenStorage = SubscriptionTokenKeychainStorage(keychainType: .dataProtection(.named(subscriptionAppGroup)))
            let subscriptionEndpointService = DefaultSubscriptionEndpointService(currentServiceEnvironment: subscriptionEnvironment.serviceEnvironment)
            let authService = DefaultAuthEndpointService(currentServiceEnvironment: subscriptionEnvironment.serviceEnvironment)
            let subscriptionFeatureMappingCache = DefaultSubscriptionFeatureMappingCache(subscriptionEndpointService: subscriptionEndpointService,
                                                                                         userDefaults: subscriptionUserDefaults)
            let accountManager = DefaultAccountManager(accessTokenStorage: accessTokenStorage,
                                                       entitlementsCache: entitlementsCache,
                                                       subscriptionEndpointService: subscriptionEndpointService,
                                                       authEndpointService: authService)

            let internalUserDecider = featureFlagger.internalUserDecider
            let subscriptionFeatureFlagger = SubscriptionFeatureFlagMapping(internalUserDecider: internalUserDecider,
                                                                            subscriptionEnvironment: subscriptionEnvironment,
                                                                            subscriptionUserDefaults: subscriptionUserDefaults)

            let storePurchaseManager = DefaultStorePurchaseManager(subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                                                                   subscriptionFeatureFlagger: subscriptionFeatureFlagger)

            let subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                                 accountManager: accountManager,
                                                                 subscriptionEndpointService: subscriptionEndpointService,
                                                                 authEndpointService: authService,
                                                                 subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                                                                 subscriptionEnvironment: subscriptionEnvironment,
                                                                 isInternalUserEnabled: { ContentBlocking.shared.privacyConfigurationManager.internalUserDecider.isInternalUser })
            accountManager.delegate = subscriptionManager

            self.subscriptionManager = subscriptionManager

            accessTokenProvider = {
                return { accountManager.accessToken }
            }()
            tokenHandler = accountManager
            authenticationStateProvider = subscriptionManager
            subscriptionAuthV1toV2Bridge = subscriptionManager

            if tokenStorageV2.tokenContainer != nil {
                Logger.subscription.debug("Cleaning up Auth V2 token")
                tokenStorageV2.tokenContainer = nil
                subscriptionEndpointService.clearSubscription()
            }
        } else {
            // V2
            Logger.subscription.debug("Configuring Subscription V2")
            vpnSettings.alignTo(subscriptionEnvironment: subscriptionEnvironment)

            let authEnvironment: OAuthEnvironment = subscriptionEnvironment.serviceEnvironment == .production ? .production : .staging
            let authService = DefaultOAuthService(baseURL: authEnvironment.url, apiService: APIServiceFactory.makeAPIServiceForAuthV2())
            let legacyAccountStorage = SubscriptionTokenKeychainStorage(keychainType: .dataProtection(.named(subscriptionAppGroup)))
            let authClient = DefaultOAuthClient(tokensStorage: tokenStorageV2,
                                                legacyTokenStorage: legacyAccountStorage,
                                                authService: authService)

            var apiServiceForSubscription = APIServiceFactory.makeAPIServiceForSubscription()
            let subscriptionEndpointService = DefaultSubscriptionEndpointServiceV2(apiService: apiServiceForSubscription,
                                                                                   baseURL: subscriptionEnvironment.serviceEnvironment.url)
            apiServiceForSubscription.authorizationRefresherCallback = { _ in

                guard let tokenContainer = tokenStorageV2.tokenContainer else {
                    throw OAuthClientError.internalError("Missing refresh token")
                }

                if tokenContainer.decodedAccessToken.isExpired() {
                    Logger.OAuth.debug("Refreshing tokens")
                    let tokens = try await authClient.getTokens(policy: .localForceRefresh)
                    return tokens.accessToken
                } else {
                    Logger.general.debug("Trying to refresh valid token, using the old one")
                    return tokenContainer.accessToken
                }
            }


            let internalUserDecider = featureFlagger.internalUserDecider
            let subscriptionFeatureFlagger = SubscriptionFeatureFlagMapping(internalUserDecider: internalUserDecider,
                                                                            subscriptionEnvironment: subscriptionEnvironment,
                                                                            subscriptionUserDefaults: subscriptionUserDefaults)

            let storePurchaseManager = DefaultStorePurchaseManagerV2(subscriptionFeatureMappingCache: subscriptionEndpointService,
                                                                     subscriptionFeatureFlagger: subscriptionFeatureFlagger)
            let pixelHandler = AuthV2PixelHandler(source: .mainApp)
            let subscriptionManager = DefaultSubscriptionManagerV2(storePurchaseManager: storePurchaseManager,
                                                                   oAuthClient: authClient,
                                                                   subscriptionEndpointService: subscriptionEndpointService,
                                                                   subscriptionEnvironment: subscriptionEnvironment,
                                                                   pixelHandler: pixelHandler,
                                                                   legacyAccountStorage: AccountKeychainStorage(),
                                                                   isInternalUserEnabled: {
                ContentBlocking.shared.privacyConfigurationManager.internalUserDecider.isInternalUser
            })

            let restoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager, storePurchaseManager: storePurchaseManager)
            subscriptionManager.tokenRecoveryHandler = {
                do {
                    try await DeadTokenRecoverer.attemptRecoveryFromPastPurchase(subscriptionManager: subscriptionManager, restoreFlow: restoreFlow)
                    DailyPixel.fire(pixel: .privacyProInvalidRefreshTokenRecovered)
                    Pixel.fire(pixel: .privacyProInvalidRefreshTokenRecovered)
                } catch {
                    DailyPixel.fire(pixel: .privacyProInvalidRefreshTokenSignedOut)
                    Pixel.fire(pixel: .privacyProInvalidRefreshTokenSignedOut)
                }
            }

            self.subscriptionManagerV2 = subscriptionManager

            accessTokenProvider = {
                { return try? await subscriptionManager.getTokenContainer(policy: .localValid).accessToken }
            }()
            tokenHandler = subscriptionManager
            authenticationStateProvider = subscriptionManager
            subscriptionAuthV1toV2Bridge = subscriptionManager
        }

        vpnFeatureVisibility = DefaultNetworkProtectionVisibility(authenticationStateProvider: authenticationStateProvider)
        networkProtectionKeychainTokenStore = NetworkProtectionKeychainTokenStore(accessTokenProvider: accessTokenProvider)
        networkProtectionTunnelController = NetworkProtectionTunnelController(tokenHandler: tokenHandler,
                                                                              featureFlagger: featureFlagger,
                                                                              persistentPixel: persistentPixel,
                                                                              settings: vpnSettings)

    }

}

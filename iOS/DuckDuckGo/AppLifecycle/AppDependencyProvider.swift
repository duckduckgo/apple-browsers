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
import VPN
import DataBrokerProtectionCore
import DataBrokerProtection_iOS
import RemoteMessaging
import PageRefreshMonitor
import PixelKit
import PixelExperimentKit
import PrivacyConfig
import Networking
import Configuration
import Network

protocol DependencyProvider {

    var appSettings: AppSettings { get }
    var variantManager: VariantManager { get }
    var internalUserDecider: InternalUserDecider { get }
    var featureFlagger: FeatureFlagger { get }
    var configurationURLProvider: CustomConfigurationURLProviding { get }
    var contentScopeExperimentsManager: ContentScopeExperimentsManaging { get }
    var storageCache: StorageCache { get }
    var downloadManager: DownloadManager { get }
    var autofillLoginSession: AutofillLoginSession { get }
    var autofillNeverPromptWebsitesManager: AutofillNeverPromptWebsitesManager { get }
    var configurationManager: ConfigurationManager { get }
    var configurationStore: ConfigurationStore { get }
    var pageRefreshMonitor: PageRefreshMonitor { get }
    var vpnFeatureVisibility: DefaultNetworkProtectionVisibility { get }
    var networkProtectionTunnelController: NetworkProtectionTunnelController { get }
    var connectionObserver: ConnectionStatusObserver { get }
    var serverInfoObserver: ConnectionServerInfoObserver { get }
    var vpnSettings: VPNSettings { get }
    var persistentPixel: PersistentPixelFiring { get }
    var wideEvent: WideEventManaging { get }
    var freeTrialConversionService: FreeTrialConversionInstrumentationService { get }
    var subscriptionManager: any SubscriptionManager { get }
    var tokenHandlerProvider: any SubscriptionTokenHandling { get }
    var dbpSettings: DataBrokerProtectionSettings { get }
}

/// Provides dependencies for objects that are not directly instantiated
/// through `init` call (e.g. ViewControllers created from Storyboards).
final class AppDependencyProvider: DependencyProvider {

    static var shared: DependencyProvider = AppDependencyProvider()
    let appSettings: AppSettings = AppUserDefaults()
    let variantManager: VariantManager = DefaultVariantManager()
    let internalUserDecider: InternalUserDecider = ContentBlocking.shared.privacyConfigurationManager.internalUserDecider
    let featureFlagger: FeatureFlagger
    let configurationURLProvider: CustomConfigurationURLProviding
    let contentScopeExperimentsManager: ContentScopeExperimentsManaging

    let storageCache = StorageCache()
    let downloadManager = DownloadManager()
    let autofillLoginSession = AutofillLoginSession()
    lazy var autofillNeverPromptWebsitesManager = AutofillNeverPromptWebsitesManager()

    let configurationManager: ConfigurationManager
    let configurationStore = ConfigurationStore()

    let pageRefreshMonitor = PageRefreshMonitor(onDidDetectRefreshPattern: PageRefreshMonitor.onDidDetectRefreshPattern)

    // Subscription
    var subscriptionManager: any SubscriptionManager
    var tokenHandlerProvider: any SubscriptionTokenHandling
    static let deadTokenRecoverer = DeadTokenRecoverer()

    let vpnFeatureVisibility: DefaultNetworkProtectionVisibility
    let networkProtectionTunnelController: NetworkProtectionTunnelController

    let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)

    let connectionObserver: ConnectionStatusObserver = ConnectionStatusObserverThroughSession()
    let serverInfoObserver: ConnectionServerInfoObserver = ConnectionServerInfoObserverThroughSession()
    let vpnSettings = VPNSettings(defaults: .networkProtectionGroupDefaults)
    let dbpSettings = DataBrokerProtectionSettings(defaults: .dbp)
    let persistentPixel: PersistentPixelFiring = PersistentPixel()
    let wideEvent: WideEventManaging
    let freeTrialConversionService: FreeTrialConversionInstrumentationService

    private init() {
        let featureFlagOverrideStore = UserDefaults(suiteName: FeatureFlag.localOverrideStoreName)!

        // Apply UI test overrides
        LaunchOptionsHandler().applyUITestOverrides(
            featureFlagOverrideStore: featureFlagOverrideStore,
            configRolloutStore: .standard
        )

        let featureFlaggerOverrides = FeatureFlagLocalOverrides(keyValueStore: featureFlagOverrideStore,
                                                                actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>()
        )
        let experimentManager = ExperimentCohortsManager(store: ExperimentsDataStore(), fireCohortAssigned: PixelKit.fireExperimentEnrollmentPixel(subfeatureID:experiment:))

        var featureFlagger: FeatureFlagger
        if [.unitTests, .integrationTests, .xcPreviews].contains(AppVersion.runType) {
            let mockFeatureFlagger = MockFeatureFlagger()
            self.contentScopeExperimentsManager = MockContentScopeExperimentManager()
            self.featureFlagger = mockFeatureFlagger
            featureFlagger = mockFeatureFlagger
        } else {
            let defaultFeatureFlagger = DefaultFeatureFlagger(internalUserDecider: internalUserDecider,
                                                              privacyConfigManager: ContentBlocking.shared.privacyConfigurationManager,
                                                              localOverrides: featureFlaggerOverrides,
                                                              experimentManager: experimentManager,
                                                              for: FeatureFlag.self)
            self.featureFlagger = defaultFeatureFlagger
            self.contentScopeExperimentsManager = defaultFeatureFlagger
            featureFlagger = defaultFeatureFlagger
        }

        self.wideEvent = WideEvent(featureFlagProvider: WideEventFeatureFlagAdapter(featureFlagger: featureFlagger))
        self.freeTrialConversionService = DefaultFreeTrialConversionInstrumentationService(
            wideEvent: wideEvent,
            pixelHandler: FreeTrialPixelHandler(),
            isFeatureEnabled: { featureFlagger.isFeatureOn(.freeTrialConversionWideEvent) }
        )
        self.freeTrialConversionService.startObservingSubscriptionChanges()
        configurationURLProvider = ConfigurationURLProvider(defaultProvider: AppConfigurationURLProvider(featureFlagger: featureFlagger), internalUserDecider: internalUserDecider, store: CustomConfigurationURLStorage(defaults: UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults()))
        configurationManager = ConfigurationManager(fetcher: ConfigurationFetcher(store: configurationStore, configurationURLProvider: configurationURLProvider, eventMapping: ConfigurationManager.configurationDebugEvents), store: configurationStore)

        // Configure Subscription
        let pixelHandler = SubscriptionPixelHandler(source: .mainApp)
        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
        let subscriptionEnvironment = DefaultSubscriptionManager.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)
        var tokenHandler: any SubscriptionTokenHandling
        var authenticationStateProvider: (any SubscriptionAuthenticationStateProvider)!

        let keychainType = KeychainType.dataProtection(.named(subscriptionAppGroup))
        let keychainManager = KeychainManager(attributes: SubscriptionTokenKeychainStorage.defaultAttributes(keychainType: keychainType), pixelHandler: pixelHandler)
        let tokenStorageV2 = SubscriptionTokenKeychainStorage(keychainManager: keychainManager,
                                                                userDefaults: subscriptionUserDefaults) { accessType, error in

            let parameters = [PixelParameters.subscriptionKeychainAccessType: accessType.rawValue,
                              PixelParameters.subscriptionKeychainError: error.localizedDescription,
                              PixelParameters.source: KeychainErrorSource.browser.rawValue,
                              PixelParameters.authVersion: KeychainErrorAuthVersion.v2.rawValue]
            DailyPixel.fireDailyAndCount(pixel: .subscriptionKeychainAccessError,
                                         pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                                         withAdditionalParameters: parameters)
        }

        // Init V2 classes for migration
        let authEnvironment: OAuthEnvironment = subscriptionEnvironment.serviceEnvironment == .production ? .production : .staging
        let authService = DefaultOAuthService(baseURL: authEnvironment.url,
                                              apiService: APIServiceFactory.makeAPIServiceForAuthV2(withUserAgent: DefaultUserAgentManager.duckDuckGoUserAgent))
        let refreshEventMapper = AuthV2TokenRefreshWideEventData.authV2RefreshEventMapping(wideEvent: wideEvent, isFeatureEnabled: {
#if DEBUG
            return true // Allow the refresh event when using staging in debug mode, for easier testing
#else
            return authEnvironment == .production
#endif
        })

        let authClient = DefaultOAuthClient(tokensStorage: tokenStorageV2,
                                            authService: authService,
                                            refreshEventMapping: refreshEventMapper)
        vpnSettings.alignTo(subscriptionEnvironment: subscriptionEnvironment)
        dbpSettings.alignTo(subscriptionEnvironment: subscriptionEnvironment)

        Logger.subscription.debug("Configuring Subscription")

        var apiServiceForSubscription = APIServiceFactory.makeAPIServiceForSubscription(withUserAgent: DefaultUserAgentManager.duckDuckGoUserAgent)
        let subscriptionEndpointService = DefaultSubscriptionEndpointService(apiService: apiServiceForSubscription,
                                                                               baseURL: subscriptionEnvironment.serviceEnvironment.url)
        apiServiceForSubscription.authorizationRefresherCallback = { _ in

            guard let tokenContainer = try? tokenStorageV2.getTokenContainer() else {
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

        let pendingTransactionHandler = DefaultPendingTransactionHandler(userDefaults: subscriptionUserDefaults,
                                                                         pixelHandler: pixelHandler)
        let storePurchaseManager = DefaultStorePurchaseManager(subscriptionFeatureMappingCache: subscriptionEndpointService,
                                                               subscriptionFeatureFlagger: subscriptionFeatureFlagger,
                                                               pendingTransactionHandler: pendingTransactionHandler)
        let subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                               oAuthClient: authClient,
                                                               userDefaults: subscriptionUserDefaults,
                                                               subscriptionEndpointService: subscriptionEndpointService,
                                                               subscriptionEnvironment: subscriptionEnvironment,
                                                               pixelHandler: pixelHandler,
                                                               isInternalUserEnabled: {
            ContentBlocking.shared.privacyConfigurationManager.internalUserDecider.isInternalUser
        })
        self.tokenHandlerProvider = subscriptionManager
        let restoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: subscriptionManager,
                                                     storePurchaseManager: storePurchaseManager,
                                                     pendingTransactionHandler: pendingTransactionHandler)
        subscriptionManager.tokenRecoveryHandler = {
            try await Self.deadTokenRecoverer.attemptRecoveryFromPastPurchase(purchasePlatform: subscriptionManager.currentEnvironment.purchasePlatform, restoreFlow: restoreFlow)
        }

        self.subscriptionManager = subscriptionManager
        tokenHandler = subscriptionManager
        authenticationStateProvider = subscriptionManager

        vpnFeatureVisibility = DefaultNetworkProtectionVisibility(authenticationStateProvider: authenticationStateProvider)
        networkProtectionTunnelController = NetworkProtectionTunnelController(tokenHandler: tokenHandler,
                                                                              featureFlagger: featureFlagger,
                                                                              persistentPixel: persistentPixel,
                                                                              settings: vpnSettings,
                                                                              wideEvent: wideEvent,
                                                                              freeTrialConversionService: freeTrialConversionService
        )
    }

}

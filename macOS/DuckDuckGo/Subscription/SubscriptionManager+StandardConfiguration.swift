//
//  SubscriptionManager+StandardConfiguration.swift
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

import Foundation
import Subscription
import Common
import PixelKit
import BrowserServicesKit
import FeatureFlags
import Networking
import os.log

extension DefaultSubscriptionManager {

    // Init the SubscriptionManager using the standard dependencies and configuration, to be used only in the dependencies tree root
    public convenience init(featureFlagger: FeatureFlagger? = nil) {
        // Configure Subscription
        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
        let subscriptionEnvironment = DefaultSubscriptionManager.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)
        let entitlementsCache = UserDefaultsCache<[Entitlement]>(userDefaults: subscriptionUserDefaults,
                                                                 key: UserDefaultsCacheKey.subscriptionEntitlements,
                                                                 settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))
        let keychainType = KeychainType.dataProtection(.named(subscriptionAppGroup))
        let accessTokenStorage = SubscriptionTokenKeychainStorage(keychainType: keychainType)
        let subscriptionEndpointService = DefaultSubscriptionEndpointService(currentServiceEnvironment: subscriptionEnvironment.serviceEnvironment)
        let authEndpointService = DefaultAuthEndpointService(currentServiceEnvironment: subscriptionEnvironment.serviceEnvironment)
        let subscriptionFeatureMappingCache = DefaultSubscriptionFeatureMappingCache(subscriptionEndpointService: subscriptionEndpointService,
                                                                                     userDefaults: subscriptionUserDefaults)

        let accountManager = DefaultAccountManager(accessTokenStorage: accessTokenStorage,
                                                   entitlementsCache: entitlementsCache,
                                                   subscriptionEndpointService: subscriptionEndpointService,
                                                   authEndpointService: authEndpointService)

        let subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags> = FeatureFlaggerMapping { feature in
            guard let featureFlagger else {
                // With no featureFlagger provided there is no gating of features
                return feature.defaultState
            }

            switch feature {
            case .usePrivacyProUSARegionOverride:
                return (featureFlagger.internalUserDecider.isInternalUser &&
                        subscriptionEnvironment.serviceEnvironment == .staging &&
                        subscriptionUserDefaults.storefrontRegionOverride == .usa)
            case .usePrivacyProROWRegionOverride:
                return (featureFlagger.internalUserDecider.isInternalUser &&
                        subscriptionEnvironment.serviceEnvironment == .staging &&
                        subscriptionUserDefaults.storefrontRegionOverride == .restOfWorld)
            }
        }

        let isInternalUserEnabled = { featureFlagger?.internalUserDecider.isInternalUser ?? false }

        if #available(macOS 12.0, *) {
            let storePurchaseManager = DefaultStorePurchaseManager(subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                                                                   subscriptionFeatureFlagger: subscriptionFeatureFlagger)
            self.init(storePurchaseManager: storePurchaseManager,
                      accountManager: accountManager,
                      subscriptionEndpointService: subscriptionEndpointService,
                      authEndpointService: authEndpointService,
                      subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                      subscriptionEnvironment: subscriptionEnvironment,
                      isInternalUserEnabled: isInternalUserEnabled)
        } else {
            self.init(accountManager: accountManager,
                      subscriptionEndpointService: subscriptionEndpointService,
                      authEndpointService: authEndpointService,
                      subscriptionFeatureMappingCache: subscriptionFeatureMappingCache,
                      subscriptionEnvironment: subscriptionEnvironment,
                      isInternalUserEnabled: isInternalUserEnabled)
        }

        accountManager.delegate = self

        // Auth V2 cleanup in case of rollback
        let tokenStorage = SubscriptionTokenKeychainStorageV2(keychainType: keychainType) { _, error in
            Logger.subscription.error("Failed to remove AuthV2 token container : \(error.localizedDescription, privacy: .public)")
        }
        try? tokenStorage.saveTokenContainer(nil)
    }
}

extension DefaultSubscriptionManager: @retroactive AccountManagerKeychainAccessDelegate {

    public func accountManagerKeychainAccessFailed(accessType: AccountKeychainAccessType, error: any Error) {

        guard let expectedError = error as? AccountKeychainAccessError else {
            assertionFailure("Unexpected error type: \(error)")
            Logger.networkProtection.fault("Unexpected error type: \(error)")
            return
        }

        PixelKit.fire(PrivacyProErrorPixel.privacyProKeychainAccessError(accessType: accessType,
                                                                         accessError: expectedError,
                                                                         source: KeychainErrorSource.shared,
                                                                         authVersion: KeychainErrorAuthVersion.v1),
                      frequency: .legacyDailyAndCount)
    }
}

// MARK: V2

extension DefaultSubscriptionManagerV2 {
    // Init the SubscriptionManager using the standard dependencies and configuration, to be used only in the dependencies tree root
    public convenience init(keychainType: KeychainType,
                            environment: SubscriptionEnvironment,
                            featureFlagger: FeatureFlagger? = nil,
                            userDefaults: UserDefaults,
                            canPerformAuthMigration: Bool,
                            pixelHandlingSource: AuthV2PixelHandler.Source) {

        let authService = DefaultOAuthService(baseURL: environment.authEnvironment.url, apiService: APIServiceFactory.makeAPIServiceForAuthV2())
        let tokenStorage = SubscriptionTokenKeychainStorageV2(keychainType: keychainType) { accessType, error in
            PixelKit.fire(PrivacyProErrorPixel.privacyProKeychainAccessError(accessType: accessType,
                                                                             accessError: error,
                                                                             source: KeychainErrorSource.shared,
                                                                             authVersion: KeychainErrorAuthVersion.v2),
                          frequency: .legacyDailyAndCount)
        }
        let legacyTokenStorage = canPerformAuthMigration == true ? SubscriptionTokenKeychainStorage(keychainType: keychainType) : nil
        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            legacyTokenStorage: legacyTokenStorage,
                                            authService: authService)
        var apiServiceForSubscription = APIServiceFactory.makeAPIServiceForSubscription()
        let subscriptionEndpointService = DefaultSubscriptionEndpointServiceV2(apiService: apiServiceForSubscription,
                                                                               baseURL: environment.serviceEnvironment.url)
        apiServiceForSubscription.authorizationRefresherCallback = { _ in

            guard let tokenContainer = try? tokenStorage.getTokenContainer() else {
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
        let subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags> = FeatureFlaggerMapping { feature in
            guard let featureFlagger else {
                // With no featureFlagger provided there is no gating of features
                return feature.defaultState
            }

            switch feature {
            case .usePrivacyProUSARegionOverride:
                return (featureFlagger.internalUserDecider.isInternalUser &&
                        environment.serviceEnvironment == .staging &&
                        userDefaults.storefrontRegionOverride == .usa)
            case .usePrivacyProROWRegionOverride:
                return (featureFlagger.internalUserDecider.isInternalUser &&
                        environment.serviceEnvironment == .staging &&
                        userDefaults.storefrontRegionOverride == .restOfWorld)
            }
        }

        // Pixel handler configuration
        let pixelHandler: SubscriptionPixelHandler = AuthV2PixelHandler(source: pixelHandlingSource)

        let isInternalUserEnabled = { featureFlagger?.internalUserDecider.isInternalUser ?? false }
        let legacyAccountStorage = AccountKeychainStorage()
        if #available(macOS 12.0, *) {
            self.init(storePurchaseManager: DefaultStorePurchaseManagerV2(subscriptionFeatureMappingCache: subscriptionEndpointService,
                                                                          subscriptionFeatureFlagger: subscriptionFeatureFlagger),
                      oAuthClient: authClient,
                      subscriptionEndpointService: subscriptionEndpointService,
                      subscriptionEnvironment: environment,
                      pixelHandler: pixelHandler,
                      legacyAccountStorage: legacyAccountStorage,
                      isInternalUserEnabled: isInternalUserEnabled)
        } else {
            self.init(oAuthClient: authClient,
                      subscriptionEndpointService: subscriptionEndpointService,
                      subscriptionEnvironment: environment,
                      pixelHandler: pixelHandler,
                      legacyAccountStorage: legacyAccountStorage,
                      isInternalUserEnabled: isInternalUserEnabled)
        }
    }
}

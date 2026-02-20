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
import PrivacyConfig
import FeatureFlags
import Networking
import os.log

extension DefaultSubscriptionManager {
    // Init the SubscriptionManager using the standard dependencies and configuration, to be used only in the dependencies tree root
    public convenience init(keychainType: KeychainType,
                            environment: SubscriptionEnvironment,
                            featureFlagger: FeatureFlagger? = nil,
                            userDefaults: UserDefaults,
                            pixelHandlingSource: SubscriptionPixelHandler.Source,
                            source: KeychainErrorSource) {

        let pixelHandler: SubscriptionPixelHandling = SubscriptionPixelHandler(source: pixelHandlingSource, pixelKit: PixelKit.shared)
        let keychainManager = KeychainManager(attributes: SubscriptionTokenKeychainStorage.defaultAttributes(keychainType: keychainType), pixelHandler: pixelHandler)
        let authService = DefaultOAuthService(baseURL: environment.authEnvironment.url,
                                              apiService: APIServiceFactory.makeAPIServiceForAuthV2(withUserAgent: UserAgent.duckDuckGoUserAgent()))
        let tokenStorage = SubscriptionTokenKeychainStorage(keychainManager: keychainManager,
                                                              userDefaults: userDefaults) { accessType, error in
            PixelKit.fire(SubscriptionErrorPixel.subscriptionKeychainAccessError(accessType: accessType,
                                                                             accessError: error,
                                                                             source: source,
                                                                             authVersion: KeychainErrorAuthVersion.v2),
                          frequency: .legacyDailyAndCount)
        }

        let featureFlagProvider: WideEventFeatureFlagProviding = featureFlagger.map {
            WideEventFeatureFlagAdapter(featureFlagger: $0)
        } ?? StaticWideEventFeatureFlagProvider(isPostEndpointEnabled: true)

        let wideEvent: WideEventManaging = WideEvent(featureFlagProvider: featureFlagProvider)
        let authRefreshEventMapping = AuthV2TokenRefreshWideEventData.authV2RefreshEventMapping(wideEvent: wideEvent, isFeatureEnabled: {
#if DEBUG
            return true // Allow the refresh event when using staging in debug mode, for easier testing
#else
            return environment.serviceEnvironment == .production
#endif
        })
        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            authService: authService,
                                            refreshEventMapping: authRefreshEventMapping)
        var apiServiceForSubscription = APIServiceFactory.makeAPIServiceForSubscription(withUserAgent: UserAgent.duckDuckGoUserAgent())
        let subscriptionEndpointService = DefaultSubscriptionEndpointService(apiService: apiServiceForSubscription,
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
            case .useSubscriptionUSARegionOverride:
                return (featureFlagger.internalUserDecider.isInternalUser &&
                        environment.serviceEnvironment == .staging &&
                        userDefaults.storefrontRegionOverride == .usa)
            case .useSubscriptionROWRegionOverride:
                return (featureFlagger.internalUserDecider.isInternalUser &&
                        environment.serviceEnvironment == .staging &&
                        userDefaults.storefrontRegionOverride == .restOfWorld)
            }
        }
        let isInternalUserEnabled = { featureFlagger?.internalUserDecider.isInternalUser ?? false }
        if #available(macOS 12.0, *) {
            let pendingTransactionHandler = DefaultPendingTransactionHandler(userDefaults: userDefaults,
                                                                             pixelHandler: pixelHandler)
            self.init(storePurchaseManager: DefaultStorePurchaseManager(subscriptionFeatureMappingCache: subscriptionEndpointService,
                                                                        subscriptionFeatureFlagger: subscriptionFeatureFlagger,
                                                                        pendingTransactionHandler: pendingTransactionHandler),
                      oAuthClient: authClient,
                      userDefaults: userDefaults,
                      subscriptionEndpointService: subscriptionEndpointService,
                      subscriptionEnvironment: environment,
                      pixelHandler: pixelHandler,
                      isInternalUserEnabled: isInternalUserEnabled)
        } else {
            self.init(oAuthClient: authClient,
                      userDefaults: userDefaults,
                      subscriptionEndpointService: subscriptionEndpointService,
                      subscriptionEnvironment: environment,
                      pixelHandler: pixelHandler,
                      isInternalUserEnabled: isInternalUserEnabled)
        }
    }
}

private struct StaticWideEventFeatureFlagProvider: WideEventFeatureFlagProviding {
    let isPostEndpointEnabled: Bool

    func isEnabled(_ flag: WideEventFeatureFlag) -> Bool {
        switch flag {
        case .postEndpoint:
#if DEBUG || REVIEW || ALPHA
            return false
#else
            return isPostEndpointEnabled
#endif
        }
    }
}

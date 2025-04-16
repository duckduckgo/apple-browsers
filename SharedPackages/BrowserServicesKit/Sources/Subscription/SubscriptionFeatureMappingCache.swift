//
//  SubscriptionFeatureMappingCache.swift
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

import Foundation
import os.log

public protocol SubscriptionFeatureMappingCache {
    func subscriptionFeatures(for subscriptionIdentifier: String) async -> [Entitlement.ProductName]
}

public actor DefaultSubscriptionFeatureMappingCache: SubscriptionFeatureMappingCache {

    private let subscriptionEndpointService: SubscriptionEndpointService
    private let userDefaults: UserDefaults

    public init(subscriptionEndpointService: SubscriptionEndpointService, userDefaults: UserDefaults) {
        self.subscriptionEndpointService = subscriptionEndpointService
        self.userDefaults = userDefaults
    }

    public func subscriptionFeatures(for subscriptionIdentifier: String) async -> [Entitlement.ProductName] {
        Logger.subscription.debug("[SubscriptionFeatureMappingCache] \(#function) \(subscriptionIdentifier)")
        let features: [Entitlement.ProductName]

        if let subscriptionFeatures = currentSubscriptionFeatureMapping[subscriptionIdentifier] {
            Logger.subscription.debug("[SubscriptionFeatureMappingCache] - got cached features")
            features = subscriptionFeatures
        } else if let subscriptionFeatures = await fetchRemoteFeatures(for: subscriptionIdentifier) {
            Logger.subscription.debug("[SubscriptionFeatureMappingCache] - fetching features from BE API")
            features = subscriptionFeatures
            updateCachedFeatureMapping(with: subscriptionFeatures, for: subscriptionIdentifier)
        } else {
            Logger.subscription.debug("[SubscriptionFeatureMappingCache] - Error: using fallback")
            features = fallbackFeatures
        }

        return features
    }

    // MARK: - Current feature mapping

    private var currentSubscriptionFeatureMapping: SubscriptionFeatureMapping {
        Logger.subscription.debug("[SubscriptionFeatureMappingCache] - \(#function)")
        let featureMapping: SubscriptionFeatureMapping

        if let cachedFeatureMapping {
            Logger.subscription.debug("[SubscriptionFeatureMappingCache] -- got cachedFeatureMapping")
            featureMapping = cachedFeatureMapping
        } else if let storedFeatureMapping {
            Logger.subscription.debug("[SubscriptionFeatureMappingCache] -- have to fetchStoredFeatureMapping")
            featureMapping = storedFeatureMapping
            updateCachedFeatureMapping(to: featureMapping)
        } else {
            Logger.subscription.debug("[SubscriptionFeatureMappingCache] -- <nil> so creating a new one!")
            featureMapping = SubscriptionFeatureMapping()
            updateCachedFeatureMapping(to: featureMapping)
        }

        return featureMapping
    }

    // MARK: - Cached subscription feature mapping

    private var cachedFeatureMapping: SubscriptionFeatureMapping?

    private func updateCachedFeatureMapping(to featureMapping: SubscriptionFeatureMapping) {
        cachedFeatureMapping = featureMapping
    }

    private func updateCachedFeatureMapping(with features: [Entitlement.ProductName], for subscriptionIdentifier: String) {
        var updatedFeatureMapping = cachedFeatureMapping ?? SubscriptionFeatureMapping()
        updatedFeatureMapping[subscriptionIdentifier] = features

        self.cachedFeatureMapping = updatedFeatureMapping
        self.storedFeatureMapping = updatedFeatureMapping
    }

    // MARK: - Stored subscription feature mapping

    static private let subscriptionFeatureMappingKey = "com.duckduckgo.subscription.featuremapping"

    var storedFeatureMapping: SubscriptionFeatureMapping? {
        get {
            guard let data = userDefaults.data(forKey: Self.subscriptionFeatureMappingKey) else { return nil }
            do {
                return try JSONDecoder().decode(SubscriptionFeatureMapping?.self, from: data)
            } catch {
                assertionFailure("Errored while decoding feature mapping")
                return nil
            }
        }

        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                userDefaults.set(data, forKey: Self.subscriptionFeatureMappingKey)
            } catch {
                assertionFailure("Errored while encoding feature mapping")
            }
        }
    }

    // MARK: - Remote subscription feature mapping

    private func fetchRemoteFeatures(for subscriptionIdentifier: String) async -> [Entitlement.ProductName]? {
        if case let .success(response) = await subscriptionEndpointService.getSubscriptionFeatures(for: subscriptionIdentifier) {
            Logger.subscription.debug("[SubscriptionFeatureMappingCache] -- Fetched features for `\(subscriptionIdentifier)`: \(response.features)")
            return response.features
        }

        return nil
    }

    // MARK: - Fallback subscription feature mapping

    private let fallbackFeatures: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration]
}

typealias SubscriptionFeatureMapping = [String: [Entitlement.ProductName]]

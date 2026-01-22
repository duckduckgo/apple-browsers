//
//  SubscriptionFeatureMappingCacheMock.swift
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
import Networking

public final class SubscriptionFeatureMappingCacheMock: SubscriptionFeatureMappingCache {

    public var didCallSubscriptionFeatures = false
    public var lastCalledSubscriptionId: String?

    public var mapping: [String: [SubscriptionEntitlement]] = [:]
    public var tierMapping: [String: [TierFeature]] = [:]
    public var shouldThrowError: Error?

    public init() { }

    public func subscriptionFeatures(for subscriptionIdentifier: String) async -> [SubscriptionEntitlement] {
        didCallSubscriptionFeatures = true
        lastCalledSubscriptionId = subscriptionIdentifier
        return mapping[subscriptionIdentifier] ?? []
    }

    public func subscriptionTierFeatures(for subscriptionIdentifiers: [String]) async throws -> [String: [TierFeature]] {
        if let error = shouldThrowError {
            throw error
        }
        var result: [String: [TierFeature]] = [:]
        for identifier in subscriptionIdentifiers {
            result[identifier] = tierMapping[identifier] ?? []
        }
        return result
    }
}

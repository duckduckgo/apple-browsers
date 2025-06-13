//
//  DataBrokerProtectionSubscriptionManaging.swift
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

public protocol DataBrokerProtectionSubscriptionManaging {
    func accessToken() async -> String?
    func hasValidEntitlement() async throws -> Bool
}

public final class DataBrokerProtectionSubscriptionManager: DataBrokerProtectionSubscriptionManaging {

    let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    let runTypeProvider: AppRunTypeProviding
    let isAuthV2Enabled: Bool

    public func accessToken() async -> String? {
        // We use a staging token for privacy pro supplied through a github secret/action
        // for PIR end to end tests. This is also stored in bitwarden if you want to run
        // the tests locally

        if runTypeProvider.runType == .integrationTests {
            var tokenKey: String
            if !isAuthV2Enabled {
                tokenKey = "PRIVACYPRO_STAGING_TOKEN"
            } else {
                tokenKey = "PRIVACYPRO_STAGING_ACCESS_TOKEN_V2"
            }

            if let token = ProcessInfo.processInfo.environment[tokenKey] {
                return token
            }
        }
        return try? await subscriptionManager.getAccessToken()
    }

    public init(subscriptionManager: any SubscriptionAuthV1toV2Bridge, runTypeProvider: AppRunTypeProviding, isAuthV2Enabled: Bool) {
        self.subscriptionManager = subscriptionManager
        self.runTypeProvider = runTypeProvider
        self.isAuthV2Enabled = isAuthV2Enabled
    }

    public func hasValidEntitlement() async throws -> Bool {
        if runTypeProvider.runType == .integrationTests {
            return true // real entitlements check are not possible here in AuthV2 because the SubscriptionManager has no token
        } else {
            return await subscriptionManager.isFeatureEnabledForUser(feature: .dataBrokerProtection)
        }
    }
}

// MARK: - Wrapper Protocols

/// This protocol exists only as a wrapper on top of the AccountManager since it is a concrete type on BSK
public protocol DataBrokerProtectionAccountManaging {
    func accessToken() async -> String?
    func hasEntitlement(for cachePolicy: APICachePolicy) async -> Result<Bool, Error>
}

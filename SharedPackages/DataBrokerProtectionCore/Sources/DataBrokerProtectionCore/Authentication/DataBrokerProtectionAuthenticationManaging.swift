//
//  DataBrokerProtectionAuthenticationManaging.swift
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

public enum AuthenticationError: Error, Equatable {
    case noAuthToken
}

public protocol DataBrokerProtectionAuthenticationManaging {
    var isUserAuthenticated: Bool { get async }
    /// Returns whether the user is eligible for a free trial
    var isUserEligibleForFreeTrial: Bool { get }
    func accessToken() async -> String?
    /// Returns whether the current token carries the PIR entitlement.
    /// - Returns: `.enabled` or `.disabled` from the token's entitlements, or `.error` when no token can be read.
    func entitlementStatus() async -> DataBrokerProtectionEntitlementStatus
    func getAuthHeader() async -> String?
}

public final class DataBrokerProtectionAuthenticationManager: DataBrokerProtectionAuthenticationManaging {
    private let subscriptionManager: DataBrokerProtectionSubscriptionManaging

    /// The subscription's authentication state, which doesn't depend on a token being stored.
    public var isUserAuthenticated: Bool {
        get async {
            subscriptionManager.isUserAuthenticated
        }
    }

    /// Returns whether the user is eligible for a free trial
    public var isUserEligibleForFreeTrial: Bool {
        subscriptionManager.isUserEligibleForFreeTrial()
    }

    public func accessToken() async -> String? {
        await subscriptionManager.accessToken()
    }

    public init(subscriptionManager: any DataBrokerProtectionSubscriptionManaging) {
        self.subscriptionManager = subscriptionManager
    }

    public func entitlementStatus() async -> DataBrokerProtectionEntitlementStatus {
        await subscriptionManager.entitlementStatus()
    }

    public func getAuthHeader() async -> String? {
        let token = await accessToken()
        return ServicesAuthHeaderBuilder().getAuthHeader(token)
    }
}

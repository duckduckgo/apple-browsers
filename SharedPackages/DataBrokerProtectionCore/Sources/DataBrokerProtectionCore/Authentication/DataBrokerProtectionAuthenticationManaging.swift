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
    case noInviteCode
    case cantGenerateURL
    case noAuthToken
    case issueRedeemingInviteCode(error: String)
}

public protocol DataBrokerProtectionAuthenticationManaging {
    var isUserAuthenticated: Bool { get }
    /// Returns whether the user is eligible for a free trial
    var isUserEligibleForFreeTrial: Bool { get }
    func accessToken() async -> String?
    func hasValidEntitlement() async throws -> Bool
    func getAuthHeader() async -> String?
}

public final class DataBrokerProtectionAuthenticationManager: DataBrokerProtectionAuthenticationManaging {
    private let subscriptionManager: DataBrokerProtectionSubscriptionManaging

    public var isUserAuthenticated: Bool {
        var token: String?
        // extremely ugly hack, will be removed as soon auth v1 is removed
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            token = await accessToken()
            semaphore.signal()
        }
        semaphore.wait()
        return token != nil
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

    public func hasValidEntitlement() async throws -> Bool {
        try await subscriptionManager.hasValidEntitlement()
    }

    public func getAuthHeader() async -> String? {
        let token = await accessToken()
        return ServicesAuthHeaderBuilder().getAuthHeader(token)
    }
}

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
import AppKitExtensions

public protocol DataBrokerProtectionSubscriptionManaging {
    var isUserAuthenticated: Bool { get }
    func accessToken() async -> String?
    func hasValidEntitlement() async throws -> Bool
}

public final class DataBrokerProtectionSubscriptionManager: DataBrokerProtectionSubscriptionManaging {

    let subscriptionManager: any SubscriptionAuthV1toV2Bridge

    public var isUserAuthenticated: Bool {
        subscriptionManager.isUserAuthenticated
    }

    public func accessToken() async -> String? {
        // We use a staging token for privacy pro supplied through a github secret/action
        // for PIR end to end tests. This is also stored in bitwarden if you want to run
        // the tests locally 
        let dbpSettings = DataBrokerProtectionSettings()
        if dbpSettings.storedRunType == .integrationTests,
           let token = ProcessInfo.processInfo.environment["PRIVACYPRO_STAGING_TOKEN"] { // todo auth V1 token??
            return token
        }
        return try? await subscriptionManager.getAccessToken()
    }

    public init(subscriptionManager: any SubscriptionAuthV1toV2Bridge) {
        self.subscriptionManager = subscriptionManager
    }

    public func hasValidEntitlement() async throws -> Bool {
        try await subscriptionManager.isEnabled(feature: .dataBrokerProtection)
    }
}

// MARK: - Wrapper Protocols

/// This protocol exists only as a wrapper on top of the AccountManager since it is a concrete type on BSK
public protocol DataBrokerProtectionAccountManaging {
    func accessToken() async -> String?
    func hasEntitlement(for cachePolicy: APICachePolicy) async -> Result<Bool, Error>
}

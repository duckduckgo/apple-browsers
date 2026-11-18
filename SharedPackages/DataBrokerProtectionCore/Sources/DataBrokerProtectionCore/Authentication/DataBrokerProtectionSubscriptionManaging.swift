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
import os.log

public protocol DataBrokerProtectionSubscriptionManaging {
    func accessToken() async -> String?
    func hasValidEntitlement() async throws -> Bool
    /// Returns whether the user is eligible for a free trial
    /// - Returns: `true` if the user is eligible for a free trial, `false` otherwise
    func isUserEligibleForFreeTrial() -> Bool
}

public final class DataBrokerProtectionSubscriptionManager: DataBrokerProtectionSubscriptionManaging {

    let subscriptionManager: any SubscriptionManager
    let runTypeProvider: AppRunTypeProviding

    #if DEBUG
    private let debugAccessToken: String?
    #endif

    public func accessToken() async -> String? {
        #if DEBUG
        if isDebugAccessTokenProvided { return isDebugAccessTokenValid ? debugAccessToken : nil }
        #endif
        // We use a staging token for DuckDuckGo subscription supplied through a github secret/action
        // for PIR end to end tests. This is also stored in bitwarden if you want to run
        // the tests locally

        if runTypeProvider.runType == .integrationTests {
            Logger.dataBrokerProtection.log("🐕 integrationTests")
            var tokenKey: String
            Logger.dataBrokerProtection.log("🐕 auth v2")
            tokenKey = "PRIVACYPRO_STAGING_ACCESS_TOKEN_V2"

            if let token = ProcessInfo.processInfo.environment[tokenKey] {
                return token
            } else {
                Logger.dataBrokerProtection.error("🐕 No environment token")
                assertionFailure("No environment token")
            }
        }
        return try? await subscriptionManager.getAccessToken()
    }

    /// Returns whether the user is eligible for a free trial
    /// - Returns: `true` if the user is eligible for a free trial, `false` otherwise
    public func isUserEligibleForFreeTrial() -> Bool {
        subscriptionManager.isUserEligibleForFreeTrial()
    }

    public init(subscriptionManager: any SubscriptionManager, runTypeProvider: AppRunTypeProviding) {
        self.subscriptionManager = subscriptionManager
        self.runTypeProvider = runTypeProvider
        #if DEBUG
        self.debugAccessToken = nil
        #endif
    }

    #if DEBUG
    private init(subscriptionManager: any SubscriptionManager, runTypeProvider: AppRunTypeProviding, debugAccessToken: String) {
        self.subscriptionManager = subscriptionManager
        self.runTypeProvider = runTypeProvider
        self.debugAccessToken = debugAccessToken
    }
    #endif

    public func hasValidEntitlement() async throws -> Bool {
        #if DEBUG
        guard !isDebugAccessTokenProvided else { return false }
        #endif
        if runTypeProvider.runType == .integrationTests {
            return true // real entitlements check are not possible here in AuthV2 because the SubscriptionManager has no token
        } else {
            return try await subscriptionManager.isFeatureEnabled(.dataBrokerProtection)
        }
    }
}

#if DEBUG
extension DataBrokerProtectionSubscriptionManager {

    public static let debugAccessTokenEnvironmentKey = "PIR_DEBUG_ACCESS_TOKEN"

    /// The app-wide manager never reads the debug token, so only the debug runner sees it.
    public func debugRunnerManager(environment: [String: String] = ProcessInfo.processInfo.environment) -> DataBrokerProtectionSubscriptionManager {
        guard let token = environment[Self.debugAccessTokenEnvironmentKey] else { return self }
        return DataBrokerProtectionSubscriptionManager(subscriptionManager: subscriptionManager, runTypeProvider: runTypeProvider, debugAccessToken: token)
    }

    public var isDebugAccessTokenProvided: Bool { debugAccessToken != nil }

    public var isDebugAccessTokenValid: Bool {
        guard let debugAccessToken else { return false }
        return !debugAccessToken.isEmpty && debugAccessToken.utf8.count <= 65_536
            && !debugAccessToken.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }
    }

    public var isSubscriptionAuthenticated: Bool { subscriptionManager.isUserAuthenticated }

    public var entitlementEnvironment: String {
        subscriptionManager.currentEnvironment.serviceEnvironment.rawValue
    }

    /// Uses the normal token policy but preserves failures instead of falling back to cached entitlements.
    public func debugEntitlement() async throws -> Bool {
        guard !isDebugAccessTokenProvided, !isEntitlementCheckBypassed else { return false }
        guard subscriptionManager.isUserAuthenticated else { return false }
        let container = try await subscriptionManager.getTokenContainer(policy: .localValid)
        return container.decodedAccessToken.subscriptionEntitlements.contains(.dataBrokerProtection)
    }

    public var isEntitlementCheckBypassed: Bool {
        !isDebugAccessTokenProvided && runTypeProvider.runType == .integrationTests
    }
}
#endif

// MARK: - Wrapper Protocols

/// This protocol exists only as a wrapper on top of the AccountManager since it is a concrete type on BSK
public protocol DataBrokerProtectionAccountManaging {
    func accessToken() async -> String?
    func hasEntitlement(for cachePolicy: APICachePolicy) async -> Result<Bool, Error>
}

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
import Networking
import os.log
import Security

/// Whether the current token carries the PIR entitlement.
public enum DataBrokerProtectionEntitlementStatus: Equatable {
    /// The token carries the PIR entitlement.
    case enabled
    /// The token doesn't carry the PIR entitlement.
    case disabled
    /// The entitlement couldn't be checked.
    case error(DataBrokerProtectionEntitlementErrorReason)
}

public enum DataBrokerProtectionEntitlementErrorReason: String {
    case noToken = "no_token"
    case keychainLocked = "keychain_locked"
    case keychainError = "keychain_error"
    case network
    case profileRead = "profile_read"
    case unknown

    public init(_ error: Error) {
        let underlyingError: Error
        switch error {
        case SubscriptionManagerError.noTokenAvailable:
            self = .noToken
            return
        case SubscriptionManagerError.errorRetrievingTokenContainer(let wrappedError?):
            underlyingError = wrappedError
        default:
            underlyingError = error
        }

        switch underlyingError {
        case AccountKeychainAccessError.keychainLookupFailure(let status) where status == errSecInteractionNotAllowed:
            self = .keychainLocked
        case is AccountKeychainAccessError:
            self = .keychainError
        case is URLError, APIRequestV2Error.urlSession:
            self = .network
        case OAuthServiceError.invalidResponseCode(let status) where status.isServerError || status == .requestTimeout || status == .tooManyRequests:
            self = .network
        default:
            self = .unknown
        }
    }
}

public protocol DataBrokerProtectionSubscriptionManaging {
    /// Whether the user is signed in to the subscription. Doesn't depend on a token being stored.
    var isUserAuthenticated: Bool { get }
    func accessToken() async -> String?
    /// Returns whether the current token carries the PIR entitlement.
    /// - Returns: `.enabled` or `.disabled` from the token's entitlements, or `.error` when no token can be read.
    func entitlementStatus() async -> DataBrokerProtectionEntitlementStatus
    /// Returns whether the user is eligible for a free trial
    /// - Returns: `true` if the user is eligible for a free trial, `false` otherwise
    func isUserEligibleForFreeTrial() -> Bool
}

public final class DataBrokerProtectionSubscriptionManager: DataBrokerProtectionSubscriptionManaging {

    let subscriptionManager: any SubscriptionManager
    let runTypeProvider: AppRunTypeProviding
    let featureFlagger: EntitlementCheckErrorHandlingFeatureFlagging
    private static let integrationTestsTokenKey = "PRIVACYPRO_STAGING_ACCESS_TOKEN_V2"

    public func accessToken() async -> String? {
        // We use a staging token for DuckDuckGo subscription supplied through a github secret/action
        // for PIR end to end tests. This is also stored in bitwarden if you want to run
        // the tests locally

        if runTypeProvider.runType == .integrationTests {
            Logger.dataBrokerProtection.log("🐕 integrationTests")
            Logger.dataBrokerProtection.log("🐕 auth v2")
            let tokenKey = Self.integrationTestsTokenKey

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

    public init(subscriptionManager: any SubscriptionManager,
                runTypeProvider: AppRunTypeProviding,
                featureFlagger: EntitlementCheckErrorHandlingFeatureFlagging) {
        self.subscriptionManager = subscriptionManager
        self.runTypeProvider = runTypeProvider
        self.featureFlagger = featureFlagger
    }

    /// The subscription's authentication state. In integration tests, whether the environment provides a token.
    public var isUserAuthenticated: Bool {
        if runTypeProvider.runType == .integrationTests {
            return ProcessInfo.processInfo.environment[Self.integrationTestsTokenKey] != nil
        }
        return subscriptionManager.isUserAuthenticated
    }

    /// Reads the current token with `getTokenContainer(policy: .localValid)`, which restores a missing one first when it can.
    /// Always `.enabled` in integration tests.
    public func entitlementStatus() async -> DataBrokerProtectionEntitlementStatus {
        if runTypeProvider.runType == .integrationTests {
            return .enabled
        }
        do {
            guard featureFlagger.isEntitlementCheckErrorHandlingOn else {
                return try await subscriptionManager.isFeatureEnabled(.dataBrokerProtection) ? .enabled : .disabled
            }
            let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
            return tokenContainer.decodedAccessToken.hasEntitlement(.dataBrokerProtection) ? .enabled : .disabled
        } catch {
            Logger.dataBrokerProtection.error("Failed to read the current token for the PIR entitlement: \(error.localizedDescription, privacy: .public)")
            return .error(DataBrokerProtectionEntitlementErrorReason(error))
        }
    }
}

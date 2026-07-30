//
//  PIRDebugSubscriptionAuthManager.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import DataBrokerProtectionCore
import Networking
import Subscription

/// The auth environment a stored token was issued by. Must match the environment of the DBP
/// services being called: a `quackdev` token is rejected by production services and vice versa.
public enum PIRAuthEnvironment {
    case production
    case staging

    var oAuthEnvironment: OAuthEnvironment {
        switch self {
        case .production: return .production
        case .staging: return .staging
        }
    }

    /// The auth environment matching a services endpoint, so one `--environment` selects both.
    public init(servicesEndpoint: PIRServicesEndpoint) {
        switch servicesEndpoint {
        case .staging: self = .staging
        case .production, .custom: self = .production
        }
    }
}

/// A ``DataBrokerProtectionAuthenticationManaging`` over a real subscription token container,
/// refreshing it as needed.
///
/// Unlike ``StaticTokenAuthenticationManager``, every `accessToken()` call goes through
/// `OAuthClient.getTokens(policy: .localValid)`, which refreshes via the stored refresh token when
/// the access token has expired. Access tokens are short-lived (minutes on staging), so a long run —
/// an opt-out waiting on email confirmation, say — outlives its initial token; a static token starts
/// returning 401 partway through, this does not.
public final class PIRDebugSubscriptionAuthManager: DataBrokerProtectionAuthenticationManaging {

    private let store: PIRDebugTokenStore
    private let oAuthClient: any OAuthClient

    public init(store: PIRDebugTokenStore = PIRDebugTokenStore(),
                environment: PIRAuthEnvironment,
                userAgent: String = PIRDebugUserAgent.toolLike) {
        self.store = store
        let authService = DefaultOAuthService(baseURL: environment.oAuthEnvironment.url,
                                             apiService: APIServiceFactory.makeAPIServiceForAuthV2(withUserAgent: userAgent))
        self.oAuthClient = DefaultOAuthClient(tokensStorage: store,
                                              authService: authService,
                                              refreshEventMapping: nil)
    }

    /// The stored container without contacting the network — for `auth status`, which reports what
    /// is on disk rather than provoking a refresh.
    public func storedTokenContainer() throws -> TokenContainer? {
        try store.getTokenContainer()
    }

    public var isUserAuthenticated: Bool {
        get async { await accessToken() != nil }
    }

    /// Free-trial eligibility is a purchase-flow concern the debug engine never exercises.
    public var isUserEligibleForFreeTrial: Bool { false }

    public func accessToken() async -> String? {
        do {
            return try await oAuthClient.getTokens(policy: .localValid).accessToken
        } catch {
            // Nothing imported yet, or the refresh token is expired/revoked. The services surface
            // this as a missing-auth-header failure, which the CLI reports with a re-import hint.
            return nil
        }
    }

    public func hasValidEntitlement() async throws -> Bool {
        guard let container = try? await oAuthClient.getTokens(policy: .localValid) else { return false }
        return container.decodedAccessToken.hasEntitlement(.dataBrokerProtection)
    }

    /// Mirrors `ServicesAuthHeaderBuilder` (internal to DataBrokerProtectionCore) and
    /// ``StaticTokenAuthenticationManager``: the services expect a lowercase `bearer` scheme.
    public func getAuthHeader() async -> String? {
        guard let token = await accessToken(), !token.isEmpty else { return nil }
        return "bearer \(token)"
    }
}

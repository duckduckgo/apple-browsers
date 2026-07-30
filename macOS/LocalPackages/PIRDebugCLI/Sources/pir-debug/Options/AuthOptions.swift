//
//  AuthOptions.swift
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

import ArgumentParser
import DataBrokerProtectionCore
import Foundation
import PIRDebugKit

/// Credentials for the email/captcha services (opt-out and the `email` commands). Rules fetch and
/// captcha-free scans need none.
///
/// Two sources, in precedence order:
///  1. `--auth-token` / `$PRIVACYPRO_STAGING_ACCESS_TOKEN_V2` — a bare access token, used verbatim
///     and never refreshed. Access tokens are short-lived, so a long run can outlive one.
///  2. The token container stored by `pir-debug auth import` — refreshed automatically for the life
///     of its refresh token, which is what long `--wait` runs need.
struct AuthOptions: ParsableArguments {

    static let envVariableName = "PRIVACYPRO_STAGING_ACCESS_TOKEN_V2"

    @Option(name: .long, help: "Access token used verbatim, no refresh. Falls back to $\(AuthOptions.envVariableName). Overrides the stored token.")
    var authToken: String?

    @Option(name: .long, help: "Stored token container to use (default: ~/.config/pir-debug/token.json). See 'pir-debug auth'.", completion: .file(extensions: ["json"]))
    var tokenFile: String?

    enum Source {
        /// A bare access token from `--auth-token` or the environment.
        case explicitToken
        /// A stored, self-refreshing token container.
        case storedContainer
        case none
    }

    /// `--auth-token`, else the environment variable, else `nil`.
    var explicitToken: String? {
        if let authToken, !authToken.isEmpty { return authToken }
        if let env = ProcessInfo.processInfo.environment[Self.envVariableName], !env.isEmpty { return env }
        return nil
    }

    var tokenStore: PIRDebugTokenStore {
        guard let tokenFile else { return PIRDebugTokenStore() }
        return PIRDebugTokenStore(url: URL(fileURLWithPath: (tokenFile as NSString).expandingTildeInPath))
    }

    var source: Source {
        if explicitToken != nil { return .explicitToken }
        if tokenStore.hasToken { return .storedContainer }
        return .none
    }

    var hasCredentials: Bool {
        source != .none
    }

    /// How the credentials were resolved, for a stderr progress line.
    var sourceDescription: String {
        switch source {
        case .explicitToken: return "--auth-token (no refresh)"
        case .storedContainer: return "stored token \(tokenStore.url.path) (auto-refreshing)"
        case .none: return "none"
        }
    }

    /// The error shown when a command needs credentials and has none.
    var missingCredentialsMessage: String {
        """
        No credentials. Either:
          • pir-debug auth import --file <token.json>   (from the app's "Export token for pir-debug" debug item)
          • --auth-token <jwt> / export \(Self.envVariableName)=<jwt>
        """
    }

    /// - Parameter servicesEndpoint: selects the auth environment for a stored container — a token
    ///   issued by staging auth is rejected by production services and vice versa.
    func authenticationManager(servicesEndpoint: PIRServicesEndpoint) -> DataBrokerProtectionAuthenticationManaging {
        switch source {
        case .explicitToken:
            return StaticTokenAuthenticationManager(token: explicitToken)
        case .storedContainer:
            return PIRDebugSubscriptionAuthManager(store: tokenStore,
                                                   environment: PIRAuthEnvironment(servicesEndpoint: servicesEndpoint))
        case .none:
            return StaticTokenAuthenticationManager(token: nil)
        }
    }
}

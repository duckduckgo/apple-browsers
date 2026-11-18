//
//  DebugModeAuthenticationManager.swift
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

#if DEBUG
import Foundation

/// Credentials belong only to one debug runner and never enter subscription storage.
public final class DebugModeAuthenticationManager: DataBrokerProtectionAuthenticationManaging {
    public enum ConfigurationError: Error {
        case invalidCredential, environmentMismatch, credentialLocked
    }

    private let lock = NSLock()
    private let fallback: DataBrokerProtectionAuthenticationManaging
    private let settings: DataBrokerProtectionSettings
    private var token: String?
    private var environment: String?
    private var frozen = false

    public init(fallback: DataBrokerProtectionAuthenticationManaging, settings: DataBrokerProtectionSettings) {
        self.fallback = fallback
        self.settings = settings
    }

    public func configure(token: String, environment: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard self.token == nil, !frozen else { throw ConfigurationError.credentialLocked }
        guard !token.isEmpty, token.utf8.count <= 65_536,
              !token.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            throw ConfigurationError.invalidCredential
        }
        guard Self.matches(environment: environment, settings: settings) else { throw ConfigurationError.environmentMismatch }
        self.token = token
        self.environment = environment
    }

    /// Called before the first scan is admitted, including when it uses the normal subscription.
    public func freeze() {
        lock.lock()
        defer { lock.unlock() }
        frozen = true
    }

    public var providedEnvironment: String? {
        lock.lock()
        defer { lock.unlock() }
        return environment
    }

    public var endpointURL: URL {
        var components = URLComponents(url: settings.endpointURL, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? settings.endpointURL
    }
    public var pirEnvironment: String { settings.selectedEnvironment.rawValue }

    private func credential() -> (configured: Bool, token: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard let environment else { return (false, nil) }
        // Fail closed if someone changes the debug menu's environment during a run.
        return (true, Self.matches(environment: environment, settings: settings) ? token : nil)
    }

    private static func matches(environment: String, settings: DataBrokerProtectionSettings) -> Bool {
        guard environment == settings.selectedEnvironment.rawValue else { return false }
        let url = settings.endpointURL
        let host = environment == "production" ? "dbp.duckduckgo.com" : "dbp-staging.duckduckgo.com"
        return url.scheme == "https" && url.host == host && url.port == nil && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }

    public var isUserAuthenticated: Bool {
        get async {
            let credential = credential()
            if credential.configured { return credential.token != nil }
            return await fallback.isUserAuthenticated
        }
    }

    public var isUserEligibleForFreeTrial: Bool { fallback.isUserEligibleForFreeTrial }

    public func accessToken() async -> String? {
        let credential = credential()
        if credential.configured { return credential.token }
        return await fallback.accessToken()
    }

    public func hasValidEntitlement() async throws -> Bool {
        // Injection proves possession only; it does not assert a backend entitlement.
        if credential().configured { return false }
        return try await fallback.hasValidEntitlement()
    }

    public func getAuthHeader() async -> String? {
        let credential = credential()
        if credential.configured { return ServicesAuthHeaderBuilder().getAuthHeader(credential.token) }
        return await fallback.getAuthHeader()
    }
}
#endif

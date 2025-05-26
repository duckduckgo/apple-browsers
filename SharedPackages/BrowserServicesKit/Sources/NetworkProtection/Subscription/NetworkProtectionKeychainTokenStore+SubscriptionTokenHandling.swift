//
//  NetworkProtectionKeychainTokenStore+SubscriptionTokenHandling.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Common
import os.log

extension NetworkProtectionKeychainTokenStore: SubscriptionTokenHandling {

    public func getToken() async throws -> String {
        Logger.networkProtection.debug("[NetworkProtectionKeychainTokenStore+SubscriptionTokenHandling] Getting token")
        guard let token = try await fetchToken() else { // Warning in macOS, will be removed alongside AuthV1
            throw NetworkProtectionError.noAuthTokenFound
        }
        return token
    }

    public func removeToken() async throws {
        Logger.networkProtection.debug("[NetworkProtectionKeychainTokenStore+SubscriptionTokenHandling] Removing token")
        try deleteToken()
    }

    public func refreshToken() async throws {
        // Unused in Auth V1
        assertionFailure("refreshToken() should not be called")
    }

    public func adoptToken(_ someKindOfToken: Any) async throws {
        Logger.networkProtection.debug("[NetworkProtectionKeychainTokenStore+SubscriptionTokenHandling] Adopting token")
        guard let token = someKindOfToken as? String else {
            throw NetworkProtectionError.invalidAuthToken
        }
        try store(token)
    }
}

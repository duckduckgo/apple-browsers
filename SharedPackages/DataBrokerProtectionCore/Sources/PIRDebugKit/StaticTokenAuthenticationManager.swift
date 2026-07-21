//
//  StaticTokenAuthenticationManager.swift
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

/// A `DataBrokerProtectionAuthenticationManaging` backed by a fixed access token (or none).
///
/// Scans without captcha need no token; email/captcha services during opt-out require one.
/// `hasValidEntitlement()` is `true` iff a token is present.
public struct StaticTokenAuthenticationManager: DataBrokerProtectionAuthenticationManaging {

    private let token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public var isUserAuthenticated: Bool {
        get async { token != nil }
    }

    public var isUserEligibleForFreeTrial: Bool { false }

    public func accessToken() async -> String? {
        token
    }

    public func hasValidEntitlement() async throws -> Bool {
        token != nil
    }

    public func getAuthHeader() async -> String? {
        guard let token else { return nil }
        return "bearer \(token)"
    }
}

//
//  VPNAuthTokenBuilder.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Networking
import Common

public struct VPNAuthTokenBuilder {

    static let tokenPrefix = "ddg:"

    public static func getVPNAuthToken(from tokenProvider: any SubscriptionTokenHandling) async throws -> String {
        let token = try await tokenProvider.getToken()
        return getVPNAuthToken(from: token)
    }

    public static func getVPNAuthToken(from originalToken: String) -> String{
        if originalToken.hasPrefix(tokenPrefix) {
            // In AuthV1 adding the token prefix is managed by the classes storing the token, in AuthV2 the token is stored as the original TokenContainer and the prefix is added by this builder
            return originalToken
        }
        return tokenPrefix + originalToken
    }
}

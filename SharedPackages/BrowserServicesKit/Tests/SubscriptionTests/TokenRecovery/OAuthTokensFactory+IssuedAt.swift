//
//  OAuthTokensFactory+IssuedAt.swift
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
import JWTKit
@_spi(Testing) @testable import Networking

extension OAuthTokensFactory {

    /// Builds a valid container whose access token was issued at `accessTokenIssuedAt`.
    /// - Parameters:
    ///   - accessToken: The encoded access token string.
    ///   - refreshToken: The encoded refresh token string.
    ///   - accessTokenIssuedAt: The access token's `iat`.
    static func makeTokenContainer(accessToken: String = "accessToken",
                                   refreshToken: String = "refreshToken",
                                   accessTokenIssuedAt: Date) -> TokenContainer {
        let base = makeTokenContainer(accessToken: accessToken, refreshToken: refreshToken)
        let decoded = base.decodedAccessToken
        let decodedAccessToken = JWTAccessToken(exp: decoded.exp,
                                                iat: IssuedAtClaim(value: accessTokenIssuedAt),
                                                sub: decoded.sub,
                                                aud: decoded.aud,
                                                iss: decoded.iss,
                                                jti: decoded.jti,
                                                scope: decoded.scope,
                                                api: decoded.api,
                                                email: decoded.email,
                                                entitlements: decoded.entitlements)
        return TokenContainer(accessToken: accessToken,
                              refreshToken: refreshToken,
                              decodedAccessToken: decodedAccessToken,
                              decodedRefreshToken: base.decodedRefreshToken)
    }
}

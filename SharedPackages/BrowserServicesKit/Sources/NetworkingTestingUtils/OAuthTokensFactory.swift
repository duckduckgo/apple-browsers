//
//  OAuthTokensFactory.swift
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
@testable import Networking
@testable import JWTKit

public struct OAuthTokensFactory {

    // Helper function to create an expired JWTAccessToken
    public static func makeExpiredAccessToken() -> JWTAccessToken {
        return JWTAccessToken(
            exp: ExpirationClaim(value: Date().addingTimeInterval(-3600)), // Expired 1 hour ago
            iat: IssuedAtClaim(value: Date().addingTimeInterval(-7200)),
            sub: SubjectClaim(value: "test-subject"),
            aud: AudienceClaim(value: ["test-audience"]),
            iss: IssuerClaim(value: "test-issuer"),
            jti: IDClaim(value: "test-id"),
            scope: "privacypro",
            api: "v2",
            email: "test@example.com",
            entitlements: []
        )
    }

    // Helper function to create a valid JWTAccessToken with customizable scope
    public static func makeAccessToken(scope: String, email: String = "test@example.com") -> JWTAccessToken {
        return JWTAccessToken(
            exp: ExpirationClaim(value: Date().addingTimeInterval(3600)), // 1 hour from now
            iat: IssuedAtClaim(value: Date()),
            sub: SubjectClaim(value: "test-subject"),
            aud: AudienceClaim(value: ["test-audience"]),
            iss: IssuerClaim(value: "test-issuer"),
            jti: IDClaim(value: "test-id"),
            scope: scope,
            api: "v2",
            email: email,
            entitlements: []
        )
    }

    public static func makeAccessToken(thatExpiresIn timeInterval: TimeInterval, scope: String, email: String = "test@example.com") -> JWTAccessToken {
        return JWTAccessToken(
            exp: ExpirationClaim(value: Date().addingTimeInterval(timeInterval)),
            iat: IssuedAtClaim(value: Date()),
            sub: SubjectClaim(value: "test-subject"),
            aud: AudienceClaim(value: ["test-audience"]),
            iss: IssuerClaim(value: "test-issuer"),
            jti: IDClaim(value: "test-id"),
            scope: scope,
            api: "v2",
            email: email,
            entitlements: []
        )
    }

    // Helper function to create a valid JWTRefreshToken with customizable scope
    public static func makeRefreshToken(scope: String) -> JWTRefreshToken {
        return JWTRefreshToken(
            exp: ExpirationClaim(value: Date().addingTimeInterval(3600)),
            iat: IssuedAtClaim(value: Date()),
            sub: SubjectClaim(value: "test-subject"),
            aud: AudienceClaim(value: ["test-audience"]),
            iss: IssuerClaim(value: "test-issuer"),
            jti: IDClaim(value: "test-id"),
            scope: scope,
            api: "v2"
        )
    }

    public static func makeExpiredRefreshToken(scope: String) -> JWTRefreshToken {
        return JWTRefreshToken(
            exp: ExpirationClaim(value: Date().daysAgo(40)),
            iat: IssuedAtClaim(value: Date().daysAgo(70)),
            sub: SubjectClaim(value: "test-subject"),
            aud: AudienceClaim(value: ["test-audience"]),
            iss: IssuerClaim(value: "test-issuer"),
            jti: IDClaim(value: "test-id"),
            scope: scope,
            api: "v2"
        )
    }

    public static func makeValidTokenContainer() -> TokenContainer {
        return TokenContainer(accessToken: "accessToken",
                               refreshToken: "refreshToken",
                               decodedAccessToken: OAuthTokensFactory.makeAccessToken(scope: "privacypro"),
                               decodedRefreshToken: OAuthTokensFactory.makeRefreshToken(scope: "refresh"))
    }

    public static func makeTokenContainer(thatExpiresIn timeInterval: TimeInterval) -> TokenContainer {
        return TokenContainer(accessToken: "AccessTokenExpiringIn\(timeInterval)seconds",
                               refreshToken: "refreshToken",
                              decodedAccessToken: OAuthTokensFactory.makeAccessToken(thatExpiresIn: timeInterval, scope: "privacypro"),
                               decodedRefreshToken: OAuthTokensFactory.makeRefreshToken(scope: "refresh"))
    }

    public static func makeValidTokenContainerWithEntitlements() -> TokenContainer {
        return TokenContainer(accessToken: "accessToken",
                              refreshToken: "refreshToken",
                              decodedAccessToken: JWTAccessToken.mock,
                              decodedRefreshToken: JWTRefreshToken.mock)
    }

    public static func makeExpiredTokenContainer() -> TokenContainer {
        return TokenContainer(accessToken: "accessToken",
                               refreshToken: "refreshToken",
                               decodedAccessToken: OAuthTokensFactory.makeExpiredAccessToken(),
                               decodedRefreshToken: OAuthTokensFactory.makeRefreshToken(scope: "refresh"))
    }

    public static func makeExpiredOAuthTokenResponse() -> OAuthTokenResponse {
        return OAuthTokenResponse(accessToken: "eyJraWQiOiIzODJiNzQ5Yy1hNTc3LTRkOTMtOTU0My04NTI5MWZiYTM3MmEiLCJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiJxWHk2TlRjeEI2UkQ0UUtSU05RYkNSM3ZxYU1SQU1RM1Q1UzVtTWdOWWtCOVZTVnR5SHdlb1R4bzcxVG1DYkJKZG1GWmlhUDVWbFVRQnd5V1dYMGNGUjo3ZjM4MTljZi0xNTBmLTRjYjEtOGNjNy1iNDkyMThiMDA2ZTgiLCJzY29wZSI6InByaXZhY3lwcm8iLCJhdWQiOiJQcml2YWN5UHJvIiwic3ViIjoiZTM3NmQ4YzQtY2FhOS00ZmNkLThlODYtMTlhNmQ2M2VlMzcxIiwiZXhwIjoxNzMwMzAxNTcyLCJlbWFpbCI6bnVsbCwiaWF0IjoxNzMwMjg3MTcyLCJpc3MiOiJodHRwczovL3F1YWNrZGV2LmR1Y2tkdWNrZ28uY29tIiwiZW50aXRsZW1lbnRzIjpbXSwiYXBpIjoidjIifQ.wOYgz02TXPJjDcEsp-889Xe1zh6qJG0P1UNHUnFBBELmiWGa91VQpqdl41EOOW3aE89KGvrD8YphRoZKiA3nHg",
                                  refreshToken: "eyJraWQiOiIzODJiNzQ5Yy1hNTc3LTRkOTMtOTU0My04NTI5MWZiYTM3MmEiLCJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJhcGkiOiJ2MiIsImlzcyI6Imh0dHBzOi8vcXVhY2tkZXYuZHVja2R1Y2tnby5jb20iLCJleHAiOjE3MzI4NzkxNzIsInN1YiI6ImUzNzZkOGM0LWNhYTktNGZjZC04ZTg2LTE5YTZkNjNlZTM3MSIsImF1ZCI6IkF1dGgiLCJpYXQiOjE3MzAyODcxNzIsInNjb3BlIjoicmVmcmVzaCIsImp0aSI6InFYeTZOVGN4QjZSRDRRS1JTTlFiQ1IzdnFhTVJBTVEzVDVTNW1NZ05Za0I5VlNWdHlId2VvVHhvNzFUbUNiQkpkbUZaaWFQNVZsVVFCd3lXV1gwY0ZSOmU2ODkwMDE5LWJmMDUtNGQxZC04OGFhLThlM2UyMDdjOGNkOSJ9.OQaGCmDBbDMM5XIpyY-WCmCLkZxt5Obp4YAmtFP8CerBSRexbUUp6SNwGDjlvCF0-an2REBsrX92ZmQe5ewqyQ")
    }

    public static func makeValidOAuthTokenResponse() -> OAuthTokenResponse {
        return OAuthTokenResponse(accessToken: "**validaccesstoken**", refreshToken: "**validrefreshtoken**")
    }

    public static func makeDeadTokenContainer() -> TokenContainer {
        return TokenContainer(accessToken: "expiredAccessToken",
                               refreshToken: "expiredRefreshToken",
                               decodedAccessToken: OAuthTokensFactory.makeExpiredAccessToken(),
                              decodedRefreshToken: OAuthTokensFactory.makeExpiredRefreshToken(scope: "refresh"))
    }
}

public extension JWTAccessToken {

    static var mock: Self {
        let now = Date()
        return JWTAccessToken(exp: ExpirationClaim(value: now.addingTimeInterval(3600)),
                              iat: IssuedAtClaim(value: now),
                              sub: SubjectClaim(value: "test-subject"),
                              aud: AudienceClaim(value: ["PrivacyPro"]),
                              iss: IssuerClaim(value: "test-issuer"),
                              jti: IDClaim(value: "test-id"),
                              scope: "privacypro",
                              api: "v2",
                              email: nil,
                              entitlements: [EntitlementPayload(product: .networkProtection, name: "subscriber"),
                                             EntitlementPayload(product: .dataBrokerProtection, name: "subscriber"),
                                             EntitlementPayload(product: .identityTheftRestoration, name: "subscriber")])
    }
}

public extension JWTRefreshToken {

    static var mock: Self {
        let now = Date()
        return JWTRefreshToken(exp: ExpirationClaim(value: now.addingTimeInterval(3600)),
                               iat: IssuedAtClaim(value: now),
                               sub: SubjectClaim(value: "test-subject"),
                               aud: AudienceClaim(value: ["PrivacyPro"]),
                               iss: IssuerClaim(value: "test-issuer"),
                               jti: IDClaim(value: "test-id"),
                               scope: "privacypro",
                               api: "v2")
    }
}

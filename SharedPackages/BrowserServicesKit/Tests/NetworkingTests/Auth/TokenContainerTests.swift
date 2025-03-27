//
//  TokenContainerTests.swift
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

import XCTest
import JWTKit
@testable import Networking
import NetworkingTestingUtils

final class TokenContainerTests: XCTestCase {

    // Test expired access token
    func testExpiredAccessToken() {
        let token = OAuthTokensFactory.makeExpiredAccessToken()
        XCTAssertTrue(token.isExpired(), "Expected token to be expired.")
    }

    // Test invalid scope in access token
    func testAccessTokenInvalidScope() {
        let token = OAuthTokensFactory.makeAccessToken(scope: "invalid-scope")
        XCTAssertThrowsError(try token.verify(using: .hs256(key: "secret"))) { error in
            XCTAssertEqual(error as? TokenPayloadError, .invalidTokenScope, "Expected invalidTokenScope error.")
        }
    }

    // Test invalid scope in refresh token
    func testRefreshTokenInvalidScope() {
        let token = OAuthTokensFactory.makeRefreshToken(scope: "invalid-scope")
        XCTAssertThrowsError(try token.verify(using: .hs256(key: "secret"))) { error in
            XCTAssertEqual(error as? TokenPayloadError, .invalidTokenScope, "Expected invalidTokenScope error.")
        }
    }

    // Test valid scope in access token
    func testAccessTokenValidScope() {
        let token = OAuthTokensFactory.makeAccessToken(scope: "privacypro")
        XCTAssertNoThrow(try token.verify(using: .hs256(key: "secret")), "Expected no error for valid scope.")
    }

    // Test valid scope in refresh token
    func testRefreshTokenValidScope() {
        let token = OAuthTokensFactory.makeRefreshToken(scope: "refresh")
        XCTAssertNoThrow(try token.verify(using: .hs256(key: "secret")), "Expected no error for valid scope.")
    }

    // Test entitlements with multiple types, including unsupported
    func testSubscriptionEntitlements() {
        let entitlements = [
            EntitlementPayload(product: .networkProtection, name: "subscriber"),
            EntitlementPayload(product: .unknown, name: "subscriber")
        ]
        let token = JWTAccessToken(
            exp: ExpirationClaim(value: Date().addingTimeInterval(3600)),
            iat: IssuedAtClaim(value: Date()),
            sub: SubjectClaim(value: "test-subject"),
            aud: AudienceClaim(value: ["test-audience"]),
            iss: IssuerClaim(value: "test-issuer"),
            jti: IDClaim(value: "test-id"),
            scope: "privacypro",
            api: "v2",
            email: "test@example.com",
            entitlements: entitlements
        )

        XCTAssertEqual(token.subscriptionEntitlements, [.networkProtection, .unknown], "Expected mixed entitlements including unknown.")
        XCTAssertTrue(token.hasEntitlement(.networkProtection), "Expected entitlement for networkProtection.")
        XCTAssertFalse(token.hasEntitlement(.identityTheftRestoration), "Expected no entitlement for identityTheftRestoration.")
    }

    // Test equatability of TokenContainer with same tokens but different fields
    func testTokenContainerEquatabilitySameTokens() {
        let accessToken = "same-access-token"
        let refreshToken = "same-refresh-token"

        let container1 = TokenContainer(
            accessToken: accessToken,
            refreshToken: refreshToken,
            decodedAccessToken: OAuthTokensFactory.makeAccessToken(scope: "privacypro"),
            decodedRefreshToken: OAuthTokensFactory.makeRefreshToken(scope: "refresh")
        )

        let container2 = TokenContainer(
            accessToken: accessToken,
            refreshToken: refreshToken,
            decodedAccessToken: OAuthTokensFactory.makeAccessToken(scope: "privacypro"),
            decodedRefreshToken: OAuthTokensFactory.makeRefreshToken(scope: "refresh")
        )

        XCTAssertEqual(container1, container2, "Expected containers with identical tokens to be equal.")
    }

    // Test equatability of TokenContainer with same token values but different decoded content
    func testTokenContainerEquatabilityDifferentContent() {
        let accessToken = "same-access-token"
        let refreshToken = "same-refresh-token"

        let container1 = TokenContainer(
            accessToken: accessToken,
            refreshToken: refreshToken,
            decodedAccessToken: OAuthTokensFactory.makeAccessToken(scope: "privacypro"),
            decodedRefreshToken: OAuthTokensFactory.makeRefreshToken(scope: "refresh")
        )

        let modifiedAccessToken = OAuthTokensFactory.makeAccessToken(scope: "privacypro", email: "modified@example.com") // Changing a field in decoded token

        let container2 = TokenContainer(
            accessToken: accessToken,
            refreshToken: refreshToken,
            decodedAccessToken: modifiedAccessToken,
            decodedRefreshToken: OAuthTokensFactory.makeRefreshToken(scope: "refresh")
        )

        XCTAssertEqual(container1, container2, "Expected containers with identical tokens but different decoded content to be equal.")
    }

    func testEncodeDecodeData() throws {
        let container = OAuthTokensFactory.makeValidTokenContainer()
        let tokenContainer = try TokenContainer(with: container.data!)
        XCTAssertEqual(container, tokenContainer, "Expected decoded token container to be equal to original.")
        XCTAssertEqual(container.accessToken, tokenContainer.accessToken)
        XCTAssertEqual(container.refreshToken, tokenContainer.refreshToken)
        XCTAssertEqual(container.decodedAccessToken, tokenContainer.decodedAccessToken)
        XCTAssertEqual(container.decodedRefreshToken, tokenContainer.decodedRefreshToken)
    }
}

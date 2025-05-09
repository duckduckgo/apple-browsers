//
//  OAuthClientTests.swift
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
import NetworkingTestingUtils
@testable import Networking
import JWTKit

final class OAuthClientTests: XCTestCase {

    var oAuthClient: DefaultOAuthClient!
    var mockOAuthService: MockOAuthService!
    var tokenStorage: MockTokenStorage!
    var legacyTokenStorage: MockLegacyTokenStorage!

    override func setUp() async throws {
        mockOAuthService = MockOAuthService()
        tokenStorage = MockTokenStorage()
        legacyTokenStorage = MockLegacyTokenStorage()
        oAuthClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                         legacyTokenStorage: legacyTokenStorage,
                                         authService: mockOAuthService)
    }

    override func tearDown() async throws {
        mockOAuthService = nil
        oAuthClient = nil
        tokenStorage = nil
        legacyTokenStorage = nil
    }

    // MARK: -

    func testUserNotAuthenticated() async throws {
        let authenticated = await oAuthClient.isUserAuthenticated
        XCTAssertFalse(authenticated)
    }

    func testUserAuthenticated() async throws {
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())
        let authenticated = await oAuthClient.isUserAuthenticated
        XCTAssertTrue(authenticated)
    }

    func testCurrentTokenContainer() async throws {
        var currentToken = try await oAuthClient.currentTokenContainer()
        XCTAssertNil(currentToken)
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())
        currentToken = try await oAuthClient.currentTokenContainer()
        XCTAssertNotNil(currentToken)
    }

    // MARK: - Get tokens

    // MARK: Local

    func testGetToken_Local_Fail() async throws {
        let localContainer = try? await oAuthClient.getTokens(policy: .local)
        XCTAssertNil(localContainer)
    }

    func testGetToken_Local_Success() async throws {
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())

        let localContainer = try? await oAuthClient.getTokens(policy: .local)
        XCTAssertNotNil(localContainer)
        XCTAssertFalse(localContainer!.decodedAccessToken.isExpired())
    }

    func testGetToken_Local_SuccessExpired() async throws {
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        let localContainer = try? await oAuthClient.getTokens(policy: .local)
        XCTAssertNotNil(localContainer)
        XCTAssertTrue(localContainer!.decodedAccessToken.isExpired())
    }

    // MARK: Local Valid

    /// A valid local token exists
    func testGetToken_localValid_local() async throws {

        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())

        let localContainer = try await oAuthClient.getTokens(policy: .localValid)
        XCTAssertNotNil(localContainer.accessToken)
        XCTAssertNotNil(localContainer.refreshToken)
        XCTAssertNotNil(localContainer.decodedAccessToken)
        XCTAssertNotNil(localContainer.decodedRefreshToken)
        XCTAssertFalse(localContainer.decodedAccessToken.isExpired())
    }

    /// An expired local token exists and is refreshed successfully
    func testGetToken_localValid_refreshSuccess() async throws {

        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success( OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        await oAuthClient.setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainer())

        let localContainer = try await oAuthClient.getTokens(policy: .localValid)
        XCTAssertNotNil(localContainer.accessToken)
        XCTAssertNotNil(localContainer.refreshToken)
        XCTAssertNotNil(localContainer.decodedAccessToken)
        XCTAssertNotNil(localContainer.decodedRefreshToken)
        XCTAssertFalse(localContainer.decodedAccessToken.isExpired())
    }

    /// If a token expires in less that *Constants.tokenExpiryBufferInterval* then is treated as expired and refreshed
    func testGetToken_localValid_expiresIn5minutes_refreshSuccess() async throws {

        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: .seconds(25)))
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        await oAuthClient.setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainer())

        let localContainer = try await oAuthClient.getTokens(policy: .localValid)
        XCTAssertNotNil(localContainer.accessToken)
        XCTAssertNotNil(localContainer.refreshToken)
        XCTAssertNotNil(localContainer.decodedAccessToken)
        XCTAssertNotNil(localContainer.decodedRefreshToken)
        XCTAssertFalse(localContainer.decodedAccessToken.isExpired())
        XCTAssertTrue(localContainer.decodedAccessToken.exp.value.timeIntervalSinceNow > .minutes(10))
    }

    /// An expired local token exists but refresh fails
    func testGetToken_localValid_refreshFail() async throws {

        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        do {
            _ = try await oAuthClient.getTokens(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }

    // MARK: Force Refresh

    /// Local token is missing, refresh fails
    func testGetToken_localForceRefresh_missingLocal() async throws {
        do {
            _ = try await oAuthClient.getTokens(policy: .localForceRefresh)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? Networking.OAuthClientError, .missingTokenContainer)
        }
    }

    /// An expired local token exists and is refreshed successfully
    func testGetToken_localForceRefresh_success() async throws {

        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success( OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        await oAuthClient.setTestingDecodedTokenContainer(TokenContainer(accessToken: "accessToken",
                                                                         refreshToken: "refreshToken",
                                                                         decodedAccessToken: JWTAccessToken.mock,
                                                                         decodedRefreshToken: JWTRefreshToken.mock))

        let localContainer = try await oAuthClient.getTokens(policy: .localForceRefresh)
        XCTAssertNotNil(localContainer.accessToken)
        XCTAssertNotNil(localContainer.refreshToken)
        XCTAssertNotNil(localContainer.decodedAccessToken)
        XCTAssertNotNil(localContainer.decodedRefreshToken)
        XCTAssertFalse(localContainer.decodedAccessToken.isExpired())
    }

    func testGetToken_localForceRefresh_refreshFail() async throws {

        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        do {
            _ = try await oAuthClient.getTokens(policy: .localForceRefresh)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }

    // MARK: Create if needed

    func testGetToken_createIfNeeded_foundLocal() async throws {
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())

        let tokenContainer = try await oAuthClient.getTokens(policy: .createIfNeeded)
        XCTAssertNotNil(tokenContainer.accessToken)
        XCTAssertNotNil(tokenContainer.refreshToken)
        XCTAssertNotNil(tokenContainer.decodedAccessToken)
        XCTAssertNotNil(tokenContainer.decodedRefreshToken)
        XCTAssertFalse(tokenContainer.decodedAccessToken.isExpired())
    }

    func testGetToken_createIfNeeded_missingLocal_createSuccess() async throws {
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.createAccountResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())

        await oAuthClient.setTestingDecodedTokenContainer(TokenContainer(accessToken: "accessToken",
                                                                         refreshToken: "refreshToken",
                                                                         decodedAccessToken: JWTAccessToken.mock,
                                                                         decodedRefreshToken: JWTRefreshToken.mock))

        let tokenContainer = try await oAuthClient.getTokens(policy: .createIfNeeded)
        XCTAssertNotNil(tokenContainer.accessToken)
        XCTAssertNotNil(tokenContainer.refreshToken)
        XCTAssertNotNil(tokenContainer.decodedAccessToken)
        XCTAssertNotNil(tokenContainer.decodedRefreshToken)
        XCTAssertFalse(tokenContainer.decodedAccessToken.isExpired())
    }

    func testGetToken_createIfNeeded_missingLocal_createFail() async throws {
        mockOAuthService.authorizeResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))

        do {
            _ = try await oAuthClient.getTokens(policy: .createIfNeeded)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }

    func testGetToken_createIfNeeded_missingLocal_createFail2() async throws {
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.createAccountResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))

        do {
            _ = try await oAuthClient.getTokens(policy: .createIfNeeded)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }

    func testGetToken_createIfNeeded_missingLocal_createFail3() async throws {
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.createAccountResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))

        do {
            _ = try await oAuthClient.getTokens(policy: .createIfNeeded)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }
}

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
import Common
@testable import Networking
import JWTKit

extension OAuthClientRefreshEvent: Equatable {
    public static func == (lhs: OAuthClientRefreshEvent, rhs: OAuthClientRefreshEvent) -> Bool {
        switch (lhs, rhs) {
        case (.tokenRefreshStarted(_), .tokenRefreshStarted(_)),
             (.tokenRefreshRefreshingAccessToken(_), .tokenRefreshRefreshingAccessToken(_)),
             (.tokenRefreshRefreshedAccessToken(_), .tokenRefreshRefreshedAccessToken(_)),
             (.tokenRefreshFetchingJWKS(_), .tokenRefreshFetchingJWKS(_)),
             (.tokenRefreshFetchedJWKS(_), .tokenRefreshFetchedJWKS(_)),
             (.tokenRefreshVerifyingAccessToken(_), .tokenRefreshVerifyingAccessToken(_)),
             (.tokenRefreshVerifyingRefreshToken(_), .tokenRefreshVerifyingRefreshToken(_)),
             (.tokenRefreshSavingTokens(_), .tokenRefreshSavingTokens(_)),
             (.tokenRefreshSucceeded(_), .tokenRefreshSucceeded(_)),
             (.tokenRefreshFailed(_, _), .tokenRefreshFailed(_, _)):
            return true
        default:
            return false
        }
    }
}

class OAuthEventCapture {
    private(set) var capturedEvents: [OAuthClientRefreshEvent] = []

    var eventMapping: EventMapping<OAuthClientRefreshEvent> {
        EventMapping { [weak self] event, _, _, _ in
            self?.capturedEvents.append(event)
        }
    }

    func reset() {
        capturedEvents.removeAll()
    }
}

final class OAuthClientTests: XCTestCase {

    var oAuthClient: DefaultOAuthClient!
    var mockOAuthService: MockOAuthService!
    var tokenStorage: MockTokenStorage!
    var eventCapture: OAuthEventCapture!

    override func setUp() async throws {
        mockOAuthService = MockOAuthService()
        tokenStorage = MockTokenStorage()
        eventCapture = OAuthEventCapture()
        oAuthClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                         authService: mockOAuthService,
                                         refreshEventMapping: eventCapture.eventMapping)
    }

    override func tearDown() async throws {
        mockOAuthService = nil
        oAuthClient = nil
        tokenStorage = nil
        eventCapture = nil
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

    private func assertRefreshSuccessEvents() {
        let expectedEventSequence: [OAuthClientRefreshEvent] = [
            .tokenRefreshStarted(refreshID: ""),
            .tokenRefreshRefreshingAccessToken(refreshID: ""),
            .tokenRefreshRefreshedAccessToken(refreshID: ""),
            .tokenRefreshSavingTokens(refreshID: ""),
            .tokenRefreshSucceeded(refreshID: "")
        ]

        XCTAssertEqual(eventCapture.capturedEvents, expectedEventSequence)

        guard let firstEvent = eventCapture.capturedEvents.first,
              case .tokenRefreshStarted(let refreshID) = firstEvent else {
            XCTFail("First event should be tokenRefreshStarted")
            return
        }

        for event in eventCapture.capturedEvents {
            switch event {
            case .tokenRefreshStarted(let id),
                 .tokenRefreshRefreshingAccessToken(let id),
                 .tokenRefreshRefreshedAccessToken(let id),
                 .tokenRefreshFetchingJWKS(let id),
                 .tokenRefreshFetchedJWKS(let id),
                 .tokenRefreshVerifyingAccessToken(let id),
                 .tokenRefreshVerifyingRefreshToken(let id),
                 .tokenRefreshSavingTokens(let id),
                 .tokenRefreshSucceeded(let id):
                XCTAssertEqual(id, refreshID, "All events should have the same refreshID")
            case .tokenRefreshFailed:
                XCTFail("Should not have tokenRefreshFailed in successful refresh")
            }
        }
    }

    private func assertRefreshFailedEvents(validateError: (Error) -> Void) {
        XCTAssertTrue(eventCapture.capturedEvents.contains(.tokenRefreshStarted(refreshID: "")))
        XCTAssertTrue(eventCapture.capturedEvents.contains(.tokenRefreshRefreshingAccessToken(refreshID: "")))
        XCTAssertTrue(eventCapture.capturedEvents.contains(.tokenRefreshFailed(refreshID: "", error: OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))))
        XCTAssertFalse(eventCapture.capturedEvents.contains(.tokenRefreshSucceeded(refreshID: "")))

        guard let lastEvent = eventCapture.capturedEvents.last,
              case .tokenRefreshFailed(_, let error) = lastEvent else {
            XCTFail("Last event should be tokenRefreshFailed")
            return
        }

        validateError(error)
    }

    private func assertRefreshFailedEventsWithoutRefresh(validateError: (Error) -> Void) {
        XCTAssertTrue(eventCapture.capturedEvents.contains(.tokenRefreshStarted(refreshID: "")))
        XCTAssertFalse(eventCapture.capturedEvents.contains(.tokenRefreshRefreshingAccessToken(refreshID: "")))
        XCTAssertTrue(eventCapture.capturedEvents.contains(.tokenRefreshFailed(refreshID: "", error: OAuthClientError.missingTokenContainer)))
        XCTAssertFalse(eventCapture.capturedEvents.contains(.tokenRefreshSucceeded(refreshID: "")))

        guard let lastEvent = eventCapture.capturedEvents.last,
              case .tokenRefreshFailed(_, let error) = lastEvent else {
            XCTFail("Last event should be tokenRefreshFailed")
            return
        }

        validateError(error)
    }

    // MARK: Auth Code Exchange

    func testGetTokensWithAuthCodeSuccess() async throws {
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())

        let expectedContainer = OAuthTokensFactory.makeValidTokenContainer()
        await oAuthClient.setTestingDecodedTokenContainer(expectedContainer)

        let tokenContainer = try await oAuthClient.getTokens(authCode: "authCode", codeVerifier: "codeVerifier")
        XCTAssertEqual(tokenContainer, expectedContainer)
    }

    func testGetTokensWithAuthCodeFailure() async throws {
        mockOAuthService.getAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.badRequest))

        do {
            _ = try await oAuthClient.getTokens(authCode: "authCode", codeVerifier: "codeVerifier")
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.badRequest))
        }
    }

    func testGetTokensWithAuthCodeInvalidTokenRequestWithTokenStatus() async throws {
        let bodyError = OAuthRequest.BodyError(errorCode: .invalidTokenRequest, tokenStatus: .reused)
        let requestError = OAuthRequestError(from: bodyError)
        mockOAuthService.getAccessTokenResponse = .failure(OAuthServiceError.authAPIError(requestError))

        do {
            _ = try await oAuthClient.getTokens(authCode: "authCode", codeVerifier: "codeVerifier")
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .authAPIError(requestError))
        }
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
        assertRefreshSuccessEvents()
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
        assertRefreshSuccessEvents()
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

        assertRefreshFailedEvents { error in
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }

    func testGetToken_localValid_refreshFailInvalidTokenRequestWithTokenStatus() async throws {
        let bodyError = OAuthRequest.BodyError(errorCode: .invalidTokenRequest, tokenStatus: .reused)
        let requestError = OAuthRequestError(from: bodyError)
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthServiceError.authAPIError(requestError))
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        do {
            _ = try await oAuthClient.getTokens(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            let authClientError = error as? OAuthClientError
            XCTAssertEqual(authClientError, OAuthClientError.invalidTokenRequest(OAuthRequest.TokenStatus.reused))
            XCTAssertEqual(authClientError?.underlyingError as? OAuthRequest.TokenStatus, OAuthRequest.TokenStatus.reused)
        }

        assertRefreshFailedEvents { error in
            XCTAssertEqual(error as? OAuthClientError, .invalidTokenRequest(.reused))
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

        assertRefreshFailedEventsWithoutRefresh { error in
            XCTAssertEqual(error as? OAuthClientError, .missingTokenContainer)
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
        assertRefreshSuccessEvents()
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

        assertRefreshFailedEvents { error in
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }

    func testGetToken_localForceRefresh_unknownAccount() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        let bodyError = OAuthRequest.BodyError(errorCode: .unknownAccount, tokenStatus: nil)
        let requestError = OAuthRequestError(from: bodyError)
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthServiceError.authAPIError(requestError))
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        do {
            _ = try await oAuthClient.getTokens(policy: .localForceRefresh)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthClientError, .unknownAccount)
        }

        assertRefreshFailedEvents { error in
            XCTAssertEqual(error as? OAuthClientError, .unknownAccount)
        }
    }

    func testGetToken_localForceRefresh_concurrentCallsOnlyRefreshOnce() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        mockOAuthService.setRefreshAccessTokenDelay(100_000_000) // 0.1 seconds

        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await oAuthClient.setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainer())

        async let result1 = oAuthClient.getTokens(policy: .localForceRefresh)
        async let result2 = oAuthClient.getTokens(policy: .localForceRefresh)
        async let result3 = oAuthClient.getTokens(policy: .localForceRefresh)
        async let result4 = oAuthClient.getTokens(policy: .localForceRefresh)
        async let result5 = oAuthClient.getTokens(policy: .localForceRefresh)

        let results = try await [result1, result2, result3, result4, result5]

        for result in results {
            XCTAssertNotNil(result.accessToken)
            XCTAssertNotNil(result.refreshToken)
            XCTAssertFalse(result.decodedAccessToken.isExpired())
        }

        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1, "Expected only one refresh call for concurrent requests")
        assertRefreshSuccessEvents()
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

    // MARK: - Event Mapping

    func testEventMapping_successfulRefresh() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        await oAuthClient.setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainer())

        _ = try await oAuthClient.getTokens(policy: .localForceRefresh)
        assertRefreshSuccessEvents()
    }

    func testEventMapping_failedRefresh() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        do {
            _ = try await oAuthClient.getTokens(policy: .localForceRefresh)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
        assertRefreshFailedEvents { error in
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }
}

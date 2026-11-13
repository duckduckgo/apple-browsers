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
import Common
@_spi(Testing) @testable import Networking
import JWTKit

extension OAuthClientRefreshEvent: Equatable {
    public static func == (lhs: OAuthClientRefreshEvent, rhs: OAuthClientRefreshEvent) -> Bool {
        switch (lhs, rhs) {
        case (.tokenRefreshStarted, .tokenRefreshStarted),
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

final class OAuthEventCapture {
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
    var tokenRefresher: DefaultTokenRefresher!

    override func setUp() async throws {
        mockOAuthService = MockOAuthService()
        tokenStorage = MockTokenStorage()
        eventCapture = OAuthEventCapture()
        tokenRefresher = DefaultTokenRefresher(authService: mockOAuthService,
                                               clientID: "client",
                                               refreshEventMapping: eventCapture.eventMapping)
        oAuthClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                         authService: mockOAuthService,
                                         refreshEventMapping: eventCapture.eventMapping,
                                         tokenRefresher: tokenRefresher)
    }

    override func tearDown() async throws {
        mockOAuthService = nil
        oAuthClient = nil
        tokenRefresher = nil
        tokenStorage = nil
        eventCapture = nil
    }

    private func makeClient(storage: any AuthTokenStoring) -> DefaultOAuthClient {
        DefaultOAuthClient(tokensStorage: storage,
                           authService: mockOAuthService,
                           refreshEventMapping: eventCapture.eventMapping,
                           tokenRefresher: tokenRefresher)
    }

    private func makeAuthAPIError(_ code: OAuthRequest.BodyErrorCode, tokenStatus: OAuthRequest.TokenStatus? = nil) -> OAuthServiceError {
        .authAPIError(OAuthRequestError(from: OAuthRequest.BodyError(errorCode: code, tokenStatus: tokenStatus)))
    }

    private var startedTriggers: [TokenRefreshTrigger] {
        eventCapture.capturedEvents.compactMap {
            if case .tokenRefreshStarted(_, let trigger) = $0 { return trigger }
            return nil
        }
    }

    // MARK: - Authentication state

    func testIsUserAuthenticated_noTokenStored_isFalse() async throws {
        let authenticated = await oAuthClient.isUserAuthenticated
        XCTAssertFalse(authenticated)
    }

    func testIsUserAuthenticated_tokenStored_isTrue() async throws {
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())
        let authenticated = await oAuthClient.isUserAuthenticated
        XCTAssertTrue(authenticated)
    }

    func testIsUserAuthenticated_storageReadFails_isFalse() async throws {
        let storage = ConfigurableTokenStorage(stored: OAuthTokensFactory.makeValidTokenContainer())
        storage.readError = ConfigurableTokenStorage.readFailure

        let authenticated = await makeClient(storage: storage).isUserAuthenticated

        XCTAssertFalse(authenticated)
    }

    // MARK: - Current token container

    func testCurrentTokenContainer_noTokenStored_isNil() async throws {
        let current = try await oAuthClient.currentTokenContainer()
        XCTAssertNil(current)
    }

    func testCurrentTokenContainer_tokenStored_returnsIt() async throws {
        let stored = OAuthTokensFactory.makeValidTokenContainer()
        try tokenStorage.saveTokenContainer(stored)

        let current = try await oAuthClient.currentTokenContainer()

        XCTAssertEqual(current, stored)
    }

    func testCurrentTokenContainer_storageReadFails_rethrows() async throws {
        let storage = ConfigurableTokenStorage(stored: nil)
        storage.readError = ConfigurableTokenStorage.readFailure

        do {
            _ = try await makeClient(storage: storage).currentTokenContainer()
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.readFailure)
        }
    }

    // MARK: - Set current token container

    func testSetCurrentTokenContainer_storesIt() async throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        try await oAuthClient.setCurrentTokenContainer(tokenContainer)

        XCTAssertEqual(try tokenStorage.getTokenContainer(), tokenContainer)
    }

    func testSetCurrentTokenContainer_nil_removesTheStoredToken() async throws {
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())

        try await oAuthClient.setCurrentTokenContainer(nil)

        XCTAssertNil(try tokenStorage.getTokenContainer())
    }

    func testSetCurrentTokenContainer_storageWriteFails_rethrows() async throws {
        let storage = ConfigurableTokenStorage(stored: nil)
        storage.writeError = ConfigurableTokenStorage.writeFailure

        do {
            try await makeClient(storage: storage).setCurrentTokenContainer(OAuthTokensFactory.makeValidTokenContainer())
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.writeFailure)
        }
    }

    // MARK: - Adopt

    func testAdopt_storesTheTokenContainerWithoutRefreshing() async throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        try await oAuthClient.adopt(tokenContainer: tokenContainer)

        XCTAssertEqual(try tokenStorage.getTokenContainer(), tokenContainer)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
    }

    func testAdopt_storageWriteFails_rethrows() async throws {
        let storage = ConfigurableTokenStorage(stored: nil)
        storage.writeError = ConfigurableTokenStorage.writeFailure

        do {
            try await makeClient(storage: storage).adopt(tokenContainer: OAuthTokensFactory.makeValidTokenContainer())
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.writeFailure)
        }
    }

    // MARK: - Get tokens

    // MARK: Local

    func testGetTokens_local_noTokenStored_throwsMissingTokenContainer() async throws {
        do {
            _ = try await oAuthClient.getTokens(policy: .local)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthClientError, .missingTokenContainer)
        }
    }

    func testGetTokens_local_tokenStored_returnsItWithoutRefreshing() async throws {
        let stored = OAuthTokensFactory.makeValidTokenContainer()
        try tokenStorage.saveTokenContainer(stored)

        let result = try await oAuthClient.getTokens(policy: .local)

        XCTAssertEqual(result, stored)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
    }

    func testGetTokens_local_expiredToken_returnsItWithoutRefreshing() async throws {
        let stored = OAuthTokensFactory.makeExpiredTokenContainer()
        try tokenStorage.saveTokenContainer(stored)

        let result = try await oAuthClient.getTokens(policy: .local)

        XCTAssertEqual(result, stored)
        XCTAssertTrue(result.decodedAccessToken.isExpired())
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
    }

    func testGetTokens_local_storageReadFails_rethrows() async throws {
        let storage = ConfigurableTokenStorage(stored: nil)
        storage.readError = ConfigurableTokenStorage.readFailure

        do {
            _ = try await makeClient(storage: storage).getTokens(policy: .local)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.readFailure)
        }
    }

    private func assertRefreshSuccessEvents() {
        let expectedEventSequence: [OAuthClientRefreshEvent] = [
            .tokenRefreshStarted(refreshID: "", trigger: .client),
            .tokenRefreshRefreshingAccessToken(refreshID: ""),
            .tokenRefreshRefreshedAccessToken(refreshID: ""),
            .tokenRefreshSavingTokens(refreshID: ""),
            .tokenRefreshSucceeded(refreshID: "")
        ]

        XCTAssertEqual(eventCapture.capturedEvents, expectedEventSequence)

        guard let firstEvent = eventCapture.capturedEvents.first,
              case .tokenRefreshStarted(let refreshID, _) = firstEvent else {
            XCTFail("First event should be tokenRefreshStarted")
            return
        }

        for event in eventCapture.capturedEvents {
            switch event {
            case .tokenRefreshStarted(let id, _):
                XCTAssertEqual(id, refreshID, "All events should have the same refreshID")
            case .tokenRefreshRefreshingAccessToken(let id),
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
        XCTAssertTrue(eventCapture.capturedEvents.contains(.tokenRefreshStarted(refreshID: "", trigger: .client)))
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
        XCTAssertTrue(eventCapture.capturedEvents.contains(.tokenRefreshStarted(refreshID: "", trigger: .client)))
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

    func testGetTokensWithAuthCode_validCode_returnsTheDecodedTokens() async throws {
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())

        let expectedContainer = OAuthTokensFactory.makeValidTokenContainer()
        await tokenRefresher.setTestingDecodedTokenContainers([expectedContainer])

        let tokenContainer = try await oAuthClient.getTokens(authCode: "authCode", codeVerifier: "codeVerifier")
        XCTAssertEqual(tokenContainer, expectedContainer)
        XCTAssertEqual(mockOAuthService.getAccessTokenCodes, ["authCode"])
    }

    func testGetTokensWithAuthCode_serverError_rethrows() async throws {
        mockOAuthService.getAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.badRequest))

        do {
            _ = try await oAuthClient.getTokens(authCode: "authCode", codeVerifier: "codeVerifier")
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.badRequest))
        }
    }

    func testGetTokensWithAuthCode_invalidTokenRequestWithTokenStatus_rethrowsTheAPIError() async throws {
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

    // MARK: Verification codes

    func testGetVerificationCodes_returnsAVerifierAndItsSHA256Challenge() async throws {
        let codes = try await oAuthClient.getVerificationCodes()

        XCTAssertFalse(codes.codeVerifier.isEmpty)
        XCTAssertEqual(codes.codeChallenge, OAuthCodesGenerator.codeChallenge(codeVerifier: codes.codeVerifier))
        XCTAssertNil(codes.codeVerifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")), "The verifier must be URL safe")
    }

    func testGetVerificationCodes_eachCallReturnsANewVerifier() async throws {
        let first = try await oAuthClient.getVerificationCodes()
        let second = try await oAuthClient.getVerificationCodes()

        XCTAssertNotEqual(first.codeVerifier, second.codeVerifier)
    }

    // MARK: Local Valid

    func testGetTokens_localValid_validToken_returnsItWithoutRefreshing() async throws {
        let stored = OAuthTokensFactory.makeValidTokenContainer()
        try tokenStorage.saveTokenContainer(stored)

        let localContainer = try await oAuthClient.getTokens(policy: .localValid)

        XCTAssertEqual(localContainer, stored)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
        XCTAssertTrue(eventCapture.capturedEvents.isEmpty)
    }

    func testGetTokens_localValid_expiredToken_refreshesAndStoresTheNewToken() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success( OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let refreshed = OAuthTokensFactory.makeValidTokenContainer()
        await tokenRefresher.setTestingDecodedTokenContainers([refreshed])

        let localContainer = try await oAuthClient.getTokens(policy: .localValid)

        XCTAssertEqual(localContainer, refreshed)
        XCTAssertEqual(try tokenStorage.getTokenContainer(), refreshed)
        XCTAssertFalse(localContainer.decodedAccessToken.isExpired())
        assertRefreshSuccessEvents()
    }

    /// A token that expires within the expiry buffer is treated as expired and refreshed.
    func testGetTokens_localValid_tokenExpiringSoon_refreshesIt() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(thatExpiresIn: .seconds(25)))
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        await tokenRefresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

        let localContainer = try await oAuthClient.getTokens(policy: .localValid)

        XCTAssertFalse(localContainer.decodedAccessToken.isExpired())
        XCTAssertTrue(localContainer.decodedAccessToken.exp.value.timeIntervalSinceNow > .minutes(10))
        assertRefreshSuccessEvents()
    }

    func testGetTokens_localValid_refreshFails_throwsAndKeepsTheStoredToken() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        let stored = OAuthTokensFactory.makeExpiredTokenContainer()
        try tokenStorage.saveTokenContainer(stored)

        do {
            _ = try await oAuthClient.getTokens(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }

        XCTAssertEqual(try tokenStorage.getTokenContainer(), stored)
        assertRefreshFailedEvents { error in
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }

    func testGetTokens_localValid_refreshRejected_throwsInvalidTokenRequestWithTheTokenStatus() async throws {
        mockOAuthService.refreshAccessTokenResponse = .failure(makeAuthAPIError(.invalidTokenRequest, tokenStatus: .reused))
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

    func testGetTokens_localValid_refreshUnknownAccount_throwsUnknownAccount() async throws {
        mockOAuthService.refreshAccessTokenResponse = .failure(makeAuthAPIError(.unknownAccount))
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        do {
            _ = try await oAuthClient.getTokens(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthClientError, .unknownAccount)
        }
    }

    func testGetTokens_localValid_noTokenStored_throwsMissingTokenContainerWithoutRefreshing() async throws {
        do {
            _ = try await oAuthClient.getTokens(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthClientError, .missingTokenContainer)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
    }

    func testGetTokens_localValid_storageReadFails_rethrowsWithoutRefreshing() async throws {
        let storage = ConfigurableTokenStorage(stored: OAuthTokensFactory.makeExpiredTokenContainer())
        storage.readError = ConfigurableTokenStorage.readFailure

        do {
            _ = try await makeClient(storage: storage).getTokens(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.readFailure)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
    }

    // MARK: Force Refresh

    func testGetTokens_localForceRefresh_noTokenStored_throwsMissingTokenContainerAndReportsTheFailure() async throws {
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

    func testGetTokens_localForceRefresh_expiredToken_refreshesAndStoresTheNewToken() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success( OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let refreshed = TokenContainer(accessToken: "accessToken",
                                       refreshToken: "refreshToken",
                                       decodedAccessToken: JWTAccessToken.mock,
                                       decodedRefreshToken: JWTRefreshToken.mock)
        await tokenRefresher.setTestingDecodedTokenContainers([refreshed])

        let localContainer = try await oAuthClient.getTokens(policy: .localForceRefresh)

        XCTAssertEqual(localContainer, refreshed)
        XCTAssertEqual(try tokenStorage.getTokenContainer(), refreshed)
        XCTAssertFalse(localContainer.decodedAccessToken.isExpired())
        assertRefreshSuccessEvents()
    }

    func testGetTokens_localForceRefresh_validToken_stillRefreshes() async throws {
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        let stored = OAuthTokensFactory.makeValidTokenContainer()
        try tokenStorage.saveTokenContainer(stored)
        let refreshed = OAuthTokensFactory.makeTokenContainer(accessToken: "refreshedA", refreshToken: "refreshedR")
        await tokenRefresher.setTestingDecodedTokenContainers([refreshed])

        let result = try await oAuthClient.getTokens(policy: .localForceRefresh)

        XCTAssertEqual(result, refreshed)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenRequestedTokens, [stored.refreshToken])
    }

    func testGetTokens_localForceRefresh_refreshFails_throwsAndKeepsTheStoredToken() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        let stored = OAuthTokensFactory.makeExpiredTokenContainer()
        try tokenStorage.saveTokenContainer(stored)

        do {
            _ = try await oAuthClient.getTokens(policy: .localForceRefresh)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }

        XCTAssertEqual(try tokenStorage.getTokenContainer(), stored)
        assertRefreshFailedEvents { error in
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
    }

    func testGetTokens_localForceRefresh_refreshUnknownAccount_throwsUnknownAccount() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .failure(makeAuthAPIError(.unknownAccount))
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

    func testGetTokens_localForceRefresh_storageReadFails_rethrowsAndReportsTheFailureWithoutRefreshing() async throws {
        let storage = ConfigurableTokenStorage(stored: OAuthTokensFactory.makeExpiredTokenContainer())
        storage.readError = ConfigurableTokenStorage.readFailure

        do {
            _ = try await makeClient(storage: storage).getTokens(policy: .localForceRefresh)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.readFailure)
        }

        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
        XCTAssertEqual(eventCapture.capturedEvents, [.tokenRefreshStarted(refreshID: "", trigger: .client),
                                                     .tokenRefreshFailed(refreshID: "", error: ConfigurableTokenStorage.readFailure)])
    }

    func testGetTokens_localForceRefresh_concurrentCalls_refreshOnce() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        mockOAuthService.setRefreshAccessTokenDelay(100_000_000) // 0.1 seconds

        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await tokenRefresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

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

    // MARK: Trigger

    func testGetTokens_localForceRefresh_reportsTheGivenTrigger() async throws {
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await tokenRefresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

        _ = try await oAuthClient.getTokens(policy: .localForceRefresh, trigger: .backend)

        XCTAssertEqual(startedTriggers, [.backend])
    }

    func testGetTokens_localValid_expiredToken_reportsTheGivenTrigger() async throws {
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await tokenRefresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

        _ = try await oAuthClient.getTokens(policy: .localValid, trigger: .tokenAdoption)

        XCTAssertEqual(startedTriggers, [.tokenAdoption])
    }

    func testGetTokens_withoutTrigger_reportsTheClientTrigger() async throws {
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await tokenRefresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

        _ = try await oAuthClient.getTokens(policy: .localForceRefresh)

        XCTAssertEqual(startedTriggers, [.client])
    }

    // MARK: Create if needed

    func testGetTokens_createIfNeeded_validToken_returnsItWithoutCreatingAnAccount() async throws {
        let stored = OAuthTokensFactory.makeValidTokenContainer()
        try tokenStorage.saveTokenContainer(stored)

        let tokenContainer = try await oAuthClient.getTokens(policy: .createIfNeeded)

        XCTAssertEqual(tokenContainer, stored)
        XCTAssertEqual(mockOAuthService.authorizeCallCount, 0)
        XCTAssertEqual(mockOAuthService.createAccountCallCount, 0)
    }

    func testGetTokens_createIfNeeded_noTokenStored_createsAnAccountAndStoresIt() async throws {
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.createAccountResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        let created = TokenContainer(accessToken: "accessToken",
                                     refreshToken: "refreshToken",
                                     decodedAccessToken: JWTAccessToken.mock,
                                     decodedRefreshToken: JWTRefreshToken.mock)
        await tokenRefresher.setTestingDecodedTokenContainers([created])

        let tokenContainer = try await oAuthClient.getTokens(policy: .createIfNeeded)

        XCTAssertEqual(tokenContainer, created)
        XCTAssertEqual(try tokenStorage.getTokenContainer(), created)
        XCTAssertEqual(mockOAuthService.createAccountCallCount, 1)
        XCTAssertEqual(mockOAuthService.getAccessTokenCodes, ["auth_code"])
    }

    func testGetTokens_createIfNeeded_noTokenStored_authorizeFails_throwsAndStoresNothing() async throws {
        mockOAuthService.authorizeResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))

        do {
            _ = try await oAuthClient.getTokens(policy: .createIfNeeded)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
        XCTAssertNil(try tokenStorage.getTokenContainer())
    }

    func testGetTokens_createIfNeeded_noTokenStored_createAccountFails_throwsAndStoresNothing() async throws {
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.createAccountResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))

        do {
            _ = try await oAuthClient.getTokens(policy: .createIfNeeded)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
        XCTAssertNil(try tokenStorage.getTokenContainer())
    }

    func testGetTokens_createIfNeeded_noTokenStored_tokenExchangeFails_throwsAndStoresNothing() async throws {
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.createAccountResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))

        do {
            _ = try await oAuthClient.getTokens(policy: .createIfNeeded)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
        XCTAssertNil(try tokenStorage.getTokenContainer())
    }

    func testGetTokens_createIfNeeded_storageReadFails_throwsWithoutCreatingAnAccount() async throws {
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.createAccountResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        let storage = ConfigurableTokenStorage(stored: nil)
        storage.readError = ConfigurableTokenStorage.readFailure

        do {
            _ = try await makeClient(storage: storage).getTokens(policy: .createIfNeeded)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.readFailure)
        }
        XCTAssertEqual(mockOAuthService.authorizeCallCount, 0)
        XCTAssertEqual(mockOAuthService.createAccountCallCount, 0)
        XCTAssertNil(storage.stored)
    }

    func testGetTokens_createIfNeeded_expiredInvalidRefreshToken_usesCreateIfNeededTriggerThenCreatesAccount() async throws {
        mockOAuthService.refreshAccessTokenResponse = .failure(makeAuthAPIError(.invalidTokenRequest, tokenStatus: .reused))
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.createAccountResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await tokenRefresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

        let tokenContainer = try await oAuthClient.getTokens(policy: .createIfNeeded)

        XCTAssertFalse(tokenContainer.decodedAccessToken.isExpired())
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
        XCTAssertEqual(startedTriggers, [.createIfNeeded])
    }

    // MARK: - Decode

    func testDecode_decodesThroughTheTokenRefresher() async throws {
        let decoded = OAuthTokensFactory.makeValidTokenContainer()
        let client = DefaultOAuthClient(tokensStorage: tokenStorage,
                                        authService: mockOAuthService,
                                        refreshEventMapping: nil,
                                        tokenRefresher: StubTokenRefresher(refreshed: decoded))

        let result = try await client.decode(accessToken: "a", refreshToken: "r", refreshID: nil)

        XCTAssertEqual(result, decoded)
    }

    func testDecode_invalidTokens_rethrowsTheDecodingError() async throws {
        let decodeError = NSError(domain: "jwt", code: 1)
        let client = DefaultOAuthClient(tokensStorage: tokenStorage,
                                        authService: mockOAuthService,
                                        refreshEventMapping: nil,
                                        tokenRefresher: StubTokenRefresher(refreshed: OAuthTokensFactory.makeValidTokenContainer(),
                                                                           decodeError: decodeError))

        do {
            _ = try await client.decode(accessToken: "not a jwt", refreshToken: "not a jwt", refreshID: nil)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, decodeError)
        }
    }

    // MARK: - Activate

    func testActivate_validSignature_storesAndReturnsTheTokens() async throws {
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.loginWithSignatureResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        let activated = OAuthTokensFactory.makeValidTokenContainer()
        await tokenRefresher.setTestingDecodedTokenContainers([activated])

        let result = try await oAuthClient.activate(withPlatformSignature: "signature")

        XCTAssertEqual(result, activated)
        XCTAssertEqual(try tokenStorage.getTokenContainer(), activated)
        XCTAssertEqual(mockOAuthService.loginSignatures, ["signature"])
        XCTAssertEqual(mockOAuthService.getAccessTokenCodes, ["auth_code"])
    }

    func testActivate_authorizeFails_throwsAndKeepsTheCurrentToken() async throws {
        let current = OAuthTokensFactory.makeValidTokenContainer()
        try tokenStorage.saveTokenContainer(current)
        mockOAuthService.authorizeResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))

        do {
            _ = try await oAuthClient.activate(withPlatformSignature: "signature")
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
        XCTAssertEqual(try tokenStorage.getTokenContainer(), current)
        XCTAssertTrue(mockOAuthService.loginSignatures.isEmpty)
    }

    func testActivate_signatureRejected_throwsAndKeepsTheCurrentToken() async throws {
        let current = OAuthTokensFactory.makeValidTokenContainer()
        try tokenStorage.saveTokenContainer(current)
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.loginWithSignatureResponse = .failure(makeAuthAPIError(.invalidAuthorizationRequest))

        do {
            _ = try await oAuthClient.activate(withPlatformSignature: "invalid signature")
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, makeAuthAPIError(.invalidAuthorizationRequest))
        }
        XCTAssertEqual(try tokenStorage.getTokenContainer(), current)
        XCTAssertTrue(mockOAuthService.getAccessTokenCodes.isEmpty)
    }

    func testActivate_tokenExchangeFails_throwsAndKeepsTheCurrentToken() async throws {
        let current = OAuthTokensFactory.makeValidTokenContainer()
        try tokenStorage.saveTokenContainer(current)
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.loginWithSignatureResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.gatewayTimeout))

        do {
            _ = try await oAuthClient.activate(withPlatformSignature: "signature")
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? OAuthServiceError, .invalidResponseCode(HTTPStatusCode.gatewayTimeout))
        }
        XCTAssertEqual(try tokenStorage.getTokenContainer(), current)
    }

    func testActivate_storageWriteFails_rethrows() async throws {
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.loginWithSignatureResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        await tokenRefresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])
        let storage = ConfigurableTokenStorage(stored: nil)
        storage.writeError = ConfigurableTokenStorage.writeFailure

        do {
            _ = try await makeClient(storage: storage).activate(withPlatformSignature: "signature")
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.writeFailure)
        }
    }

    // MARK: - Logout

    func testLogout_removesTheTokenAndInvalidatesItsAccessTokenOnTheServer() async throws {
        let stored = OAuthTokensFactory.makeValidTokenContainer()
        try tokenStorage.saveTokenContainer(stored)
        let serverLogout = expectation(description: "Server logout")
        mockOAuthService.onLogout = { _ in serverLogout.fulfill() }

        try await oAuthClient.logout()
        await fulfillment(of: [serverLogout], timeout: 2)

        XCTAssertNil(try tokenStorage.getTokenContainer())
        XCTAssertEqual(mockOAuthService.logoutAccessTokens, [stored.accessToken])
    }

    func testLogout_noTokenStored_doesNotCallTheServer() async throws {
        let serverLogout = expectation(description: "Server logout")
        serverLogout.isInverted = true
        mockOAuthService.onLogout = { _ in serverLogout.fulfill() }

        try await oAuthClient.logout()
        await fulfillment(of: [serverLogout], timeout: 0.3)

        XCTAssertTrue(mockOAuthService.logoutAccessTokens.isEmpty)
    }

    func testLogout_serverLogoutFails_stillSucceedsLocally() async throws {
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())
        mockOAuthService.logoutError = OAuthServiceError.invalidResponseCode(HTTPStatusCode.internalServerError)
        let serverLogout = expectation(description: "Server logout")
        mockOAuthService.onLogout = { _ in serverLogout.fulfill() }

        try await oAuthClient.logout()
        await fulfillment(of: [serverLogout], timeout: 2)

        XCTAssertNil(try tokenStorage.getTokenContainer())
    }

    func testLogout_removingTheTokenFails_rethrowsWithoutCallingTheServer() async throws {
        let storage = ConfigurableTokenStorage(stored: OAuthTokensFactory.makeValidTokenContainer())
        storage.writeError = ConfigurableTokenStorage.writeFailure
        let serverLogout = expectation(description: "Server logout")
        serverLogout.isInverted = true
        mockOAuthService.onLogout = { _ in serverLogout.fulfill() }

        do {
            try await makeClient(storage: storage).logout()
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.writeFailure)
        }
        await fulfillment(of: [serverLogout], timeout: 0.3)
    }

    // MARK: - Remove local account

    func testRemoveLocalAccount_removesTheTokenWithoutCallingTheServer() async throws {
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())
        let serverLogout = expectation(description: "Server logout")
        serverLogout.isInverted = true
        mockOAuthService.onLogout = { _ in serverLogout.fulfill() }

        try await oAuthClient.removeLocalAccount(includingBackup: false)
        await fulfillment(of: [serverLogout], timeout: 0.3)

        XCTAssertNil(try tokenStorage.getTokenContainer())
    }

    func testRemoveLocalAccount_storageWriteFails_rethrows() async throws {
        let storage = ConfigurableTokenStorage(stored: OAuthTokensFactory.makeValidTokenContainer())
        storage.writeError = ConfigurableTokenStorage.writeFailure

        do {
            try await makeClient(storage: storage).removeLocalAccount(includingBackup: false)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as NSError, ConfigurableTokenStorage.writeFailure)
        }
    }

    // MARK: - Event Mapping

    func testEventMapping_successfulRefresh() async throws {
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        await tokenRefresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

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

    // MARK: - Token refresher injection

    func testInit_withTokenRefresher_refreshesThroughIt() async throws {
        let refreshed = OAuthTokensFactory.makeValidTokenContainer()
        let stubRefresher = StubTokenRefresher(refreshed: refreshed)
        let client = DefaultOAuthClient(tokensStorage: tokenStorage,
                                        authService: mockOAuthService,
                                        refreshEventMapping: nil,
                                        tokenRefresher: stubRefresher)
        try tokenStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())

        let result = try await client.getTokens(policy: .localForceRefresh)

        XCTAssertEqual(result, refreshed)
        let refreshCount = await stubRefresher.refreshCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
    }
}

private actor StubTokenRefresher: TokenRefreshing {
    private let refreshed: TokenContainer
    private let decodeError: Error?
    private(set) var refreshCount = 0

    init(refreshed: TokenContainer, decodeError: Error? = nil) {
        self.refreshed = refreshed
        self.decodeError = decodeError
    }

    func decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> TokenContainer {
        if let decodeError { throw decodeError }
        return refreshed
    }

    func refresh(_ tokenContainer: TokenContainer, refreshID: String?) async throws -> TokenContainer {
        refreshCount += 1
        return refreshed
    }

    func fork(_ tokenContainer: TokenContainer, count: Int) async throws(TokenForkError) -> [TokenContainer] {
        Array(repeating: refreshed, count: count)
    }
}

/// A token storage whose reads and writes can be made to fail.
private final class ConfigurableTokenStorage: AuthTokenStoring {
    static let readFailure = NSError(domain: "keychain", code: 1)
    static let writeFailure = NSError(domain: "keychain", code: 2)

    private(set) var stored: TokenContainer?
    var readError: Error?
    var writeError: Error?

    init(stored: TokenContainer?) {
        self.stored = stored
    }

    func getTokenContainer() throws -> TokenContainer? {
        if let readError { throw readError }
        return stored
    }

    func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        if let writeError { throw writeError }
        stored = tokenContainer
    }
}

//
//  TokenRefresherTests.swift
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

import XCTest
import Common
@_spi(Testing) @testable import Networking
import JWTKit

final class TokenRefresherTests: XCTestCase {

    var mockOAuthService: MockOAuthService!
    var eventCapture: OAuthEventCapture!
    var refresher: DefaultTokenRefresher!

    override func setUp() async throws {
        mockOAuthService = MockOAuthService()
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        eventCapture = OAuthEventCapture()
        refresher = DefaultTokenRefresher(authService: mockOAuthService,
                                          clientID: "client",
                                          refreshEventMapping: eventCapture.eventMapping)
    }

    override func tearDown() async throws {
        mockOAuthService = nil
        eventCapture = nil
        refresher = nil
    }

    func testRefresh_success_returnsDecodedContainer() async throws {
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        let expected = OAuthTokensFactory.makeValidTokenContainer()
        await refresher.setTestingDecodedTokenContainers([expected])

        let result = try await refresher.refresh(OAuthTokensFactory.makeExpiredTokenContainer(), refreshID: "r1")

        XCTAssertEqual(result, expected)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
    }

    func testRefresh_invalidTokenRequest_mapsToOAuthClientError() async throws {
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthTokensFactory.makeAuthAPIError(.invalidTokenRequest, tokenStatus: .reused))

        do {
            _ = try await refresher.refresh(OAuthTokensFactory.makeExpiredTokenContainer(), refreshID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? OAuthClientError, .invalidTokenRequest(.reused))
        }
    }

    func testRefresh_unknownAccount_mapsToOAuthClientError() async throws {
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthTokensFactory.makeAuthAPIError(.unknownAccount, tokenStatus: nil))

        do {
            _ = try await refresher.refresh(OAuthTokensFactory.makeExpiredTokenContainer(), refreshID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? OAuthClientError, .unknownAccount)
        }
    }

    func testRefresh_withoutRefreshID_firesNoEvents() async throws {
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        await refresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

        _ = try await refresher.refresh(OAuthTokensFactory.makeExpiredTokenContainer(), refreshID: nil)

        XCTAssertTrue(eventCapture.capturedEvents.isEmpty)
    }

    func testRefresh_withRefreshID_firesRefreshAndDecodeSteps() async throws {
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())

        _ = try? await refresher.refresh(OAuthTokensFactory.makeExpiredTokenContainer(), refreshID: "r1")

        XCTAssertEqual(Array(eventCapture.capturedEvents.prefix(3)),
                       [.tokenRefreshRefreshingAccessToken(refreshID: "r1"),
                        .tokenRefreshRefreshedAccessToken(refreshID: "r1"),
                        .tokenRefreshFetchingJWKS(refreshID: "r1")])
    }

    // MARK: - Fork

    func testFork_twoPairs_spendsSameTokenTwice_andReturnsPrimaryLast() async throws {
        mockOAuthService.refreshAccessTokenResponses = [
            .success(OAuthTokenResponse(accessToken: "a1", refreshToken: "r1")),
            .success(OAuthTokenResponse(accessToken: "a2", refreshToken: "r2"))
        ]
        let backup = OAuthTokensFactory.makeTokenContainer(accessToken: "a1", refreshToken: "r1")
        let primary = OAuthTokensFactory.makeTokenContainer(accessToken: "a2", refreshToken: "r2")
        await refresher.setTestingDecodedTokenContainers([backup, primary])
        let source = OAuthTokensFactory.makeTokenContainer(accessToken: "a0", refreshToken: "r0")

        let result = try await refresher.fork(source, count: 2, refreshID: "r")

        XCTAssertEqual(result, [backup, primary])
        XCTAssertEqual(mockOAuthService.refreshAccessTokenRequestedTokens, ["r0", "r0"])
    }

    func testFork_onlyFirstCallReportsItsSteps() async throws {
        mockOAuthService.refreshAccessTokenResponses = [
            .success(OAuthTokensFactory.makeValidOAuthTokenResponse()),
            .failure(URLError(.timedOut))
        ]
        await refresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

        _ = try? await refresher.fork(OAuthTokensFactory.makeValidTokenContainer(), count: 2, refreshID: "r")

        XCTAssertEqual(eventCapture.capturedEvents, [.tokenRefreshRefreshingAccessToken(refreshID: "r"),
                                                     .tokenRefreshRefreshedAccessToken(refreshID: "r")])
        for event in eventCapture.capturedEvents {
            switch event {
            case .tokenRefreshRefreshingAccessToken(let refreshID), .tokenRefreshRefreshedAccessToken(let refreshID):
                XCTAssertEqual(refreshID, "r")
            default:
                XCTFail("Unexpected event \(event)")
            }
        }
    }

    func testFork_firstCallFails_reportsTheFailingStep() async throws {
        mockOAuthService.refreshAccessTokenResponses = [.failure(URLError(.timedOut))]

        _ = try? await refresher.fork(OAuthTokensFactory.makeValidTokenContainer(), count: 2, refreshID: "r")

        XCTAssertEqual(eventCapture.capturedEvents, [.tokenRefreshRefreshingAccessToken(refreshID: "r")])
    }

    func testFork_secondCallFails_throwsIncompleteWithFirstPair() async throws {
        mockOAuthService.refreshAccessTokenResponses = [
            .success(OAuthTokenResponse(accessToken: "a1", refreshToken: "r1")),
            .failure(URLError(.notConnectedToInternet))
        ]
        let first = OAuthTokensFactory.makeTokenContainer(accessToken: "a1", refreshToken: "r1")
        await refresher.setTestingDecodedTokenContainers([first])

        do {
            _ = try await refresher.fork(OAuthTokensFactory.makeValidTokenContainer(), count: 2, refreshID: nil)
            XCTFail("Expected error")
        } catch {
            guard case .incomplete(let minted, let underlying) = error else {
                return XCTFail("Expected incomplete, got \(error)")
            }
            XCTAssertEqual(minted, [first])
            XCTAssertEqual((underlying as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testFork_firstCallFails_throwsIncompleteWithNothingMinted() async throws {
        mockOAuthService.refreshAccessTokenResponses = [
            .failure(OAuthTokensFactory.makeAuthAPIError(.invalidTokenRequest, tokenStatus: .reused))
        ]

        do {
            _ = try await refresher.fork(OAuthTokensFactory.makeValidTokenContainer(), count: 2, refreshID: nil)
            XCTFail("Expected error")
        } catch TokenForkError.incomplete(let minted, let underlying) {
            XCTAssertTrue(minted.isEmpty)
            XCTAssertEqual(underlying as? OAuthClientError, .invalidTokenRequest(.reused))
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1, "A failed call stops the fork")
    }

    func testFork_threePairs_returnsThree() async throws {
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        await refresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeValidTokenContainer()])

        let result = try await refresher.fork(OAuthTokensFactory.makeValidTokenContainer(), count: 3, refreshID: nil)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 3)
    }
}

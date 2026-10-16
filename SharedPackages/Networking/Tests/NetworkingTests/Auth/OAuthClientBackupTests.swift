//
//  OAuthClientBackupTests.swift
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
import FoundationExtensions
@_spi(Testing) @testable import Networking
import JWTKit

final class OAuthClientBackupTests: XCTestCase {

    var mockOAuthService: MockOAuthService!
    var primaryStorage: MockTokenStorage!
    var backupStorage: MockTokenStorage!
    var refresher: DefaultTokenRefresher!
    var eventCapture: OAuthEventCapture!

    private let newBackup = OAuthTokensFactory.makeTokenContainer(accessToken: "backupA", refreshToken: "backupR")
    private let newPrimary = OAuthTokensFactory.makeTokenContainer(accessToken: "primaryA", refreshToken: "primaryR")

    override func setUp() async throws {
        mockOAuthService = MockOAuthService()
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        primaryStorage = MockTokenStorage()
        backupStorage = MockTokenStorage()
        eventCapture = OAuthEventCapture()
        refresher = DefaultTokenRefresher(authService: mockOAuthService, clientID: "c", refreshEventMapping: eventCapture.eventMapping)
    }

    override func tearDown() async throws {
        mockOAuthService = nil
        primaryStorage = nil
        backupStorage = nil
        refresher = nil
        eventCapture = nil
    }

    private func makeClient(primaryStorage: (any AuthTokenStoring)? = nil,
                            backupStorage: (any AuthTokenStoring)?,
                            tokenRefresher: (any TokenRefreshing)? = nil) -> DefaultOAuthClient {
        DefaultOAuthClient(tokensStorage: primaryStorage ?? self.primaryStorage,
                           authService: mockOAuthService,
                           refreshEventMapping: eventCapture.eventMapping,
                           tokenRefresher: tokenRefresher ?? refresher,
                           backupStorage: backupStorage)
    }

    // MARK: - Renewal

    func testRefresh_backupMissing_forksAndStoresBoth() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])

        let result = try await makeClient(backupStorage: backupStorage).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 2)
    }

    func testRefresh_backupFresh_refreshesOnce() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let existing = OAuthTokensFactory.makeTokenContainer(refreshToken: "existing", refreshTokenIssuedAt: Date().addingTimeInterval(-TimeInterval.days(1)))
        try backupStorage.saveTokenContainer(existing)
        await refresher.setTestingDecodedTokenContainers([newPrimary])

        _ = try await makeClient(backupStorage: backupStorage).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
        XCTAssertEqual(try backupStorage.getTokenContainer(), existing)
    }

    func testRefresh_noBackupStorage_neverForks() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary])

        _ = try await makeClient(backupStorage: nil).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
    }

    func testRefresh_backupUnreadable_refreshesOnce() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary])

        let result = try await makeClient(backupStorage: FailingTokenStorage(failOnRead: true)).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
    }

    // MARK: - Saving

    func testRefresh_backupSaveFails_refreshStillSucceeds() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])

        let result = try await makeClient(backupStorage: FailingTokenStorage(failOnSave: true)).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
    }

    func testRefresh_primarySaveFails_failsAndStoresNoBackup() async throws {
        let failingPrimary = FailingTokenStorage(stored: OAuthTokensFactory.makeExpiredTokenContainer(), failOnSave: true)
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])

        do {
            _ = try await makeClient(primaryStorage: failingPrimary, backupStorage: backupStorage).getTokens(policy: .localForceRefresh)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual((error as NSError).domain, "keychain")
        }
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    // MARK: - Fork failures

    func testRefresh_partialFork_usesMintedPairAsPrimary_noBackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.refreshAccessTokenResponses = [
            .success(OAuthTokensFactory.makeValidOAuthTokenResponse()),
            .failure(URLError(.timedOut))
        ]
        await refresher.setTestingDecodedTokenContainers([newBackup])

        let result = try await makeClient(backupStorage: backupStorage).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(result, newBackup)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newBackup)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRefresh_forkReturnsOnePair_failsWithInternalError() async throws {
        let expired = OAuthTokensFactory.makeExpiredTokenContainer()
        try primaryStorage.saveTokenContainer(expired)
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: SinglePairRefresher(pair: newPrimary))

        do {
            _ = try await client.getTokens(policy: .localForceRefresh)
            XCTFail("Expected error")
        } catch let error as OAuthClientError {
            guard case .internalError = error else { return XCTFail("Unexpected error \(error)") }
        }
        XCTAssertEqual(try primaryStorage.getTokenContainer(), expired)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRefresh_forkFirstCall11003_throwsInvalidTokenRequestAsToday() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthTokensFactory.makeAuthAPIError(.invalidTokenRequest, tokenStatus: .reused))

        do {
            _ = try await makeClient(backupStorage: backupStorage).getTokens(policy: .localForceRefresh)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? OAuthClientError, .invalidTokenRequest(.reused))
        }
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    // MARK: - Refresh reporting and single flight

    func testRefresh_withFork_reportsASingleRefresh() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])

        _ = try await makeClient(backupStorage: backupStorage).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(eventCapture.capturedEvents, [.tokenRefreshStarted(refreshID: "", trigger: .client),
                                                     .tokenRefreshRefreshingAccessToken(refreshID: ""),
                                                     .tokenRefreshRefreshedAccessToken(refreshID: ""),
                                                     .tokenRefreshSavingTokens(refreshID: ""),
                                                     .tokenRefreshSucceeded(refreshID: "")])
    }

    func testRefresh_partialFork_reportsASingleSuccessfulRefresh() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.refreshAccessTokenResponses = [
            .success(OAuthTokensFactory.makeValidOAuthTokenResponse()),
            .failure(URLError(.timedOut))
        ]
        await refresher.setTestingDecodedTokenContainers([newBackup])

        _ = try await makeClient(backupStorage: backupStorage).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(eventCapture.capturedEvents, [.tokenRefreshStarted(refreshID: "", trigger: .client),
                                                     .tokenRefreshRefreshingAccessToken(refreshID: ""),
                                                     .tokenRefreshRefreshedAccessToken(refreshID: ""),
                                                     .tokenRefreshSavingTokens(refreshID: ""),
                                                     .tokenRefreshSucceeded(refreshID: "")])
    }

    func testRefresh_forkFirstCallFails_reportsTheFailingStep() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.refreshAccessTokenResponse = .failure(URLError(.notConnectedToInternet))

        _ = try? await makeClient(backupStorage: backupStorage).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(eventCapture.capturedEvents, [.tokenRefreshStarted(refreshID: "", trigger: .client),
                                                     .tokenRefreshRefreshingAccessToken(refreshID: ""),
                                                     .tokenRefreshFailed(refreshID: "", error: URLError(.notConnectedToInternet))])
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
    }

    func testRefresh_concurrentCalls_forkOnce() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.setRefreshAccessTokenDelay(100_000_000)
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])
        let client = makeClient(backupStorage: backupStorage)

        async let first = client.getTokens(policy: .localForceRefresh)
        async let second = client.getTokens(policy: .localForceRefresh)
        let results = try await [first, second]

        XCTAssertEqual(results, [newPrimary, newPrimary])
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 2)
    }

    // MARK: - Sign-out

    func testLogout_deletesBackupBeforePrimary() async throws {
        let log = StorageCallLog()
        let primary = RecordingTokenStorage(name: "primary", log: log, stored: OAuthTokensFactory.makeValidTokenContainer())
        let backup = RecordingTokenStorage(name: "backup", log: log, stored: OAuthTokensFactory.makeValidTokenContainer())
        mockOAuthService.logoutError = nil

        try await makeClient(primaryStorage: primary, backupStorage: backup).logout()

        XCTAssertNil(try backup.getTokenContainer())
        XCTAssertNil(try primary.getTokenContainer())
        XCTAssertEqual(log.deletions, ["backup", "primary"])
    }

    func testRemoveLocalAccount_keepsBackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())
        try backupStorage.saveTokenContainer(newBackup)

        try await makeClient(backupStorage: backupStorage).removeLocalAccount()

        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
    }
}

private final class StorageCallLog {
    var deletions: [String] = []
}

private final class RecordingTokenStorage: AuthTokenStoring {
    private let name: String
    private let log: StorageCallLog
    private var stored: TokenContainer?

    init(name: String, log: StorageCallLog, stored: TokenContainer?) {
        self.name = name
        self.log = log
        self.stored = stored
    }

    func getTokenContainer() throws -> TokenContainer? {
        stored
    }

    func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        if tokenContainer == nil {
            log.deletions.append(name)
        }
        stored = tokenContainer
    }
}

private final class FailingTokenStorage: AuthTokenStoring {
    private let stored: TokenContainer?
    private let failOnRead: Bool
    private let failOnSave: Bool

    init(stored: TokenContainer? = nil, failOnRead: Bool = false, failOnSave: Bool = false) {
        self.stored = stored
        self.failOnRead = failOnRead
        self.failOnSave = failOnSave
    }

    func getTokenContainer() throws -> TokenContainer? {
        if failOnRead { throw NSError(domain: "keychain", code: 1) }
        return stored
    }

    func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        if failOnSave { throw NSError(domain: "keychain", code: 2) }
    }
}

/// A refresher whose `fork` breaks its contract by returning a single pair whatever `count` is.
private final class SinglePairRefresher: TokenRefreshing, @unchecked Sendable {
    private let pair: TokenContainer

    init(pair: TokenContainer) {
        self.pair = pair
    }

    func decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> TokenContainer {
        pair
    }

    func refresh(_ tokenContainer: TokenContainer, refreshID: String?) async throws -> TokenContainer {
        pair
    }

    func fork(_ tokenContainer: TokenContainer, count: Int, refreshID: String?) async throws(TokenForkError) -> [TokenContainer] {
        [pair]
    }
}

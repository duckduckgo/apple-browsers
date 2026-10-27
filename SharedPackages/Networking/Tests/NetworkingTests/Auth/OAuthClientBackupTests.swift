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
    var userDefaults: UserDefaults!

    private let newBackup = OAuthTokensFactory.makeTokenContainer(accessToken: "backupA", refreshToken: "backupR")
    private let newPrimary = OAuthTokensFactory.makeTokenContainer(accessToken: "primaryA", refreshToken: "primaryR")

    override func setUp() async throws {
        mockOAuthService = MockOAuthService()
        mockOAuthService.getJWTSignersResponse = .success(JWTSigners())
        mockOAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        primaryStorage = MockTokenStorage()
        backupStorage = MockTokenStorage()
        eventCapture = OAuthEventCapture()
        userDefaults = UserDefaults(suiteName: "OAuthClientBackupTests.\(UUID().uuidString)")
        refresher = DefaultTokenRefresher(authService: mockOAuthService, clientID: "c", refreshEventMapping: eventCapture.eventMapping)
    }

    override func tearDown() async throws {
        mockOAuthService = nil
        primaryStorage = nil
        backupStorage = nil
        refresher = nil
        eventCapture = nil
        userDefaults = nil
    }

    private func makeClient(primaryStorage: (any AuthTokenStoring)? = nil,
                            backupStorage: (any AuthTokenStoring)?,
                            tokenRefresher: (any TokenRefreshing)? = nil) -> DefaultOAuthClient {
        DefaultOAuthClient(tokensStorage: primaryStorage ?? self.primaryStorage,
                           authService: mockOAuthService,
                           refreshEventMapping: eventCapture.eventMapping,
                           tokenRefresher: tokenRefresher ?? refresher,
                           backupStorage: backupStorage,
                           backupUserDefaults: userDefaults)
    }

    // MARK: - Renewal

    func testRefresh_backupMissing_storesThePrimaryThenRenewsTheBackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        let client = makeClient(backupStorage: backupStorage)

        let result = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 2)
    }

    func testRefresh_backupRenewal_doesNotDelayTheRefresh() async throws {
        let source = OAuthTokensFactory.makeExpiredTokenContainer()
        try primaryStorage.saveTokenContainer(source)
        let gated = GatedRenewalRefresher(primary: newPrimary, backup: newBackup)
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: gated)

        let result = try await client.getTokens(policy: .localForceRefresh)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertNil(try backupStorage.getTokenContainer())

        await gated.openGate()
        await client.waitForBackupRenewal()

        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
        let refreshedTokens = await gated.refreshedRefreshTokens
        XCTAssertEqual(refreshedTokens, [source.refreshToken, source.refreshToken])
    }

    func testRefresh_backupRenewalRunning_doesNotStartAnother() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let gated = GatedRenewalRefresher(primary: newPrimary, backup: newBackup)
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: gated)

        _ = try await client.getTokens(policy: .localForceRefresh)
        _ = try await client.getTokens(policy: .localForceRefresh)
        await gated.openGate()
        await client.waitForBackupRenewal()

        let renewalCalls = await gated.renewalCalls
        XCTAssertEqual(renewalCalls, 1)
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
    }

    func testRefresh_signOutDuringBackupRenewal_storesNoBackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let gated = GatedRenewalRefresher(primary: newPrimary, backup: newBackup)
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: gated)

        _ = try await client.getTokens(policy: .localForceRefresh)
        try await client.logout()
        await gated.openGate()
        await client.waitForBackupRenewal()

        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRefresh_anotherAccountStoredDuringBackupRenewal_storesNoBackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let otherAccount = OAuthTokensFactory.makeTokenContainer(refreshToken: "otherR", externalID: "other")
        let gated = GatedRenewalRefresher(primary: newPrimary, backup: newBackup)
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: gated)

        _ = try await client.getTokens(policy: .localForceRefresh)
        try primaryStorage.saveTokenContainer(otherAccount)
        await gated.openGate()
        await client.waitForBackupRenewal()

        XCTAssertNil(try backupStorage.getTokenContainer())
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
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        let client = makeClient(backupStorage: FailingTokenStorage(failOnSave: true))

        let result = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
    }

    func testRefresh_primarySaveFails_failsAndStoresNoBackup() async throws {
        let failingPrimary = FailingTokenStorage(stored: OAuthTokensFactory.makeExpiredTokenContainer(), failOnSave: true)
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        let client = makeClient(primaryStorage: failingPrimary, backupStorage: backupStorage)

        do {
            _ = try await client.getTokens(policy: .localForceRefresh)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual((error as NSError).domain, "keychain")
        }
        await client.waitForBackupRenewal()
        XCTAssertNil(try backupStorage.getTokenContainer())
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
    }

    // MARK: - Renewal failures

    func testRefresh_backupRenewalFails_keepsThePrimaryAndStoresNoBackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.refreshAccessTokenResponses = [
            .success(OAuthTokensFactory.makeValidOAuthTokenResponse()),
            .failure(URLError(.timedOut))
        ]
        await refresher.setTestingDecodedTokenContainers([newPrimary])
        let client = makeClient(backupStorage: backupStorage)

        let result = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRefresh_firstCall11003_throwsInvalidTokenRequestAsToday() async throws {
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

    func testRefresh_withBackupRenewal_reportsASingleRefresh() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        let client = makeClient(backupStorage: backupStorage)

        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(eventCapture.capturedEvents, [.tokenRefreshStarted(refreshID: "", trigger: .client),
                                                     .tokenRefreshRefreshingAccessToken(refreshID: ""),
                                                     .tokenRefreshRefreshedAccessToken(refreshID: ""),
                                                     .tokenRefreshSavingTokens(refreshID: ""),
                                                     .tokenRefreshSucceeded(refreshID: "")])
    }

    func testRefresh_failedBackupRenewal_reportsASingleSuccessfulRefresh() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.refreshAccessTokenResponses = [
            .success(OAuthTokensFactory.makeValidOAuthTokenResponse()),
            .failure(URLError(.timedOut))
        ]
        await refresher.setTestingDecodedTokenContainers([newPrimary])
        let client = makeClient(backupStorage: backupStorage)

        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(eventCapture.capturedEvents, [.tokenRefreshStarted(refreshID: "", trigger: .client),
                                                     .tokenRefreshRefreshingAccessToken(refreshID: ""),
                                                     .tokenRefreshRefreshedAccessToken(refreshID: ""),
                                                     .tokenRefreshSavingTokens(refreshID: ""),
                                                     .tokenRefreshSucceeded(refreshID: "")])
    }

    func testRefresh_firstCallFails_reportsTheFailingStep() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.refreshAccessTokenResponse = .failure(URLError(.notConnectedToInternet))

        _ = try? await makeClient(backupStorage: backupStorage).getTokens(policy: .localForceRefresh)

        XCTAssertEqual(eventCapture.capturedEvents, [.tokenRefreshStarted(refreshID: "", trigger: .client),
                                                     .tokenRefreshRefreshingAccessToken(refreshID: ""),
                                                     .tokenRefreshFailed(refreshID: "", error: URLError(.notConnectedToInternet))])
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
    }

    func testRefresh_concurrentCalls_refreshAndRenewOnce() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.setRefreshAccessTokenDelay(100_000_000)
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        let client = makeClient(backupStorage: backupStorage)

        async let first = client.getTokens(policy: .localForceRefresh)
        async let second = client.getTokens(policy: .localForceRefresh)
        let results = try await [first, second]
        await client.waitForBackupRenewal()

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

    func testLogout_recordsTheCutoff_soAnOlderBackupIsNeverRestored() async throws {
        let signOut = Date()
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "currentR", refreshTokenIssuedAt: signOut))
        let client = makeClient(backupStorage: backupStorage)

        try await client.logout()
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "staleR",
                                                                                     refreshTokenIssuedAt: signOut.addingTimeInterval(-60)))

        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .predatesSignOut)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
    }

    func testLogout_currentUnreadable_recordsTheCutoffAndDeletesTheBackupBeforeThrowing() async throws {
        let primary = ToggleFailingTokenStorage(stored: OAuthTokensFactory.makeValidTokenContainer())
        primary.failReads = true
        let backupIssuedAt = Date().addingTimeInterval(-60)
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", refreshTokenIssuedAt: backupIssuedAt))
        let client = makeClient(primaryStorage: primary, backupStorage: backupStorage)

        do {
            try await client.logout()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual((error as NSError).domain, "keychain")
        }
        XCTAssertNil(try backupStorage.getTokenContainer())

        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "staleR", refreshTokenIssuedAt: backupIssuedAt))
        primary.failReads = false
        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .predatesSignOut)
        }
    }

    // MARK: - Restore from backup

    func testRestore_success_storesNewPrimaryAndNewBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])

        let result = try await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: "test-subject")

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenRequestedTokens, ["storedBackupR", "storedBackupR"])
    }

    func testRestore_noBackupStorage_isUnavailable() async {
        do {
            _ = try await makeClient(backupStorage: nil).restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
    }

    func testRestore_rejectedBackup_throwsTheReasonWithoutRefreshing() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR", externalID: "other"))

        do {
            _ = try await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: "acct")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .accountMismatch)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
        XCTAssertNil(try primaryStorage.getTokenContainer())
    }

    func testRestore_terminalRefreshError_deletesBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthTokensFactory.makeAuthAPIError(.invalidTokenRequest, tokenStatus: .reused))

        do {
            _ = try await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? OAuthClientError, .invalidTokenRequest(.reused))
        }
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_unknownAccount_deletesBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        mockOAuthService.refreshAccessTokenResponse = .failure(OAuthTokensFactory.makeAuthAPIError(.unknownAccount, tokenStatus: nil))

        _ = try? await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: nil)

        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_transientRefreshError_keepsBackup() async throws {
        let stored = OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR")
        try backupStorage.saveTokenContainer(stored)
        mockOAuthService.refreshAccessTokenResponse = .failure(URLError(.notConnectedToInternet))

        do {
            _ = try await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertEqual(try backupStorage.getTokenContainer(), stored)
        XCTAssertNil(try primaryStorage.getTokenContainer())
    }

    func testRestore_partialFork_storesMintedPairAsPrimaryAndDeletesSpentBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        mockOAuthService.refreshAccessTokenResponses = [
            .success(OAuthTokensFactory.makeValidOAuthTokenResponse()),
            .failure(URLError(.timedOut))
        ]
        await refresher.setTestingDecodedTokenContainers([newPrimary])

        let result = try await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_primarySaveFails_throwsAndKeepsSpentBackupUntouched() async throws {
        let stored = OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR")
        try backupStorage.saveTokenContainer(stored)
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])

        do {
            _ = try await makeClient(primaryStorage: FailingTokenStorage(failOnSave: true), backupStorage: backupStorage)
                .restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual((error as NSError).domain, "keychain")
        }
        XCTAssertEqual(try backupStorage.getTokenContainer(), stored)
    }

    func testRestore_currentRemovedByAnotherProcessDuringFork_stillRestores() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "deadR"))
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let primary = primaryStorage!
        let stub = SideEffectForkRefresher(minted: [newBackup, newPrimary]) { try? primary.saveTokenContainer(nil) }

        let result = try await makeClient(backupStorage: backupStorage, tokenRefresher: stub).restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
    }

    func testRestore_explicitSignOutDuringFork_whoseBackupDeleteFails_storesNothing() async throws {
        let backupStorage = DeleteFailingTokenStorage(stored: OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let stub = SideEffectForkRefresher(minted: [newBackup, newPrimary]) { }
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: stub)
        stub.sideEffect = {
            try? await client.logout()
        }

        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .sessionChanged)
        }
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertEqual(backupStorage.stored?.refreshToken, "storedBackupR")
    }

    func testRestore_accountActivatedDuringFork_storesNothing() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let otherAccount = OAuthTokensFactory.makeTokenContainer(refreshToken: "otherR", externalID: "other")
        let stub = SideEffectForkRefresher(minted: [newBackup, newPrimary]) { }
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: stub)
        stub.sideEffect = { try? await client.adopt(tokenContainer: otherAccount) }

        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .sessionChanged)
        }
        XCTAssertEqual(try primaryStorage.getTokenContainer(), otherAccount)
    }

    func testRestore_currentUnreadableBeforeFork_rethrowsTheStorageErrorWithoutRefreshing() async throws {
        let primary = ToggleFailingTokenStorage(stored: nil)
        primary.failReads = true
        let stored = OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR")
        try backupStorage.saveTokenContainer(stored)

        do {
            _ = try await makeClient(primaryStorage: primary, backupStorage: backupStorage).restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertNil(error as? TokenBackupError)
            XCTAssertEqual((error as NSError).domain, "keychain")
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
        XCTAssertEqual(try backupStorage.getTokenContainer(), stored)
    }

    // MARK: - Account switches

    func testAdopt_anotherAccount_deletesTheBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "oldBackupR", externalID: "old-account"))
        let adopted = OAuthTokensFactory.makeTokenContainer(refreshToken: "adoptedR", externalID: "new-account")

        try await makeClient(backupStorage: backupStorage).adopt(tokenContainer: adopted)

        XCTAssertNil(try backupStorage.getTokenContainer())
        XCTAssertEqual(try primaryStorage.getTokenContainer(), adopted)
    }

    func testAdopt_sameAccount_keepsTheBackup() async throws {
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", externalID: "account")
        try backupStorage.saveTokenContainer(backup)

        try await makeClient(backupStorage: backupStorage).adopt(tokenContainer: OAuthTokensFactory.makeTokenContainer(refreshToken: "adoptedR", externalID: "account"))

        XCTAssertEqual(try backupStorage.getTokenContainer(), backup)
    }

    func testActivate_anotherAccount_deletesTheBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "oldBackupR", externalID: "old-account"))
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.loginWithSignatureResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        await refresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeTokenContainer(refreshToken: "activatedR", externalID: "new-account")])

        _ = try await makeClient(backupStorage: backupStorage).activate(withPlatformSignature: "signature")

        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testCreateIfNeeded_newAccount_deletesTheBackupOfAnotherAccount() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "oldBackupR", externalID: "old-account"))
        mockOAuthService.authorizeResponse = .success("auth_session_id")
        mockOAuthService.createAccountResponse = .success("auth_code")
        mockOAuthService.getAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        await refresher.setTestingDecodedTokenContainers([OAuthTokensFactory.makeTokenContainer(refreshToken: "createdR", externalID: "new-account")])

        _ = try await makeClient(backupStorage: backupStorage).getTokens(policy: .createIfNeeded)

        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_currentUnreadableAfterFork_storesNothing() async throws {
        let primary = ToggleFailingTokenStorage(stored: nil)
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let stub = SideEffectForkRefresher(minted: [newBackup, newPrimary]) { primary.failReads = true }

        do {
            _ = try await makeClient(primaryStorage: primary, backupStorage: backupStorage, tokenRefresher: stub)
                .restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .sessionChanged)
        }
        primary.failReads = false
        XCTAssertNil(try primary.getTokenContainer())
    }

    func testRestore_backupDeletedDuringFork_storesNothingAndThrowsSessionChanged() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let storage = backupStorage!
        let stub = SideEffectForkRefresher(minted: [newBackup, newPrimary]) { try? storage.saveTokenContainer(nil) }

        do {
            _ = try await makeClient(backupStorage: backupStorage, tokenRefresher: stub).restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .sessionChanged)
        }
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_primaryStoredDuringFork_isNotOverwritten() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let otherAccount = OAuthTokensFactory.makeTokenContainer(refreshToken: "otherAccountR", externalID: "other")
        let primary = primaryStorage!
        let stub = SideEffectForkRefresher(minted: [newBackup, newPrimary]) { try? primary.saveTokenContainer(otherAccount) }

        do {
            _ = try await makeClient(backupStorage: backupStorage, tokenRefresher: stub).restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .sessionChanged)
        }
        XCTAssertEqual(try primaryStorage.getTokenContainer(), otherAccount)
    }

    func testRestore_partialForkAfterSessionChange_storesNothing() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let storage = backupStorage!
        let stub = SideEffectForkRefresher(minted: [newPrimary], failAfterMinted: URLError(.timedOut)) { try? storage.saveTokenContainer(nil) }

        _ = try? await makeClient(backupStorage: backupStorage, tokenRefresher: stub).restoreFromBackup(expectedExternalID: nil)

        XCTAssertNil(try primaryStorage.getTokenContainer())
    }

    func testRestore_sameAccountAdoptedDuringFork_deletesTheSpentBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let sameAccount = OAuthTokensFactory.makeTokenContainer(refreshToken: "adoptedR")
        let stub = SideEffectForkRefresher(minted: [newBackup, newPrimary]) { }
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: stub)
        stub.sideEffect = { try? await client.adopt(tokenContainer: sameAccount) }

        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .sessionChanged)
        }
        XCTAssertEqual(try primaryStorage.getTokenContainer(), sameAccount)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_primaryStoredDuringPartialFork_deletesTheSpentBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let otherProcessToken = OAuthTokensFactory.makeTokenContainer(refreshToken: "otherProcessR")
        let primary = primaryStorage!
        let stub = SideEffectForkRefresher(minted: [newPrimary], failAfterMinted: URLError(.timedOut)) {
            try? primary.saveTokenContainer(otherProcessToken)
        }

        _ = try? await makeClient(backupStorage: backupStorage, tokenRefresher: stub).restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(try primaryStorage.getTokenContainer(), otherProcessToken)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_concurrentCalls_forkOnce() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        mockOAuthService.setRefreshAccessTokenDelay(100_000_000)
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])
        let client = makeClient(backupStorage: backupStorage)

        async let first = client.restoreFromBackup(expectedExternalID: nil)
        async let second = client.restoreFromBackup(expectedExternalID: nil)
        let results = try await [first, second]

        XCTAssertEqual(results, [newPrimary, newPrimary])
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 2)
    }
}

private final class SideEffectForkRefresher: TokenRefreshing, @unchecked Sendable {
    private let minted: [TokenContainer]
    private let failAfterMinted: Error?
    var sideEffect: () async -> Void

    init(minted: [TokenContainer], failAfterMinted: Error? = nil, sideEffect: @escaping () async -> Void) {
        self.minted = minted
        self.failAfterMinted = failAfterMinted
        self.sideEffect = sideEffect
    }

    func decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> TokenContainer {
        minted[0]
    }

    func refresh(_ tokenContainer: TokenContainer, refreshID: String?) async throws -> TokenContainer {
        minted[0]
    }

    func fork(_ tokenContainer: TokenContainer, count: Int, refreshID: String?) async throws(TokenForkError) -> [TokenContainer] {
        await sideEffect()
        if let failAfterMinted {
            throw .incomplete(minted: minted, underlying: failAfterMinted)
        }
        return minted
    }
}

/// Holds one token container; deleting it always fails.
private final class DeleteFailingTokenStorage: AuthTokenStoring {
    private(set) var stored: TokenContainer?

    init(stored: TokenContainer?) {
        self.stored = stored
    }

    func getTokenContainer() throws -> TokenContainer? {
        stored
    }

    func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        guard let tokenContainer else { throw NSError(domain: "keychain", code: 3) }
        stored = tokenContainer
    }
}

/// A `MockTokenStorage` whose reads can be made to fail.
private final class ToggleFailingTokenStorage: AuthTokenStoring {
    private var stored: TokenContainer?
    var failReads = false

    init(stored: TokenContainer?) {
        self.stored = stored
    }

    func getTokenContainer() throws -> TokenContainer? {
        if failReads { throw NSError(domain: "keychain", code: 4) }
        return stored
    }

    func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        stored = tokenContainer
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
/// Returns `primary` for a refresh that reports under a refresh ID, the user-facing one, and holds every other refresh,
/// the background backup renewal, until `openGate()` is called, then returns `backup`.
private actor GatedRenewalRefresher: TokenRefreshing {
    private let primary: TokenContainer
    private let backup: TokenContainer
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var refreshedRefreshTokens: [String] = []
    private(set) var renewalCalls = 0

    init(primary: TokenContainer, backup: TokenContainer) {
        self.primary = primary
        self.backup = backup
    }

    func decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> TokenContainer {
        primary
    }

    func refresh(_ tokenContainer: TokenContainer, refreshID: String?) async throws -> TokenContainer {
        refreshedRefreshTokens.append(tokenContainer.refreshToken)
        guard refreshID == nil else { return primary }
        renewalCalls += 1
        if !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        return backup
    }

    func fork(_ tokenContainer: TokenContainer, count: Int, refreshID: String?) async throws(TokenForkError) -> [TokenContainer] {
        []
    }

    func openGate() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

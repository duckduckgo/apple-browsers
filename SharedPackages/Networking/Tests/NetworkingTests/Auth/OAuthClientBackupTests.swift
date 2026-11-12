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
    var backupEventCapture: BackupEventCapture!
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
        backupEventCapture = BackupEventCapture()
        userDefaults = UserDefaults(suiteName: "OAuthClientBackupTests.\(UUID().uuidString)")
        refresher = DefaultTokenRefresher(authService: mockOAuthService, clientID: "c", refreshEventMapping: eventCapture.eventMapping)
    }

    override func tearDown() async throws {
        mockOAuthService = nil
        primaryStorage = nil
        backupStorage = nil
        refresher = nil
        eventCapture = nil
        backupEventCapture = nil
        userDefaults = nil
    }

    private func makeClient(primaryStorage: (any AuthTokenStoring)? = nil,
                            backupStorage: (any AuthTokenStoring)?,
                            isBackupEnabled: @escaping () -> Bool = { true },
                            tokenRefresher: (any TokenRefreshing)? = nil) -> DefaultOAuthClient {
        DefaultOAuthClient(tokensStorage: primaryStorage ?? self.primaryStorage,
                           authService: mockOAuthService,
                           refreshEventMapping: eventCapture.eventMapping,
                           tokenRefresher: tokenRefresher ?? refresher,
                           backupStorage: backupStorage,
                           isBackupEnabled: isBackupEnabled,
                           backupUserDefaults: userDefaults,
                           backupEventMapping: backupEventCapture.eventMapping)
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

    func testRefresh_signOutDuringTheRefresh_storesNeitherTheRefreshedTokensNorABackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let gated = GatedPrimaryRefresher(primary: newPrimary, backup: newBackup)
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: gated)

        let refresh = Task { try await client.getTokens(policy: .localForceRefresh) }
        await gated.waitUntilRefreshStarted()
        try await client.logout()
        await gated.openGate()

        do {
            _ = try await refresh.value
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? OAuthClientError, .missingTokenContainer)
        }
        await client.waitForBackupRenewal()
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertNil(try backupStorage.getTokenContainer())
        let renewalCalls = await gated.renewalCalls
        XCTAssertEqual(renewalCalls, 0)
    }

    func testRefresh_anotherAccountAdoptedDuringTheRefresh_returnsAndKeepsTheAdoptedTokens() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let adopted = OAuthTokensFactory.makeTokenContainer(refreshToken: "adoptedR", externalID: "adopted-account")
        let gated = GatedPrimaryRefresher(primary: newPrimary, backup: newBackup)
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: gated)

        let refresh = Task { try await client.getTokens(policy: .localForceRefresh) }
        await gated.waitUntilRefreshStarted()
        try await client.adopt(tokenContainer: adopted)
        await gated.openGate()

        let result = try await refresh.value
        await client.waitForBackupRenewal()

        XCTAssertEqual(result, adopted)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), adopted)
        XCTAssertNil(try backupStorage.getTokenContainer())
        let renewalCalls = await gated.renewalCalls
        XCTAssertEqual(renewalCalls, 0)
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

    // MARK: - Renewal reporting

    func testRefresh_backupRenewed_reportsRenewed() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        let client = makeClient(backupStorage: backupStorage)

        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(backupEventCapture.names, ["renewed"])
    }

    func testRefresh_backupRenewalRefreshFails_reportsTheFailure() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        mockOAuthService.refreshAccessTokenResponses = [
            .success(OAuthTokensFactory.makeValidOAuthTokenResponse()),
            .failure(URLError(.timedOut))
        ]
        await refresher.setTestingDecodedTokenContainers([newPrimary])
        let client = makeClient(backupStorage: backupStorage)

        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(backupEventCapture.names, ["renewal_failed"])
        XCTAssertEqual((backupEventCapture.renewalErrors.first as? URLError)?.code, .timedOut)
    }

    func testRefresh_backupRenewalSaveFails_reportsTheStorageError() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        let client = makeClient(backupStorage: FailingTokenStorage(failOnSave: true))

        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(backupEventCapture.names, ["storage_failed:renewal:write", "renewal_failed"])
        XCTAssertEqual((backupEventCapture.renewalErrors.first as? NSError)?.code, 2)
    }

    // MARK: - Storage failure reporting

    func testRefresh_backupReadFails_reportsARenewalReadFailure() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary])
        let client = makeClient(backupStorage: FailingTokenStorage(failOnRead: true))

        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(backupEventCapture.names, ["storage_failed:renewal:read"])
    }

    func testRestore_backupReadFails_reportsARestoreReadFailure() async throws {
        _ = try? await makeClient(backupStorage: FailingTokenStorage(failOnRead: true)).restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(backupEventCapture.names, ["storage_failed:restore:read"])
    }

    func testRestore_newBackupWriteFails_reportsARestoreWriteFailure() async throws {
        let backupStorage = FailingTokenStorage(stored: OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"), failOnSave: true)
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])

        let result = try await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(backupEventCapture.names, ["storage_failed:restore:write"])
    }

    func testRestore_rejectedBackupDeleteFails_reportsARestoreDeleteFailure() async throws {
        let expired = OAuthTokensFactory.makeTokenContainer(refreshToken: "expiredR", refreshTokenExpiresAt: Date().addingTimeInterval(-60))
        let backupStorage = DeleteFailingTokenStorage(stored: expired)

        _ = try? await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(backupEventCapture.names, ["storage_failed:restore:delete"])
    }

    func testLogout_backupDeleteFails_reportsASignOutDeleteFailure() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())
        let backupStorage = DeleteFailingTokenStorage(stored: newBackup)

        try? await makeClient(backupStorage: backupStorage).logout()

        XCTAssertEqual(backupEventCapture.names, ["storage_failed:sign_out:delete"])
    }

    func testRemoveLocalAccountIncludingBackup_deleteFails_reportsALocalSignOutDeleteFailure() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeValidTokenContainer())
        let backupStorage = DeleteFailingTokenStorage(stored: newBackup)

        try await makeClient(backupStorage: backupStorage).removeLocalAccount(includingBackup: true)

        XCTAssertEqual(backupEventCapture.names, ["storage_failed:local_sign_out:delete"])
        XCTAssertNil(try primaryStorage.getTokenContainer())
    }

    func testAdopt_anotherAccountsBackupDeleteFails_reportsASignInDeleteFailure() async throws {
        let backupStorage = DeleteFailingTokenStorage(stored: OAuthTokensFactory.makeTokenContainer(refreshToken: "oldR", externalID: "old-account"))
        let adopted = OAuthTokensFactory.makeTokenContainer(refreshToken: "adoptedR", externalID: "new-account")

        try await makeClient(backupStorage: backupStorage).adopt(tokenContainer: adopted)

        XCTAssertEqual(backupEventCapture.names, ["storage_failed:sign_in:delete"])
    }

    func testRefresh_signOutDuringBackupRenewal_reportsNothing() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let gated = GatedRenewalRefresher(primary: newPrimary, backup: newBackup)
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: gated)

        _ = try await client.getTokens(policy: .localForceRefresh)
        try await client.logout()
        await gated.openGate()
        await client.waitForBackupRenewal()

        XCTAssertEqual(backupEventCapture.names, [])
    }

    func testRefresh_backupFresh_reportsNothing() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let existing = OAuthTokensFactory.makeTokenContainer(refreshToken: "existing", refreshTokenIssuedAt: Date().addingTimeInterval(-TimeInterval.days(1)))
        try backupStorage.saveTokenContainer(existing)
        await refresher.setTestingDecodedTokenContainers([newPrimary])
        let client = makeClient(backupStorage: backupStorage)

        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(backupEventCapture.names, [])
    }

    func testRestore_success_reportsNoRenewal() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])

        _ = try await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: "test-subject")

        XCTAssertEqual(backupEventCapture.names, [])
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

        try await makeClient(backupStorage: backupStorage).removeLocalAccount(includingBackup: false)

        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
    }

    func testRemoveLocalAccount_includingBackup_deletesBoth_andNoLaterRestoreIsTried() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        let client = makeClient(backupStorage: backupStorage)
        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)

        try await client.removeLocalAccount(includingBackup: true)

        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertNil(try backupStorage.getTokenContainer())
        let refreshCalls = mockOAuthService.refreshAccessTokenCallCount
        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, refreshCalls)
    }

    func testRemoveLocalAccount_includingBackup_doesNotRecordASignOutCutoff() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        let client = makeClient(backupStorage: backupStorage)
        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()
        try await client.removeLocalAccount(includingBackup: true)

        let laterBackup = OAuthTokensFactory.makeTokenContainer(refreshToken: "laterBackupR", refreshTokenIssuedAt: Date().addingTimeInterval(-60))
        try backupStorage.saveTokenContainer(laterBackup)
        let restoredBackup = OAuthTokensFactory.makeTokenContainer(accessToken: "restoredBackupA", refreshToken: "restoredBackupR")
        let restoredPrimary = OAuthTokensFactory.makeTokenContainer(accessToken: "restoredPrimaryA", refreshToken: "restoredPrimaryR")
        await refresher.setTestingDecodedTokenContainers([restoredBackup, restoredPrimary])
        let result = try await client.restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(result, restoredPrimary)
    }

    func testRemoveLocalAccount_includingBackup_duringARestore_storesNothing() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let stub = SideEffectForkRefresher(minted: [newBackup, newPrimary]) { }
        let client = makeClient(backupStorage: backupStorage, tokenRefresher: stub)
        stub.sideEffect = {
            try? await client.removeLocalAccount(includingBackup: true)
        }

        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .sessionChanged)
        }
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertNil(try backupStorage.getTokenContainer())
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

    // MARK: - Backup disabled

    func testRefresh_backupDisabled_neverForks() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary])
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { false })

        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_backupDisabled_isUnavailableAndKeepsTheBackup() async throws {
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR")
        try backupStorage.saveTokenContainer(backup)

        do {
            _ = try await makeClient(backupStorage: backupStorage, isBackupEnabled: { false }).restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
        XCTAssertEqual(try backupStorage.getTokenContainer(), backup)
    }

    func testLogout_backupDisabled_deletesTheBackupAndRecordsTheCutoff_soItIsNeverRestoredOnceEnabled() async throws {
        let signOut = Date()
        let staleBackup = OAuthTokensFactory.makeTokenContainer(refreshToken: "staleR", refreshTokenIssuedAt: signOut.addingTimeInterval(-60))
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "currentR", refreshTokenIssuedAt: signOut))
        try backupStorage.saveTokenContainer(staleBackup)
        mockOAuthService.logoutError = nil

        try await makeClient(backupStorage: backupStorage, isBackupEnabled: { false }).logout()

        XCTAssertNil(try backupStorage.getTokenContainer())

        try backupStorage.saveTokenContainer(staleBackup)
        do {
            _ = try await makeClient(backupStorage: backupStorage).restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .predatesSignOut)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)
    }

    func testRestore_backupEnabledAfterTheClientWasCreated_restores() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        await refresher.setTestingDecodedTokenContainers([newBackup, newPrimary])
        var isEnabled = false
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { isEnabled })

        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }

        isEnabled = true
        let result = try await client.restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
    }

    func testRefresh_backupDisabledAfterTheClientWasCreated_neverForks() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary])
        var isEnabled = true
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { isEnabled })

        isEnabled = false
        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 1)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRefresh_backupDisabledDuringRenewal_storesNoBackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        let gated = GatedRenewalRefresher(primary: newPrimary, backup: newBackup)
        var isEnabled = true
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { isEnabled }, tokenRefresher: gated)

        _ = try await client.getTokens(policy: .localForceRefresh)
        isEnabled = false
        await gated.openGate()
        await client.waitForBackupRenewal()

        let renewalCalls = await gated.renewalCalls
        XCTAssertEqual(renewalCalls, 1)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_backupDisabledDuringFork_storesThePrimaryAndDeletesTheSpentBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        var isEnabled = true
        let stub = SideEffectForkRefresher(minted: [newBackup, newPrimary]) { }
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { isEnabled }, tokenRefresher: stub)
        stub.sideEffect = { isEnabled = false }

        let result = try await client.restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testAdopt_anotherAccount_backupDisabled_deletesTheBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "oldBackupR", externalID: "old-account"))
        let adopted = OAuthTokensFactory.makeTokenContainer(refreshToken: "adoptedR", externalID: "new-account")

        try await makeClient(backupStorage: backupStorage, isBackupEnabled: { false }).adopt(tokenContainer: adopted)

        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    // MARK: - Backup enabled, disabled and enabled again

    func testOnOffOn_signOutWhileOff_isNeverRestoredOnceBackOn() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        var isEnabled = true
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { isEnabled })
        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)

        isEnabled = false
        try await client.logout()

        isEnabled = true
        let refreshCalls = mockOAuthService.refreshAccessTokenCallCount
        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, refreshCalls)
        XCTAssertNil(try primaryStorage.getTokenContainer())
    }

    func testOnOffOn_stillSignedIn_keepsTheBackupWhileOffAndRestoresFromItOnceBackOn() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        var isEnabled = true
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { isEnabled })
        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        isEnabled = false
        try await client.removeLocalAccount(includingBackup: false)
        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)

        isEnabled = true
        let restoredBackup = OAuthTokensFactory.makeTokenContainer(accessToken: "restoredBackupA", refreshToken: "restoredBackupR")
        let restoredPrimary = OAuthTokensFactory.makeTokenContainer(accessToken: "restoredPrimaryA", refreshToken: "restoredPrimaryR")
        await refresher.setTestingDecodedTokenContainers([restoredBackup, restoredPrimary])
        let result = try await client.restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(result, restoredPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), restoredPrimary)
        XCTAssertEqual(try backupStorage.getTokenContainer(), restoredBackup)
    }

    func testOnOffOn_removeIncludingBackupWhileOff_deletesTheBackup_andNothingIsRestoredOnceBackOn() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        var isEnabled = true
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { isEnabled })
        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)

        isEnabled = false
        try await client.removeLocalAccount(includingBackup: true)
        XCTAssertNil(try backupStorage.getTokenContainer())

        isEnabled = true
        let refreshCalls = mockOAuthService.refreshAccessTokenCallCount
        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, refreshCalls)
    }

    func testOffOnOff_createsTheBackupOnlyWhileOnAndStopsRestoringFromItOnceOffAgain() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary])
        var isEnabled = false
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { isEnabled })
        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()
        XCTAssertNil(try backupStorage.getTokenContainer())

        isEnabled = true
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)

        isEnabled = false
        try await client.removeLocalAccount(includingBackup: false)
        let refreshCalls = mockOAuthService.refreshAccessTokenCallCount
        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, refreshCalls)
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
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

    func testRestore_undecodableBackup_throwsUndecodableDeletesIt_andTheNextRefreshRenewsIt() async throws {
        let backupStorage = UndecodableBackupStorage()
        let client = makeClient(backupStorage: backupStorage)

        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .undecodable)
        }
        XCTAssertEqual(try backupStorage.readTokenContainer(), .missing)
        XCTAssertEqual(mockOAuthService.refreshAccessTokenCallCount, 0)

        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        await refresher.setTestingDecodedTokenContainers([newPrimary, newBackup])
        _ = try await client.getTokens(policy: .localForceRefresh)
        await client.waitForBackupRenewal()

        XCTAssertEqual(try backupStorage.readTokenContainer(), .found(newBackup))
    }

    func testOffOn_undecodableBackupKeptWhileOff_isDeletedByTheFirstRestoreOnceOn() async throws {
        let backupStorage = UndecodableBackupStorage()
        var isEnabled = false
        let client = makeClient(backupStorage: backupStorage, isBackupEnabled: { isEnabled })

        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .unavailable)
        }
        XCTAssertEqual(try backupStorage.readTokenContainer(), .undecodable)

        isEnabled = true
        do {
            _ = try await client.restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? TokenBackupError, .undecodable)
        }
        XCTAssertEqual(try backupStorage.readTokenContainer(), .missing)
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

    func testRestore_forkReturnsOnePair_storesItAsPrimaryAndDeletesTheSpentBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let stub = SideEffectForkRefresher(minted: [newPrimary]) { }

        let result = try await makeClient(backupStorage: backupStorage, tokenRefresher: stub).restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertNil(try backupStorage.getTokenContainer())
    }

    func testRestore_forkReturnsThreePairs_storesTheLastAsPrimaryAndTheFirstAsBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR"))
        let extra = OAuthTokensFactory.makeTokenContainer(accessToken: "extraA", refreshToken: "extraR")
        let stub = SideEffectForkRefresher(minted: [newBackup, extra, newPrimary]) { }

        let result = try await makeClient(backupStorage: backupStorage, tokenRefresher: stub).restoreFromBackup(expectedExternalID: nil)

        XCTAssertEqual(result, newPrimary)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), newPrimary)
        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
    }

    func testRestore_forkReturnsNoPair_throwsAndKeepsTheBackup() async throws {
        let stored = OAuthTokensFactory.makeTokenContainer(refreshToken: "storedBackupR")
        try backupStorage.saveTokenContainer(stored)
        let stub = SideEffectForkRefresher(minted: []) { }

        do {
            _ = try await makeClient(backupStorage: backupStorage, tokenRefresher: stub).restoreFromBackup(expectedExternalID: nil)
            XCTFail("Expected error")
        } catch OAuthClientError.internalError {
            // Expected.
        }
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertEqual(try backupStorage.getTokenContainer(), stored)
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

    func testSetCurrentTokenContainer_anotherAccount_deletesTheBackup() async throws {
        try backupStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "oldBackupR", externalID: "old-account"))
        let stored = OAuthTokensFactory.makeTokenContainer(refreshToken: "storedR", externalID: "new-account")

        try await makeClient(backupStorage: backupStorage).setCurrentTokenContainer(stored)

        XCTAssertNil(try backupStorage.getTokenContainer())
        XCTAssertEqual(try primaryStorage.getTokenContainer(), stored)
    }

    func testSetCurrentTokenContainer_sameAccount_keepsTheBackup() async throws {
        try backupStorage.saveTokenContainer(newBackup)
        let stored = OAuthTokensFactory.makeTokenContainer(refreshToken: "storedR")

        try await makeClient(backupStorage: backupStorage).setCurrentTokenContainer(stored)

        XCTAssertEqual(try backupStorage.getTokenContainer(), newBackup)
        XCTAssertEqual(try primaryStorage.getTokenContainer(), stored)
    }

    func testSetCurrentTokenContainer_nil_keepsTheBackup() async throws {
        let backup = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR", externalID: "account")
        try backupStorage.saveTokenContainer(backup)
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(refreshToken: "primaryR", externalID: "account"))

        try await makeClient(backupStorage: backupStorage).setCurrentTokenContainer(nil)

        XCTAssertEqual(try backupStorage.getTokenContainer(), backup)
        XCTAssertNil(try primaryStorage.getTokenContainer())
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

    func fork(_ tokenContainer: TokenContainer, count: Int) async throws(TokenForkError) -> [TokenContainer] {
        await sideEffect()
        if let failAfterMinted {
            throw .incomplete(minted: minted, underlying: failAfterMinted)
        }
        return minted
    }
}

/// Records the backup events a client reports.
final class BackupEventCapture {
    private(set) var capturedEvents: [OAuthClientBackupEvent] = []

    var eventMapping: EventMapping<OAuthClientBackupEvent> {
        EventMapping { [weak self] event, _, _, _ in
            self?.capturedEvents.append(event)
        }
    }

    /// The captured events' names: `renewed`, `renewal_failed`, or `storage_failed:<action>:<operation>`.
    var names: [String] {
        capturedEvents.map {
            switch $0 {
            case .backupRenewed: "renewed"
            case .backupRenewalFailed: "renewal_failed"
            case .storageFailed(let action, let operation, _): "storage_failed:\(action.rawValue):\(operation.rawValue)"
            }
        }
    }

    /// The errors of the captured `.backupRenewalFailed` events.
    var renewalErrors: [Error] {
        capturedEvents.compactMap {
            if case .backupRenewalFailed(let error) = $0 { return error }
            return nil
        }
    }
}

/// Holds an item that can't be decoded until a token container is saved or the item is deleted.
private final class UndecodableBackupStorage: AuthTokenStoring, @unchecked Sendable {
    private var stored: TokenContainerReadResult = .undecodable

    func getTokenContainer() throws -> TokenContainer? {
        guard case .found(let tokenContainer) = stored else { return nil }
        return tokenContainer
    }

    func readTokenContainer() throws -> TokenContainerReadResult {
        stored
    }

    func saveTokenContainer(_ tokenContainer: TokenContainer?) throws {
        stored = tokenContainer.map(TokenContainerReadResult.found) ?? .missing
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
/// Holds the primary refresh until `openGate()` is called, and returns the backup from a renewal right away.
private actor GatedPrimaryRefresher: TokenRefreshing {
    private let primary: TokenContainer
    private let backup: TokenContainer
    private var gate: CheckedContinuation<Void, Never>?
    private var hasStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var renewalCalls = 0

    init(primary: TokenContainer, backup: TokenContainer) {
        self.primary = primary
        self.backup = backup
    }

    func decode(accessToken: String, refreshToken: String, refreshID: String?) async throws -> TokenContainer {
        primary
    }

    func refresh(_ tokenContainer: TokenContainer, refreshID: String?) async throws -> TokenContainer {
        guard refreshID != nil else {
            renewalCalls += 1
            return backup
        }
        hasStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        await withCheckedContinuation { gate = $0 }
        return primary
    }

    func fork(_ tokenContainer: TokenContainer, count: Int) async throws(TokenForkError) -> [TokenContainer] {
        []
    }

    /// Returns once the primary refresh is waiting at the gate.
    func waitUntilRefreshStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func openGate() {
        gate?.resume()
        gate = nil
    }
}

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

    func fork(_ tokenContainer: TokenContainer, count: Int) async throws(TokenForkError) -> [TokenContainer] {
        []
    }

    func openGate() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

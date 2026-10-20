//
//  SubscriptionManagerTests.swift
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
@testable import Subscription
@_spi(Testing) @testable import Networking
import SubscriptionTestingUtilities
@_spi(Testing) import PixelKit
@_spi(Testing) import WideEvent

class SubscriptionManagerTests: XCTestCase {

    struct Constants {
        static let tld = TLD()
    }

    var subscriptionManager: DefaultSubscriptionManager!
    var mockOAuthClient: MockOAuthClient!
    var mockSubscriptionEndpointService: SubscriptionEndpointServiceMock!
    var mockSubscriptionCachingService: SubscriptionCachingServiceMock!
    var mockStorePurchaseManager: StorePurchaseManagerMock!
    var mockAppStoreRestoreFlowV2: AppStoreRestoreFlowMock!
    fileprivate var mockPixelHandler: MockSubscriptionPixelHandler!
    var mockWideEvent: WideEventMock!
    var overrideTokenResponseInRecovery: Result<Networking.TokenContainer, Error>?
    var recoverySideEffect: (() -> Void)?

    override func setUp() {
        super.setUp()

        mockOAuthClient = MockOAuthClient()
        mockSubscriptionEndpointService = SubscriptionEndpointServiceMock()
        mockSubscriptionCachingService = SubscriptionCachingServiceMock()
        mockStorePurchaseManager = StorePurchaseManagerMock()
        mockAppStoreRestoreFlowV2 = AppStoreRestoreFlowMock()
        mockPixelHandler = MockSubscriptionPixelHandler()
        mockWideEvent = WideEventMock()
        let authV2RefreshInstrumentation = DefaultAuthV2TokenRefreshInstrumentation(wideEvent: mockWideEvent,
                                                                                    isFeatureEnabled: { true })
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        subscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionCachingService: mockSubscriptionCachingService,
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
            pixelHandler: mockPixelHandler,
            wideEvent: mockWideEvent,
            isAuthV2WideEventEnabled: { true },
            authV2TokenRefreshInstrumentation: authV2RefreshInstrumentation
        )

        let testRecovery = ClosureTokenRecovery { context in
            if let overrideTokenResponse = self.overrideTokenResponseInRecovery {
                self.mockOAuthClient.getTokensResponse = overrideTokenResponse
                switch overrideTokenResponse {
                case .success(let token):
                    self.mockOAuthClient.internalCurrentTokenContainer = token
                case .failure:
                    self.mockOAuthClient.internalCurrentTokenContainer = nil
                }
            }
            self.recoverySideEffect?()
            try await AppStoreTokenRecovery(purchasePlatform: self.subscriptionManager.currentEnvironment.purchasePlatform, restoreFlow: self.mockAppStoreRestoreFlowV2)
                .recover(context)
        }
        subscriptionManager.tokenRecoveryCoordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [testRecovery], missingTokenStrategies: [])
    }

    override func tearDown() {
        recoverySideEffect = nil
        subscriptionManager = nil
        mockOAuthClient = nil
        mockSubscriptionEndpointService = nil
        mockSubscriptionCachingService = nil
        mockStorePurchaseManager = nil
        mockPixelHandler = nil
        mockWideEvent = nil
        super.tearDown()
    }

    // MARK: - Token Retrieval Tests

    func testWhenLocalTokenStateHasTokenThenReturnsPresentWithoutRefreshing() {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        let tokenState = subscriptionManager.localTokenState()

        XCTAssertEqual(tokenState, .present)
        XCTAssertTrue(mockOAuthClient.getTokensTriggers.isEmpty)
    }

    func testWhenLocalTokenStateHasNoTokenThenReturnsMissingWithoutRefreshing() {
        mockOAuthClient.internalCurrentTokenContainer = nil

        let tokenState = subscriptionManager.localTokenState()

        XCTAssertEqual(tokenState, .missing)
        XCTAssertTrue(mockOAuthClient.getTokensTriggers.isEmpty)
    }

    func testWhenLocalTokenStateCannotBeReadThenReturnsReadErrorWithoutRefreshing() {
        mockOAuthClient.currentTokenContainerError = NSError(domain: "LocalTokenStore", code: 1)

        let tokenState = subscriptionManager.localTokenState()

        XCTAssertEqual(tokenState, .readError)
        XCTAssertTrue(mockOAuthClient.getTokensTriggers.isEmpty)
    }

    func testGetTokenContainer_Success() async throws {
        let expectedTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(expectedTokenContainer)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(result, expectedTokenContainer)
    }

    func testGetTokenContainer_MissingTokenContainer_NoPixels() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.missingTokenContainer)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            let managerError = error as? SubscriptionManagerError
            XCTAssertEqual(managerError, .noTokenAvailable)
            XCTAssertNil(managerError?.underlyingError)
        }

        XCTAssertTrue(mockPixelHandler.handledPixels.isEmpty)
        assertNoGetTokensErrorPixel()
    }

    func testGetTokenContainer_UnknownAccount_SendsGetTokensError() async throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer
        mockSubscriptionCachingService.cachedSubscription = SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            activeOffers: [DuckDuckGoSubscription.Offer(type: .trial)])
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.unknownAccount)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            let managerError = error as? SubscriptionManagerError
            XCTAssertEqual(managerError, .noTokenAvailable)
            XCTAssertNil(managerError?.underlyingError)
        }

        assertGetTokensErrorPixel(policy: .localValid)
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(.invalidRefreshToken))

        let automaticSignOut = try XCTUnwrap(automaticSignOutPixel())
        let automaticSignOutData = automaticSignOut.data
        let automaticSignOutError = automaticSignOut.error as NSError
        XCTAssertEqual(automaticSignOutError.domain, OAuthClientError.errorDomain)
        XCTAssertEqual(automaticSignOutError.code, OAuthClientError.unknownAccount.errorCode)
        XCTAssertNil(automaticSignOutError.userInfo[NSUnderlyingErrorKey])
        XCTAssertEqual(automaticSignOutData.recoveryOutcome, .notApplicable)
        XCTAssertEqual(automaticSignOutData.tokenCachePolicy, .localValid)
        XCTAssertEqual(automaticSignOutData.entitlementStateBefore, .present)
        XCTAssertEqual(automaticSignOutData.accessTokenTimeRemainingBefore, .lessThanOneHour)
        XCTAssertEqual(automaticSignOutData.refreshTokenTimeRemainingBefore, .lessThanOneHour)
        XCTAssertEqual(automaticSignOutData.refreshTokenAgeBefore, .lessThanOneHour)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionStatusBefore, .autoRenewable)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionTrialStatusBefore, .active)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionPurchasePlatformBefore, .appStore)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionTimeRemainingBefore, .moreThanThreeDays)
        XCTAssertEqual(automaticSignOutData.storedRefreshTokenStateDuringAttempt, .unchanged)
        XCTAssertEqual(automaticSignOutData.localTokenStateAfterSignOut, .missing)
    }

    func testGetTokenContainer_UnknownAccount_WhenLocalRemovalFails_ReportsLocalTokenStillPresent() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.unknownAccount)
        mockOAuthClient.removeLocalAccountError = NSError(domain: "Keychain", code: 1)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch SubscriptionManagerError.noTokenAvailable {
            // Expected.
        }

        let automaticSignOutData = try XCTUnwrap(automaticSignOutPixel()).data
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionTrialStatusBefore, .unavailable)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionPurchasePlatformBefore, .unavailable)
        XCTAssertEqual(automaticSignOutData.localTokenStateAfterSignOut, .present)
    }

    func testGetTokenContainer_InvalidTokenRequest_RecoveryFailure_DoesNotCallServerLogout() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenError = NSError(domain: "RecoveryError", code: 1)

        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(mockOAuthClient.logoutCallCount, 0)
        XCTAssertEqual(mockOAuthClient.removeLocalAccountCallCount, 1)
        XCTAssertNil(mockOAuthClient.internalCurrentTokenContainer)
    }

    func testGetTokenContainer_UnknownAccount_DoesNotCallServerLogout() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.unknownAccount)

        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(mockOAuthClient.logoutCallCount, 0)
        XCTAssertEqual(mockOAuthClient.removeLocalAccountCallCount, 1)
        XCTAssertNil(mockOAuthClient.internalCurrentTokenContainer)
    }

    func testSignOut_Explicit_StillCallsServerLogout() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        await subscriptionManager.signOut(notifyUI: false)
        await subscriptionManager.signOut(notifyUI: true, userInitiated: true)

        XCTAssertEqual(mockOAuthClient.logoutCallCount, 2)
    }

    func testSignOut_Explicit_DeletesBackupBeforeLogout() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        await subscriptionManager.signOut(notifyUI: false)

        XCTAssertEqual(mockOAuthClient.removeBackupCallCount, 1)
        XCTAssertEqual(mockOAuthClient.callOrder.prefix(2), ["removeBackup", "logout"])
        XCTAssertNotNil(subscriptionManager.signOutCutoff)
    }

    func testSignOut_Explicit_RecordsTheNewestStoredTokenIssueDateAsTheCutoff() async throws {
        let currentIssuedAt = Date().addingTimeInterval(3600)
        let backupIssuedAt = Date().addingTimeInterval(7200)
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(refreshToken: "currentR",
                                                                                              refreshTokenIssuedAt: currentIssuedAt,
                                                                                              refreshTokenExpiresAt: currentIssuedAt.addingTimeInterval(3600))
        mockOAuthClient.internalBackupTokenContainer = OAuthTokensFactory.makeTokenContainer(refreshToken: "backupR",
                                                                                             refreshTokenIssuedAt: backupIssuedAt,
                                                                                             refreshTokenExpiresAt: backupIssuedAt.addingTimeInterval(3600))

        await subscriptionManager.signOut(notifyUI: false)

        XCTAssertEqual(subscriptionManager.signOutCutoff, backupIssuedAt)
    }

    func testSignOut_Explicit_NoStoredTokens_KeepsThePreviousCutoff() async throws {
        let issuedAt = Date().addingTimeInterval(-3600)
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(refreshToken: "currentR", refreshTokenIssuedAt: issuedAt)
        await subscriptionManager.signOut(notifyUI: false)
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.internalBackupTokenContainer = nil

        await subscriptionManager.signOut(notifyUI: false)

        XCTAssertEqual(subscriptionManager.signOutCutoff, issuedAt)
    }

    func testSignOut_Explicit_NoStoredTokensAndNoPreviousSignOut_RecordsNoCutoff() async throws {
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.internalBackupTokenContainer = nil

        await subscriptionManager.signOut(notifyUI: false)

        XCTAssertNil(subscriptionManager.signOutCutoff)
    }

    func testSignOut_Explicit_CurrentTokenUnreadable_RecordsTheDeviceTimeAsTheCutoff() async throws {
        mockOAuthClient.currentTokenContainerError = NSError(domain: "keychain", code: 1)
        let before = Date()

        await subscriptionManager.signOut(notifyUI: false)

        let cutoff = try XCTUnwrap(subscriptionManager.signOutCutoff)
        XCTAssertGreaterThanOrEqual(cutoff, before)
        XCTAssertLessThanOrEqual(cutoff, Date())
    }

    func testSignOut_Explicit_RecordsTimeWhenLogoutFails() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.logoutError = NSError(domain: "Logout", code: 1)

        await subscriptionManager.signOut(notifyUI: false)

        XCTAssertNotNil(subscriptionManager.signOutCutoff)
        XCTAssertEqual(mockOAuthClient.removeBackupCallCount, 1)
    }

    func testAutomaticSignOut_DoesNotRecordTimeOrDeleteBackup() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.unknownAccount)

        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertNil(subscriptionManager.signOutCutoff)
        XCTAssertEqual(mockOAuthClient.removeBackupCallCount, 0)
    }

    // MARK: - Backup recovery

    private func installCoordinator(backupResult: Result<TokenContainer, Error>?, appStoreSucceeds: Bool) {
        mockOAuthClient.restoreFromBackupResponse = backupResult
        let backup = BackupTokenRecovery(oAuthClient: mockOAuthClient, onRestored: { _ in })
        let appStore = AppStoreTokenRecovery(purchasePlatform: .appStore,
                                             restoreFlow: mockAppStoreRestoreFlowV2)
        if !appStoreSucceeds {
            mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenError = NSError(domain: "AppStore", code: 1)
        }
        subscriptionManager.tokenRecoveryCoordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [backup, appStore],
                                                                                missingTokenStrategies: [backup])
    }

    func testInvalidToken_BackupSucceeds_ReturnsRestoredWithoutAppStore() async throws {
        let restored = OAuthTokensFactory.makeTokenContainer(accessToken: "restoredA", refreshToken: "restoredR")
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(externalID: "acct")
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(backupResult: .success(restored), appStoreSucceeds: false)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(result, restored)
        XCTAssertEqual(mockOAuthClient.restoreFromBackupCalls.first?.expectedExternalID, "acct")
        XCTAssertFalse(mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenCalled)
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenRecovered))
        XCTAssertNil(automaticSignOutPixel())
    }

    func testInvalidToken_BackupFails_FallsBackToAppStore_ThenSignsOut() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(backupResult: .failure(OAuthClientError.invalidTokenRequest(.reused)), appStoreSucceeds: false)

        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(mockOAuthClient.restoreFromBackupCalls.count, 1)
        XCTAssertTrue(mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenCalled)
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenSignedOut))
    }

    func testInvalidToken_StoredTokenAlreadyReplaced_ReturnsItWithoutRecovery() async throws {
        let dead = OAuthTokensFactory.makeTokenContainer(refreshToken: "deadR")
        let fresh = OAuthTokensFactory.makeTokenContainer(refreshToken: "freshR")
        mockOAuthClient.internalCurrentTokenContainer = dead
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        mockOAuthClient.onGetTokens = { [unowned self] in self.mockOAuthClient.internalCurrentTokenContainer = fresh }
        installCoordinator(backupResult: nil, appStoreSucceeds: false)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(result, fresh)
        XCTAssertTrue(mockOAuthClient.restoreFromBackupCalls.isEmpty)
        XCTAssertFalse(mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenCalled)
        XCTAssertNil(automaticSignOutPixel())
    }

    func testInvalidToken_AlreadyReplaced_CompletesThePendingRecoveryFlowAsSucceeded() async throws {
        let pendingFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                          globalData: WideEventGlobalData(id: "refresh-1"))
        pendingFlow.errorData = WideEventErrorData(error: OAuthClientError.invalidTokenRequest(.reused))
        pendingFlow.recoveryDuration = .startingNow()
        mockWideEvent.startFlow(pendingFlow)
        let fresh = OAuthTokensFactory.makeTokenContainer(refreshToken: "freshR")
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(refreshToken: "deadR")
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        mockOAuthClient.onGetTokens = { [unowned self] in self.mockOAuthClient.internalCurrentTokenContainer = fresh }

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let refreshData = try XCTUnwrap(mockWideEvent.completions.first?.0 as? AuthV2TokenRefreshWideEventData)
        XCTAssertEqual(refreshData.recoveryOutcome, .succeeded)
    }

    func testInvalidToken_FirstReadFailed_DoesNotTreatTheDeadTokenAsAReplacement() async throws {
        let dead = OAuthTokensFactory.makeTokenContainer(refreshToken: "deadR")
        let recovered = OAuthTokensFactory.makeTokenContainer(refreshToken: "recoveredR")
        mockOAuthClient.currentTokenContainerError = NSError(domain: "keychain", code: 1)
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        mockOAuthClient.onGetTokens = { [unowned self] in
            self.mockOAuthClient.currentTokenContainerError = nil
            self.mockOAuthClient.internalCurrentTokenContainer = dead
        }
        overrideTokenResponseInRecovery = .success(recovered)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(result, recovered)
    }

    func testInvalidToken_SignOutDuringRestore_NeitherSignsOutAgainNorRunsAppStoreRestore() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(refreshToken: "deadR")
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(backupResult: .failure(TokenBackupError.sessionChanged), appStoreSucceeds: true)
        mockOAuthClient.onRestoreFromBackup = { [unowned self] in self.mockOAuthClient.internalCurrentTokenContainer = nil }

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable)
        }
        XCTAssertFalse(mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenCalled)
        XCTAssertEqual(mockOAuthClient.removeLocalAccountCallCount, 0)
        XCTAssertNil(automaticSignOutPixel())
    }

    func testInvalidToken_SessionChangedWhileTheRejectedTokenIsStillStored_DoesNotReturnIt() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(refreshToken: "deadR")
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(backupResult: .failure(TokenBackupError.sessionChanged), appStoreSucceeds: true)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable)
        }
        XCTAssertEqual(mockOAuthClient.removeLocalAccountCallCount, 0)
        XCTAssertNil(automaticSignOutPixel())
    }

    func testInvalidToken_SignInDuringRestore_ReturnsTheNewSessionWithoutSigningOut() async throws {
        let otherAccount = OAuthTokensFactory.makeTokenContainer(refreshToken: "otherR", externalID: "other")
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(refreshToken: "deadR")
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(backupResult: .failure(TokenBackupError.sessionChanged), appStoreSucceeds: true)
        mockOAuthClient.onRestoreFromBackup = { [unowned self] in self.mockOAuthClient.internalCurrentTokenContainer = otherAccount }

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(result, otherAccount)
        XCTAssertEqual(mockOAuthClient.internalCurrentTokenContainer, otherAccount)
        XCTAssertFalse(mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenCalled)
        XCTAssertNil(automaticSignOutPixel())
    }

    func testMissingPrimary_RestoresFromBackup() async throws {
        let restored = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.missingTokenContainer)
        installCoordinator(backupResult: .success(restored), appStoreSucceeds: true)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(result, restored)
        XCTAssertEqual(mockOAuthClient.restoreFromBackupCalls.count, 1)
        XCTAssertNil(mockOAuthClient.restoreFromBackupCalls.first?.expectedExternalID)
        XCTAssertTrue(subscriptionManager.cachedIsUserAuthenticated)
    }

    func testMissingPrimary_NeverRunsAppStoreRestore() async throws {
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.missingTokenContainer)
        installCoordinator(backupResult: .failure(TokenBackupError.unavailable), appStoreSucceeds: true)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable)
        }
        XCTAssertFalse(mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func testMissingPrimary_NoCoordinator_ThrowsNoTokenAsToday() async throws {
        subscriptionManager.tokenRecoveryCoordinator = nil
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.missingTokenContainer)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable)
        }
        XCTAssertFalse(mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenCalled)
    }

    func testMissingPrimary_PassesLastSignOutDate() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        await subscriptionManager.signOut(notifyUI: false)
        let signOutDate = try XCTUnwrap(subscriptionManager.signOutCutoff)
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.missingTokenContainer)
        installCoordinator(backupResult: .failure(TokenBackupError.predatesSignOut), appStoreSucceeds: true)

        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(mockOAuthClient.restoreFromBackupCalls.first?.issuedAfter, signOutDate)
    }

    func testCreateIfNeeded_MissingPrimary_RestoresBeforeTheClientCanCreateAnAccount() async throws {
        let restored = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.getTokensResponse = .success(restored)
        var restoredBeforeGetTokens = false
        mockOAuthClient.onGetTokens = { [unowned self] in restoredBeforeGetTokens = !self.mockOAuthClient.restoreFromBackupCalls.isEmpty }
        installCoordinator(backupResult: .success(restored), appStoreSucceeds: true)

        _ = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded)

        XCTAssertTrue(restoredBeforeGetTokens)
        XCTAssertEqual(mockOAuthClient.getTokensPolicies, [.createIfNeeded])
    }

    func testCreateIfNeeded_MissingPrimary_RestoresEvenDuringTheMissingTokenRetryPause() async throws {
        mockOAuthClient.internalCurrentTokenContainer = nil
        installCoordinator(backupResult: .failure(URLError(.timedOut)), appStoreSucceeds: true)
        await subscriptionManager.restoreMissingTokenIfPossible()
        let restored = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.restoreFromBackupResponse = .success(restored)
        mockOAuthClient.getTokensResponse = .success(restored)

        _ = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded)

        XCTAssertEqual(mockOAuthClient.restoreFromBackupCalls.count, 2)
    }

    func testCreateIfNeeded_MissingPrimary_TransientRestoreFailure_ThrowsWithoutCreatingAnAccount() async {
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        installCoordinator(backupResult: .failure(URLError(.timedOut)), appStoreSucceeds: true)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded)
            XCTFail("Expected error")
        } catch {
            XCTAssertNotNil(error as? SubscriptionManagerError)
        }
        XCTAssertTrue(mockOAuthClient.getTokensPolicies.isEmpty)
    }

    func testCreateIfNeeded_MissingPrimary_NoUsableBackup_CreatesAnAccount() async throws {
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        installCoordinator(backupResult: .failure(TokenBackupError.unavailable), appStoreSucceeds: true)

        _ = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded)

        XCTAssertEqual(mockOAuthClient.getTokensPolicies, [.createIfNeeded])
    }

    func testCreateIfNeeded_PrimaryPresent_DoesNotTouchTheBackup() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        installCoordinator(backupResult: .success(OAuthTokensFactory.makeValidTokenContainer()), appStoreSucceeds: true)

        _ = try await subscriptionManager.getTokenContainer(policy: .createIfNeeded)

        XCTAssertTrue(mockOAuthClient.restoreFromBackupCalls.isEmpty)
    }

    func testRestoreMissingTokenIfPossible_PrimaryPresent_DoesNothing() async {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        installCoordinator(backupResult: .success(OAuthTokensFactory.makeValidTokenContainer()), appStoreSucceeds: true)

        await subscriptionManager.restoreMissingTokenIfPossible()

        XCTAssertTrue(mockOAuthClient.restoreFromBackupCalls.isEmpty)
        XCTAssertFalse(mockSubscriptionEndpointService.getSubscriptionCalled)
    }

    func testRestoreMissingTokenIfPossible_PrimaryMissing_RestoresUpdatesTheCachedStateAndRefreshesTheSubscription() async {
        let restored = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.getTokensResponse = .success(restored)
        mockSubscriptionEndpointService.getSubscriptionResult = .failure(.noData)
        installCoordinator(backupResult: .success(restored), appStoreSucceeds: true)
        let signedIn = expectation(forNotification: .accountDidSignIn, object: subscriptionManager)

        await subscriptionManager.restoreMissingTokenIfPossible()

        await fulfillment(of: [signedIn], timeout: 1)
        XCTAssertEqual(mockOAuthClient.restoreFromBackupCalls.count, 1)
        XCTAssertTrue(subscriptionManager.cachedIsUserAuthenticated)
        XCTAssertFalse(mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenCalled)
        XCTAssertTrue(mockSubscriptionEndpointService.getSubscriptionCalled)
    }

    func testInvalidToken_RecoverySucceeds_UpdatesTheCachedStateAndEntitlements() async throws {
        let restored = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(refreshToken: "deadR")
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(backupResult: .success(restored), appStoreSucceeds: false)
        let entitlementsChanged = expectation(forNotification: .entitlementsDidChange, object: subscriptionManager)
        let signedIn = expectation(forNotification: .accountDidSignIn, object: subscriptionManager)

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        await fulfillment(of: [entitlementsChanged, signedIn], timeout: 1)
        XCTAssertTrue(subscriptionManager.cachedIsUserAuthenticated)
    }

    func testRestoreMissingTokenIfPossible_NoCoordinator_DoesNothing() async {
        mockOAuthClient.internalCurrentTokenContainer = nil

        await subscriptionManager.restoreMissingTokenIfPossible()

        XCTAssertTrue(mockOAuthClient.restoreFromBackupCalls.isEmpty)
        XCTAssertFalse(subscriptionManager.isUserAuthenticated)
    }

    func testLoadInitialData_PrimaryMissing_RestoresFromBackupBeforeLoadingTheSubscription() async {
        let restored = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.getTokensResponse = .success(restored)
        mockSubscriptionEndpointService.getSubscriptionResult = .failure(.noData)
        installCoordinator(backupResult: .success(restored), appStoreSucceeds: true)
        var restoresBeforeFirstTokenRead: Int?
        mockOAuthClient.onGetTokens = { [unowned self] in
            if restoresBeforeFirstTokenRead == nil {
                restoresBeforeFirstTokenRead = self.mockOAuthClient.restoreFromBackupCalls.count
            }
        }

        await subscriptionManager.loadInitialData()

        XCTAssertEqual(restoresBeforeFirstTokenRead, 1)
        XCTAssertTrue(subscriptionManager.cachedIsUserAuthenticated)
    }

    func testGetTokenContainer_InvalidTokenRequest_RecoverySuccess_Pixels() async throws {
        let recoveredTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        overrideTokenResponseInRecovery = .success(recoveredTokenContainer)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(result, recoveredTokenContainer)

        assertGetTokensErrorPixel(policy: .localValid)
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshToken))
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenRecovered))
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenSignedOut))
        XCTAssertNil(automaticSignOutPixel())
    }

    func testGetTokenContainer_InvalidTokenRequest_RecoveryFailure_Pixels() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionCachingService.cachedSubscription = SubscriptionMockFactory.appleSubscription
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenError = NSError(domain: "RecoveryError", code: 1)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            let managerError = error as? SubscriptionManagerError
            XCTAssertEqual(managerError, .noTokenAvailable)
            XCTAssertNil(managerError?.underlyingError)
        }

        assertGetTokensErrorPixel(policy: .localValid)
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshToken))
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenSignedOut))
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenRecovered))

        let automaticSignOut = try XCTUnwrap(automaticSignOutPixel())
        let automaticSignOutData = automaticSignOut.data
        let automaticSignOutError = automaticSignOut.error as NSError
        XCTAssertEqual(automaticSignOutError.domain, OAuthClientError.errorDomain)
        XCTAssertEqual(automaticSignOutError.code, OAuthClientError.invalidTokenRequest(.reused).errorCode)
        let underlyingError = try XCTUnwrap(automaticSignOutError.userInfo[NSUnderlyingErrorKey] as? NSError)
        XCTAssertEqual(underlyingError.domain, OAuthRequest.TokenStatus.errorDomain)
        XCTAssertEqual(underlyingError.code, OAuthRequest.TokenStatus.reused.errorCode)
        XCTAssertEqual(automaticSignOutData.recoveryOutcome, .failed)
        XCTAssertEqual(automaticSignOutData.entitlementStateBefore, .present)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionStatusBefore, .autoRenewable)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionTrialStatusBefore, .notActive)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionPurchasePlatformBefore, .appStore)
        // The recovery attempt drops the stored container, but that happens after the request this
        // pixel describes, so the token is still reported as unchanged during the attempt itself.
        XCTAssertEqual(automaticSignOutData.storedRefreshTokenStateDuringAttempt, .unchanged)
        XCTAssertEqual(automaticSignOutData.localTokenStateAfterSignOut, .missing)
    }

    func testGetTokenContainer_InvalidTokenRequest_WhenRecoveryClearsState_ReportsStateFromBeforeRecovery() async throws {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionCachingService.cachedSubscription = SubscriptionMockFactory.appleSubscription
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        overrideTokenResponseInRecovery = .failure(OAuthClientError.invalidTokenRequest(.reused))
        // The real restore flow clears the subscription cache and adopts a new token container before
        // it can fail, so the pixel must report what was there when the request failed, not after.
        recoverySideEffect = { [weak self] in
            self?.mockSubscriptionCachingService.cachedSubscription = nil
            self?.mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeDeadTokenContainer()
        }

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch SubscriptionManagerError.noTokenAvailable {
            // Expected.
        }

        let automaticSignOutData = try XCTUnwrap(automaticSignOutPixel()).data
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionStatusBefore, .autoRenewable)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionTrialStatusBefore, .notActive)
        XCTAssertEqual(automaticSignOutData.cachedSubscriptionPurchasePlatformBefore, .appStore)
        XCTAssertEqual(automaticSignOutData.storedRefreshTokenStateDuringAttempt, .unchanged)
    }

    // MARK: - Invalid-token recovery wide event completion

    func testGetTokenContainer_InvalidTokenRequest_RecoverySuccess_CompletesWideEventAsRecoveredWithoutError() async throws {
        // Simulate the refresh flow the OAuthClient event mapping leaves pending on an invalid token:
        // marked .recoverInvalidToken, carrying the originating error, with the recovery clock started.
        let pendingFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                          globalData: WideEventGlobalData(id: "refresh-1"))
        pendingFlow.errorData = WideEventErrorData(error: OAuthClientError.invalidTokenRequest(.reused))
        pendingFlow.recoveryDuration = .startingNow()
        mockWideEvent.startFlow(pendingFlow)

        let recoveredTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        overrideTokenResponseInRecovery = .success(recoveredTokenContainer)

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (data, status) = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(data.globalData.id, "refresh-1")
        // Recovery SUCCESS is a plain SUCCESS with no status reason; the recovery is recorded via the outcome.
        XCTAssertEqual(status, .success(reason: nil))
        let refreshData = try XCTUnwrap(data as? AuthV2TokenRefreshWideEventData)
        XCTAssertEqual(refreshData.recoveryOutcome, .succeeded)
        // A recovered SUCCESS must not carry the stale invalid_token_request error, or the sender will
        // emit a self-contradictory "successful failure" (WideEventSending merges errorData regardless of status).
        XCTAssertNil(refreshData.errorData)
        XCTAssertNil(refreshData.failingStep)
        XCTAssertNotNil(refreshData.recoveryDuration?.end)
    }

    func testGetTokenContainer_InvalidTokenRequest_RecoveryFailure_CompletesWideEventAsFailure() async throws {
        let pendingFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                          globalData: WideEventGlobalData(id: "refresh-1"))
        pendingFlow.recoveryDuration = .startingNow()
        mockWideEvent.startFlow(pendingFlow)

        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        overrideTokenResponseInRecovery = .failure(OAuthClientError.invalidTokenRequest(.reused))

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable)
        }

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (data, status) = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(status, .failure)
        let refreshData = try XCTUnwrap(data as? AuthV2TokenRefreshWideEventData)
        XCTAssertNotNil(refreshData.errorData)
        // A restore ran and failed - the outcome reflects a real (failed) recovery attempt.
        XCTAssertEqual(refreshData.recoveryOutcome, .failed)
    }

    func testGetTokenContainer_InvalidTokenRequest_RecoveryNotAttempted_CompletesWideEventAsNotAttempted() async throws {
        let pendingFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                          globalData: WideEventGlobalData(id: "refresh-1"))
        pendingFlow.errorData = WideEventErrorData(error: OAuthClientError.invalidTokenRequest(.reused))
        pendingFlow.recoveryDuration = .startingNow()
        mockWideEvent.startFlow(pendingFlow)

        // With no recovery coordinator, recovery cannot even be attempted.
        subscriptionManager.tokenRecoveryCoordinator = nil
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable)
        }

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (data, status) = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(status, .failure)
        let refreshData = try XCTUnwrap(data as? AuthV2TokenRefreshWideEventData)
        XCTAssertEqual(refreshData.recoveryOutcome, .notAttempted)
        // No restore ran, so the meaningless recovery latency is dropped, but the original
        // invalid-token error is preserved for debugging.
        XCTAssertNil(refreshData.recoveryDuration)
        XCTAssertNotNil(refreshData.errorData)

        let automaticSignOutData = try XCTUnwrap(automaticSignOutPixel()).data
        XCTAssertEqual(automaticSignOutData.recoveryOutcome, .notAttempted)
        XCTAssertEqual(automaticSignOutData.storedRefreshTokenStateDuringAttempt, .unchanged)
        XCTAssertEqual(automaticSignOutData.localTokenStateAfterSignOut, .missing)
    }

    func testGetTokenContainer_InvalidTokenRequest_SelectsNewestPendingFlow() async throws {
        // An older orphan from the recovery-less callback path must NOT be the one completed.
        let staleFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                        globalData: WideEventGlobalData(id: "stale"))
        staleFlow.recoveryDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSinceNow: -120), end: nil)
        mockWideEvent.startFlow(staleFlow)

        let freshFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                        globalData: WideEventGlobalData(id: "fresh"))
        freshFlow.recoveryDuration = .startingNow()
        mockWideEvent.startFlow(freshFlow)

        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        overrideTokenResponseInRecovery = .success(OAuthTokensFactory.makeValidTokenContainer())

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        let (data, _) = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(data.globalData.id, "fresh")
    }

    func testGetTokenContainer_UsesClientTrigger_SoInvalidTokenRecoveryCanDefer() async throws {
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(mockOAuthClient.getTokensTriggers, [.client])
    }

    func testAdopt_FromWebRestore_RecordsWebRestoreAdoptionSource() async throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.decodeResponse = .success(tokenContainer)
        mockOAuthClient.getTokensResponse = .success(tokenContainer)

        try await subscriptionManager.adopt(accessToken: "at", refreshToken: "rt")

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (data, status) = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(status, .success(reason: nil))
        let adoptionData = try XCTUnwrap(data as? AuthV2TokenAdoptionWideEventData)
        XCTAssertEqual(adoptionData.adoptionSource, .webRestore)
    }

    func testAdoptToken_FromVPN_RecordsVPNAdoptionSource() async throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)

        try await subscriptionManager.adoptToken(tokenContainer)

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (data, status) = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(status, .success(reason: nil))
        let adoptionData = try XCTUnwrap(data as? AuthV2TokenAdoptionWideEventData)
        XCTAssertEqual(adoptionData.adoptionSource, .vpn)
    }

    func testGetTokenContainer_OtherError_ReportsPixelAndUnderlyingError() async throws {
        let expectedError = OAuthServiceError.invalidResponseCode(.badRequest)
        mockOAuthClient.getTokensResponse = .failure(expectedError)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            let managerError = error as? SubscriptionManagerError
            XCTAssertEqual(managerError, .errorRetrievingTokenContainer(error: expectedError))
            XCTAssertEqual(managerError?.underlyingError as? OAuthServiceError, expectedError)
        }

        assertGetTokensErrorPixel(policy: .localValid)
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(.invalidRefreshToken))
    }

    // MARK: - Subscription Status Tests

    func testRefreshCachedSubscription_ActiveSubscription() async throws {
        let activeSubscription = DuckDuckGoSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.minutes(-5)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(30)),
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(activeSubscription)
        mockSubscriptionEndpointService.getSubscriptionTierFeaturesResult = .success(GetSubscriptionTierFeaturesResponse(features: [:]))
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer

        let subscription = try await subscriptionManager.getSubscription(forceRefresh: true)
        XCTAssertNotNil(subscription)
        XCTAssertTrue(subscription!.isActive)
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.subscriptionIsActive))
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.osDistributionActiveSubscription))
    }

    func testRefreshCachedSubscription_ExpiredSubscription() async throws {
        let expiredSubscription = DuckDuckGoSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.days(-30)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(-1)), // expired
            platform: .apple,
            status: .expired,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(expiredSubscription)
        mockSubscriptionEndpointService.getSubscriptionTierFeaturesResult = .success(GetSubscriptionTierFeaturesResponse(features: [:]))
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer

        let subscription = try await subscriptionManager.getSubscription(forceRefresh: true)
        XCTAssertNotNil(subscription, "Expired subscription should still be returned")
        XCTAssertFalse(subscription!.isActive, "Expired subscription should not be active")
        XCTAssertEqual(subscription!.status, .expired)
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(.osDistributionActiveSubscription),
                       "OS-distribution pixel must not fire for an inactive subscription")
    }

    func testGetSubscription_NoDataOnBackend_ReturnsNil() async throws {
        mockSubscriptionEndpointService.getSubscriptionResult = .failure(.noData)
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer

        let subscription = try await subscriptionManager.getSubscription(forceRefresh: true)
        XCTAssertNil(subscription)
    }

    func testGetSubscription_TransientError_ReturnsCachedSubscription() async throws {
        // Populate the cache with an active subscription
        let cachedSubscription = DuckDuckGoSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.minutes(-5)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(30)),
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(cachedSubscription)
        mockSubscriptionEndpointService.getSubscriptionTierFeaturesResult = .success(GetSubscriptionTierFeaturesResponse(features: [:]))
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer

        _ = try await subscriptionManager.getSubscription(forceRefresh: true)

        // Now simulate a transient backend error on the next forceRefresh
        mockSubscriptionEndpointService.getSubscriptionResult = .failure(.invalidResponseCode(.internalServerError))

        let result = try await subscriptionManager.getSubscription(forceRefresh: true)
        XCTAssertNotNil(result, "Should fall back to the cached subscription on transient error")
        XCTAssertEqual(result?.productId, cachedSubscription.productId)
        XCTAssertTrue(result!.isActive)
    }

    func testGetSubscription_TierFeaturesError_ReturnsCachedSubscription() async throws {
        // Populate the cache with an active subscription
        let cachedSubscription = DuckDuckGoSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.minutes(-5)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(30)),
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(cachedSubscription)
        mockSubscriptionEndpointService.getSubscriptionTierFeaturesResult = .success(GetSubscriptionTierFeaturesResponse(features: [:]))
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer

        _ = try await subscriptionManager.getSubscription(forceRefresh: true)

        // Subscription endpoint succeeds but tier-features endpoint fails
        mockSubscriptionEndpointService.getSubscriptionTierFeaturesResult = .failure(APIServiceError.serverError(statusCode: 500, statusDescription: "Internal Server Error"))

        let result = try await subscriptionManager.getSubscription(forceRefresh: true)
        XCTAssertNotNil(result, "Should fall back to the cached subscription when tier-features fails")
        XCTAssertEqual(result?.productId, cachedSubscription.productId)
        XCTAssertTrue(result!.isActive)
    }

    /// When the token is unavailable, the cache must be cleared but no `.subscriptionDidChange`
    /// notification is posted — even if a subscription was previously cached.
    /// This documents a known asymmetry: the `noData` path posts a notification on state change,
    /// while the `noToken` path does not, which can leave the UI stale until the next refresh.
    func testGetSubscription_NoToken_WithCachedSubscription_ClearsCacheButDoesNotPostNotification() async throws {
        let cachedSubscription = DuckDuckGoSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.minutes(-5)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(30)),
            platform: .apple,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionCachingService.cachedSubscription = cachedSubscription
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.missingTokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = nil

        let notificationExpectation = XCTestExpectation(description: "subscriptionDidChange must NOT fire")
        notificationExpectation.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: .subscriptionDidChange, object: nil, queue: nil) { _ in
            notificationExpectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        do {
            _ = try await subscriptionManager.getSubscription(forceRefresh: true)
            XCTFail("Expected SubscriptionManagerError.noTokenAvailable")
        } catch SubscriptionManagerError.noTokenAvailable {}

        await fulfillment(of: [notificationExpectation], timeout: 0.1)
        XCTAssertTrue(mockSubscriptionCachingService.resetCalled, "Cache must be cleared when token is unavailable")
        XCTAssertNil(mockSubscriptionCachingService.cachedSubscription, "Cached subscription must be nil after token loss")
    }

    func testGetSubscription_CachedSubscription_ReturnsCachedWithoutRefresh() async throws {
        // First, populate the cache with an active subscription
        let activeSubscription = DuckDuckGoSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.minutes(-5)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(30)),
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(activeSubscription)
        mockSubscriptionEndpointService.getSubscriptionTierFeaturesResult = .success(GetSubscriptionTierFeaturesResponse(features: [:]))
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer

        _ = try await subscriptionManager.getSubscription(forceRefresh: true)

        // Now request without force refresh — should return cached
        mockSubscriptionEndpointService.getSubscriptionResult = .failure(.noData)
        let cached = try await subscriptionManager.getSubscription()
        XCTAssertNotNil(cached)
        XCTAssertTrue(cached!.isActive)
    }

    // MARK: - URL Generation Tests

    func testURLGeneration_ForCustomerPortal() async throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        let customerPortalURLString = "https://example.com/customer-portal"
        mockSubscriptionEndpointService.getCustomerPortalURLResult = .success(GetCustomerPortalURLResponse(customerPortalUrl: customerPortalURLString))

        let url = try await subscriptionManager.getCustomerPortalURL()
        XCTAssertEqual(url.absoluteString, customerPortalURLString)
    }

    func testURLGeneration_ForSubscriptionTypes() {
        let environment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        subscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionCachingService: mockSubscriptionCachingService,
            subscriptionEnvironment: environment,
            pixelHandler: MockPixelHandler()
        )

        let helpURL = subscriptionManager.url(for: .purchase)
        XCTAssertEqual(helpURL.absoluteString, "https://duckduckgo.com/subscriptions")
    }

    // MARK: - Purchase Confirmation Tests

    func testConfirmPurchase_ErrorHandling() async throws {
        let testSignature = "invalidSignature"
        mockSubscriptionEndpointService.confirmPurchaseResult = .failure(APIRequestV2Error.invalidResponse)
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        do {
            _ = try await subscriptionManager.confirmPurchase(signature: testSignature, experimentAttribution: nil)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? APIRequestV2Error, APIRequestV2Error.invalidResponse)
        }
    }

    func testConfirmPurchase_TierFeaturesError_SubscriptionStillPresent() async throws {
        // Regression test: a transient tier-features failure must not clear the cache.
        // A user who just paid should still see a subscription even if enrichment fails.
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer

        let purchasedSubscription = DuckDuckGoSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.minutes(-1)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(30)),
            platform: .apple,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionEndpointService.confirmPurchaseResult = .success(ConfirmPurchaseResponse(email: nil, subscription: purchasedSubscription))
        mockSubscriptionEndpointService.getSubscriptionTierFeaturesResult = .failure(APIServiceError.serverError(statusCode: 500, statusDescription: "Internal Server Error"))

        do {
            _ = try await subscriptionManager.confirmPurchase(signature: "testSignature", experimentAttribution: nil)
            XCTFail("Error expected from tier-features failure")
        } catch {
            // The cache must hold the raw (unenriched) subscription — not be empty.
            XCTAssertTrue(subscriptionManager.isSubscriptionPresent(), "isSubscriptionPresent() must be true after a tier-features failure post-purchase")
            XCTAssertNotNil(mockSubscriptionCachingService.cachedSubscription, "Cache must contain the raw subscription when enrichment fails")
        }
    }

    // MARK: - Tests for save and loadEnvironmentFrom

    var subscriptionEnvironment: SubscriptionEnvironment!

    func testLoadEnvironmentFromUserDefaults() async throws {
        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                          purchasePlatform: .appStore)
        let userDefaultsSuiteName = "SubscriptionManagerTests"
        // Given
        let userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)

        var loadedEnvironment = DefaultSubscriptionManager.loadEnvironmentFrom(userDefaults: userDefaults)
        XCTAssertNil(loadedEnvironment)

        // When
        DefaultSubscriptionManager.save(subscriptionEnvironment: subscriptionEnvironment,
                                          userDefaults: userDefaults)
        loadedEnvironment = DefaultSubscriptionManager.loadEnvironmentFrom(userDefaults: userDefaults)

        // Then
        XCTAssertEqual(loadedEnvironment?.serviceEnvironment, subscriptionEnvironment.serviceEnvironment)
        XCTAssertEqual(loadedEnvironment?.purchasePlatform, subscriptionEnvironment.purchasePlatform)
    }

    // MARK: - Tests for url

    func testForProductionURL() throws {
        // Given
        let productionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let productionSubscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionCachingService: mockSubscriptionCachingService,
            subscriptionEnvironment: productionEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let productionPurchaseURL = productionSubscriptionManager.url(for: .purchase)

        // Then
        XCTAssertEqual(productionPurchaseURL, SubscriptionURL.purchase.subscriptionURL(environment: .production))
    }

    func testForStagingURL() throws {
        // Given
        let stagingEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let stagingSubscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionCachingService: mockSubscriptionCachingService,
            subscriptionEnvironment: stagingEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let stagingPurchaseURL = stagingSubscriptionManager.url(for: .purchase)

        // Then
        XCTAssertEqual(stagingPurchaseURL, SubscriptionURL.purchase.subscriptionURL(environment: .staging))
    }

    // MARK: - Dead token recovery

    func testDeadTokenRecoverySuccess() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(OAuthRequest.TokenStatus.expired))
        overrideTokenResponseInRecovery = .success(OAuthTokensFactory.makeValidTokenContainer())
        mockAppStoreRestoreFlowV2.restoreAccountFromPastPurchaseResult = .success("some")
        let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertFalse(tokenContainer.decodedAccessToken.isExpired())
    }

    func testDeadTokenRecoveryFailure() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(OAuthRequest.TokenStatus.fraudDetected))
        mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenError = SubscriptionManagerError.errorRetrievingTokenContainer(error: nil)

        do {
            try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("This should fail with error: SubscriptionManagerError.tokenRefreshFailed")
        } catch SubscriptionManagerError.noTokenAvailable {

        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// Dead token error loop detector: this case shouldn't be possible, but if the BE starts to send back expired tokens we risk to enter in an infinite loop.
    func testDeadTokenRecoveryLoop() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(OAuthRequest.TokenStatus.expired))
        mockAppStoreRestoreFlowV2.restoreAccountFromPastPurchaseResult = .success("some")
        do {
            try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("This should fail with error: SubscriptionManagerError.tokenRefreshFailed")
        } catch SubscriptionManagerError.noTokenAvailable {

        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("This should fail with error: SubscriptionManagerError.tokenRefreshFailed")
        } catch SubscriptionManagerError.noTokenAvailable {

        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Tests for Free Trial Eligibility

    func testWhenPlatformIsStripeUserIsEligibleForFreeTrialThenReturnsEligible() throws {
        // Given
        mockStorePurchaseManager.isEligibleForFreeTrialResult = false
        let stripeEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let sut = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionCachingService: mockSubscriptionCachingService,
            subscriptionEnvironment: stripeEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let result = sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertTrue(result)
    }

    func testWhenPlatformIsAppStoreAndUserIsEligibleForFreeTrialThenReturnsEligible() throws {
        // Given
        mockStorePurchaseManager.isEligibleForFreeTrialResult = true
        let appStoreEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let sut = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionCachingService: mockSubscriptionCachingService,
            subscriptionEnvironment: appStoreEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let result = sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertTrue(result)
    }

    func testWhenPlatformIsAppStoreAndUserIsNotEligibleForFreeTrialThenReturnsNotEligible() throws {
        // Given
        mockStorePurchaseManager.isEligibleForFreeTrialResult = false
        let appStoreEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let sut = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionCachingService: mockSubscriptionCachingService,
            subscriptionEnvironment: appStoreEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let result = sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Tests for hasAppStoreProductsAvailablePublisher

    @MainActor
    func testWhenInitialProductFetchFinishesThenAvailabilityIsResolved() async {
        for available in [false, true] {
            let store = StorePurchaseManagerMock()
            let defaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
            let manager = DefaultSubscriptionManager(
                storePurchaseManager: store,
                oAuthClient: mockOAuthClient,
                userDefaults: defaults,
                subscriptionEndpointService: mockSubscriptionEndpointService,
                subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
                pixelHandler: mockPixelHandler
            )
            store.onUpdateAvailableProducts = { [weak manager, weak store] in
                XCTAssertEqual(manager?.hasResolvedAppStoreProducts, false)
                store?.areProductsAvailable = available
            }
            XCTAssertFalse(manager.hasResolvedAppStoreProducts)
            XCTAssertFalse(manager.hasAppStoreProductsAvailable)

            let resolved = expectation(description: "initial product fetch resolved")
            let cancellable = manager.hasAppStoreProductsAvailablePublisher
                .sink { value in
                    XCTAssertTrue(manager.hasResolvedAppStoreProducts)
                    XCTAssertEqual(value, available)
                    XCTAssertEqual(manager.hasAppStoreProductsAvailable, available)
                    resolved.fulfill()
                }
            await fulfillment(of: [resolved], timeout: 1)

            XCTAssertTrue(manager.hasResolvedAppStoreProducts)
            XCTAssertEqual(manager.hasAppStoreProductsAvailable, available)
            cancellable.cancel()
        }
    }

    @MainActor
    func testCanPurchasePublisherEmitsValuesFromStorePurchaseManager() async throws {
        try await waitForInitialProductFetch()

        // Given
        let expectation = expectation(description: "Publisher should emit value")
        var receivedValue: Bool?

        // When
        let cancellable = subscriptionManager.hasAppStoreProductsAvailablePublisher
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }

        // Simulate store purchase manager emitting a value
        mockStorePurchaseManager.areProductsAvailableSubject.send(true)

        // Then
        await fulfillment(of: [expectation], timeout: 0.5)
        XCTAssertTrue(receivedValue ?? false)

        // Clean up
        cancellable.cancel()
    }

    @MainActor
    func testCanPurchasePublisherEmitsMultipleValues() async throws {
        try await waitForInitialProductFetch()

        // Given
        let expectation1 = expectation(description: "Publisher should emit first value")
        let expectation2 = expectation(description: "Publisher should emit second value")
        var receivedValues: [Bool] = []

        // When
        let cancellable = subscriptionManager.hasAppStoreProductsAvailablePublisher
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count == 1 {
                    expectation1.fulfill()
                } else if receivedValues.count == 2 {
                    expectation2.fulfill()
                }
            }

        // Simulate store purchase manager emitting multiple values
        mockStorePurchaseManager.areProductsAvailableSubject.send(true)
        mockStorePurchaseManager.areProductsAvailableSubject.send(false)

        // Then
        await fulfillment(of: [expectation1, expectation2], timeout: 0.5)
        XCTAssertEqual(receivedValues, [true, false])

        // Clean up
        cancellable.cancel()
    }

    @MainActor
    private func waitForInitialProductFetch() async throws {
        let manager = try XCTUnwrap(subscriptionManager)
        guard !manager.hasResolvedAppStoreProducts else { return }

        let resolved = expectation(description: "initial product fetch finished before forwarding test")
        let cancellable = manager.hasAppStoreProductsAvailablePublisher
            .first { _ in manager.hasResolvedAppStoreProducts }
            .sink { _ in resolved.fulfill() }
        await fulfillment(of: [resolved], timeout: 1)
        cancellable.cancel()
    }

    private func assertGetTokensErrorPixel(policy: AuthTokensCachePolicy) {
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(where: { pixel in
            guard case .getTokensError(let capturedPolicy, _) = pixel else { return false }
            return capturedPolicy == policy
        }))
    }

    private func assertNoGetTokensErrorPixel() {
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(where: { pixel in
            if case .getTokensError = pixel { return true }
            return false
        }))
    }

    private func automaticSignOutPixel() -> (data: SubscriptionAutomaticSignOutPixelData, error: Error)? {
        mockPixelHandler.handledPixels.compactMap { pixel in
            guard case .automaticSignOut(let data, let error) = pixel else {
                return nil
            }
            return (data, error)
        }.first
    }
}

// MARK: - Mock

private final class MockSubscriptionPixelHandler: SubscriptionPixelHandling {
    var handledPixels: [SubscriptionPixelType] = []
    var handledKeychainPixels: [KeychainManager.Pixel] = []

    func handle(pixel: SubscriptionPixelType) {
        handledPixels.append(pixel)
    }

    func handle(pixel: KeychainManager.Pixel) {
        handledKeychainPixels.append(pixel)
    }
}

private struct SubscriptionPixelEvent: PixelKit.Event {
    let name: String
    let parameters: [String: String]?
    let standardParameters: [PixelKitStandardParameter]? = [.pixelSource]
}

/// A token recovery strategy that runs a closure.
private struct ClosureTokenRecovery: TokenRecoveryStrategy {
    let body: (TokenRecoveryContext) async throws -> Void

    func recover(_ context: TokenRecoveryContext) async throws {
        try await body(context)
    }
}

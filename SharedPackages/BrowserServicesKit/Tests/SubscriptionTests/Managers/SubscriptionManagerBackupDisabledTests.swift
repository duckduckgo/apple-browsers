//
//  SubscriptionManagerBackupDisabledTests.swift
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
import JWTKit
@testable import Subscription
@_spi(Testing) @testable import Networking
import SubscriptionTestingUtilities
@_spi(Testing) import WideEvent

/// Runs the manager with a real `DefaultOAuthClient` wired as in the apps, with the backup token feature off until a test turns it on.
final class SubscriptionManagerBackupDisabledTests: XCTestCase {

    private var isBackupEnabled = false
    private var oAuthService: MockOAuthService!
    private var primaryStorage: MockTokenStorage!
    private var backupStorage: MockTokenStorage!
    private var refresher: DefaultTokenRefresher!
    private var appStoreRestoreFlow: AppStoreRestoreFlowMock!
    private var pixelHandler: RecordingPixelHandler!
    private var oAuthClient: DefaultOAuthClient!
    private var subscriptionManager: DefaultSubscriptionManager!

    private let storedBackup = OAuthTokensFactory.makeTokenContainer(accessToken: "backupA", refreshToken: "backupR")

    override func setUp() {
        super.setUp()
        oAuthService = MockOAuthService()
        oAuthService.getJWTSignersResponse = .success(JWTSigners())
        oAuthService.refreshAccessTokenResponse = .failure(URLError(.notConnectedToInternet))
        primaryStorage = MockTokenStorage()
        backupStorage = MockTokenStorage(tokenContainer: storedBackup)
        appStoreRestoreFlow = AppStoreRestoreFlowMock()
        appStoreRestoreFlow.restoreSubscriptionAfterExpiredRefreshTokenError = NSError(domain: "AppStore", code: 1)
        pixelHandler = RecordingPixelHandler()
        refresher = DefaultTokenRefresher(authService: oAuthService, clientID: "c", refreshEventMapping: nil)

        let userDefaults = UserDefaults(suiteName: "SubscriptionManagerBackupDisabledTests.\(UUID().uuidString)")!
        isBackupEnabled = false
        oAuthClient = DefaultOAuthClient(tokensStorage: primaryStorage,
                                         authService: oAuthService,
                                         refreshEventMapping: nil,
                                         tokenRefresher: refresher,
                                         backupStorage: backupStorage,
                                         isBackupEnabled: { [weak self] in self?.isBackupEnabled ?? false },
                                         backupUserDefaults: userDefaults,
                                         backupEventMapping: pixelHandler.backupEventMapping())
        let wideEvent = WideEventMock()
        let subscriptionEndpointService = SubscriptionEndpointServiceMock()
        subscriptionEndpointService.getSubscriptionResult = .failure(.noData)
        subscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: StorePurchaseManagerMock(),
            oAuthClient: oAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: subscriptionEndpointService,
            subscriptionCachingService: SubscriptionCachingServiceMock(),
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
            pixelHandler: pixelHandler,
            wideEvent: wideEvent,
            isAuthV2WideEventEnabled: { true },
            authV2TokenRefreshInstrumentation: DefaultAuthV2TokenRefreshInstrumentation(wideEvent: wideEvent, isFeatureEnabled: { true })
        )
        let backupRecovery = BackupTokenRecovery(oAuthClient: oAuthClient, pixelHandler: pixelHandler)
        let appStoreRecovery = AppStoreTokenRecovery(purchasePlatform: .appStore, restoreFlow: appStoreRestoreFlow)
        subscriptionManager.tokenRecoveryCoordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [backupRecovery, appStoreRecovery],
                                                                                missingTokenStrategies: [backupRecovery])
    }

    override func tearDown() {
        oAuthService = nil
        primaryStorage = nil
        backupStorage = nil
        refresher = nil
        appStoreRestoreFlow = nil
        pixelHandler = nil
        oAuthClient = nil
        subscriptionManager = nil
        super.tearDown()
    }

    func testRefreshSucceeds_doesNotCreateABackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        try backupStorage.saveTokenContainer(nil)
        oAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        let refreshed = OAuthTokensFactory.makeTokenContainer(accessToken: "refreshedA", refreshToken: "refreshedR")
        await refresher.setTestingDecodedTokenContainers([refreshed])

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)
        await oAuthClient.waitForBackupRenewal()

        XCTAssertEqual(result, refreshed)
        XCTAssertEqual(oAuthService.refreshAccessTokenCallCount, 1)
        XCTAssertNil(try backupStorage.getTokenContainer())
        XCTAssertEqual(pixelHandler.backupPixels.count, 0)
    }

    func testRefreshRejected_runsTheAppStoreRestoreOnly_andSignsOutWithoutTouchingTheBackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        oAuthService.refreshAccessTokenResponse = .failure(OAuthTokensFactory.makeAuthAPIError(.invalidTokenRequest, tokenStatus: .reused))

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable)
        }

        XCTAssertTrue(appStoreRestoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
        XCTAssertEqual(oAuthService.refreshAccessTokenCallCount, 1)
        XCTAssertEqual(pixelHandler.backupPixels.count, 0)
        XCTAssertEqual(pixelHandler.automaticSignOutData?.recoveryOutcome, .failed)
        XCTAssertEqual(pixelHandler.automaticSignOutData?.backupOutcome, .notAttempted)
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertEqual(try backupStorage.getTokenContainer(), storedBackup)
    }

    func testTokenMissing_throwsWithoutRestoring_andKeepsTheBackup() async throws {
        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable)
        }

        XCTAssertEqual(oAuthService.refreshAccessTokenCallCount, 0)
        XCTAssertFalse(appStoreRestoreFlow.restoreSubscriptionAfterExpiredRefreshTokenCalled)
        XCTAssertEqual(pixelHandler.backupPixels.count, 0)
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertEqual(try backupStorage.getTokenContainer(), storedBackup)
    }

    func testTokenMissing_restoreMissingTokenIfPossible_doesNothing() async throws {
        await subscriptionManager.restoreMissingTokenIfPossible()

        XCTAssertEqual(oAuthService.refreshAccessTokenCallCount, 0)
        XCTAssertEqual(pixelHandler.backupPixels.count, 0)
        XCTAssertFalse(subscriptionManager.cachedIsUserAuthenticated)
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertEqual(try backupStorage.getTokenContainer(), storedBackup)
    }

    // MARK: - Flag turned on after an action taken while it was off

    func testAutomaticSignOutWhileOff_thenOn_restoresTheKeptBackup() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeExpiredTokenContainer())
        oAuthService.refreshAccessTokenResponse = .failure(OAuthTokensFactory.makeAuthAPIError(.invalidTokenRequest, tokenStatus: .reused))
        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertEqual(try backupStorage.getTokenContainer(), storedBackup)

        isBackupEnabled = true
        oAuthService.refreshAccessTokenResponse = .success(OAuthTokensFactory.makeValidOAuthTokenResponse())
        let restoredBackup = OAuthTokensFactory.makeTokenContainer(accessToken: "restoredBackupA", refreshToken: "restoredBackupR")
        let restoredPrimary = OAuthTokensFactory.makeTokenContainer(accessToken: "restoredA", refreshToken: "restoredR")
        await refresher.setTestingDecodedTokenContainers([restoredBackup, restoredPrimary])
        await subscriptionManager.restoreMissingTokenIfPossible()

        XCTAssertEqual(oAuthService.refreshAccessTokenRequestedTokens.suffix(2), ["backupR", "backupR"])
        XCTAssertEqual(try primaryStorage.getTokenContainer(), restoredPrimary)
        XCTAssertEqual(try backupStorage.getTokenContainer(), restoredBackup)
        XCTAssertTrue(subscriptionManager.cachedIsUserAuthenticated)
        XCTAssertEqual(pixelHandler.backupPixels, [.backupRestored(.missingToken)])
    }

    func testExplicitSignOutWhileOff_thenOn_doesNotRestoreTheSignedOutAccount() async throws {
        try primaryStorage.saveTokenContainer(OAuthTokensFactory.makeTokenContainer(accessToken: "currentA", refreshToken: "currentR"))
        oAuthService.logoutError = nil
        await subscriptionManager.signOut(notifyUI: false, userInitiated: true)
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertNil(try backupStorage.getTokenContainer())

        isBackupEnabled = true
        await subscriptionManager.restoreMissingTokenIfPossible()

        XCTAssertEqual(oAuthService.refreshAccessTokenCallCount, 0)
        XCTAssertNil(try primaryStorage.getTokenContainer())
        XCTAssertNil(try backupStorage.getTokenContainer())
        XCTAssertFalse(subscriptionManager.cachedIsUserAuthenticated)
        XCTAssertEqual(pixelHandler.backupPixels.count, 0)
    }
}

private final class RecordingPixelHandler: SubscriptionPixelHandling {
    private(set) var handledPixels: [SubscriptionPixelType] = []

    var backupPixels: [SubscriptionPixelType] {
        handledPixels.filter {
            switch $0 {
            case .backupRestored, .backupRestoreFailed, .backupRenewed, .backupRenewalFailed, .backupKeychainError:
                return true
            default:
                return false
            }
        }
    }

    var automaticSignOutData: SubscriptionAutomaticSignOutPixelData? {
        handledPixels.lazy.compactMap { pixel -> SubscriptionAutomaticSignOutPixelData? in
            guard case .automaticSignOut(let data, _) = pixel else { return nil }
            return data
        }.first
    }

    func handle(pixel: SubscriptionPixelType) {
        handledPixels.append(pixel)
    }

    func handle(pixel: KeychainManager.Pixel) { }
}

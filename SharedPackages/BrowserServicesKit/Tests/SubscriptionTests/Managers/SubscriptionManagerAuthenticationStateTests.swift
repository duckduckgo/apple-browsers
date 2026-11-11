//
//  SubscriptionManagerAuthenticationStateTests.swift
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
@testable import Subscription
@_spi(Testing) @testable import Networking
import SubscriptionTestingUtilities

final class SubscriptionManagerAuthenticationStateTests: XCTestCase {

    private static let isUserAuthenticatedKey = "com.duckduckgo.subscription.isUserAuthenticated"
    private static let reconciledKey = "com.duckduckgo.subscription.isUserAuthenticatedReconciled"

    private var oAuthClient: MockOAuthClient!
    private var userDefaults: UserDefaults!
    private var cachingService: SubscriptionCachingServiceMock!
    private var restoreFlow: AppStoreRestoreFlowMock!
    private var pixelHandler: RecordingPixelHandler!
    private var signInNotifications = 0
    private var signOutNotifications = 0
    private var entitlementNotifications = 0
    private var observers: [NSObjectProtocol] = []

    override func setUp() {
        super.setUp()
        oAuthClient = MockOAuthClient()
        userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionAuthenticationStateTests.\(UUID().uuidString)")!
        cachingService = SubscriptionCachingServiceMock()
        restoreFlow = AppStoreRestoreFlowMock()
        pixelHandler = RecordingPixelHandler()
        signInNotifications = 0
        signOutNotifications = 0
        entitlementNotifications = 0
        observers = [
            NotificationCenter.default.addObserver(forName: .accountDidSignIn, object: nil, queue: nil) { [weak self] _ in
                self?.signInNotifications += 1
            },
            NotificationCenter.default.addObserver(forName: .accountDidSignOut, object: nil, queue: nil) { [weak self] _ in
                self?.signOutNotifications += 1
            },
            NotificationCenter.default.addObserver(forName: .entitlementsDidChange, object: nil, queue: nil) { [weak self] _ in
                self?.entitlementNotifications += 1
            }
        ]
    }

    override func tearDown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        oAuthClient = nil
        userDefaults = nil
        cachingService = nil
        restoreFlow = nil
        super.tearDown()
    }

    // MARK: - Stored flag

    func testWhenTokenIsDeletedFromKeychainThenUserStaysSignedIn() {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        let manager = makeManager()

        oAuthClient.internalCurrentTokenContainer = nil

        XCTAssertTrue(manager.isUserAuthenticated)
    }

    func testWhenRemoveLocalAccountThenUserStaysSignedInAndNoNotificationIsPosted() throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        let manager = makeManager()

        try manager.removeLocalAccount()

        XCTAssertNil(oAuthClient.internalCurrentTokenContainer)
        XCTAssertTrue(manager.isUserAuthenticated)
        XCTAssertEqual(signOutNotifications, 0)
    }

    // MARK: - Upgrade reconcile

    func testWhenUpgradingWithFlagFalseAndTokenPresentThenUserIsSignedIn() {
        userDefaults.set(false, forKey: Self.isUserAuthenticatedKey)
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        let manager = makeManager()

        XCTAssertTrue(manager.isUserAuthenticated)
        XCTAssertTrue(userDefaults.bool(forKey: Self.isUserAuthenticatedKey))
        XCTAssertEqual(signInNotifications, 0)
    }

    func testWhenUpgradingWithFlagTrueAndNoTokenThenUserStaysSignedIn() {
        userDefaults.set(true, forKey: Self.isUserAuthenticatedKey)

        let manager = makeManager()

        XCTAssertTrue(manager.isUserAuthenticated)
    }

    func testWhenUpgradingWithFlagFalseAndNoTokenThenUserStaysSignedOut() {
        userDefaults.set(false, forKey: Self.isUserAuthenticatedKey)

        let manager = makeManager()

        XCTAssertFalse(manager.isUserAuthenticated)
    }

    func testWhenUpgradingWithTokenReadErrorThenFlagIsKept() {
        userDefaults.set(false, forKey: Self.isUserAuthenticatedKey)
        oAuthClient.currentTokenContainerError = NSError(domain: "keychain", code: 1)

        let manager = makeManager()

        XCTAssertFalse(manager.isUserAuthenticated)
        XCTAssertFalse(userDefaults.bool(forKey: Self.reconciledKey))
    }

    func testWhenAlreadyReconciledThenInitKeepsTheFlag() {
        userDefaults.set(false, forKey: Self.isUserAuthenticatedKey)
        userDefaults.set(true, forKey: Self.reconciledKey)
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        let manager = makeManager()

        XCTAssertFalse(manager.isUserAuthenticated)
    }

    // MARK: - Rejected refresh

    func testWhenRefreshIsRejectedAndRecoveryFailsTemporarilyThenUserStaysSignedInWithTheDeadToken() async {
        let manager = await makeSignedInManager()
        let deadToken = oAuthClient.internalCurrentTokenContainer
        oAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(on: manager, backup: .failure(URLError(.timedOut)), appStoreError: URLError(.timedOut))

        await assertThrowsRetrievalFailure { try await manager.getTokenContainer(policy: .localValid) }

        XCTAssertEqual(oAuthClient.internalCurrentTokenContainer, deadToken)
        XCTAssertEqual(oAuthClient.removeLocalAccountCallCount, 0)
        XCTAssertTrue(manager.isUserAuthenticated)
        XCTAssertEqual(signOutNotifications, 0)
    }

    func testWhenRefreshIsRejectedAndRecoveryIsUnrecoverableThenUserIsSignedOut() async {
        let manager = await makeSignedInManager()
        oAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(on: manager, backup: nil, appStoreError: AppStoreRestoreFlowError.missingAccountOrTransactions)

        await assertThrowsNoTokenAvailable { try await manager.getTokenContainer(policy: .localValid) }

        XCTAssertNil(oAuthClient.internalCurrentTokenContainer)
        XCTAssertFalse(manager.isUserAuthenticated)
    }

    func testWhenRecoveryFailsWithUnknownErrorThenUserStaysSignedIn() async {
        let manager = await makeSignedInManager()
        oAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(on: manager, backup: nil, appStoreError: NSError(domain: "AppStore", code: 1))

        await assertThrowsRetrievalFailure { try await manager.getTokenContainer(policy: .localValid) }

        XCTAssertTrue(manager.isUserAuthenticated)
        XCTAssertEqual(oAuthClient.removeLocalAccountCallCount, 0)
    }

    // MARK: - Missing token

    func testWhenTokenIsMissingAndNoBackupThenUserIsSignedOutAndNotified() async {
        let manager = await makeSignedInManager()
        loseToken()
        installCoordinator(on: manager, backup: nil, appStoreError: nil)

        await assertThrowsNoTokenAvailable { try await manager.getTokenContainer(policy: .localValid) }

        XCTAssertFalse(manager.isUserAuthenticated)
        XCTAssertEqual(signOutNotifications, 1)
    }

    func testWhenMissingTokenRestoreIsDeferredThenUserStaysSignedInAndEntitlementsAreKept() async {
        let manager = await makeSignedInManager()
        let entitlements = manager.cachedUserEntitlements
        let entitlementNotificationsAfterSignIn = entitlementNotifications
        loseToken()
        installCoordinator(on: manager, backup: .failure(URLError(.timedOut)), appStoreError: nil)

        await assertThrowsRetrievalFailure { try await manager.getTokenContainer(policy: .localValid) }
        await assertThrowsRetrievalFailure { try await manager.getTokenContainer(policy: .localValid) }

        XCTAssertEqual(oAuthClient.restoreFromBackupCalls.count, 1)
        XCTAssertTrue(manager.isUserAuthenticated)
        XCTAssertFalse(entitlements.isEmpty)
        XCTAssertEqual(manager.cachedUserEntitlements, entitlements)
        XCTAssertEqual(entitlementNotifications, entitlementNotificationsAfterSignIn)
        XCTAssertEqual(signOutNotifications, 0)
    }

    func testWhenMissingTokenRestoreFailsTemporarilyThenSubscriptionCacheIsKept() async throws {
        let manager = await makeSignedInManager()
        let subscription = SubscriptionMockFactory.subscription(status: .autoRenewable)
        cachingService.cachedSubscription = subscription
        loseToken()
        installCoordinator(on: manager, backup: .failure(URLError(.timedOut)), appStoreError: nil)

        let result = try await manager.getSubscription(forceRefresh: true)

        XCTAssertEqual(result, subscription)
        XCTAssertFalse(cachingService.resetCalled)
    }

    func testWhenNoCoordinatorAndTokenIsMissingThenEntitlementsAreKept() async {
        // The browser process signed the user in; the VPN process only reads the shared flag
        userDefaults.set(true, forKey: Self.isUserAuthenticatedKey)
        let manager = await makeSignedInManager(process: .vpn)
        let entitlements = manager.cachedUserEntitlements
        loseToken()

        await assertThrowsNoTokenAvailable { try await manager.getTokenContainer(policy: .localValid) }

        XCTAssertFalse(entitlements.isEmpty)
        XCTAssertEqual(manager.cachedUserEntitlements, entitlements)
        XCTAssertTrue(manager.isUserAuthenticated)
    }

    func testWhenUserSignsOutDuringRecoveryThenUserStaysSignedOut() async {
        let manager = await makeSignedInManager()
        loseToken()
        let strategy = SigningOutStrategy()
        strategy.manager = manager
        manager.tokenRecoveryCoordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [strategy], missingTokenStrategies: [strategy])
        let signInsBefore = signInNotifications

        await assertThrowsNoTokenAvailable { try await manager.getTokenContainer(policy: .localValid) }

        XCTAssertFalse(manager.isUserAuthenticated)
        XCTAssertEqual(signInNotifications, signInsBefore)
    }

    func testWhenUserSignsInDuringAnUnrecoverableRestoreThenTheNewSessionIsKept() async {
        let manager = await makeSignedInManager()
        loseToken()
        let newToken = OAuthTokensFactory.makeValidTokenContainer()
        manager.tokenRecoveryCoordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [], missingTokenStrategies: [ClosureStrategy { [oAuthClient] _ in
            oAuthClient?.internalCurrentTokenContainer = newToken
            return .failed(TokenBackupError.expired)
        }])

        let result = try? await manager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(result, newToken)
        XCTAssertEqual(oAuthClient.internalCurrentTokenContainer, newToken)
        XCTAssertTrue(manager.isUserAuthenticated)
        XCTAssertEqual(signOutNotifications, 0)
    }

    func testWhenTokenCantBeReadRightAfterARestoreThenUserStaysSignedIn() async {
        let manager = await makeSignedInManager()
        loseToken()
        manager.tokenRecoveryCoordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [], missingTokenStrategies: [ClosureStrategy { [oAuthClient] _ in
            oAuthClient?.currentTokenContainerError = NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInteractionNotAllowed))
            return .recovered
        }])

        await assertThrowsRetrievalFailure { try await manager.getTokenContainer(policy: .localValid) }

        XCTAssertTrue(manager.isUserAuthenticated)
        XCTAssertEqual(signOutNotifications, 0)
        XCTAssertEqual(oAuthClient.removeLocalAccountCallCount, 0)
    }

    func testWhenATokenIsStoredWhileTheMissingOneIsReadThenTheStoredTokenIsReturned() async throws {
        let manager = await makeSignedInManager()
        loseToken()
        installCoordinator(on: manager, backup: nil, appStoreError: nil)
        let storedMeanwhile = OAuthTokensFactory.makeValidTokenContainer()
        oAuthClient.onGetTokens = { [oAuthClient] in
            oAuthClient?.internalCurrentTokenContainer = storedMeanwhile
        }

        let result = try await manager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(result, storedMeanwhile)
        XCTAssertTrue(manager.isUserAuthenticated)
    }

    func testWhenRejectedRefreshRecoveryIsPendingThenTheInvalidTokenPixelFiresOncePerEpisode() async {
        let manager = await makeSignedInManager()
        oAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        installCoordinator(on: manager, backup: .failure(URLError(.timedOut)), appStoreError: URLError(.timedOut))

        await assertThrowsRetrievalFailure { try await manager.getTokenContainer(policy: .localValid) }
        await assertThrowsRetrievalFailure { try await manager.getTokenContainer(policy: .localValid) }

        XCTAssertEqual(pixelHandler.handledPixels.filter { $0 == .invalidRefreshToken }.count, 1)
        XCTAssertEqual(oAuthClient.restoreFromBackupCalls.count, 1)
    }

    // MARK: - Foreground restore

    func testWhenForegroundRestoreIsUnrecoverableThenUserIsSignedOut() async {
        let manager = await makeSignedInManager()
        oAuthClient.internalCurrentTokenContainer = nil
        installCoordinator(on: manager, backup: nil, appStoreError: nil)

        await manager.restoreMissingTokenIfPossible()

        XCTAssertFalse(manager.isUserAuthenticated)
        XCTAssertEqual(signOutNotifications, 1)
    }

    func testWhenForegroundRestoreIsPendingThenUserStaysSignedIn() async {
        let manager = await makeSignedInManager()
        oAuthClient.internalCurrentTokenContainer = nil
        installCoordinator(on: manager, backup: .failure(URLError(.timedOut)), appStoreError: nil)

        await manager.restoreMissingTokenIfPossible()

        XCTAssertTrue(manager.isUserAuthenticated)
        XCTAssertEqual(signOutNotifications, 0)
    }

    // MARK: - Helpers

    /// Signs in through a successful token request with a token that carries entitlements.
    private func makeSignedInManager(process: SubscriptionProcess = .browser) async -> DefaultSubscriptionManager {
        let token = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        oAuthClient.internalCurrentTokenContainer = token
        oAuthClient.getTokensResponse = .success(token)
        let manager = makeManager(process: process)
        _ = try? await manager.getTokenContainer(policy: .localValid)
        return manager
    }

    /// Removes the stored token the way a keychain loss does, without a sign-out.
    private func loseToken() {
        oAuthClient.internalCurrentTokenContainer = nil
        oAuthClient.getTokensResponse = .failure(OAuthClientError.missingTokenContainer)
    }

    private func installCoordinator(on manager: DefaultSubscriptionManager, backup: Result<TokenContainer, Error>?, appStoreError: Error?) {
        oAuthClient.restoreFromBackupResponse = backup
        restoreFlow.restoreSubscriptionAfterExpiredRefreshTokenError = appStoreError
        let backupRecovery = BackupTokenRecovery(oAuthClient: oAuthClient, pixelHandler: RecordingPixelHandler())
        let appStoreRecovery = AppStoreTokenRecovery(purchasePlatform: .appStore, restoreFlow: restoreFlow)
        manager.tokenRecoveryCoordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [backupRecovery, appStoreRecovery],
                                                                    missingTokenStrategies: [backupRecovery])
    }

    private func assertThrowsNoTokenAvailable(_ body: () async throws -> TokenContainer, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await body()
            XCTFail("Error expected", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable, file: file, line: line)
        }
    }

    private func assertThrowsRetrievalFailure(_ body: () async throws -> TokenContainer, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await body()
            XCTFail("Error expected", file: file, line: line)
        } catch {
            guard case .errorRetrievingTokenContainer = error as? SubscriptionManagerError else {
                return XCTFail("Expected errorRetrievingTokenContainer, got \(error)", file: file, line: line)
            }
        }
    }

    private func makeManager(process: SubscriptionProcess = .browser) -> DefaultSubscriptionManager {
        DefaultSubscriptionManager(oAuthClient: oAuthClient,
                                   userDefaults: userDefaults,
                                   subscriptionEndpointService: SubscriptionEndpointServiceMock(),
                                   subscriptionCachingService: cachingService,
                                   subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
                                   process: process,
                                   pixelHandler: pixelHandler,
                                   initForPurchase: false)
    }
}

private final class RecordingPixelHandler: SubscriptionPixelHandling {
    private(set) var handledPixels: [SubscriptionPixelType] = []

    func handle(pixel: SubscriptionPixelType) {
        handledPixels.append(pixel)
    }

    func handle(pixel: KeychainManager.Pixel) {}
}

/// Signs the user out while it runs, then reports that the session changed.
private final class SigningOutStrategy: TokenRecoveryStrategy {
    let method: TokenRecoveryMethod = .backup
    weak var manager: DefaultSubscriptionManager?

    func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryResult {
        await manager?.signOut(notifyUI: true, userInitiated: true)
        return .sessionChanged
    }
}

/// Runs a closure as its recovery.
private struct ClosureStrategy: TokenRecoveryStrategy {
    let method: TokenRecoveryMethod = .backup
    let block: (TokenRecoveryContext) async -> TokenRecoveryResult

    init(_ block: @escaping (TokenRecoveryContext) async -> TokenRecoveryResult) {
        self.block = block
    }

    func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryResult {
        await block(context)
    }
}

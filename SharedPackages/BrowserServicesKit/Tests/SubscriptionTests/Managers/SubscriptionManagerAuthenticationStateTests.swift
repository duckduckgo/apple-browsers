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
    private var signInNotifications = 0
    private var signOutNotifications = 0
    private var observers: [NSObjectProtocol] = []

    override func setUp() {
        super.setUp()
        oAuthClient = MockOAuthClient()
        userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionAuthenticationStateTests.\(UUID().uuidString)")!
        signInNotifications = 0
        signOutNotifications = 0
        observers = [
            NotificationCenter.default.addObserver(forName: .accountDidSignIn, object: nil, queue: nil) { [weak self] _ in
                self?.signInNotifications += 1
            },
            NotificationCenter.default.addObserver(forName: .accountDidSignOut, object: nil, queue: nil) { [weak self] _ in
                self?.signOutNotifications += 1
            }
        ]
    }

    override func tearDown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        oAuthClient = nil
        userDefaults = nil
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

    // MARK: - Helpers

    private func makeManager(process: SubscriptionProcess = .browser) -> DefaultSubscriptionManager {
        DefaultSubscriptionManager(oAuthClient: oAuthClient,
                                   userDefaults: userDefaults,
                                   subscriptionEndpointService: SubscriptionEndpointServiceMock(),
                                   subscriptionCachingService: SubscriptionCachingServiceMock(),
                                   subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
                                   process: process,
                                   pixelHandler: RecordingPixelHandler(),
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

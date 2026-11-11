//
//  SubscriptionManagerProcessTests.swift
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

final class SubscriptionManagerProcessTests: XCTestCase {

    private static let isUserAuthenticatedKey = "com.duckduckgo.subscription.isUserAuthenticated"

    private var oAuthClient: MockOAuthClient!
    private var pixelHandler: RecordingPixelHandler!
    private var userDefaults: UserDefaults!
    private var signOutNotifications = 0
    private var signOutObserver: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        oAuthClient = MockOAuthClient()
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        pixelHandler = RecordingPixelHandler()
        userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionProcessTests.\(UUID().uuidString)")!
        userDefaults.set(true, forKey: Self.isUserAuthenticatedKey)
        signOutNotifications = 0
        signOutObserver = NotificationCenter.default.addObserver(forName: .accountDidSignOut, object: nil, queue: nil) { [weak self] _ in
            self?.signOutNotifications += 1
        }
    }

    override func tearDown() {
        if let signOutObserver {
            NotificationCenter.default.removeObserver(signOutObserver)
        }
        signOutObserver = nil
        oAuthClient = nil
        pixelHandler = nil
        userDefaults = nil
        super.tearDown()
    }

    // MARK: - VPN and PIR processes keep the token

    func testWhenVPNProcessRefreshIsRejectedThenTokenIsKeptAndUserIsNotSignedOut() async {
        oAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))

        await assertTokenKeptAndNotSignedOut(makeManager(process: .vpn))
    }

    func testWhenVPNProcessAccountIsUnknownThenTokenIsKeptAndUserIsNotSignedOut() async {
        oAuthClient.getTokensResponse = .failure(OAuthClientError.unknownAccount)

        await assertTokenKeptAndNotSignedOut(makeManager(process: .vpn))
    }

    func testWhenPIRProcessRefreshIsRejectedThenTokenIsKeptAndUserIsNotSignedOut() async {
        oAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))

        await assertTokenKeptAndNotSignedOut(makeManager(process: .pir))
    }

    func testWhenPIRProcessAccountIsUnknownThenTokenIsKeptAndUserIsNotSignedOut() async {
        oAuthClient.getTokensResponse = .failure(OAuthClientError.unknownAccount)

        await assertTokenKeptAndNotSignedOut(makeManager(process: .pir))
    }

    // MARK: - Signing out

    func testWhenBrowserProcessAccountIsUnknownThenUserIsSignedOut() async {
        oAuthClient.getTokensResponse = .failure(OAuthClientError.unknownAccount)
        let manager = makeManager(process: .browser)

        _ = try? await manager.getTokenContainer(policy: .localValid)

        XCTAssertNil(oAuthClient.internalCurrentTokenContainer)
        XCTAssertFalse(userDefaults.bool(forKey: Self.isUserAuthenticatedKey))
        XCTAssertNotNil(automaticSignOutPixel())
    }

    func testWhenVPNProcessSignsOutExplicitlyThenTokenIsRemovedAndTheSharedFlagIsUntouched() async {
        let manager = makeManager(process: .vpn)

        await manager.signOut(notifyUI: true, userInitiated: false)

        XCTAssertEqual(oAuthClient.logoutCallCount, 1)
        XCTAssertNil(oAuthClient.internalCurrentTokenContainer)
        XCTAssertTrue(userDefaults.bool(forKey: Self.isUserAuthenticatedKey))
    }

    func testWhenVPNProcessGetsATokenThenTheSharedFlagIsUntouched() async throws {
        userDefaults.set(false, forKey: Self.isUserAuthenticatedKey)
        let token = try XCTUnwrap(oAuthClient.internalCurrentTokenContainer)
        oAuthClient.getTokensResponse = .success(token)
        let manager = makeManager(process: .vpn)

        _ = try await manager.getTokenContainer(policy: .localValid)

        XCTAssertFalse(userDefaults.bool(forKey: Self.isUserAuthenticatedKey))
        XCTAssertFalse(userDefaults.bool(forKey: "com.duckduckgo.subscription.isUserAuthenticatedReconciled"))
    }

    // MARK: - Helpers

    private func makeManager(process: SubscriptionProcess) -> DefaultSubscriptionManager {
        DefaultSubscriptionManager(oAuthClient: oAuthClient,
                                   userDefaults: userDefaults,
                                   subscriptionEndpointService: SubscriptionEndpointServiceMock(),
                                   subscriptionCachingService: SubscriptionCachingServiceMock(),
                                   subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
                                   process: process,
                                   pixelHandler: pixelHandler,
                                   initForPurchase: false)
    }

    private func assertTokenKeptAndNotSignedOut(_ manager: DefaultSubscriptionManager, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await manager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SubscriptionManagerError, .noTokenAvailable, file: file, line: line)
        }
        XCTAssertNotNil(oAuthClient.internalCurrentTokenContainer, file: file, line: line)
        XCTAssertEqual(oAuthClient.removeLocalAccountCallCount, 0, file: file, line: line)
        XCTAssertEqual(oAuthClient.logoutCallCount, 0, file: file, line: line)
        XCTAssertTrue(userDefaults.bool(forKey: Self.isUserAuthenticatedKey), file: file, line: line)
        XCTAssertNil(automaticSignOutPixel(), file: file, line: line)
        XCTAssertEqual(signOutNotifications, 0, file: file, line: line)
    }

    private func automaticSignOutPixel() -> SubscriptionPixelType? {
        pixelHandler.handledPixels.first {
            if case .automaticSignOut = $0 { return true }
            return false
        }
    }
}

private final class RecordingPixelHandler: SubscriptionPixelHandling {
    private(set) var handledPixels: [SubscriptionPixelType] = []

    func handle(pixel: SubscriptionPixelType) {
        handledPixels.append(pixel)
    }

    func handle(pixel: KeychainManager.Pixel) {}
}

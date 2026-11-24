//
//  SubscriptionManagerRecoveryLoopGuardTests.swift
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
import FoundationExtensions
@testable import Subscription
@_spi(Testing) @testable import Networking
import SubscriptionTestingUtilities

final class SubscriptionManagerRecoveryLoopGuardTests: XCTestCase {

    private var subscriptionManager: DefaultSubscriptionManager!
    private var oAuthClient: MockOAuthClient!
    private var pixelHandler: RecordingSubscriptionPixelHandler!
    private var recovery: StoringTokenRecovery!
    private var currentDate = Date()

    private let rejectedRefresh = OAuthClientError.invalidTokenRequest(.reused)

    override func setUp() {
        super.setUp()
        currentDate = Date()
        oAuthClient = MockOAuthClient()
        pixelHandler = RecordingSubscriptionPixelHandler()
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        subscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: StorePurchaseManagerMock(),
            oAuthClient: oAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: SubscriptionEndpointServiceMock(),
            subscriptionCachingService: SubscriptionCachingServiceMock(),
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
            pixelHandler: pixelHandler,
            initForPurchase: false,
            clockSkewMonitor: ClockSkewMonitor(now: { [unowned self] in self.currentDate }),
            invalidTokenRecoveryInterval: .minutes(1),
            now: { [unowned self] in self.currentDate }
        )
        recovery = StoringTokenRecovery(oAuthClient: oAuthClient)
        subscriptionManager.tokenRecoveryCoordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [recovery],
                                                                                missingTokenStrategies: [recovery])
    }

    override func tearDown() {
        subscriptionManager = nil
        oAuthClient = nil
        pixelHandler = nil
        recovery = nil
        super.tearDown()
    }

    // MARK: - Loop guard

    func testRefreshRejectedAgainRightAfterRecovery_KeepsTheTokenAndDoesNotRecoverAgain() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)

        let recovered = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(recovered.refreshToken, "recoveredR1")

        // The server rejects the recovered token too, a few seconds later
        currentDate = currentDate.addingTimeInterval(5)
        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Expected the request to fail")
        } catch SubscriptionManagerError.errorRetrievingTokenContainer(let error) {
            XCTAssertEqual(error as? OAuthClientError, rejectedRefresh)
        }

        XCTAssertEqual(recovery.calls, 1)
        XCTAssertEqual(oAuthClient.internalCurrentTokenContainer?.refreshToken, "recoveredR1")
        XCTAssertEqual(oAuthClient.removeLocalAccountCallCount, 0)
        XCTAssertFalse(pixelHandler.handledPixels.contains(.invalidRefreshTokenSignedOut))
        XCTAssertEqual(pixelHandler.deferredPixelCount, 1)
    }

    func testRepeatedRejectionsWithinTheInterval_RecoverOncePerInterval() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
        for _ in 0..<20 {
            currentDate = currentDate.addingTimeInterval(1)
            _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)
        }
        XCTAssertEqual(recovery.calls, 1)
        XCTAssertEqual(pixelHandler.deferredPixelCount, 20)

        // Once the interval has passed, the next rejection recovers again
        currentDate = currentDate.addingTimeInterval(.minutes(1))
        let recoveredAgain = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(recovery.calls, 2)
        XCTAssertEqual(recoveredAgain.refreshToken, "recoveredR2")
    }

    func testRecoveryReportsSuccessButLeavesTheRejectedToken_SignsOutAndDoesNotDeferTheNextRecovery() async throws {
        let dead = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.internalCurrentTokenContainer = dead
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)
        recovery.storesNewToken = false

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Expected the request to fail")
        } catch SubscriptionManagerError.noTokenAvailable {}

        XCTAssertNil(oAuthClient.internalCurrentTokenContainer)
        XCTAssertTrue(pixelHandler.handledPixels.contains(.invalidRefreshTokenSignedOut))
        XCTAssertEqual(pixelHandler.automaticSignOutErrors.count, 1)

        // A new session whose refresh is rejected moments later runs the recovery instead of deferring it
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "newA", refreshToken: "newR")
        recovery.storesNewToken = true
        currentDate = currentDate.addingTimeInterval(5)
        let recovered = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(recovery.calls, 2)
        XCTAssertEqual(recovered.refreshToken, "recoveredR2")
        XCTAssertEqual(pixelHandler.deferredPixelCount, 0)
    }

    func testSignOutAfterARecovery_DoesNotDeferTheRecoveryOfTheNextSession() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)
        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        await subscriptionManager.signOut(notifyUI: false, userInitiated: true)
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "otherA", refreshToken: "otherR")
        currentDate = currentDate.addingTimeInterval(5)
        let recovered = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(recovery.calls, 2)
        XCTAssertEqual(recovered.refreshToken, "recoveredR2")
        XCTAssertEqual(pixelHandler.deferredPixelCount, 0)
    }

    func testMissingTokenRightAfterARecovery_IsStillRestored() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)
        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        oAuthClient.internalCurrentTokenContainer = nil
        oAuthClient.getTokensResponse = .failure(OAuthClientError.missingTokenContainer)
        currentDate = currentDate.addingTimeInterval(5)
        let restored = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(recovery.calls, 2)
        XCTAssertEqual(restored.refreshToken, "recoveredR2")
    }

    // MARK: - Clock skew

    func testRecoveredTokenIssuedHoursBeforeTheDeviceTime_ReportsTheDeviceClockAhead() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)
        recovery.issuedAt = { [unowned self] in self.currentDate.addingTimeInterval(-TimeInterval.hours(2)) }

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(subscriptionManager.clockSkewMonitor.current, .ahead1HourTo1Day)
        XCTAssertEqual(pixelHandler.recoveredPixelSkews, [.ahead1HourTo1Day])
    }

    func testDeferredRecovery_ReportsTheSkewMeasuredFromTheRecoveredToken() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)
        recovery.issuedAt = { [unowned self] in self.currentDate.addingTimeInterval(-TimeInterval.days(2)) }

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
        currentDate = currentDate.addingTimeInterval(5)
        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertTrue(pixelHandler.handledPixels.contains(.invalidRefreshTokenRecoveryDeferred(.aheadOver1Day)))
    }

    func testRefreshReturnsANewToken_MeasuresTheSkewFromIt() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "oldA", refreshToken: "oldR")
        let refreshed = OAuthTokensFactory.makeTokenContainer(accessToken: "newA",
                                                              refreshToken: "newR",
                                                              accessTokenIssuedAt: currentDate.addingTimeInterval(.days(2)))
        oAuthClient.getTokensResponse = .success(refreshed)

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(subscriptionManager.clockSkewMonitor.current, .behindOver1Day)
    }

    func testStoredTokenReturnedUnchanged_DoesNotMeasureTheSkew() async throws {
        let stored = OAuthTokensFactory.makeTokenContainer(accessToken: "oldA",
                                                           refreshToken: "oldR",
                                                           accessTokenIssuedAt: currentDate.addingTimeInterval(-TimeInterval.hours(3)))
        oAuthClient.internalCurrentTokenContainer = stored
        oAuthClient.getTokensResponse = .success(stored)

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertNil(subscriptionManager.clockSkewMonitor.current)
    }
}

/// A recovery strategy that stores a new token container on each call, issued at `issuedAt`.
private final class StoringTokenRecovery: TokenRecoveryStrategy {
    let method: TokenRecoveryMethod = .appStore
    private let oAuthClient: MockOAuthClient
    private(set) var calls = 0
    /// When false, the strategy reports success without storing anything.
    var storesNewToken = true
    var issuedAt: () -> Date = { Date() }

    init(oAuthClient: MockOAuthClient) {
        self.oAuthClient = oAuthClient
    }

    func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryResult {
        calls += 1
        if storesNewToken {
            oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "recoveredA\(calls)",
                                                                                              refreshToken: "recoveredR\(calls)",
                                                                                              accessTokenIssuedAt: issuedAt())
        }
        return .recovered
    }
}

private final class RecordingSubscriptionPixelHandler: SubscriptionPixelHandling {
    private(set) var handledPixels: [SubscriptionPixelType] = []

    var deferredPixelCount: Int {
        handledPixels.filter {
            if case .invalidRefreshTokenRecoveryDeferred = $0 { return true }
            return false
        }.count
    }

    var recoveredPixelSkews: [ClockSkew?] {
        handledPixels.compactMap {
            if case .invalidRefreshTokenRecovered(_, let skew) = $0 { return skew }
            return nil
        }
    }

    var automaticSignOutErrors: [Error] {
        handledPixels.compactMap {
            if case .automaticSignOut(_, let error) = $0 { return error }
            return nil
        }
    }

    func handle(pixel: SubscriptionPixelType) {
        handledPixels.append(pixel)
    }

    func handle(pixel: KeychainManager.Pixel) {}
}

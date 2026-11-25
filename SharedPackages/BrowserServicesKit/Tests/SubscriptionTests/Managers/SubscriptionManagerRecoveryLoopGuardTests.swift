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
    private var subscriptionCachingService: SubscriptionCachingServiceMock!
    private var pixelHandler: RecordingSubscriptionPixelHandler!
    private var recovery: StoringTokenRecovery!
    private var clockSkewMonitor: ClockSkewMonitor!
    private var currentDate = Date()
    private var currentUptime: TimeInterval = 1000

    private let rejectedRefresh = OAuthClientError.invalidTokenRequest(.reused)

    override func setUp() {
        super.setUp()
        currentDate = Date()
        currentUptime = 1000
        oAuthClient = MockOAuthClient()
        subscriptionCachingService = SubscriptionCachingServiceMock()
        pixelHandler = RecordingSubscriptionPixelHandler()
        clockSkewMonitor = ClockSkewMonitor(now: { [unowned self] in self.currentDate })
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        subscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: StorePurchaseManagerMock(),
            oAuthClient: oAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: SubscriptionEndpointServiceMock(),
            subscriptionCachingService: subscriptionCachingService,
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
            pixelHandler: pixelHandler,
            initForPurchase: false,
            clockSkewMonitor: clockSkewMonitor,
            invalidTokenRecoveryInterval: .minutes(1),
            uptime: { [unowned self] in self.currentUptime }
        )
        recovery = StoringTokenRecovery(oAuthClient: oAuthClient)
        subscriptionManager.tokenRecoveryCoordinator = TokenRecoveryCoordinator(invalidTokenStrategies: [recovery],
                                                                                missingTokenStrategies: [recovery])
    }

    override func tearDown() {
        subscriptionManager = nil
        oAuthClient = nil
        subscriptionCachingService = nil
        pixelHandler = nil
        recovery = nil
        clockSkewMonitor = nil
        super.tearDown()
    }

    // MARK: - Loop guard

    func testRefreshRejectedAgainRightAfterRecovery_KeepsTheTokenAndDoesNotRecoverAgain() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)

        let recovered = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(recovered.refreshToken, "recoveredR1")

        // The server rejects the recovered token too, a few seconds later
        currentUptime += 5
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
            currentUptime += 1
            _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)
        }
        XCTAssertEqual(recovery.calls, 1)
        XCTAssertEqual(pixelHandler.deferredPixelCount, 20)

        // Once the interval has passed, the next rejection recovers again
        currentUptime += .minutes(1)
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
        currentUptime += 5
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
        currentUptime += 5
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
        currentUptime += 5
        let restored = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(recovery.calls, 2)
        XCTAssertEqual(restored.refreshToken, "recoveredR2")
    }

    func testDeviceClockChangesAfterARecovery_DoNotChangeTheDeferral() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)
        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        // The device clock is set back two hours: the next rejection within the minute is still deferred
        currentDate = currentDate.addingTimeInterval(-TimeInterval.hours(2))
        currentUptime += 5
        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(recovery.calls, 1)
        XCTAssertEqual(pixelHandler.deferredPixelCount, 1)

        // The device clock is set forward a day: a rejection is still deferred until a minute of uptime has passed
        currentDate = currentDate.addingTimeInterval(.days(1))
        currentUptime += 5
        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(recovery.calls, 1)
        XCTAssertEqual(pixelHandler.deferredPixelCount, 2)

        currentUptime += .minutes(1)
        let recoveredAgain = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(recovery.calls, 2)
        XCTAssertEqual(recoveredAgain.refreshToken, "recoveredR2")
    }

    func testConcurrentRequestRejectedWhileAnotherRecoveryStoresAToken_ReturnsTheStoredTokenInsteadOfDeferring() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)
        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        // A second request starts from the dead token. Its refresh is rejected, and another request's recovery stores a fresh token
        // while it snapshots the failed request's state.
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        let concurrentlyRecovered = OAuthTokensFactory.makeTokenContainer(accessToken: "concurrentA", refreshToken: "concurrentR")
        subscriptionCachingService.onGet = { [unowned self] in
            self.oAuthClient.internalCurrentTokenContainer = concurrentlyRecovered
        }
        currentUptime += 5
        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(result, concurrentlyRecovered)
        XCTAssertEqual(recovery.calls, 1)
        XCTAssertEqual(pixelHandler.deferredPixelCount, 0)
        XCTAssertEqual(oAuthClient.removeLocalAccountCallCount, 0)
    }

    // MARK: - Clock skew

    func testRecoveryWhoseServerResponsesShowTheClockAhead_ReportsTheSkewOnTheRecoveredPixel() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)
        recovery.onRecover = { [unowned self] in
            // The auth service sees the server's time in the recovery's responses
            self.clockSkewMonitor.measure(serverDate: self.currentDate.addingTimeInterval(-TimeInterval.hours(2)))
        }

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(pixelHandler.recoveredPixelSkews, [.ahead1HourTo1Day])
    }

    func testDeferredRecovery_ReportsTheLastMeasuredSkew() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "deadA", refreshToken: "deadR")
        oAuthClient.getTokensResponse = .failure(rejectedRefresh)
        recovery.onRecover = { [unowned self] in
            self.clockSkewMonitor.measure(serverDate: self.currentDate.addingTimeInterval(-TimeInterval.days(2)))
        }

        _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
        currentUptime += 5
        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertTrue(pixelHandler.handledPixels.contains(.invalidRefreshTokenRecoveryDeferred(.aheadOver1Day)))
    }

    func testTokensFailingVerificationOnAClockFarAhead_ReportTheSkewOnTheGetTokensErrorPixel() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "storedA", refreshToken: "storedR")
        // The refresh response arrives, so its Date header is measured, but the tokens fail verification on the device clock
        oAuthClient.onGetTokens = { [unowned self] in
            self.clockSkewMonitor.measure(serverDate: self.currentDate.addingTimeInterval(-TimeInterval.days(3)))
        }
        oAuthClient.getTokensResponse = .failure(NSError(domain: "JWTKit.JWTError", code: 0))

        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(pixelHandler.getTokensErrorSkews, [.aheadOver1Day])
    }

    func testGetTokensErrorBeforeAnyServerResponse_ReportsNoSkew() async throws {
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "storedA", refreshToken: "storedR")
        oAuthClient.getTokensResponse = .failure(URLError(.notConnectedToInternet))

        _ = try? await subscriptionManager.getTokenContainer(policy: .localValid)

        XCTAssertEqual(pixelHandler.getTokensErrorSkews, [nil])
    }
}

/// A recovery strategy that stores a new token container on each call.
private final class StoringTokenRecovery: TokenRecoveryStrategy {
    let method: TokenRecoveryMethod = .appStore
    private let oAuthClient: MockOAuthClient
    private(set) var calls = 0
    /// When false, the strategy reports success without storing anything.
    var storesNewToken = true
    /// Called at the start of each recovery.
    var onRecover: (() -> Void)?

    init(oAuthClient: MockOAuthClient) {
        self.oAuthClient = oAuthClient
    }

    func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryResult {
        calls += 1
        onRecover?()
        if storesNewToken {
            oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "recoveredA\(calls)",
                                                                                              refreshToken: "recoveredR\(calls)")
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

    var getTokensErrorSkews: [ClockSkew?] {
        handledPixels.compactMap {
            if case .getTokensError(_, _, let skew) = $0 { return skew }
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

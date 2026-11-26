//
//  SubscriptionManagerClockSkewTests.swift
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

final class SubscriptionManagerClockSkewTests: XCTestCase {

    private var subscriptionManager: DefaultSubscriptionManager!
    private var oAuthClient: MockOAuthClient!
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
        pixelHandler = RecordingSubscriptionPixelHandler()
        clockSkewMonitor = ClockSkewMonitor(now: { [unowned self] in self.currentDate })
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
        pixelHandler = nil
        recovery = nil
        clockSkewMonitor = nil
        super.tearDown()
    }

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
    /// Called at the start of each recovery.
    var onRecover: (() -> Void)?

    init(oAuthClient: MockOAuthClient) {
        self.oAuthClient = oAuthClient
    }

    func recover(_ context: TokenRecoveryContext) async -> TokenRecoveryResult {
        calls += 1
        onRecover?()
        oAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeTokenContainer(accessToken: "recoveredA\(calls)",
                                                                                          refreshToken: "recoveredR\(calls)")
        return .recovered
    }
}

private final class RecordingSubscriptionPixelHandler: SubscriptionPixelHandling {
    private(set) var handledPixels: [SubscriptionPixelType] = []

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

    func handle(pixel: SubscriptionPixelType) {
        handledPixels.append(pixel)
    }

    func handle(pixel: KeychainManager.Pixel) {}
}

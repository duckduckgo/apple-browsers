//
//  SubscriptionUserScriptHandlerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

@testable import Subscription
import SubscriptionTestingUtilities
import UserScript
import WebKit
import XCTest

final class SubscriptionUserScriptHandlerTests: XCTestCase {

    var subscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    var handler: SubscriptionUserScriptHandler!

    override func setUp() async throws {
        subscriptionManager = SubscriptionAuthV1toV2BridgeMock()
        handler = .init(platform: .ios, subscriptionManager: subscriptionManager)
    }

    func testWhenInitializedForIOSThenHandshakeReportsIOS() async throws {
        handler = .init(platform: .ios, subscriptionManager: subscriptionManager)
        let handshake = try await handler.handshake(params: [], message: WKScriptMessage())
        XCTAssertEqual(handshake.platform, .ios)
    }

    func testWhenInitializedForMacOSThenHandshakeReportsMacOS() async throws {
        handler = .init(platform: .macos, subscriptionManager: subscriptionManager)
        let handshake = try await handler.handshake(params: [], message: WKScriptMessage())
        XCTAssertEqual(handshake.platform, .macos)
    }

    func testThatHandshakeReportsSupportForSubcriptionDetailsMessage() async throws {
        handler = .init(platform: .ios, subscriptionManager: subscriptionManager)
        let handshake = try await handler.handshake(params: [], message: WKScriptMessage())
        XCTAssertEqual(handshake.availableMessages, [.subscriptionDetails])
    }

    func testWhenSubscriptionFailsToBeFetchedThenSubscriptionDetailsReturnsNotSubscribedState() async throws {
        struct SampleError: Error {}
        subscriptionManager.returnSubscription = .failure(SampleError())
        handler = .init(platform: .ios, subscriptionManager: subscriptionManager)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: WKScriptMessage())
        XCTAssertEqual(subscriptionDetails, .init(isSubscribed: false, billingPeriod: nil, startedAt: nil, expiresOrRenewsAt: nil, paymentPlatform: nil, status: nil))
    }

    func testWhenSubscriptionIsActiveThenSubscriptionDetailsReturnsSubscriptionData() async throws {
        let startedAt = Date().startOfDay
        let expiresAt = Date().startOfDay.daysAgo(-10)
        let subscription = PrivacyProSubscription(
            productId: "test",
            name: "test",
            billingPeriod: .yearly,
            startedAt: startedAt,
            expiresOrRenewsAt: expiresAt,
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: []
        )

        subscriptionManager.returnSubscription = .success(subscription)
        handler = .init(platform: .ios, subscriptionManager: subscriptionManager)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: WKScriptMessage())
        XCTAssertEqual(subscriptionDetails, .init(
            isSubscribed: true,
            billingPeriod: subscription.billingPeriod.rawValue,
            startedAt: Int(startedAt.timeIntervalSince1970 * 1000),
            expiresOrRenewsAt: Int(expiresAt.timeIntervalSince1970 * 1000),
            paymentPlatform: subscription.platform.rawValue,
            status: subscription.status.rawValue
        ))
    }

    func testWhenSubscriptionIsExpiredThenSubscriptionDetailsReturnsSubscriptionData() async throws {
        let subscription = PrivacyProSubscription(status: .expired)

        subscriptionManager.returnSubscription = .success(subscription)
        handler = .init(platform: .ios, subscriptionManager: subscriptionManager)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: WKScriptMessage())
        XCTAssertTrue(subscriptionDetails.isSubscribed)
    }

    func testWhenSubscriptionIsInactiveThenSubscriptionDetailsReturnsSubscriptionData() async throws {
        let subscription = PrivacyProSubscription(status: .inactive)

        subscriptionManager.returnSubscription = .success(subscription)
        handler = .init(platform: .ios, subscriptionManager: subscriptionManager)
        let subscriptionDetails = try await handler.subscriptionDetails(params: [], message: WKScriptMessage())
        XCTAssertTrue(subscriptionDetails.isSubscribed)
    }
}

private extension PrivacyProSubscription {
    init(status: Status) {
        self.init(productId: "test", name: "test", billingPeriod: .monthly, startedAt: Date(), expiresOrRenewsAt: Date(), platform: .apple, status: status, activeOffers: [])
    }
}

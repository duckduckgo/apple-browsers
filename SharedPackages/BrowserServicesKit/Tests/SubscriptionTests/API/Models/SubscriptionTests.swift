//
//  SubscriptionTests.swift
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
@testable import Subscription
import SubscriptionTestingUtilities

final class SubscriptionTests: XCTestCase {

    func testEquality() throws {
        let a = DuckDuckGoSubscription(productId: "1",
                                name: "a",
                                billingPeriod: .monthly,
                                startedAt: Date(timeIntervalSince1970: 1000),
                                expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                platform: .apple,
                                status: .autoRenewable,
                                activeOffers: [DuckDuckGoSubscription.Offer(type: .trial)])
        let b = DuckDuckGoSubscription(productId: "1",
                                name: "a",
                                billingPeriod: .monthly,
                                startedAt: Date(timeIntervalSince1970: 1000),
                                expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                platform: .apple,
                                status: .autoRenewable,
                                activeOffers: [DuckDuckGoSubscription.Offer(type: .trial)])
        let c = DuckDuckGoSubscription(productId: "2",
                                name: "a",
                                billingPeriod: .monthly,
                                startedAt: Date(timeIntervalSince1970: 1000),
                                expiresOrRenewsAt: Date(timeIntervalSince1970: 2000),
                                platform: .apple,
                                status: .autoRenewable,
                                activeOffers: [])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testIfSubscriptionWithGivenStatusIsActive() throws {
        let autoRenewableSubscription = DuckDuckGoSubscription.make(withStatus: .autoRenewable)
        XCTAssertTrue(autoRenewableSubscription.isActive)

        let notAutoRenewableSubscription = DuckDuckGoSubscription.make(withStatus: .notAutoRenewable)
        XCTAssertTrue(notAutoRenewableSubscription.isActive)

        let gracePeriodSubscription = DuckDuckGoSubscription.make(withStatus: .gracePeriod)
        XCTAssertTrue(gracePeriodSubscription.isActive)

        let inactiveSubscription = DuckDuckGoSubscription.make(withStatus: .inactive)
        XCTAssertFalse(inactiveSubscription.isActive)

        let expiredSubscription = DuckDuckGoSubscription.make(withStatus: .expired)
        XCTAssertFalse(expiredSubscription.isActive)

        let unknownSubscription = DuckDuckGoSubscription.make(withStatus: .unknown)
        XCTAssertTrue(unknownSubscription.isActive)
    }

    func testDecoding() throws {
        let rawSubscription = """
        {
            \"productId\": \"ddg-privacy-pro-sandbox-monthly-renews-us\",
            \"name\": \"Monthly Subscription\",
            \"billingPeriod\": \"Monthly\",
            \"startedAt\": 1718104783000,
            \"expiresOrRenewsAt\": 1723375183000,
            \"platform\": \"stripe\",
            \"status\": \"Auto-Renewable\",
            \"activeOffers\": []
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let subscription = try decoder.decode(DuckDuckGoSubscription.self, from: Data(rawSubscription.utf8))

        XCTAssertEqual(subscription.productId, "ddg-privacy-pro-sandbox-monthly-renews-us")
        XCTAssertEqual(subscription.name, "Monthly Subscription")
        XCTAssertEqual(subscription.startedAt, Date(timeIntervalSince1970: 1718104783))
        XCTAssertEqual(subscription.expiresOrRenewsAt, Date(timeIntervalSince1970: 1723375183))
        XCTAssertEqual(subscription.billingPeriod, .monthly)
        XCTAssertEqual(subscription.status, .autoRenewable)
    }

    func testBillingPeriodDecoding() throws {
        let monthly = try JSONDecoder().decode(DuckDuckGoSubscription.BillingPeriod.self, from: Data("\"Monthly\"".utf8))
        XCTAssertEqual(monthly, DuckDuckGoSubscription.BillingPeriod.monthly)

        let yearly = try JSONDecoder().decode(DuckDuckGoSubscription.BillingPeriod.self, from: Data("\"Yearly\"".utf8))
        XCTAssertEqual(yearly, DuckDuckGoSubscription.BillingPeriod.yearly)

        let unknown = try JSONDecoder().decode(DuckDuckGoSubscription.BillingPeriod.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, DuckDuckGoSubscription.BillingPeriod.unknown)
    }

    func testPlatformDecoding() throws {
        let apple = try JSONDecoder().decode(DuckDuckGoSubscription.Platform.self, from: Data("\"apple\"".utf8))
        XCTAssertEqual(apple, DuckDuckGoSubscription.Platform.apple)

        let google = try JSONDecoder().decode(DuckDuckGoSubscription.Platform.self, from: Data("\"google\"".utf8))
        XCTAssertEqual(google, DuckDuckGoSubscription.Platform.google)

        let stripe = try JSONDecoder().decode(DuckDuckGoSubscription.Platform.self, from: Data("\"stripe\"".utf8))
        XCTAssertEqual(stripe, DuckDuckGoSubscription.Platform.stripe)

        let unknown = try JSONDecoder().decode(DuckDuckGoSubscription.Platform.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, DuckDuckGoSubscription.Platform.unknown)
    }

    func testStatusDecoding() throws {
        let autoRenewable = try JSONDecoder().decode(DuckDuckGoSubscription.Status.self, from: Data("\"Auto-Renewable\"".utf8))
        XCTAssertEqual(autoRenewable, DuckDuckGoSubscription.Status.autoRenewable)

        let notAutoRenewable = try JSONDecoder().decode(DuckDuckGoSubscription.Status.self, from: Data("\"Not Auto-Renewable\"".utf8))
        XCTAssertEqual(notAutoRenewable, DuckDuckGoSubscription.Status.notAutoRenewable)

        let gracePeriod = try JSONDecoder().decode(DuckDuckGoSubscription.Status.self, from: Data("\"Grace Period\"".utf8))
        XCTAssertEqual(gracePeriod, DuckDuckGoSubscription.Status.gracePeriod)

        let inactive = try JSONDecoder().decode(DuckDuckGoSubscription.Status.self, from: Data("\"Inactive\"".utf8))
        XCTAssertEqual(inactive, DuckDuckGoSubscription.Status.inactive)

        let expired = try JSONDecoder().decode(DuckDuckGoSubscription.Status.self, from: Data("\"Expired\"".utf8))
        XCTAssertEqual(expired, DuckDuckGoSubscription.Status.expired)

        let unknown = try JSONDecoder().decode(DuckDuckGoSubscription.Status.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, DuckDuckGoSubscription.Status.unknown)
    }

    func testOfferTypeDecoding() throws {
        let trial = try JSONDecoder().decode(DuckDuckGoSubscription.OfferType.self, from: Data("\"Trial\"".utf8))
        XCTAssertEqual(trial, DuckDuckGoSubscription.OfferType.trial)

        let unknown = try JSONDecoder().decode(DuckDuckGoSubscription.OfferType.self, from: Data("\"something unexpected\"".utf8))
        XCTAssertEqual(unknown, DuckDuckGoSubscription.OfferType.unknown)
    }

    func testDecodingWithActiveOffers() throws {
        let rawSubscriptionWithOffers = """
        {
            \"productId\": \"ddg-privacy-pro-sandbox-monthly-renews-us\",
            \"name\": \"Monthly Subscription\",
            \"billingPeriod\": \"Monthly\",
            \"startedAt\": 1718104783000,
            \"expiresOrRenewsAt\": 1723375183000,
            \"platform\": \"stripe\",
            \"status\": \"Auto-Renewable\",
            \"activeOffers\": [{ \"type\": \"Trial\"}]
        }
        """

        let rawSubscriptionWithoutOffers = """
        {
            \"productId\": \"ddg-privacy-pro-sandbox-monthly-renews-us\",
            \"name\": \"Monthly Subscription\",
            \"billingPeriod\": \"Monthly\",
            \"startedAt\": 1718104783000,
            \"expiresOrRenewsAt\": 1723375183000,
            \"platform\": \"stripe\",
            \"status\": \"Auto-Renewable\",
            \"activeOffers\": []
        }
        """

        let rawSubscriptionWithUnknownOffers = """
        {
            \"productId\": \"ddg-privacy-pro-sandbox-monthly-renews-us\",
            \"name\": \"Monthly Subscription\",
            \"billingPeriod\": \"Monthly\",
            \"startedAt\": 1718104783000,
            \"expiresOrRenewsAt\": 1723375183000,
            \"platform\": \"stripe\",
            \"status\": \"Auto-Renewable\",
            \"activeOffers\": [{ \"type\": \"SpecialOffer\"}]
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let subscriptionWithOffers = try decoder.decode(DuckDuckGoSubscription.self, from: Data(rawSubscriptionWithOffers.utf8))
        XCTAssertEqual(subscriptionWithOffers.activeOffers, [DuckDuckGoSubscription.Offer(type: .trial)])

        let subscriptionWithoutOffers = try decoder.decode(DuckDuckGoSubscription.self, from: Data(rawSubscriptionWithoutOffers.utf8))
        XCTAssertEqual(subscriptionWithoutOffers.activeOffers, [])

        let subscriptionWithUnknownOffers = try decoder.decode(DuckDuckGoSubscription.self, from: Data(rawSubscriptionWithUnknownOffers.utf8))
        XCTAssertEqual(subscriptionWithUnknownOffers.activeOffers, [DuckDuckGoSubscription.Offer(type: .unknown)])
    }

    func testHasActiveTrialOffer_WithTrialOffer_ReturnsTrue() {
        // Given
        let subscription = DuckDuckGoSubscription.make(
            withStatus: .autoRenewable,
            activeOffers: [DuckDuckGoSubscription.Offer(type: .trial)]
        )

        // When
        let hasActiveTrialOffer = subscription.hasActiveTrialOffer

        // Then
        XCTAssertTrue(hasActiveTrialOffer)
    }

    func testHasActiveTrialOffer_WithNoOffers_ReturnsFalse() {
        // Given
        let subscription = DuckDuckGoSubscription.make(
            withStatus: .autoRenewable,
            activeOffers: []
        )

        // When
        let hasActiveTrialOffer = subscription.hasActiveTrialOffer

        // Then
        XCTAssertFalse(hasActiveTrialOffer)
    }

    func testHasActiveTrialOffer_WithNonTrialOffer_ReturnsFalse() {
        // Given
        let subscription = DuckDuckGoSubscription.make(
            withStatus: .autoRenewable,
            activeOffers: [DuckDuckGoSubscription.Offer(type: .unknown)]
        )

        // When
        let hasActiveTrialOffer = subscription.hasActiveTrialOffer

        // Then
        XCTAssertFalse(hasActiveTrialOffer)
    }

    func testHasActiveTrialOffer_WithMultipleOffersIncludingTrial_ReturnsTrue() {
        // Given
        let subscription = DuckDuckGoSubscription.make(
            withStatus: .autoRenewable,
            activeOffers: [
                DuckDuckGoSubscription.Offer(type: .unknown),
                DuckDuckGoSubscription.Offer(type: .trial),
                DuckDuckGoSubscription.Offer(type: .unknown)
            ]
        )

        // When
        let hasActiveTrialOffer = subscription.hasActiveTrialOffer

        // Then
        XCTAssertTrue(hasActiveTrialOffer)
    }
}

extension DuckDuckGoSubscription {

    static func make(withStatus status: DuckDuckGoSubscription.Status, activeOffers: [DuckDuckGoSubscription.Offer] = []) -> DuckDuckGoSubscription {
        DuckDuckGoSubscription(productId: UUID().uuidString,
                     name: "Subscription test #1",
                     billingPeriod: .monthly,
                     startedAt: Date(),
                     expiresOrRenewsAt: Date().addingTimeInterval(TimeInterval.days(+30)),
                     platform: .apple,
                     status: status,
                     activeOffers: activeOffers)
    }
}

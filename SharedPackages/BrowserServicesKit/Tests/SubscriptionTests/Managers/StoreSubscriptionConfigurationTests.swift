//
//  StoreSubscriptionConfigurationTests.swift
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

import Testing
@testable import Subscription

@Suite("Store Subscription Configuration Tests")
struct StoreSubscriptionConfigurationTests {

    let sut = DefaultStoreSubscriptionConfiguration()

    @Test("USA region returns expected product identifiers")
    func usaRegionReturnsExpectedProductIdentifiers() {
        // Given
        let expectedUSAProducts: Set<String> = [
            // Production
            "ddg.privacy.pro.monthly.renews.us",
            "ddg.privacy.pro.yearly.renews.us",
            "ddg.privacy.pro.monthly.renews.us.freetrial",
            "ddg.privacy.pro.yearly.renews.us.freetrial",
            "ddg.subscription.monthly.renews.us.freetrial.pro",
            "ddg.subscription.yearly.renews.us.freetrial.pro",

            // iOS Alpha
            "ios.subscription.1month",
            "ios.subscription.1year",
            "ios.subscription.1month.freetrial.dev",
            "ios.subscription.1year.freetrial.dev",
            "ios.subscription.1month.freetrial.dev.pro",
            "ios.subscription.1year.freetrial.dev.pro",

            // macOS Debug
            "subscription.1month",
            "subscription.1year",
            "subscription.1month.freetrial",
            "subscription.1year.freetrial",
            "subscription.1month.freetrial.pro",
            "subscription.1year.freetrial.pro",

            // macOS Review
            "review.subscription.1month",
            "review.subscription.1year",
            "review.subscription.1month.freetrial",
            "review.subscription.1year.freetrial",
            "review.subscription.1month.freetrial.pro",
            "review.subscription.1year.freetrial.pro",

            // TestFlight
            "tf.sandbox.subscription.1month",
            "tf.sandbox.subscription.1year",
            "tf.sandbox.subscription.1month.freetrial",
            "tf.sandbox.subscription.1year.freetrial",
            "tf.sandbox.subscription.1month.freetrial.pro",
            "tf.sandbox.subscription.1year.freetrial.pro"
        ]

        // When
        let actualProducts = Set(sut.subscriptionIdentifiers(for: .usa))

        // Then
        #expect(actualProducts == expectedUSAProducts,
                "USA products should match expected list exactly")
    }

    @Test("ROW region returns expected product identifiers")
    func rowRegionReturnsExpectedProductIdentifiers() {
        // Given
        let expectedROWProducts: Set<String> = [
            // Production
            "ddg.privacy.pro.monthly.renews.row",
            "ddg.privacy.pro.yearly.renews.row",
            "ddg.privacy.pro.monthly.renews.row.freetrial",
            "ddg.privacy.pro.yearly.renews.row.freetrial",
            "ddg.subscription.monthly.renews.row.freetrial.pro",
            "ddg.subscription.yearly.renews.row.freetrial.pro",

            // iOS Alpha
            "ios.subscription.1month.row",
            "ios.subscription.1year.row",
            "ios.subscription.1month.row.freetrial.dev",
            "ios.subscription.1year.row.freetrial.dev",
            "ios.subscription.1month.row.freetrial.dev.pro",
            "ios.subscription.1year.row.freetrial.dev.pro",

            // macOS Debug
            "subscription.1month.row",
            "subscription.1year.row",
            "subscription.1month.row.freetrial",
            "subscription.1year.row.freetrial",
            "subscription.1month.row.freetrial.pro",
            "subscription.1year.row.freetrial.pro",

            // macOS Review
            "review.subscription.1month.row",
            "review.subscription.1year.row",
            "review.subscription.1month.row.freetrial",
            "review.subscription.1year.row.freetrial",
            "review.subscription.1month.row.freetrial.pro",
            "review.subscription.1year.row.freetrial.pro",

            // TestFlight
            "tf.sandbox.subscription.1month.row",
            "tf.sandbox.subscription.1year.row",
            "tf.sandbox.subscription.1month.row.freetrial",
            "tf.sandbox.subscription.1year.row.freetrial",
            "tf.sandbox.subscription.1month.row.freetrial.pro",
            "tf.sandbox.subscription.1year.row.freetrial.pro"
        ]

        // When
        let actualProducts = Set(sut.subscriptionIdentifiers(for: .restOfWorld))

        // Then
        #expect(actualProducts == expectedROWProducts,
                "ROW products should match expected list exactly")
    }
}

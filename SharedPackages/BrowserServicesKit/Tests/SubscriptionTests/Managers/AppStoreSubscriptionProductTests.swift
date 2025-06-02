//
//  AppStoreSubscriptionProductTests.swift
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

import XCTest
import StoreKit
@testable import Subscription

@available(macOS 12.0, iOS 15.0, *)
final class AppStoreSubscriptionProductTests: XCTestCase {

    func testCreateWithFreeTrialProduct_EligibleUser() async throws {
        // Given
        let mockIntroOffer = MockIntroductoryOffer(
            id: "trial_offer",
            displayPrice: "$0.00",
            periodInDays: 7,
            isFreeTrial: true
        )

        let mockProduct = MockStoreProduct(
            id: "com.test.monthly.trial",
            displayName: "Monthly with Trial",
            displayPrice: "$9.99",
            isMonthly: true,
            introductoryOffer: mockIntroOffer,
            isFreeTrialProduct: true,
            isEligibleForFreeTrial: true
        )

        // When
        let subscriptionProduct = await AppStoreSubscriptionProduct.create(product: mockProduct)

        // Then
        XCTAssertEqual(subscriptionProduct.id, "com.test.monthly.trial")
        XCTAssertEqual(subscriptionProduct.displayName, "Monthly with Trial")
        XCTAssertEqual(subscriptionProduct.displayPrice, "$9.99")
        XCTAssertTrue(subscriptionProduct.isMonthly)
        XCTAssertFalse(subscriptionProduct.isYearly)
        XCTAssertTrue(subscriptionProduct.isFreeTrialProduct)
        XCTAssertTrue(subscriptionProduct.isEligibleForFreeTrial)
        XCTAssertNotNil(subscriptionProduct.introductoryOffer)
    }

    func testCreateWithFreeTrialProduct_IneligibleUser() async throws {
        // Given
        let mockIntroOffer = MockIntroductoryOffer(
            id: "trial_offer",
            displayPrice: "$0.00",
            periodInDays: 14,
            isFreeTrial: true
        )

        let mockProduct = MockStoreProduct(
            id: "com.test.yearly.trial",
            displayName: "Yearly with Trial",
            displayPrice: "$99.99",
            isYearly: true,
            introductoryOffer: mockIntroOffer,
            isFreeTrialProduct: true,
            isEligibleForFreeTrial: false
        )

        // When
        let subscriptionProduct = await AppStoreSubscriptionProduct.create(product: mockProduct)

        // Then
        XCTAssertEqual(subscriptionProduct.id, "com.test.yearly.trial")
        XCTAssertTrue(subscriptionProduct.isYearly)
        XCTAssertTrue(subscriptionProduct.isFreeTrialProduct)
        XCTAssertFalse(subscriptionProduct.isEligibleForFreeTrial)
    }

    func testCreateWithNonFreeTrialProduct() async throws {
        // Given
        let mockProduct = MockStoreProduct(
            id: "com.test.monthly.regular",
            displayName: "Monthly Regular",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: false,
            isEligibleForFreeTrial: false
        )

        // When
        let subscriptionProduct = await AppStoreSubscriptionProduct.create(product: mockProduct)

        // Then
        XCTAssertEqual(subscriptionProduct.id, "com.test.monthly.regular")
        XCTAssertTrue(subscriptionProduct.isMonthly)
        XCTAssertFalse(subscriptionProduct.isFreeTrialProduct)
        XCTAssertFalse(subscriptionProduct.isEligibleForFreeTrial)
        XCTAssertNil(subscriptionProduct.introductoryOffer)
    }

    func testRefreshFreeTrialEligibility_FreeTrialProduct() async throws {
        // Given
        let mockProduct = MockStoreProduct(
            id: "com.test.trial",
            isFreeTrialProduct: true,
            isEligibleForFreeTrial: true
        )

        var subscriptionProduct = await AppStoreSubscriptionProduct.create(product: mockProduct)
        XCTAssertTrue(subscriptionProduct.isEligibleForFreeTrial)

        // When - Simulate eligibility change
        mockProduct.mockEligibilityChange(to: false)
        let updatedEligibility = await subscriptionProduct.refreshFreeTrialEligibility()

        // Then
        XCTAssertFalse(updatedEligibility)
        XCTAssertFalse(subscriptionProduct.isEligibleForFreeTrial)
    }

    func testRefreshFreeTrialEligibility_NonFreeTrialProduct() async throws {
        // Given
        let mockProduct = MockStoreProduct(
            id: "com.test.regular",
            isFreeTrialProduct: false,
            isEligibleForFreeTrial: false
        )

        var subscriptionProduct = await AppStoreSubscriptionProduct.create(product: mockProduct)
        XCTAssertFalse(subscriptionProduct.isEligibleForFreeTrial)

        // When
        let updatedEligibility = await subscriptionProduct.refreshFreeTrialEligibility()

        // Then
        XCTAssertFalse(updatedEligibility)
        XCTAssertFalse(subscriptionProduct.isEligibleForFreeTrial)
    }

    func testInitWithCachedEligibility() throws {
        // Given
        let mockProduct = MockStoreProduct(
            id: "com.test.product",
            isFreeTrialProduct: true,
            isEligibleForFreeTrial: true
        )

        // When
        let subscriptionProduct = AppStoreSubscriptionProduct(
            product: mockProduct,
            freeTrialEligibility: false
        )

        // Then
        XCTAssertEqual(subscriptionProduct.id, "com.test.product")
        XCTAssertFalse(subscriptionProduct.isEligibleForFreeTrial)
    }

    func testEquality() throws {
        // Given
        let mockProduct1 = MockStoreProduct(id: "com.test.product1")
        let mockProduct2 = MockStoreProduct(id: "com.test.product2")
        let mockProduct3 = MockStoreProduct(id: "com.test.product1")

        let subscription1 = AppStoreSubscriptionProduct(product: mockProduct1)
        let subscription2 = AppStoreSubscriptionProduct(product: mockProduct2)
        let subscription3 = AppStoreSubscriptionProduct(product: mockProduct3)

        // Then
        XCTAssertEqual(subscription1, subscription3) // Same ID
        XCTAssertNotEqual(subscription1, subscription2) // Different ID
    }

    func testPropertyForwarding() throws {
        // Given
        let mockIntroOffer = MockIntroductoryOffer(
            id: "offer_id",
            displayPrice: "Free",
            periodInDays: 30,
            isFreeTrial: true
        )

        let mockProduct = MockStoreProduct(
            id: "com.test.product",
            displayName: "Test Product",
            displayPrice: "$19.99",
            description: "Test Description",
            isMonthly: false,
            isYearly: true,
            introductoryOffer: mockIntroOffer,
            isFreeTrialProduct: true,
            isEligibleForFreeTrial: true
        )

        let subscriptionProduct = AppStoreSubscriptionProduct(product: mockProduct)

        // Then - Verify all properties are forwarded correctly
        XCTAssertEqual(subscriptionProduct.id, "com.test.product")
        XCTAssertEqual(subscriptionProduct.displayName, "Test Product")
        XCTAssertEqual(subscriptionProduct.displayPrice, "$19.99")
        XCTAssertEqual(subscriptionProduct.description, "Test Description")
        XCTAssertFalse(subscriptionProduct.isMonthly)
        XCTAssertTrue(subscriptionProduct.isYearly)
        XCTAssertTrue(subscriptionProduct.isFreeTrialProduct)
        XCTAssertNotNil(subscriptionProduct.introductoryOffer)
        XCTAssertEqual(subscriptionProduct.introductoryOffer?.id, "offer_id")
    }
}

// MARK: - Mock Implementations

@available(macOS 12.0, iOS 15.0, *)
private class MockStoreProduct: StoreProduct {
    let id: String
    let displayName: String
    let displayPrice: String
    let description: String
    let isMonthly: Bool
    let isYearly: Bool
    let introductoryOffer: (any SubscriptionProductIntroductoryOffer)?
    let isFreeTrialProduct: Bool
    private var mockIsEligibleForFreeTrial: Bool

    init(
        id: String,
        displayName: String = "Mock Product",
        displayPrice: String = "$9.99",
        description: String = "Mock Description",
        isMonthly: Bool = false,
        isYearly: Bool = false,
        introductoryOffer: (any SubscriptionProductIntroductoryOffer)? = nil,
        isFreeTrialProduct: Bool = false,
        isEligibleForFreeTrial: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.description = description
        self.isMonthly = isMonthly
        self.isYearly = isYearly
        self.introductoryOffer = introductoryOffer
        self.isFreeTrialProduct = isFreeTrialProduct
        self.mockIsEligibleForFreeTrial = isEligibleForFreeTrial
    }

    var isEligibleForFreeTrial: Bool {
        get async {
            return mockIsEligibleForFreeTrial
        }
    }

    func mockEligibilityChange(to newValue: Bool) {
        mockIsEligibleForFreeTrial = newValue
    }

    func purchase(options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult {
        fatalError("Not implemented for mock")
    }
}

private struct MockIntroductoryOffer: SubscriptionProductIntroductoryOffer {
    let id: String?
    let displayPrice: String
    let periodInDays: Int
    let isFreeTrial: Bool

    init(id: String? = nil, displayPrice: String, periodInDays: Int, isFreeTrial: Bool) {
        self.id = id
        self.displayPrice = displayPrice
        self.periodInDays = periodInDays
        self.isFreeTrial = isFreeTrial
    }
}

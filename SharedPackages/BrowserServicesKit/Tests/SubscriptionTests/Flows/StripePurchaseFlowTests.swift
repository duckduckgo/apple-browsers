//
//  StripePurchaseFlowTests.swift
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
import Networking

final class StripePurchaseFlowTests: XCTestCase {

    private struct Constants {
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"
    }

    var subscriptionManager: SubscriptionManagerMock!
    var stripePurchaseFlow: StripePurchaseFlow!

    override func setUpWithError() throws {
        subscriptionManager = SubscriptionManagerMock()
        stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionManager: subscriptionManager)
    }

    override func tearDownWithError() throws {
        subscriptionManager = nil
        stripePurchaseFlow = nil
    }

    // MARK: - Tests for subscriptionTierOptions

    func testSubscriptionTierOptionsSuccess() async throws {
        // Given
        subscriptionManager.tierProductsResponse = .success(SubscriptionMockFactory.tierProductsResponse)

        // When
        let result = await stripePurchaseFlow.subscriptionTierOptions(includeProTier: false)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.platform, SubscriptionPlatformName.stripe)
            XCTAssertEqual(success.products.count, 1)

            let tier = success.products[0]
            XCTAssertEqual(tier.tier, .plus)
            XCTAssertEqual(tier.features.count, 4)
            XCTAssertEqual(tier.options.count, 2)

            // Verify features
            let expectedFeatures: [SubscriptionEntitlement] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]
            for expectedFeature in expectedFeatures {
                XCTAssertTrue(tier.features.contains(where: { $0.product == expectedFeature }))
            }

            // Verify options
            XCTAssertTrue(tier.options.contains(where: { $0.id == "monthly-plus" }))
            XCTAssertTrue(tier.options.contains(where: { $0.id == "yearly-plus" }))
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testSubscriptionTierOptionsFiltersOutProTierWhenDisabled() async throws {
        // Given
        let responseWithProTier = GetTierProductsResponse(products: [
            TierProduct(
                productName: "Plus Subscription",
                tier: .plus,
                regions: ["us", "row"],
                entitlements: [
                    TierFeature(product: .networkProtection, name: .plus)
                ],
                billingCycles: [
                    BillingCycle(productId: "monthly-plus", period: "Monthly", price: "9.99", currency: "USD")
                ]
            ),
            TierProduct(
                productName: "Pro Subscription",
                tier: .pro,
                regions: ["us", "row"],
                entitlements: [
                    TierFeature(product: .networkProtection, name: .pro),
                    TierFeature(product: .paidAIChat, name: .pro)
                ],
                billingCycles: [
                    BillingCycle(productId: "monthly-pro", period: "Monthly", price: "19.99", currency: "USD")
                ]
            )
        ])
        subscriptionManager.tierProductsResponse = .success(responseWithProTier)

        // When - includeProTier is false
        let result = await stripePurchaseFlow.subscriptionTierOptions(includeProTier: false)

        // Then - Only plus tier should be returned
        switch result {
        case .success(let success):
            XCTAssertEqual(success.products.count, 1)
            XCTAssertEqual(success.products[0].tier, .plus)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testSubscriptionTierOptionsIncludesProTierWhenEnabled() async throws {
        // Given
        let responseWithProTier = GetTierProductsResponse(products: [
            TierProduct(
                productName: "Plus Subscription",
                tier: .plus,
                regions: ["us", "row"],
                entitlements: [
                    TierFeature(product: .networkProtection, name: .plus)
                ],
                billingCycles: [
                    BillingCycle(productId: "monthly-plus", period: "Monthly", price: "9.99", currency: "USD")
                ]
            ),
            TierProduct(
                productName: "Pro Subscription",
                tier: .pro,
                regions: ["us", "row"],
                entitlements: [
                    TierFeature(product: .networkProtection, name: .pro),
                    TierFeature(product: .paidAIChat, name: .pro)
                ],
                billingCycles: [
                    BillingCycle(productId: "monthly-pro", period: "Monthly", price: "19.99", currency: "USD")
                ]
            )
        ])
        subscriptionManager.tierProductsResponse = .success(responseWithProTier)

        // When - includeProTier is true
        let result = await stripePurchaseFlow.subscriptionTierOptions(includeProTier: true)

        // Then - Both tiers should be returned
        switch result {
        case .success(let success):
            XCTAssertEqual(success.products.count, 2)
            XCTAssertTrue(success.products.contains(where: { $0.tier == .plus }))
            XCTAssertTrue(success.products.contains(where: { $0.tier == .pro }))
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testSubscriptionTierOptionsFailureEmptyProductsFromAPI() async throws {
        // Given
        subscriptionManager.tierProductsResponse = .success(GetTierProductsResponse(products: []))

        // When
        let result = await stripePurchaseFlow.subscriptionTierOptions(includeProTier: false)

        // Then
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error, .tieredProductsEmptyProductsFromAPI)
        }
    }

    func testSubscriptionTierOptionsFailureAPIError() async throws {
        // Given
        subscriptionManager.tierProductsResponse = .failure(SubscriptionEndpointServiceError.noData)

        // When
        let result = await stripePurchaseFlow.subscriptionTierOptions(includeProTier: false)

        // Then
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error, .tieredProductsApiCallFailed(SubscriptionEndpointServiceError.noData))
        }
    }

    func testSubscriptionTierOptionsFailureEmptyAfterFiltering() async throws {
        // Given - Only pro tier products, but pro tier is disabled
        let responseWithOnlyProTier = GetTierProductsResponse(products: [
            TierProduct(
                productName: "Pro Subscription",
                tier: .pro,
                regions: ["us", "row"],
                entitlements: [
                    TierFeature(product: .networkProtection, name: .pro),
                    TierFeature(product: .paidAIChat, name: .pro)
                ],
                billingCycles: [
                    BillingCycle(productId: "monthly-pro", period: "Monthly", price: "19.99", currency: "USD")
                ]
            )
        ])
        subscriptionManager.tierProductsResponse = .success(responseWithOnlyProTier)

        // When - includeProTier is false, which should filter out all products
        let result = await stripePurchaseFlow.subscriptionTierOptions(includeProTier: false)

        // Then
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error, .tieredProductsEmptyAfterFiltering)
        }
    }

    func testSubscriptionTierOptionsFailureTierCreationFailed() async throws {
        // Given - Products with no billing cycles (tier creation will fail)
        let responseWithNoBillingCycles = GetTierProductsResponse(products: [
            TierProduct(
                productName: "Plus Subscription",
                tier: .plus,
                regions: ["us", "row"],
                entitlements: [
                    TierFeature(product: .networkProtection, name: .plus)
                ],
                billingCycles: [] // No billing cycles = tier creation fails
            )
        ])
        subscriptionManager.tierProductsResponse = .success(responseWithNoBillingCycles)

        // When
        let result = await stripePurchaseFlow.subscriptionTierOptions(includeProTier: false)

        // Then
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error, .tieredProductsTierCreationFailed)
        }
    }

}

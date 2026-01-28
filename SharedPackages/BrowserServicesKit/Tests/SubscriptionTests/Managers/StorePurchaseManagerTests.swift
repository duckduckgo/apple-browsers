//
//  StorePurchaseManagerTests.swift
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
import StoreKit
import Combine
import Networking

final class StorePurchaseManagerTests: XCTestCase {

    private var sut: DefaultStorePurchaseManager!
    private var mockCache: SubscriptionFeatureMappingCacheMock!
    private var mockProductFetcher: MockProductFetcher!
    private var mockFeatureFlagger: MockFeatureFlagger!

    override func setUpWithError() throws {
        mockCache = SubscriptionFeatureMappingCacheMock()
        mockProductFetcher = MockProductFetcher()
        mockFeatureFlagger = MockFeatureFlagger()
        sut = DefaultStorePurchaseManager(subscriptionFeatureMappingCache: mockCache,
                                          subscriptionFeatureFlagger: mockFeatureFlagger,
                                          productFetcher: mockProductFetcher)
    }

    func testUpdateAvailableProductsSuccessfully() async {
        // Given
        let monthlyProduct = createMonthlyProduct()
        let yearlyProduct = createYearlyProduct()
        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]

        // When
        await sut.updateAvailableProducts()

        // Then
        let products = sut.availableProducts
        XCTAssertEqual(products.count, 2)
        XCTAssertTrue(products.contains(where: { $0.id == monthlyProduct.id }))
        XCTAssertTrue(products.contains(where: { $0.id == yearlyProduct.id }))
    }

    func testUpdateAvailableProductsWithError() async {
        // Given
        mockProductFetcher.fetchError = MockProductError.fetchFailed

        // When
        await sut.updateAvailableProducts()

        // Then
        let products = sut.availableProducts
        XCTAssertTrue(products.isEmpty)
    }

    func testUpdateAvailableProductsWithDifferentRegions() async {
        // Given
        let usaMonthlyProduct = MockSubscriptionProduct(
            id: "com.test.usa.monthly",
            displayName: "USA Monthly Plan",
            displayPrice: "$9.99",
            isMonthly: true
        )
        let usaYearlyProduct = MockSubscriptionProduct(
            id: "com.test.usa.yearly",
            displayName: "USA Yearly Plan",
            displayPrice: "$99.99",
            isYearly: true
        )

        let rowMonthlyProduct = MockSubscriptionProduct(
            id: "com.test.row.monthly",
            displayName: "ROW Monthly Plan",
            displayPrice: "€8.99",
            isMonthly: true
        )
        let rowYearlyProduct = MockSubscriptionProduct(
            id: "com.test.row.yearly",
            displayName: "ROW Yearly Plan",
            displayPrice: "€89.99",
            isYearly: true
        )

        // Set USA products initially
        mockProductFetcher.mockProducts = [usaMonthlyProduct, usaYearlyProduct]
        mockFeatureFlagger.enabledFeatures = [.useSubscriptionUSARegionOverride] // No ROW features enabled - defaults to USA

        // When - Update for USA region
        await sut.updateAvailableProducts()

        // Then - Verify USA products
        let usaProducts = sut.availableProducts
        XCTAssertEqual(usaProducts.count, 2)
        XCTAssertEqual(sut.currentStorefrontRegion, .usa)
        XCTAssertTrue(usaProducts.contains(where: { $0.id == "com.test.usa.monthly" }))
        XCTAssertTrue(usaProducts.contains(where: { $0.id == "com.test.usa.yearly" }))

        // When - Switch to ROW region
        mockProductFetcher.mockProducts = [rowMonthlyProduct, rowYearlyProduct]
        mockFeatureFlagger.enabledFeatures = [.useSubscriptionROWRegionOverride]
        await sut.updateAvailableProducts()

        // Then - Verify ROW products
        let rowProducts = sut.availableProducts
        XCTAssertEqual(rowProducts.count, 2)
        XCTAssertEqual(sut.currentStorefrontRegion, .restOfWorld)
        XCTAssertTrue(rowProducts.contains(where: { $0.id == "com.test.row.monthly" }))
        XCTAssertTrue(rowProducts.contains(where: { $0.id == "com.test.row.yearly" }))

        // Verify pricing differences
        let usaMonthlyPrice = usaProducts.first(where: { $0.isMonthly })?.displayPrice
        let rowMonthlyPrice = rowProducts.first(where: { $0.isMonthly })?.displayPrice
        XCTAssertEqual(usaMonthlyPrice, "$9.99")
        XCTAssertEqual(rowMonthlyPrice, "€8.99")
    }

    func testIsUserEligibleForFreeTrialReturnsTrueWhenEligibleProductExists() async {
        // Given
        let monthlyProduct = createMonthlyProduct(withTrial: true)
        let yearlyProduct = createYearlyProduct(withTrial: true)
        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // When
        let isEligible = sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertTrue(isEligible)
    }

    func testIsUserEligibleForFreeTrialReturnsFalseWhenNoEligibleProductExists() async {
        // Given
        let monthlyProduct = createMonthlyProduct(withTrial: true, isEligibleForFreeTrial: false)
        let yearlyProduct = createYearlyProduct(withTrial: true, isEligibleForFreeTrial: false)
        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // When
        let isEligible = sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertFalse(isEligible)
    }

    func testIsUserEligibleForFreeTrialReturnsFalseWhenNoTrialProductsExist() async {
        // Given
        let monthlyProduct = createMonthlyProduct(withTrial: false, isEligibleForFreeTrial: false)
        let yearlyProduct = createYearlyProduct(withTrial: false, isEligibleForFreeTrial: false)
        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // When
        let isEligible = sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertFalse(isEligible)
    }

    // MARK: - Trial Eligibility Update Tests

    func testUpdateAvailableProductsTrialEligibilityUpdatesAllProducts() async {
        // Given
        let product1 = MockSubscriptionProduct(
            id: "product1",
            hasIntroductoryFreeTrialOffer: true,
            isEligibleForFreeTrial: true
        )
        let product2 = MockSubscriptionProduct(
            id: "product2",
            hasIntroductoryFreeTrialOffer: true,
            isEligibleForFreeTrial: true
        )
        mockProductFetcher.mockProducts = [product1, product2]
        await sut.updateAvailableProducts()

        XCTAssertEqual(sut.availableProducts.count, 2)

        // Verify initial eligibility state
        XCTAssertTrue(sut.availableProducts[0].isEligibleForFreeTrial)
        XCTAssertTrue(sut.availableProducts[1].isEligibleForFreeTrial)

        // Configure products to change eligibility when refreshed
        product1.eligibilityAfterRefresh = false
        product2.eligibilityAfterRefresh = false

        // When
        await sut.updateAvailableProductsTrialEligibility()

        // Then
        XCTAssertFalse(sut.availableProducts[0].isEligibleForFreeTrial)
        XCTAssertFalse(sut.availableProducts[1].isEligibleForFreeTrial)
    }

    // MARK: - Publisher Tests

    func testAreProductsAvailablePublisherEmitsTrueWhenProductsBecomeAvailable() async {
        // Given
        let expectation = expectation(description: "Publisher should emit true")
        var receivedValue: Bool?
        let cancellable = sut.areProductsAvailablePublisher
            .dropFirst() // Drop initial `false` value
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }

        // When
        mockProductFetcher.mockProducts = [createMonthlyProduct()]
        await sut.updateAvailableProducts()

        // Then
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(receivedValue, true)
        cancellable.cancel()
    }

    func testAreProductsAvailablePublisherEmitsFalseWhenProductsBecomeUnavailable() async {
        // Given
        // Set initial state to have products
        mockProductFetcher.mockProducts = [createMonthlyProduct()]
        await sut.updateAvailableProducts()

        let expectation = expectation(description: "Publisher should emit false")
        var receivedValue: Bool?
        let cancellable = sut.areProductsAvailablePublisher
            .dropFirst() // Drop initial `true` value
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }

        // When
        mockProductFetcher.mockProducts = []
        await sut.updateAvailableProducts()

        // Then
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(receivedValue, false)
        cancellable.cancel()
    }

    func testAreProductsAvailablePublisherEmitsCorrectSequenceOnChanges() async {
        // Given
        var receivedValues: [Bool] = []
        let expectation = expectation(description: "Publisher should emit two values")
        expectation.expectedFulfillmentCount = 2

        let cancellable = sut.areProductsAvailablePublisher
            .dropFirst() // Drop initial `false` value
            .sink { value in
                receivedValues.append(value)
                expectation.fulfill()
            }

        // When
        // 1. Products become available
        mockProductFetcher.mockProducts = [createMonthlyProduct()]
        await sut.updateAvailableProducts()

        // 2. Products become unavailable
        mockProductFetcher.mockProducts = []
        await sut.updateAvailableProducts()

        // Then
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(receivedValues, [true, false])
        cancellable.cancel()
    }

    // Tiers
    func testGetAvailableProductsExcludesProTierByDefault() async {
        // Given
        let regularMonthly = MockSubscriptionProduct(id: "com.test.monthly", isMonthly: true)
        let proMonthly = MockSubscriptionProduct(id: "com.test.monthly.pro", isMonthly: true)

        mockProductFetcher.mockProducts = [regularMonthly, proMonthly]
        await sut.updateAvailableProducts()

        // When
        let products = await sut.getAvailableProducts(includeProTier: false)

        // Then
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products[0].id, "com.test.monthly")
    }

    func testGetAvailableProductsIncludesProTierWhenRequested() async {
        // Given
        let regularMonthly = MockSubscriptionProduct(id: "com.test.monthly", isMonthly: true)
        let proMonthly = MockSubscriptionProduct(id: "com.test.monthly.pro", isMonthly: true)

        mockProductFetcher.mockProducts = [regularMonthly, proMonthly]
        await sut.updateAvailableProducts()

        // When
        let products = await sut.getAvailableProducts(includeProTier: true)

        // Then
        XCTAssertEqual(products.count, 2)
        XCTAssertTrue(products.contains(where: { $0.id == "com.test.monthly" }))
        XCTAssertTrue(products.contains(where: { $0.id == "com.test.monthly.pro" }))
    }

    func testGetAvailableProductsHandlesEmptyArray() async {
        // Given
        mockProductFetcher.mockProducts = []
        await sut.updateAvailableProducts()

        // When
        let regularProducts = await sut.getAvailableProducts(includeProTier: false)
        let allProducts = await sut.getAvailableProducts(includeProTier: true)

        // Then
        XCTAssertEqual(regularProducts.count, 0)
        XCTAssertEqual(allProducts.count, 0)
    }

    func testGetAvailableProductsHandlesOnlyProTierProducts() async {
        // Given
        let proMonthly = MockSubscriptionProduct(id: "com.test.monthly.pro", isMonthly: true)
        let proYearly = MockSubscriptionProduct(id: "com.test.yearly.pro", isYearly: true)

        mockProductFetcher.mockProducts = [proMonthly, proYearly]
        await sut.updateAvailableProducts()

        // When
        let regularProducts = await sut.getAvailableProducts(includeProTier: false)
        let allProducts = await sut.getAvailableProducts(includeProTier: true)

        // Then
        XCTAssertEqual(regularProducts.count, 0, "Should filter out all pro products")
        XCTAssertEqual(allProducts.count, 2, "Should include all pro products")
    }

    // MARK: - Subscription Tier Options Tests

    func testSubscriptionTierOptionsReturnsFailureWhenNoProductsExist() async {
        // Given
        mockProductFetcher.mockProducts = []
        await sut.updateAvailableProducts()

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: false)

        // Then
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error, .tieredProductsNoProductsAvailable)
        }
    }

    func testSubscriptionTierOptionsReturnsPlusTierOnly() async {
        // Given
        let monthlyProduct = MockSubscriptionProduct(
            id: "com.test.monthly",
            displayName: "Plus Monthly",
            displayPrice: "$9.99",
            isMonthly: true
        )
        let yearlyProduct = MockSubscriptionProduct(
            id: "com.test.yearly",
            displayName: "Plus Yearly",
            displayPrice: "$99.99",
            isYearly: true
        )

        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // Setup mock features
        let plusFeatures = [
            TierFeature(product: .networkProtection, name: .plus),
            TierFeature(product: .dataBrokerProtection, name: .plus),
            TierFeature(product: .identityTheftRestoration, name: .plus),
            TierFeature(product: .paidAIChat, name: .plus)
        ]
        mockCache.tierMapping = ["com.test.monthly": plusFeatures]

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: false)

        // Then
        guard case .success(let tierOptions) = result else {
            XCTFail("Expected success but got failure")
            return
        }

        XCTAssertEqual(tierOptions.products.count, 1)

        let plusTier = tierOptions.products.first
        XCTAssertEqual(plusTier?.tier, .plus)
        XCTAssertEqual(plusTier?.features.count, 4)
        XCTAssertEqual(plusTier?.options.count, 2)

        // Verify features
        XCTAssertTrue(plusTier?.features.contains(where: { $0.product == .networkProtection && $0.name == .plus }) ?? false)
        XCTAssertTrue(plusTier?.features.contains(where: { $0.product == .dataBrokerProtection && $0.name == .plus }) ?? false)
        XCTAssertTrue(plusTier?.features.contains(where: { $0.product == .identityTheftRestoration && $0.name == .plus }) ?? false)
        XCTAssertTrue(plusTier?.features.contains(where: { $0.product == .paidAIChat && $0.name == .plus }) ?? false)

        // Verify options
        let optionIds = plusTier?.options.map { $0.id } ?? []
        XCTAssertTrue(optionIds.contains("com.test.monthly"))
        XCTAssertTrue(optionIds.contains("com.test.yearly"))
    }

    func testSubscriptionTierOptionsReturnsBothPlusAndProTiers() async {
        // Given
        let plusMonthly = MockSubscriptionProduct(
            id: "com.test.monthly",
            displayName: "Plus Monthly",
            displayPrice: "$9.99",
            isMonthly: true
        )
        let plusYearly = MockSubscriptionProduct(
            id: "com.test.yearly",
            displayName: "Plus Yearly",
            displayPrice: "$99.99",
            isYearly: true
        )
        let proMonthly = MockSubscriptionProduct(
            id: "com.test.monthly.pro",
            displayName: "Pro Monthly",
            displayPrice: "$19.99",
            isMonthly: true
        )
        let proYearly = MockSubscriptionProduct(
            id: "com.test.yearly.pro",
            displayName: "Pro Yearly",
            displayPrice: "$199.99",
            isYearly: true
        )

        mockProductFetcher.mockProducts = [plusMonthly, plusYearly, proMonthly, proYearly]
        await sut.updateAvailableProducts()

        // Setup mock features
        let plusFeatures = [
            TierFeature(product: .networkProtection, name: .plus),
            TierFeature(product: .dataBrokerProtection, name: .plus)
        ]
        let proFeatures = [
            TierFeature(product: .networkProtection, name: .pro),
            TierFeature(product: .dataBrokerProtection, name: .pro),
            TierFeature(product: .identityTheftRestoration, name: .pro),
            TierFeature(product: .paidAIChat, name: .pro)
        ]
        mockCache.tierMapping = [
            "com.test.monthly": plusFeatures,
            "com.test.monthly.pro": proFeatures
        ]

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: true)

        // Then
        guard case .success(let tierOptions) = result else {
            XCTFail("Expected success but got failure")
            return
        }

        XCTAssertEqual(tierOptions.products.count, 2)

        // Verify Plus tier
        let plusTier = tierOptions.products.first { $0.tier == .plus }
        XCTAssertNotNil(plusTier)
        XCTAssertEqual(plusTier?.features.count, 2)
        XCTAssertEqual(plusTier?.options.count, 2)
        XCTAssertTrue(plusTier?.features.allSatisfy { $0.name == .plus } ?? false)

        // Verify Pro tier
        let proTier = tierOptions.products.first { $0.tier == .pro }
        XCTAssertNotNil(proTier)
        XCTAssertEqual(proTier?.features.count, 4)
        XCTAssertEqual(proTier?.options.count, 2)
        XCTAssertTrue(proTier?.features.allSatisfy { $0.name == .pro } ?? false)

        // Verify Pro tier has more features
        XCTAssertGreaterThan(proTier?.features.count ?? 0, plusTier?.features.count ?? 0)
    }

    func testSubscriptionTierOptionsWithFreeTrialProducts() async {
        // Given
        let monthlyWithTrial = MockSubscriptionProduct(
            id: "com.test.monthly.trial",
            displayName: "Plus Monthly with Trial",
            displayPrice: "$9.99",
            isMonthly: true,
            hasIntroductoryFreeTrialOffer: true,
            introOffer: MockIntroductoryOffer(
                id: "trial1",
                displayPrice: "$0.00",
                periodInDays: 7,
                isFreeTrial: true
            ),
            isEligibleForFreeTrial: true
        )
        let yearlyWithTrial = MockSubscriptionProduct(
            id: "com.test.yearly.trial",
            displayName: "Plus Yearly with Trial",
            displayPrice: "$99.99",
            isYearly: true,
            hasIntroductoryFreeTrialOffer: true,
            introOffer: MockIntroductoryOffer(
                id: "trial2",
                displayPrice: "$0.00",
                periodInDays: 14,
                isFreeTrial: true
            ),
            isEligibleForFreeTrial: true
        )

        mockProductFetcher.mockProducts = [monthlyWithTrial, yearlyWithTrial]
        await sut.updateAvailableProducts()

        // Setup mock features
        let plusFeatures = [
            TierFeature(product: .networkProtection, name: .plus)
        ]
        mockCache.tierMapping = ["com.test.monthly.trial": plusFeatures]

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: false)

        // Then
        guard case .success(let tierOptions) = result else {
            XCTFail("Expected success but got failure")
            return
        }

        let plusTier = tierOptions.products.first
        XCTAssertNotNil(plusTier)

        // Verify trial offers are included in options
        let monthlyOption = plusTier?.options.first { $0.id == "com.test.monthly.trial" }
        XCTAssertNotNil(monthlyOption?.offer)
        XCTAssertEqual(monthlyOption?.offer?.type, .freeTrial)
        XCTAssertEqual(monthlyOption?.offer?.durationInDays, 7)
        XCTAssertTrue(monthlyOption?.offer?.isUserEligible ?? false)

        let yearlyOption = plusTier?.options.first { $0.id == "com.test.yearly.trial" }
        XCTAssertNotNil(yearlyOption?.offer)
        XCTAssertEqual(yearlyOption?.offer?.type, .freeTrial)
        XCTAssertEqual(yearlyOption?.offer?.durationInDays, 14)
        XCTAssertTrue(yearlyOption?.offer?.isUserEligible ?? false)
    }

    func testSubscriptionTierOptionsExcludesProTierWhenNotRequested() async {
        // Given
        let plusMonthly = MockSubscriptionProduct(id: "com.test.monthly", isMonthly: true)
        let plusYearly = MockSubscriptionProduct(id: "com.test.yearly", isYearly: true)
        let proMonthly = MockSubscriptionProduct(id: "com.test.monthly.pro", isMonthly: true)
        let proYearly = MockSubscriptionProduct(id: "com.test.yearly.pro", isYearly: true)

        mockProductFetcher.mockProducts = [plusMonthly, plusYearly, proMonthly, proYearly]
        await sut.updateAvailableProducts()

        // Setup mock features
        let plusFeatures = [TierFeature(product: .networkProtection, name: .plus)]
        mockCache.tierMapping = ["com.test.monthly": plusFeatures]

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: false)

        // Then
        guard case .success(let tierOptions) = result else {
            XCTFail("Expected success but got failure")
            return
        }

        XCTAssertEqual(tierOptions.products.count, 1)
        XCTAssertEqual(tierOptions.products.first?.tier, .plus)

        // Verify no Pro tier products in options
        let allOptionIds = tierOptions.products.flatMap { $0.options.map { $0.id } }
        XCTAssertFalse(allOptionIds.contains("com.test.monthly.pro"))
        XCTAssertFalse(allOptionIds.contains("com.test.yearly.pro"))
    }

    func testSubscriptionTierOptionsReturnsCorrectPlatform() async {
        // Given
        let monthlyProduct = MockSubscriptionProduct(id: "com.test.monthly", isMonthly: true)
        let yearlyProduct = MockSubscriptionProduct(id: "com.test.yearly", isYearly: true)

        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // Setup mock features
        let features = [TierFeature(product: .networkProtection, name: .plus)]
        mockCache.tierMapping = ["com.test.monthly": features]

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: false)

        // Then
        guard case .success(let tierOptions) = result else {
            XCTFail("Expected success but got failure")
            return
        }

        #if os(iOS)
        XCTAssertEqual(tierOptions.platform, .ios)
        #else
        XCTAssertEqual(tierOptions.platform, .macos)
        #endif
    }

    func testSubscriptionTierOptionsHandlesMissingFeatures() async {
        // Given
        let monthlyProduct = MockSubscriptionProduct(id: "com.test.monthly", isMonthly: true)
        let yearlyProduct = MockSubscriptionProduct(id: "com.test.yearly", isYearly: true)

        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // Setup empty features map (features not fetched successfully)
        mockCache.shouldThrowError = SubscriptionEndpointServiceError.invalidRequest

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: false)

        // Then
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error, .tieredProductsFeatureAPIFailed(SubscriptionEndpointServiceError.invalidRequest))
        }
    }

    func testSubscriptionTierOptionsReturnsNoTiersCreatedWhenFeaturesAreEmpty() async {
        // Given
        let monthlyProduct = MockSubscriptionProduct(id: "com.test.monthly", isMonthly: true)
        let yearlyProduct = MockSubscriptionProduct(id: "com.test.yearly", isYearly: true)

        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // Setup empty features for the product (API returns empty features)
        mockCache.tierMapping = ["com.test.monthly": []]

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: false)

        // Then
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error, .tieredProductsNoTiersCreated)
        }
    }

    func testSubscriptionTierOptionsReturnsNoTiersCreatedWhenFeaturesNotFoundForProduct() async {
        // Given
        let monthlyProduct = MockSubscriptionProduct(id: "com.test.monthly", isMonthly: true)
        let yearlyProduct = MockSubscriptionProduct(id: "com.test.yearly", isYearly: true)

        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // Setup features for a different product ID (not found for the representative product)
        mockCache.tierMapping = ["com.test.other": [TierFeature(product: .networkProtection, name: .plus)]]

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: false)

        // Then
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertEqual(error, .tieredProductsNoTiersCreated)
        }
    }

    func testSubscriptionTierOptionsFetchesOnlyOneProductPerTier() async {
        // Given
        let plusMonthly = MockSubscriptionProduct(id: "com.test.monthly", isMonthly: true)
        let plusYearly = MockSubscriptionProduct(id: "com.test.yearly", isYearly: true)
        let proMonthly = MockSubscriptionProduct(id: "com.test.monthly.pro", isMonthly: true)
        let proYearly = MockSubscriptionProduct(id: "com.test.yearly.pro", isYearly: true)

        mockProductFetcher.mockProducts = [plusMonthly, plusYearly, proMonthly, proYearly]
        await sut.updateAvailableProducts()

        // Setup mock features for both representative products
        let plusFeatures = [TierFeature(product: .networkProtection, name: .plus)]
        let proFeatures = [TierFeature(product: .paidAIChat, name: .pro)]
        mockCache.tierMapping = [
            "com.test.monthly": plusFeatures,
            "com.test.monthly.pro": proFeatures
        ]

        // When
        let result = await sut.subscriptionTierOptions(includeProTier: true)

        // Then
        guard case .success(let tierOptions) = result else {
            XCTFail("Expected success but got failure")
            return
        }

        // Verify that cache was called with only representative products (one per tier)
        // Both monthly products should have been used as representatives
        XCTAssertNotNil(mockCache.tierMapping["com.test.monthly"])
        XCTAssertNotNil(mockCache.tierMapping["com.test.monthly.pro"])
    }
}

private final class MockProductFetcher: ProductFetching {
    var mockProducts: [any StoreProduct] = []
    var fetchError: Error?
    var fetchCount: Int = 0

    public func products(for identifiers: [String]) async throws -> [any StoreProduct] {
        fetchCount += 1
        if let error = fetchError {
            throw error
        }
        return mockProducts
    }
}

private enum MockProductError: Error {
    case fetchFailed
}

private extension StorePurchaseManagerTests {
    func createMonthlyProduct(withTrial: Bool = false, isEligibleForFreeTrial: Bool = true) -> MockSubscriptionProduct {
        MockSubscriptionProduct(
            id: "com.test.monthly\(withTrial ? ".trial" : "")",
            displayName: "Monthly Plan\(withTrial ? " with Trial" : "")",
            displayPrice: "$9.99",
            isMonthly: true,
            hasIntroductoryFreeTrialOffer: withTrial,
            introOffer: withTrial ? MockIntroductoryOffer(
                id: "trial1",
                displayPrice: "Free",
                periodInDays: 7,
                isFreeTrial: true
            ) : nil,
            isEligibleForFreeTrial: isEligibleForFreeTrial
        )
    }

    func createYearlyProduct(withTrial: Bool = false, isEligibleForFreeTrial: Bool = true) -> MockSubscriptionProduct {
        MockSubscriptionProduct(
            id: "com.test.yearly\(withTrial ? ".trial" : "")",
            displayName: "Yearly Plan\(withTrial ? " with Trial" : "")",
            displayPrice: "$99.99",
            isYearly: true,
            hasIntroductoryFreeTrialOffer: withTrial,
            introOffer: withTrial ? MockIntroductoryOffer(
                id: "trial2",
                displayPrice: "Free",
                periodInDays: 14,
                isFreeTrial: true
            ) : nil,
            isEligibleForFreeTrial: isEligibleForFreeTrial
        )
    }
}

private class MockSubscriptionProduct: StoreProduct {
    let id: String
    let displayName: String
    let displayPrice: String
    let description: String
    let isMonthly: Bool
    let isYearly: Bool
    let hasIntroductoryFreeTrialOffer: Bool
    private let mockIntroOffer: MockIntroductoryOffer?
    private let mockIsEligibleForFreeTrial: Bool

    var eligibilityAfterRefresh: Bool?

    init(id: String,
         displayName: String = "Mock Product",
         displayPrice: String = "$4.99",
         description: String = "Mock Description",
         isMonthly: Bool = false,
         isYearly: Bool = false,
         hasIntroductoryFreeTrialOffer: Bool = false,
         introOffer: MockIntroductoryOffer? = nil,
         isEligibleForFreeTrial: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.description = description
        self.isMonthly = isMonthly
        self.isYearly = isYearly
        self.hasIntroductoryFreeTrialOffer = hasIntroductoryFreeTrialOffer
        self.mockIntroOffer = introOffer
        self.mockIsEligibleForFreeTrial = isEligibleForFreeTrial
    }

    var introductoryOffer: SubscriptionProductIntroductoryOffer? {
        return mockIntroOffer
    }

    var isEligibleForFreeTrial: Bool {
        eligibilityAfterRefresh ?? mockIsEligibleForFreeTrial
    }

    func purchase(options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult {
        fatalError("Not implemented for tests")
    }

    static func == (lhs: MockSubscriptionProduct, rhs: MockSubscriptionProduct) -> Bool {
        return lhs.id == rhs.id
    }
}

private struct MockIntroductoryOffer: SubscriptionProductIntroductoryOffer {
    var id: String?
    var displayPrice: String
    var periodInDays: Int
    var isFreeTrial: Bool
}

private class MockFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags> {
    var enabledFeatures: Set<SubscriptionFeatureFlags> = []

    init(enabledFeatures: Set<SubscriptionFeatureFlags> = []) {
        self.enabledFeatures = enabledFeatures
        super.init(mapping: { _ in true })
    }

    override func isFeatureOn(_ feature: SubscriptionFeatureFlags) -> Bool {
        return enabledFeatures.contains(feature)
    }
}

private class MockStoreSubscriptionConfiguration: StoreSubscriptionConfiguration {
    let usaIdentifiers = ["com.test.usa.monthly", "com.test.usa.yearly"]
    let rowIdentifiers = ["com.test.row.monthly", "com.test.row.yearly"]

    var allSubscriptionIdentifiers: [String] {
        usaIdentifiers + rowIdentifiers
    }

    func subscriptionIdentifiers(for region: SubscriptionRegion) -> [String] {
        switch region {
        case .usa:
            return usaIdentifiers
        case .restOfWorld:
            return rowIdentifiers
        }
    }

    func subscriptionIdentifiers(for country: String) -> [String] {
        switch country.uppercased() {
        case "USA":
            return usaIdentifiers
        default:
            return rowIdentifiers
        }
    }
}

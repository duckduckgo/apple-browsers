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

final class StorePurchaseManagerTests: XCTestCase {

    private var sut: StorePurchaseManager!
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

    func testSubscriptionOptionsReturnsOnlyNonTrialProducts() async {
        // Given
        let monthlyProduct = MockSubscriptionProduct(
            id: "com.test.monthly",
            displayName: "Monthly Plan",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: false
        )

        let yearlyProduct = MockSubscriptionProduct(
            id: "com.test.yearly",
            displayName: "Yearly Plan",
            displayPrice: "$99.99",
            isYearly: true,
            isFreeTrialProduct: false
        )

        let monthlyTrialProduct = MockSubscriptionProduct(
            id: "com.test.monthly.trial",
            displayName: "Monthly Plan with Trial",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: true,
            introOffer: MockIntroductoryOffer(
                id: "trial1",
                displayPrice: "Free",
                periodInDays: 7,
                isFreeTrial: true
            )
        )

        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct, monthlyTrialProduct]
        await sut.updateAvailableProducts()

        // When
        let subscriptionOptions = await sut.subscriptionOptions()

        // Then
        XCTAssertNotNil(subscriptionOptions)
        XCTAssertEqual(subscriptionOptions?.options.count, 2)

        let productIds = subscriptionOptions?.options.map { $0.id } ?? []
        XCTAssertTrue(productIds.contains("com.test.monthly"))
        XCTAssertTrue(productIds.contains("com.test.yearly"))
        XCTAssertFalse(productIds.contains("com.test.monthly.trial"))
    }

    func testFreeTrialSubscriptionOptionsReturnsOnlyTrialProducts() async {
        // Given
        let monthlyTrialProduct = MockSubscriptionProduct(
            id: "com.test.monthly.trial",
            displayName: "Monthly Plan with Trial",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: true,
            introOffer: MockIntroductoryOffer(
                id: "trial1",
                displayPrice: "Free",
                periodInDays: 7,
                isFreeTrial: true
            ),
            isEligibleForIntroOffer: true
        )

        let yearlyTrialProduct = MockSubscriptionProduct(
            id: "com.test.yearly.trial",
            displayName: "Yearly Plan with Trial",
            displayPrice: "$99.99",
            isYearly: true,
            isFreeTrialProduct: true,
            introOffer: MockIntroductoryOffer(
                id: "trial2",
                displayPrice: "Free",
                periodInDays: 7,
                isFreeTrial: true
            ),
            isEligibleForIntroOffer: true
        )

        let regularProduct = MockSubscriptionProduct(
            id: "com.test.regular",
            displayName: "Regular Plan",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: false
        )

        mockProductFetcher.mockProducts = [monthlyTrialProduct, yearlyTrialProduct, regularProduct]
        await sut.updateAvailableProducts()

        // When
        let subscriptionOptions = await sut.freeTrialSubscriptionOptions()

        // Then
        XCTAssertNotNil(subscriptionOptions)
        XCTAssertEqual(subscriptionOptions?.options.count, 2)

        let productIds = subscriptionOptions?.options.map { $0.id } ?? []
        XCTAssertTrue(productIds.contains("com.test.monthly.trial"))
        XCTAssertTrue(productIds.contains("com.test.yearly.trial"))
        XCTAssertFalse(productIds.contains("com.test.regular"))
    }

    func testSubscriptionOptionsReturnsNilWhenNoValidProductPairExists() async {
        // Given
        let monthlyProduct = MockSubscriptionProduct(
            id: "com.test.monthly",
            displayName: "Monthly Plan",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: false
        )

        mockProductFetcher.mockProducts = [monthlyProduct]
        await sut.updateAvailableProducts()

        // When
        let subscriptionOptions = await sut.subscriptionOptions()

        // Then
        XCTAssertNil(subscriptionOptions)
    }

    func testFreeTrialSubscriptionOptionsReturnsNilWhenNoValidProductPairExists() async {
        // Given
        let monthlyTrialProduct = MockSubscriptionProduct(
            id: "com.test.monthly.trial",
            displayName: "Monthly Plan with Trial",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: true,
            introOffer: MockIntroductoryOffer(
                id: "trial1",
                displayPrice: "Free",
                periodInDays: 7,
                isFreeTrial: true
            )
        )

        mockProductFetcher.mockProducts = [monthlyTrialProduct]
        await sut.updateAvailableProducts()

        // When
        let subscriptionOptions = await sut.freeTrialSubscriptionOptions()

        // Then
        XCTAssertNil(subscriptionOptions)
    }

    func testSubscriptionOptionsIncludesCorrectDetails() async {
        // Given
        let monthlyProduct = MockSubscriptionProduct(
            id: "com.test.monthly",
            displayName: "Monthly Plan",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: false
        )

        let yearlyProduct = MockSubscriptionProduct(
            id: "com.test.yearly",
            displayName: "Yearly Plan",
            displayPrice: "$99.99",
            isYearly: true,
            isFreeTrialProduct: false
        )

        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // When
        let subscriptionOptions = await sut.subscriptionOptions()

        // Then
        XCTAssertNotNil(subscriptionOptions)
        XCTAssertEqual(subscriptionOptions?.options.count, 2)

        let monthlyOption = subscriptionOptions?.options.first { $0.id == "com.test.monthly" }
        XCTAssertNotNil(monthlyOption)
        XCTAssertEqual(monthlyOption?.cost.displayPrice, "$9.99")
        XCTAssertEqual(monthlyOption?.cost.recurrence, "monthly")
        XCTAssertNil(monthlyOption?.offer)

        let yearlyOption = subscriptionOptions?.options.first { $0.id == "com.test.yearly" }
        XCTAssertNotNil(yearlyOption)
        XCTAssertEqual(yearlyOption?.cost.displayPrice, "$99.99")
        XCTAssertEqual(yearlyOption?.cost.recurrence, "yearly")
        XCTAssertNil(yearlyOption?.offer)
    }

    func testFreeTrialSubscriptionOptionsIncludesCorrectTrialDetails() async {
        // Given
        let monthlyTrialProduct = MockSubscriptionProduct(
            id: "com.test.monthly.trial",
            displayName: "Monthly Plan with Trial",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: true,
            introOffer: MockIntroductoryOffer(
                id: "trial1",
                displayPrice: "$0.00",
                periodInDays: 7,
                isFreeTrial: true
            ),
            isEligibleForIntroOffer: true
        )

        let yearlyTrialProduct = MockSubscriptionProduct(
            id: "com.test.yearly.trial",
            displayName: "Yearly Plan with Trial",
            displayPrice: "$99.99",
            isYearly: true,
            isFreeTrialProduct: true,
            introOffer: MockIntroductoryOffer(
                id: "trial2",
                displayPrice: "$0.00",
                periodInDays: 14,
                isFreeTrial: true
            ),
            isEligibleForIntroOffer: true
        )

        mockProductFetcher.mockProducts = [monthlyTrialProduct, yearlyTrialProduct]
        await sut.updateAvailableProducts()

        // When
        let subscriptionOptions = await sut.freeTrialSubscriptionOptions()

        // Then
        XCTAssertNotNil(subscriptionOptions)

        let monthlyOption = subscriptionOptions?.options.first { $0.id == "com.test.monthly.trial" }
        XCTAssertNotNil(monthlyOption)
        XCTAssertNotNil(monthlyOption?.offer)
        XCTAssertEqual(monthlyOption?.offer?.type, .freeTrial)
        XCTAssertEqual(monthlyOption?.offer?.durationInDays, 7)
        XCTAssertTrue(monthlyOption?.offer?.isUserEligible ?? false)

        let yearlyOption = subscriptionOptions?.options.first { $0.id == "com.test.yearly.trial" }
        XCTAssertNotNil(yearlyOption)
        XCTAssertNotNil(yearlyOption?.offer)
        XCTAssertEqual(yearlyOption?.offer?.type, .freeTrial)
        XCTAssertEqual(yearlyOption?.offer?.durationInDays, 14)
        XCTAssertTrue(yearlyOption?.offer?.isUserEligible ?? false)
    }

    func testUpdateAvailableProductsSuccessfully() async {
        // Given
        let monthlyProduct = createMonthlyProduct()
        let yearlyProduct = createYearlyProduct()
        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]

        // When
        await sut.updateAvailableProducts()

        // Then
        let products = (sut as? DefaultStorePurchaseManager)?.availableProducts ?? []
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
        let products = (sut as? DefaultStorePurchaseManager)?.availableProducts ?? []
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
        mockFeatureFlagger.enabledFeatures = [] // No ROW features enabled - defaults to USA

        // When - Update for USA region
        await sut.updateAvailableProducts()

        // Then - Verify USA products
        let usaProducts = (sut as? DefaultStorePurchaseManager)?.availableProducts ?? []
        XCTAssertEqual(usaProducts.count, 2)
        XCTAssertEqual((sut as? DefaultStorePurchaseManager)?.currentStorefrontRegion, .usa)
        XCTAssertTrue(usaProducts.contains(where: { $0.id == "com.test.usa.monthly" }))
        XCTAssertTrue(usaProducts.contains(where: { $0.id == "com.test.usa.yearly" }))

        // When - Switch to ROW region
        mockProductFetcher.mockProducts = [rowMonthlyProduct, rowYearlyProduct]
        mockFeatureFlagger.enabledFeatures = [.usePrivacyProROWRegionOverride]
        await sut.updateAvailableProducts()

        // Then - Verify ROW products
        let rowProducts = (sut as? DefaultStorePurchaseManager)?.availableProducts ?? []
        XCTAssertEqual(rowProducts.count, 2)
        XCTAssertEqual((sut as? DefaultStorePurchaseManager)?.currentStorefrontRegion, .restOfWorld)
        XCTAssertTrue(rowProducts.contains(where: { $0.id == "com.test.row.monthly" }))
        XCTAssertTrue(rowProducts.contains(where: { $0.id == "com.test.row.yearly" }))

        // Verify pricing differences
        let usaMonthlyPrice = usaProducts.first(where: { $0.isMonthly })?.displayPrice
        let rowMonthlyPrice = rowProducts.first(where: { $0.isMonthly })?.displayPrice
        XCTAssertEqual(usaMonthlyPrice, "$9.99")
        XCTAssertEqual(rowMonthlyPrice, "€8.99")
    }

    func testUpdateAvailableProductsUpdatesFeatureMapping() async {
        // Given
        let monthlyProduct = createMonthlyProduct()
        let yearlyProduct = createYearlyProduct()
        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]

        // When
        await sut.updateAvailableProducts()

        // Then
        XCTAssertTrue(mockCache.didCallSubscriptionFeatures)
        XCTAssertEqual(mockCache.lastCalledSubscriptionId, yearlyProduct.id)
    }

    func testIsUserEligibleForFreeTrialReturnsTrueWhenEligibleProductExists() async {
        // Given
        let monthlyProduct = createMonthlyProduct(withTrial: true)
        let yearlyProduct = createYearlyProduct(withTrial: true)
        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // When
        let isEligible = await sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertTrue(isEligible)
    }

    func testIsUserEligibleForFreeTrialReturnsFalseWhenNoEligibleProductExists() async {
        // Given
        let monthlyProduct = createMonthlyProduct(withTrial: true, isEligibleForIntroOffer: false)
        let yearlyProduct = createYearlyProduct(withTrial: true, isEligibleForIntroOffer: false)
        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // When
        let isEligible = await sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertFalse(isEligible)
    }

    func testIsUserEligibleForFreeTrialReturnsFalseWhenNoTrialProductsExist() async {
        // Given
        let monthlyProduct = createMonthlyProduct(withTrial: false)
        let yearlyProduct = createYearlyProduct(withTrial: false)
        mockProductFetcher.mockProducts = [monthlyProduct, yearlyProduct]
        await sut.updateAvailableProducts()

        // When
        let isEligible = await sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertFalse(isEligible)
    }
}

private final class MockProductFetcher: ProductFetching {
    var mockProducts: [any SubscriptionProduct] = []
    var fetchError: Error?
    var fetchCount: Int = 0

    public func products(for identifiers: [String]) async throws -> [any SubscriptionProduct] {
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
    func createMonthlyProduct(withTrial: Bool = false, isEligibleForIntroOffer: Bool = true) -> MockSubscriptionProduct {
        MockSubscriptionProduct(
            id: "com.test.monthly\(withTrial ? ".trial" : "")",
            displayName: "Monthly Plan\(withTrial ? " with Trial" : "")",
            displayPrice: "$9.99",
            isMonthly: true,
            isFreeTrialProduct: withTrial,
            introOffer: withTrial ? MockIntroductoryOffer(
                id: "trial1",
                displayPrice: "Free",
                periodInDays: 7,
                isFreeTrial: true
            ) : nil,
            isEligibleForIntroOffer: isEligibleForIntroOffer
        )
    }

    func createYearlyProduct(withTrial: Bool = false, isEligibleForIntroOffer: Bool = true) -> MockSubscriptionProduct {
        MockSubscriptionProduct(
            id: "com.test.yearly\(withTrial ? ".trial" : "")",
            displayName: "Yearly Plan\(withTrial ? " with Trial" : "")",
            displayPrice: "$99.99",
            isYearly: true,
            isFreeTrialProduct: withTrial,
            introOffer: withTrial ? MockIntroductoryOffer(
                id: "trial2",
                displayPrice: "Free",
                periodInDays: 14,
                isFreeTrial: true
            ) : nil,
            isEligibleForIntroOffer: isEligibleForIntroOffer
        )
    }
}

private class MockSubscriptionProduct: SubscriptionProduct {
    let id: String
    let displayName: String
    let displayPrice: String
    let description: String
    let isMonthly: Bool
    let isYearly: Bool
    let isFreeTrialProduct: Bool
    private let mockIntroOffer: MockIntroductoryOffer?
    private let mockIsEligibleForIntroOffer: Bool

    init(id: String,
         displayName: String = "Mock Product",
         displayPrice: String = "$4.99",
         description: String = "Mock Description",
         isMonthly: Bool = false,
         isYearly: Bool = false,
         isFreeTrialProduct: Bool = false,
         introOffer: MockIntroductoryOffer? = nil,
         isEligibleForIntroOffer: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.description = description
        self.isMonthly = isMonthly
        self.isYearly = isYearly
        self.isFreeTrialProduct = isFreeTrialProduct
        self.mockIntroOffer = introOffer
        self.mockIsEligibleForIntroOffer = isEligibleForIntroOffer
    }

    var introductoryOffer: SubscriptionProductIntroductoryOffer? {
        return mockIntroOffer
    }

    var isEligibleForIntroOffer: Bool {
        get async {
            return mockIsEligibleForIntroOffer
        }
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
        super.init(mapping: {_ in true})
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

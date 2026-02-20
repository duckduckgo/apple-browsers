//
//  SubscriptionTierOptionsProviderTests.swift
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
@testable import Subscription
import SubscriptionTestingUtilities
import Networking

final class SubscriptionTierOptionsProviderTests: XCTestCase {

    private var mockEndpointService: SubscriptionEndpointServiceMock!
    private var mockStorePurchaseManager: StorePurchaseManagerMock!

    override func setUpWithError() throws {
        mockEndpointService = SubscriptionEndpointServiceMock()
        mockStorePurchaseManager = StorePurchaseManagerMock()
    }

    override func tearDownWithError() throws {
        mockEndpointService = nil
        mockStorePurchaseManager = nil
    }

    // MARK: - Routing: no subscription (use app platform)

    func testWhenNoSubscriptionAndAppPlatformStripeThenFetchesStripeTierOptions() async throws {
        mockEndpointService.getTierProductsResult = .success(SubscriptionMockFactory.tierProductsResponse)

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .stripe,
            storePurchaseManager: nil,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: nil)

        guard case .success(let options) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(options.platform, .stripe)
        XCTAssertFalse(options.products.isEmpty)
    }

    func testWhenNoSubscriptionAndAppPlatformAppStoreThenFetchesAppleTierOptions() async throws {
        guard #available(macOS 12.0, iOS 15.0, *) else { throw XCTSkip("Requires macOS 12 / iOS 15") }
        let expectedOptions = SubscriptionTierOptions(platform: .ios, products: [])
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(expectedOptions)

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .appStore,
            storePurchaseManager: mockStorePurchaseManager,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: nil)

        guard case .success(let options) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(options.platform, expectedOptions.platform)
    }

    // MARK: - Routing: active subscription (use subscription platform)

    func testWhenActiveStripeSubscriptionThenFetchesStripeTierOptions() async throws {
        mockEndpointService.getTierProductsResult = .success(SubscriptionMockFactory.tierProductsResponse)
        let activeStripeSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .stripe)

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .appStore,
            storePurchaseManager: mockStorePurchaseManager,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: activeStripeSubscription)

        guard case .success(let options) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(options.platform, .stripe)
        XCTAssertFalse(options.products.isEmpty)
    }

    func testWhenActiveAppleSubscriptionAndAppStoreAppThenFetchesAppleTierOptions() async throws {
        guard #available(macOS 12.0, iOS 15.0, *) else { throw XCTSkip("Requires macOS 12 / iOS 15") }
        let expectedOptions = SubscriptionTierOptions(platform: .ios, products: [])
        mockStorePurchaseManager.subscriptionTierOptionsResult = .success(expectedOptions)
        let activeAppleSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple)

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .appStore,
            storePurchaseManager: mockStorePurchaseManager,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: activeAppleSubscription)

        guard case .success(let options) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(options.platform, expectedOptions.platform)
    }

    func testWhenActiveAppleSubscriptionAndNonAppStoreAppThenReturnsFailure() async throws {
        let activeAppleSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .apple)

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .stripe,
            storePurchaseManager: nil,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: activeAppleSubscription)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure for Apple subscription on non–App Store app")
            return
        }
        XCTAssertTrue(error is SubscriptionTierOptionsProviderError)
        XCTAssertEqual(error as? SubscriptionTierOptionsProviderError, .tierOptionsNotAvailableForPlatform)
    }

    func testWhenActiveGoogleSubscriptionThenReturnsFailure() async throws {
        let activeGoogleSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .google)

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .appStore,
            storePurchaseManager: mockStorePurchaseManager,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: activeGoogleSubscription)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure for Google subscription")
            return
        }
        XCTAssertEqual(error as? SubscriptionTierOptionsProviderError, .tierOptionsNotAvailableForPlatform)
    }

    func testWhenActiveUnknownSubscriptionThenReturnsFailure() async throws {
        let activeUnknownSubscription = SubscriptionMockFactory.subscription(status: .autoRenewable, platform: .unknown)

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .appStore,
            storePurchaseManager: mockStorePurchaseManager,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: activeUnknownSubscription)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure for unknown subscription platform")
            return
        }
        XCTAssertEqual(error as? SubscriptionTierOptionsProviderError, .tierOptionsNotAvailableForPlatform)
    }

    // MARK: - Optional store (Apple path when store is nil)

    func testWhenAppPlatformAppStoreAndStoreNilThenReturnsFailure() async throws {
        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .appStore,
            storePurchaseManager: nil,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: nil)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure when App Store app has no store")
            return
        }
        XCTAssertEqual(error as? SubscriptionTierOptionsProviderError, .tierOptionsNotAvailableForPlatform)
    }

    // MARK: - Stripe path: API failure and empty products

    func testWhenStripePathAndApiFailsThenReturnsFailure() async throws {
        mockEndpointService.getTierProductsResult = .failure(APIRequestV2Error.invalidResponse)

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .stripe,
            storePurchaseManager: nil,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: nil)

        guard case .failure = result else {
            XCTFail("Expected failure when Stripe API fails")
            return
        }
    }

    func testWhenStripePathAndApiReturnsEmptyProductsThenReturnsFailure() async throws {
        mockEndpointService.getTierProductsResult = .success(GetTierProductsResponse(products: []))

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .stripe,
            storePurchaseManager: nil,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: nil)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure when Stripe API returns empty products")
            return
        }
        XCTAssertEqual(error as? SubscriptionTierOptionsProviderError, .tierOptionsNotAvailableForPlatform)
    }

    // MARK: - Expired subscription (use app platform)

    func testWhenExpiredSubscriptionThenUsesAppPlatform() async throws {
        mockEndpointService.getTierProductsResult = .success(SubscriptionMockFactory.tierProductsResponse)
        let expiredStripeSubscription = SubscriptionMockFactory.expiredStripeSubscription

        let sut = DefaultSubscriptionTierOptionsProvider(
            subscriptionEnvironmentPlatform: .stripe,
            storePurchaseManager: nil,
            subscriptionEndpointService: mockEndpointService
        )

        let result = await sut.subscriptionTierOptions(includeProTier: false, currentSubscription: expiredStripeSubscription)

        guard case .success(let options) = result else {
            XCTFail("Expected success using app platform when subscription is expired")
            return
        }
        XCTAssertEqual(options.platform, .stripe)
    }
}

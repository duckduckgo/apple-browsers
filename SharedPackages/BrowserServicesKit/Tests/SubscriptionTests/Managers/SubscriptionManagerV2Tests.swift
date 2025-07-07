//
//  SubscriptionManagerV2Tests.swift
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
import Common
@testable import Subscription
@testable import Networking
import SubscriptionTestingUtilities
import NetworkingTestingUtils

class SubscriptionManagerV2Tests: XCTestCase {

    struct Constants {
        static let tld = TLD()
    }

    var subscriptionManager: DefaultSubscriptionManagerV2!
    var mockOAuthClient: MockOAuthClient!
    var mockSubscriptionEndpointService: SubscriptionEndpointServiceMockV2!
    var mockStorePurchaseManager: StorePurchaseManagerMockV2!
    var mockAppStoreRestoreFlowV2: AppStoreRestoreFlowMockV2!
    var overrideTokenResponseInRecoveryHandler: Result<Networking.TokenContainer, Error>?

    override func setUp() {
        super.setUp()

        mockOAuthClient = MockOAuthClient()
        mockOAuthClient.migrateV1TokenResponseError = OAuthClientError.authMigrationNotPerformed
        mockSubscriptionEndpointService = SubscriptionEndpointServiceMockV2()
        mockStorePurchaseManager = StorePurchaseManagerMockV2()
        mockAppStoreRestoreFlowV2 = AppStoreRestoreFlowMockV2()
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        subscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
            pixelHandler: MockPixelHandler()
        )

        subscriptionManager.tokenRecoveryHandler = {
            if let overrideTokenResponse = self.overrideTokenResponseInRecoveryHandler {
                self.mockOAuthClient.getTokensResponse = overrideTokenResponse
            }
            try await DeadTokenRecoverer.attemptRecoveryFromPastPurchase(subscriptionManager: self.subscriptionManager, restoreFlow: self.mockAppStoreRestoreFlowV2)
        }
    }

    override func tearDown() {
        subscriptionManager = nil
        mockOAuthClient = nil
        mockSubscriptionEndpointService = nil
        mockStorePurchaseManager = nil
        super.tearDown()
    }

    // MARK: - Token Retrieval Tests

    func testGetTokenContainer_Success() async throws {
        let expectedTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(expectedTokenContainer)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(result, expectedTokenContainer)
    }

    // MARK: - Subscription Status Tests

    func testRefreshCachedSubscription_ActiveSubscription() async throws {
        let activeSubscription = PrivacyProSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.minutes(-5)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(30)),
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: []
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(activeSubscription)
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer

        let subscription = try await subscriptionManager.getSubscription(cachePolicy: .remoteFirst)
        XCTAssertTrue(subscription.isActive)
    }

    func testRefreshCachedSubscription_ExpiredSubscription() async {
        let expiredSubscription = PrivacyProSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.days(-30)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(-1)), // expired
            platform: .apple,
            status: .expired,
            activeOffers: []
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(expiredSubscription)
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        do {
            try await subscriptionManager.getSubscription(cachePolicy: .remoteFirst)
        } catch {
            XCTAssertEqual(error.localizedDescription, SubscriptionEndpointServiceError.noData.localizedDescription)
        }
    }

    // MARK: - URL Generation Tests

    func testURLGeneration_ForCustomerPortal() async throws {
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        let customerPortalURLString = "https://example.com/customer-portal"
        mockSubscriptionEndpointService.getCustomerPortalURLResult = .success(GetCustomerPortalURLResponse(customerPortalUrl: customerPortalURLString))

        let url = try await subscriptionManager.getCustomerPortalURL()
        XCTAssertEqual(url.absoluteString, customerPortalURLString)
    }

    func testURLGeneration_ForSubscriptionTypes() {
        let environment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        subscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: environment,
            pixelHandler: MockPixelHandler()
        )

        let helpURL = subscriptionManager.url(for: .purchase)
        XCTAssertEqual(helpURL.absoluteString, "https://duckduckgo.com/subscriptions")
    }

    // MARK: - Purchase Confirmation Tests

    func testConfirmPurchase_ErrorHandling() async throws {
        let testSignature = "invalidSignature"
        mockSubscriptionEndpointService.confirmPurchaseResult = .failure(APIRequestV2.Error.invalidResponse)
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        mockOAuthClient.migrateV1TokenResponseError = OAuthClientError.authMigrationNotPerformed
        do {
            _ = try await subscriptionManager.confirmPurchase(signature: testSignature, additionalParams: nil)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? APIRequestV2.Error, APIRequestV2.Error.invalidResponse)
        }
    }

    // MARK: - Tests for save and loadEnvironmentFrom

    var subscriptionEnvironment: SubscriptionEnvironment!

    func testLoadEnvironmentFromUserDefaults() async throws {
        subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                          purchasePlatform: .appStore)
        let userDefaultsSuiteName = "SubscriptionManagerTests"
        // Given
        let userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)

        var loadedEnvironment = DefaultSubscriptionManagerV2.loadEnvironmentFrom(userDefaults: userDefaults)
        XCTAssertNil(loadedEnvironment)

        // When
        DefaultSubscriptionManagerV2.save(subscriptionEnvironment: subscriptionEnvironment,
                                          userDefaults: userDefaults)
        loadedEnvironment = DefaultSubscriptionManagerV2.loadEnvironmentFrom(userDefaults: userDefaults)

        // Then
        XCTAssertEqual(loadedEnvironment?.serviceEnvironment, subscriptionEnvironment.serviceEnvironment)
        XCTAssertEqual(loadedEnvironment?.purchasePlatform, subscriptionEnvironment.purchasePlatform)
    }

    // MARK: - Tests for url

    func testForProductionURL() throws {
        // Given
        let productionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let productionSubscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: productionEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let productionPurchaseURL = productionSubscriptionManager.url(for: .purchase)

        // Then
        XCTAssertEqual(productionPurchaseURL, SubscriptionURL.purchase.subscriptionURL(environment: .production))
    }

    func testForStagingURL() throws {
        // Given
        let stagingEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let stagingSubscriptionManager = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: stagingEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let stagingPurchaseURL = stagingSubscriptionManager.url(for: .purchase)

        // Then
        XCTAssertEqual(stagingPurchaseURL, SubscriptionURL.purchase.subscriptionURL(environment: .staging))
    }

    // MARK: - Dead token recovery

    func testDeadTokenRecoverySuccess() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.refreshTokenExpired)
        overrideTokenResponseInRecoveryHandler = .success(OAuthTokensFactory.makeValidTokenContainer())
        mockSubscriptionEndpointService.getSubscriptionResult = .success(SubscriptionMockFactory.appleSubscription)
        mockAppStoreRestoreFlowV2.restoreAccountFromPastPurchaseResult = .success("some")
        let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertFalse(tokenContainer.decodedAccessToken.isExpired())
    }

    func testDeadTokenRecoveryFailure() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.refreshTokenExpired)
        mockAppStoreRestoreFlowV2.restoreSubscriptionAfterExpiredRefreshTokenError = SubscriptionManagerError.errorRetrievingTokenContainer(error: nil)

        do {
            try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("This should fail with error: SubscriptionManagerError.tokenRefreshFailed")
        } catch SubscriptionManagerError.noTokenAvailable {

        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// Dead token error loop detector: this case shouldn't be possible, but if the BE starts to send back expired tokens we risk to enter in an infinite loop.
    func testDeadTokenRecoveryLoop() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.refreshTokenExpired)
        mockSubscriptionEndpointService.getSubscriptionResult = .success(SubscriptionMockFactory.appleSubscription)
        mockAppStoreRestoreFlowV2.restoreAccountFromPastPurchaseResult = .success("some")
        do {
            try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("This should fail with error: SubscriptionManagerError.tokenRefreshFailed")
        } catch SubscriptionManagerError.noTokenAvailable {

        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("This should fail with error: SubscriptionManagerError.tokenRefreshFailed")
        } catch SubscriptionManagerError.noTokenAvailable {

        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Tests for Free Trial Eligibility

    func testWhenPlatformIsStripeUserIsEligibleForFreeTrialThenReturnsNotEligible() throws {
        // Given
        mockStorePurchaseManager.isEligibleForFreeTrialResult = true
        let stripeEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let sut = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: stripeEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let result = sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertFalse(result)
    }

    func testWhenPlatformIsAppStoreAndUserIsEligibleForFreeTrialThenReturnsEligible() throws {
        // Given
        mockStorePurchaseManager.isEligibleForFreeTrialResult = true
        let appStoreEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let sut = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: appStoreEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let result = sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertTrue(result)
    }

    func testWhenPlatformIsAppStoreAndUserIsNotEligibleForFreeTrialThenReturnsNotEligible() throws {
        // Given
        mockStorePurchaseManager.isEligibleForFreeTrialResult = false
        let appStoreEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let sut = DefaultSubscriptionManagerV2(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: appStoreEnvironment,
            pixelHandler: MockPixelHandler()
        )

        // When
        let result = sut.isUserEligibleForFreeTrial()

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - Tests for canPurchasePublisher

    func testCanPurchasePublisherEmitsValuesFromStorePurchaseManager() async throws {
        // Given
        let expectation = expectation(description: "Publisher should emit value")
        var receivedValue: Bool?

        // When
        let cancellable = subscriptionManager.canPurchasePublisher
            .sink { value in
                receivedValue = value
                expectation.fulfill()
            }

        // Simulate store purchase manager emitting a value
        mockStorePurchaseManager.areProductsAvailableSubject.send(true)

        // Then
        await fulfillment(of: [expectation], timeout: 0.5)
        XCTAssertTrue(receivedValue ?? false)

        // Clean up
        cancellable.cancel()
    }

    func testCanPurchasePublisherEmitsMultipleValues() async throws {
        // Given
        let expectation1 = expectation(description: "Publisher should emit first value")
        let expectation2 = expectation(description: "Publisher should emit second value")
        var receivedValues: [Bool] = []

        // When
        let cancellable = subscriptionManager.canPurchasePublisher
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count == 1 {
                    expectation1.fulfill()
                } else if receivedValues.count == 2 {
                    expectation2.fulfill()
                }
            }

        // Simulate store purchase manager emitting multiple values
        mockStorePurchaseManager.areProductsAvailableSubject.send(true)
        mockStorePurchaseManager.areProductsAvailableSubject.send(false)

        // Then
        await fulfillment(of: [expectation1, expectation2], timeout: 0.5)
        XCTAssertEqual(receivedValues, [true, false])

        // Clean up
        cancellable.cancel()
    }
}

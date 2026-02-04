//
//  SubscriptionManagerTests.swift
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
import PixelKit

class SubscriptionManagerTests: XCTestCase {

    struct Constants {
        static let tld = TLD()
    }

    var subscriptionManager: DefaultSubscriptionManager!
    var mockOAuthClient: MockOAuthClient!
    var mockSubscriptionEndpointService: SubscriptionEndpointServiceMock!
    var mockStorePurchaseManager: StorePurchaseManagerMock!
    var mockAppStoreRestoreFlowV2: AppStoreRestoreFlowMock!
    fileprivate var mockPixelHandler: MockSubscriptionPixelHandler!
    var overrideTokenResponseInRecoveryHandler: Result<Networking.TokenContainer, Error>?

    override func setUp() {
        super.setUp()

        mockOAuthClient = MockOAuthClient()
        mockSubscriptionEndpointService = SubscriptionEndpointServiceMock()
        mockStorePurchaseManager = StorePurchaseManagerMock()
        mockAppStoreRestoreFlowV2 = AppStoreRestoreFlowMock()
        mockPixelHandler = MockSubscriptionPixelHandler()
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        subscriptionManager = DefaultSubscriptionManager(
            storePurchaseManager: mockStorePurchaseManager,
            oAuthClient: mockOAuthClient,
            userDefaults: userDefaults,
            subscriptionEndpointService: mockSubscriptionEndpointService,
            subscriptionEnvironment: SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore),
            pixelHandler: mockPixelHandler
        )

        subscriptionManager.tokenRecoveryHandler = {
            if let overrideTokenResponse = self.overrideTokenResponseInRecoveryHandler {
                self.mockOAuthClient.getTokensResponse = overrideTokenResponse
                switch overrideTokenResponse {
                case .success(let token):
                    self.mockOAuthClient.internalCurrentTokenContainer = token
                case .failure:
                    self.mockOAuthClient.internalCurrentTokenContainer = nil
                }
            }
            try await DeadTokenRecoverer().attemptRecoveryFromPastPurchase(purchasePlatform: self.subscriptionManager.currentEnvironment.purchasePlatform, restoreFlow: self.mockAppStoreRestoreFlowV2)
        }
    }

    override func tearDown() {
        subscriptionManager = nil
        mockOAuthClient = nil
        mockSubscriptionEndpointService = nil
        mockStorePurchaseManager = nil
        mockPixelHandler = nil
        super.tearDown()
    }

    // MARK: - Token Retrieval Tests

    func testGetTokenContainer_Success() async throws {
        let expectedTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(expectedTokenContainer)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(result, expectedTokenContainer)
    }

    func testGetTokenContainer_MissingTokenContainer_NoPixels() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.missingTokenContainer)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            let managerError = error as? SubscriptionManagerError
            XCTAssertEqual(managerError, .noTokenAvailable)
            XCTAssertNil(managerError?.underlyingError)
        }

        XCTAssertTrue(mockPixelHandler.handledPixels.isEmpty)
        assertNoGetTokensErrorPixel()
    }

    func testGetTokenContainer_UnknownAccount_SendsGetTokensError() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.unknownAccount)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            let managerError = error as? SubscriptionManagerError
            XCTAssertEqual(managerError, .noTokenAvailable)
            XCTAssertNil(managerError?.underlyingError)
        }

        assertGetTokensErrorPixel(policy: .localValid)
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(.invalidRefreshToken))
    }

    func testGetTokenContainer_InvalidTokenRequest_RecoverySuccess_Pixels() async throws {
        let recoveredTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        overrideTokenResponseInRecoveryHandler = .success(recoveredTokenContainer)

        let result = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertEqual(result, recoveredTokenContainer)

        assertGetTokensErrorPixel(policy: .localValid)
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshToken))
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenRecovered))
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenSignedOut))
    }

    func testGetTokenContainer_InvalidTokenRequest_RecoveryFailure_Pixels() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(.reused))
        overrideTokenResponseInRecoveryHandler = .failure(OAuthClientError.invalidTokenRequest(.reused))

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            let managerError = error as? SubscriptionManagerError
            XCTAssertEqual(managerError, .noTokenAvailable)
            XCTAssertNil(managerError?.underlyingError)
        }

        assertGetTokensErrorPixel(policy: .localValid)
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshToken))
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenSignedOut))
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(.invalidRefreshTokenRecovered))
    }

    func testGetTokenContainer_OtherError_ReportsPixelAndUnderlyingError() async throws {
        let expectedError = OAuthServiceError.invalidResponseCode(.badRequest)
        mockOAuthClient.getTokensResponse = .failure(expectedError)

        do {
            _ = try await subscriptionManager.getTokenContainer(policy: .localValid)
            XCTFail("Error expected")
        } catch {
            let managerError = error as? SubscriptionManagerError
            XCTAssertEqual(managerError, .errorRetrievingTokenContainer(error: expectedError))
            XCTAssertEqual(managerError?.underlyingError as? OAuthServiceError, expectedError)
        }

        assertGetTokensErrorPixel(policy: .localValid)
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(.invalidRefreshToken))
    }

    // MARK: - Subscription Status Tests

    func testRefreshCachedSubscription_ActiveSubscription() async throws {
        let activeSubscription = DuckDuckGoSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.minutes(-5)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(30)),
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(activeSubscription)
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockOAuthClient.getTokensResponse = .success(tokenContainer)
        mockOAuthClient.internalCurrentTokenContainer = tokenContainer

        let subscription = try await subscriptionManager.getSubscription(cachePolicy: .remoteFirst)
        XCTAssertTrue(subscription.isActive)
    }

    func testRefreshCachedSubscription_ExpiredSubscription() async {
        let expiredSubscription = DuckDuckGoSubscription(
            productId: "testProduct",
            name: "Test Subscription",
            billingPeriod: .monthly,
            startedAt: Date().addingTimeInterval(.days(-30)),
            expiresOrRenewsAt: Date().addingTimeInterval(.days(-1)), // expired
            platform: .apple,
            status: .expired,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionEndpointService.getSubscriptionResult = .success(expiredSubscription)
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        do {
            try await subscriptionManager.getSubscription(cachePolicy: .remoteFirst)
        } catch SubscriptionEndpointServiceError.noData {

        } catch {
            XCTFail("Unexpected error: \(error)")
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
        subscriptionManager = DefaultSubscriptionManager(
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
        mockSubscriptionEndpointService.confirmPurchaseResult = .failure(APIRequestV2Error.invalidResponse)
        mockOAuthClient.getTokensResponse = .success(OAuthTokensFactory.makeValidTokenContainer())
        do {
            _ = try await subscriptionManager.confirmPurchase(signature: testSignature, additionalParams: nil)
            XCTFail("Error expected")
        } catch {
            XCTAssertEqual(error as? APIRequestV2Error, APIRequestV2Error.invalidResponse)
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

        var loadedEnvironment = DefaultSubscriptionManager.loadEnvironmentFrom(userDefaults: userDefaults)
        XCTAssertNil(loadedEnvironment)

        // When
        DefaultSubscriptionManager.save(subscriptionEnvironment: subscriptionEnvironment,
                                          userDefaults: userDefaults)
        loadedEnvironment = DefaultSubscriptionManager.loadEnvironmentFrom(userDefaults: userDefaults)

        // Then
        XCTAssertEqual(loadedEnvironment?.serviceEnvironment, subscriptionEnvironment.serviceEnvironment)
        XCTAssertEqual(loadedEnvironment?.purchasePlatform, subscriptionEnvironment.purchasePlatform)
    }

    // MARK: - Tests for url

    func testForProductionURL() throws {
        // Given
        let productionEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let productionSubscriptionManager = DefaultSubscriptionManager(
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
        let stagingSubscriptionManager = DefaultSubscriptionManager(
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
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(OAuthRequest.TokenStatus.expired))
        overrideTokenResponseInRecoveryHandler = .success(OAuthTokensFactory.makeValidTokenContainer())
        mockSubscriptionEndpointService.getSubscriptionResult = .success(SubscriptionMockFactory.appleSubscription)
        mockAppStoreRestoreFlowV2.restoreAccountFromPastPurchaseResult = .success("some")
        let tokenContainer = try await subscriptionManager.getTokenContainer(policy: .localValid)
        XCTAssertFalse(tokenContainer.decodedAccessToken.isExpired())
    }

    func testDeadTokenRecoveryFailure() async throws {
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(OAuthRequest.TokenStatus.fraudDetected))
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
        mockOAuthClient.getTokensResponse = .failure(OAuthClientError.invalidTokenRequest(OAuthRequest.TokenStatus.expired))
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

    func testWhenPlatformIsStripeUserIsEligibleForFreeTrialThenReturnsEligible() throws {
        // Given
        mockStorePurchaseManager.isEligibleForFreeTrialResult = false
        let stripeEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let sut = DefaultSubscriptionManager(
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
        XCTAssertTrue(result)
    }

    func testWhenPlatformIsAppStoreAndUserIsEligibleForFreeTrialThenReturnsEligible() throws {
        // Given
        mockStorePurchaseManager.isEligibleForFreeTrialResult = true
        let appStoreEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        let sut = DefaultSubscriptionManager(
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
        let sut = DefaultSubscriptionManager(
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

    // MARK: - Tests for hasAppStoreProductsAvailablePublisher

    func testCanPurchasePublisherEmitsValuesFromStorePurchaseManager() async throws {
        // Given
        let expectation = expectation(description: "Publisher should emit value")
        var receivedValue: Bool?

        // When
        let cancellable = subscriptionManager.hasAppStoreProductsAvailablePublisher
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
        let cancellable = subscriptionManager.hasAppStoreProductsAvailablePublisher
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

    private func assertGetTokensErrorPixel(policy: AuthTokensCachePolicy) {
        XCTAssertTrue(mockPixelHandler.handledPixels.contains(where: { pixel in
            guard case .getTokensError(let capturedPolicy, _) = pixel else { return false }
            return capturedPolicy == policy
        }))
    }

    private func assertNoGetTokensErrorPixel() {
        XCTAssertFalse(mockPixelHandler.handledPixels.contains(where: { pixel in
            if case .getTokensError = pixel { return true }
            return false
        }))
    }
}

// MARK: - Mock

private final class MockSubscriptionPixelHandler: SubscriptionPixelHandling {
    var handledPixels: [SubscriptionPixelType] = []
    var handledKeychainPixels: [KeychainManager.Pixel] = []

    func handle(pixel: SubscriptionPixelType) {
        handledPixels.append(pixel)
    }

    func handle(pixel: KeychainManager.Pixel) {
        handledKeychainPixels.append(pixel)
    }
}

private struct SubscriptionPixelEvent: PixelKitEvent {
    let name: String
    let parameters: [String: String]?
    let standardParameters: [PixelKitStandardParameter]? = [.pixelSource]
}

//
//  DuckDuckGoSubscriptionIntegrationTests.swift
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
@testable import Networking
import NetworkingTestingUtils
import SubscriptionTestingUtilities
import PixelKitTestingUtilities
import JWTKit

final class DuckDuckGoSubscriptionIntegrationTests: XCTestCase {

    var apiService: MockAPIService!
    var tokenStorage: MockTokenStorage!
    var subscriptionManager: DefaultSubscriptionManager!
    var appStorePurchaseFlow: DefaultAppStorePurchaseFlow!
    var appStoreRestoreFlow: DefaultAppStoreRestoreFlow!
    var stripePurchaseFlow: DefaultStripePurchaseFlow!
    var storePurchaseManager: StorePurchaseManagerMock!
    var subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags>!
    var wideEvent: WideEventMock!

    let subscriptionSelectionID = "ios.subscription.1month"

    override func setUpWithError() throws {
        apiService = MockAPIService()
        apiService.authorizationRefresherCallback = { _ in
            return OAuthTokensFactory.makeValidTokenContainer().accessToken
        }
        let subscriptionEnvironment = SubscriptionEnvironment(serviceEnvironment: .staging, purchasePlatform: .appStore)
        let authService = DefaultOAuthService(baseURL: OAuthEnvironment.staging.url, apiService: apiService)
        // keychain storage
        tokenStorage = MockTokenStorage()

        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            authService: authService,
                                            refreshEventMapping: nil)
        storePurchaseManager = StorePurchaseManagerMock()
        let subscriptionEndpointService = DefaultSubscriptionEndpointService(apiService: apiService,
                                                                               baseURL: subscriptionEnvironment.serviceEnvironment.url)
        subscriptionFeatureFlagger = FeatureFlaggerMapping<SubscriptionFeatureFlags>(mapping: { $0.defaultState })
        let userDefaults = UserDefaults(suiteName: "com.duckduckgo.subscriptionUnitTests.\(UUID().uuidString)")!
        subscriptionManager = DefaultSubscriptionManager(storePurchaseManager: storePurchaseManager,
                                                           oAuthClient: authClient,
                                                           userDefaults: userDefaults,
                                                           subscriptionEndpointService: subscriptionEndpointService,
                                                           subscriptionEnvironment: subscriptionEnvironment,
                                                           pixelHandler: MockPixelHandler())

        appStoreRestoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: subscriptionManager,
                                                           storePurchaseManager: storePurchaseManager)
        wideEvent = WideEventMock()
        appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionManager: subscriptionManager,
                                                             storePurchaseManager: storePurchaseManager,
                                                             appStoreRestoreFlow: appStoreRestoreFlow,
                                                             wideEvent: wideEvent)
        stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionManager: subscriptionManager)
    }

    override func tearDownWithError() throws {
        apiService = nil
        tokenStorage = nil
        subscriptionManager = nil
        appStorePurchaseFlow = nil
        appStoreRestoreFlow = nil
        stripePurchaseFlow = nil
        wideEvent = nil
    }

    // MARK: - Apple store

    func testAppStorePurchaseSuccess() async throws {

        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockRefreshAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)
        SubscriptionAPIMockResponseFactory.mockConfirmPurchase(destinationMockAPIService: apiService, success: true)
        SubscriptionAPIMockResponseFactory.mockGetProducts(destinationMockAPIService: apiService, success: true)
        SubscriptionAPIMockResponseFactory.mockGetFeatures(destinationMockAPIService: apiService, success: true, subscriptionID: "ios.subscription.1month")

        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainerWithEntitlements())

        // configure mock store purchase manager responses
        storePurchaseManager.purchaseSubscriptionResult = .success("purchaseTransactionJWS")

        // Buy subscription

        var purchaseTransactionJWS: String?
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID, includeProTier: true) {
        case .success(let payload):
            purchaseTransactionJWS = payload.transactionJWS
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
        XCTAssertNotNil(purchaseTransactionJWS)

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS!, additionalParams: nil) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
    }

    func testAppStorePurchaseFailure_authorise() async throws {
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: false)

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID, includeProTier: true) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .errorRetrievingTokenContainer(error: OAuthServiceError.authAPIError(OAuthRequestError(from: .invalidAuthorizationRequest))))
            default:
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAppStorePurchaseFailure_create_account() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: false)

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID, includeProTier: true) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .errorRetrievingTokenContainer(error: OAuthServiceError.authAPIError(OAuthRequestError(from: .invalidAuthorizationRequest))))
            default:
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAppStorePurchaseFailure_get_token() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: false)

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID, includeProTier: true) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .errorRetrievingTokenContainer(error: OAuthServiceError.authAPIError(OAuthRequestError(from: .invalidAuthorizationRequest))))
            default:
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAppStorePurchaseFailure_get_JWKS() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: false)

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID, includeProTier: true) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .errorRetrievingTokenContainer(error: OAuthServiceError.invalidResponseCode(.badRequest)))
            default:
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAppStorePurchaseFailure_confirm_purchase() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)

        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainerWithEntitlements())
        storePurchaseManager.purchaseSubscriptionResult = .success("purchaseTransactionJWS")

        SubscriptionAPIMockResponseFactory.mockConfirmPurchase(destinationMockAPIService: apiService, success: false)

        var purchaseTransactionJWS: String?
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID, includeProTier: true) {
        case .success(let payload):
            purchaseTransactionJWS = payload.transactionJWS
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
        XCTAssertNotNil(purchaseTransactionJWS)

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS!, additionalParams: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .purchaseFailed(SubscriptionEndpointServiceError.invalidResponseCode(.badRequest)))
        }
    }

    func testAppStorePurchaseFailure_get_features() async throws {
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)

        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainerWithEntitlements())
        storePurchaseManager.purchaseSubscriptionResult = .success("purchaseTransactionJWS")

        SubscriptionAPIMockResponseFactory.mockConfirmPurchase(destinationMockAPIService: apiService, success: true)
        SubscriptionAPIMockResponseFactory.mockGetFeatures(destinationMockAPIService: apiService, success: false, subscriptionID: "ios.subscription.1month")

        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainerWithEntitlements())

        var purchaseTransactionJWS: String?
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID, includeProTier: true) {
        case .success(let payload):
            purchaseTransactionJWS = payload.transactionJWS
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
        XCTAssertNotNil(purchaseTransactionJWS)

        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: purchaseTransactionJWS!, additionalParams: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .purchaseFailed(SubscriptionEndpointServiceError.invalidResponseCode(.badRequest)))
        }
    }

    // MARK: - App Store Tier Change

    func testAppStoreChangeTierSuccess() async throws {
        // Setup: User already has a valid token (existing subscription)
        // Store the token in storage so .localValid policy can find it
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        try tokenStorage.saveTokenContainer(tokenContainer)
        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(tokenContainer)

        // Configure mock API responses for completing the purchase
        SubscriptionAPIMockResponseFactory.mockConfirmPurchase(destinationMockAPIService: apiService, success: true)
        SubscriptionAPIMockResponseFactory.mockGetProducts(destinationMockAPIService: apiService, success: true)
        SubscriptionAPIMockResponseFactory.mockGetFeatures(destinationMockAPIService: apiService, success: true, subscriptionID: "ios.subscription.1month")
        APIMockResponseFactory.mockRefreshAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)

        // Configure mock store purchase manager to succeed
        storePurchaseManager.purchaseSubscriptionResult = .success("tierChangeTransactionJWS")

        // Change tier
        let newTierSubscriptionID = "ios.subscription.1year"
        switch await appStorePurchaseFlow.changeTier(to: newTierSubscriptionID) {
        case .success(let transactionJWS):
            XCTAssertEqual(transactionJWS, "tierChangeTransactionJWS")
        case .failure(let error):
            XCTFail("Tier change failed with error: \(error)")
        }
    }

    func testAppStoreChangeTierFailure_noToken() async throws {
        // User is not authenticated (no token)
        // Don't set any token container

        switch await appStorePurchaseFlow.changeTier(to: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError:
                break // Expected - user must be authenticated to change tier
            default:
                XCTFail("Expected internalError, got: \(error)")
            }
        }
    }

    func testAppStoreChangeTierFailure_purchaseFailed() async throws {
        // Setup: User has valid token
        // Store the token in storage so .localValid policy can find it
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        try tokenStorage.saveTokenContainer(tokenContainer)
        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(tokenContainer)

        // Configure API mocks needed for token validation
        APIMockResponseFactory.mockRefreshAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)

        // Configure store purchase manager to fail
        let underlyingError = NSError(domain: "StoreKit", code: 1, userInfo: nil)
        storePurchaseManager.purchaseSubscriptionResult = .failure(.purchaseFailed(underlyingError))

        switch await appStorePurchaseFlow.changeTier(to: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .purchaseFailed:
                break // Expected
            default:
                XCTFail("Expected purchaseFailed, got: \(error)")
            }
        }
    }

    func testAppStoreChangeTierFailure_purchaseCancelled() async throws {
        // Setup: User has valid token
        // Store the token in storage so .localValid policy can find it
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        try tokenStorage.saveTokenContainer(tokenContainer)
        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(tokenContainer)

        // Configure API mocks needed for token validation
        APIMockResponseFactory.mockRefreshAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)

        // Configure store purchase manager to return cancelled
        storePurchaseManager.purchaseSubscriptionResult = .failure(.purchaseCancelledByUser)

        switch await appStorePurchaseFlow.changeTier(to: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .cancelledByUser)
        }
    }

    func testAppStoreChangeTierFailure_confirmPurchase() async throws {
        // Setup: User has valid token
        // Store the token in storage so .localValid policy can find it
        let tokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        try tokenStorage.saveTokenContainer(tokenContainer)
        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(tokenContainer)

        // Configure API mocks needed for token validation
        APIMockResponseFactory.mockRefreshAccessTokenResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetJWKS(destinationMockAPIService: apiService, success: true)

        // Configure store purchase manager to succeed
        storePurchaseManager.purchaseSubscriptionResult = .success("tierChangeTransactionJWS")

        // Configure confirm purchase to fail
        SubscriptionAPIMockResponseFactory.mockConfirmPurchase(destinationMockAPIService: apiService, success: false)

        // Change tier succeeds (returns transaction JWS)
        let changeTierResult = await appStorePurchaseFlow.changeTier(to: subscriptionSelectionID)
        guard case .success(let transactionJWS) = changeTierResult else {
            XCTFail("Tier change failed unexpectedly: \(changeTierResult)")
            return
        }

        // But completing the purchase fails
        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: transactionJWS, additionalParams: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .purchaseFailed(SubscriptionEndpointServiceError.invalidResponseCode(.badRequest)))
        }
    }

    // MARK: - Stripe

    func testStripePurchaseSuccess() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: true)

        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainerWithEntitlements())

        // Buy subscription
        let email = "test@duck.com"
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: email)
        switch result {
        case .success(let payload):
            XCTAssertNotNil(payload.purchaseUpdate.type)
            XCTAssertNotNil(payload.purchaseUpdate.token)
        case .failure(let error):
            XCTFail("Purchase failed with error: \(error)")
        }
    }

    func testStripePurchaseFailure_authorise() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: false)
        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainerWithEntitlements())

        // Buy subscription
        let email = "test@duck.com"
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: email)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .accountCreationFailed: break
            default: XCTFail("Expected accountCreationFailed")
            }
        }
    }

    func testStripePurchaseFailure_create_account() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: false)

        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainerWithEntitlements())

        // Buy subscription
        let email = "test@duck.com"
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: email)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .accountCreationFailed: break
            default: XCTFail("Expected accountCreationFailed")
            }
        }
    }

    func testStripePurchaseFailure_get_token() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockGetAccessTokenResponse(destinationMockAPIService: apiService, success: false)

        await (subscriptionManager.oAuthClient as! DefaultOAuthClient).setTestingDecodedTokenContainer(OAuthTokensFactory.makeValidTokenContainerWithEntitlements())

        // Buy subscription
        let email = "test@duck.com"
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: email)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .accountCreationFailed: break
            default: XCTFail("Expected accountCreationFailed")
            }
        }
    }
}

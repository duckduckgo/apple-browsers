//
//  PrivacyProSubscriptionV2IntegrationTests.swift
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
import JWTKit

final class PrivacyProSubscriptionV2IntegrationTests: XCTestCase {

    var apiService: MockAPIService!
    var tokenStorage: MockTokenStorage!
    var legacyAccountStorage: MockLegacyTokenStorage!
    var subscriptionManager: DefaultSubscriptionManagerV2!
    var appStorePurchaseFlow: DefaultAppStorePurchaseFlowV2!
    var appStoreRestoreFlow: DefaultAppStoreRestoreFlowV2!
    var stripePurchaseFlow: DefaultStripePurchaseFlowV2!
    var storePurchaseManager: StorePurchaseManagerMockV2!
    var subscriptionFeatureFlagger: FeatureFlaggerMapping<SubscriptionFeatureFlags>!

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
        legacyAccountStorage = MockLegacyTokenStorage()

        let authClient = DefaultOAuthClient(tokensStorage: tokenStorage,
                                            legacyTokenStorage: legacyAccountStorage,
                                            authService: authService)
        storePurchaseManager = StorePurchaseManagerMockV2()
        let subscriptionEndpointService = DefaultSubscriptionEndpointServiceV2(apiService: apiService,
                                                                               baseURL: subscriptionEnvironment.serviceEnvironment.url)
        subscriptionFeatureFlagger = FeatureFlaggerMapping<SubscriptionFeatureFlags>(mapping: { $0.defaultState })

        subscriptionManager = DefaultSubscriptionManagerV2(storePurchaseManager: storePurchaseManager,
                                                           oAuthClient: authClient,
                                                           subscriptionEndpointService: subscriptionEndpointService,
                                                           subscriptionEnvironment: subscriptionEnvironment,
                                                           pixelHandler: MockPixelHandler())

        appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManager,
                                                           storePurchaseManager: storePurchaseManager)
        appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: subscriptionManager,
                                                             storePurchaseManager: storePurchaseManager,
                                                             appStoreRestoreFlow: appStoreRestoreFlow)
        stripePurchaseFlow = DefaultStripePurchaseFlowV2(subscriptionManager: subscriptionManager)
    }

    override func tearDownWithError() throws {
        apiService = nil
        tokenStorage = nil
        legacyAccountStorage = nil
        subscriptionManager = nil
        appStorePurchaseFlow = nil
        appStoreRestoreFlow = nil
        stripePurchaseFlow = nil
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
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success(let transactionJWS):
            purchaseTransactionJWS = transactionJWS
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

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .tokenUnavailable(error: OAuthServiceError.authAPIError(code: .invalidAuthorizationRequest)))
            default:
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testAppStorePurchaseFailure_create_account() async throws {
        // configure mock API responses
        APIMockResponseFactory.mockAuthoriseResponse(destinationMockAPIService: apiService, success: true)
        APIMockResponseFactory.mockCreateAccountResponse(destinationMockAPIService: apiService, success: false)

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .tokenUnavailable(error: OAuthServiceError.authAPIError(code: .invalidAuthorizationRequest)))
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

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .tokenUnavailable(error: OAuthServiceError.authAPIError(code: .invalidAuthorizationRequest)))
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

        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .internalError(let innerError):
                XCTAssertEqual(innerError as? SubscriptionManagerError, .tokenUnavailable(error: OAuthServiceError.invalidResponseCode(.badRequest)))
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
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success(let transactionJWS):
            purchaseTransactionJWS = transactionJWS
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
        switch await appStorePurchaseFlow.purchaseSubscription(with: subscriptionSelectionID) {
        case .success(let transactionJWS):
            purchaseTransactionJWS = transactionJWS
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
        case .success(let success):
            XCTAssertNotNil(success.type)
            XCTAssertNotNil(success.token)
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
            XCTAssertEqual(error, StripePurchaseFlowError.accountCreationFailed)
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
            XCTAssertEqual(error, StripePurchaseFlowError.accountCreationFailed)
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
            XCTAssertEqual(error, StripePurchaseFlowError.accountCreationFailed)
        }
    }
}

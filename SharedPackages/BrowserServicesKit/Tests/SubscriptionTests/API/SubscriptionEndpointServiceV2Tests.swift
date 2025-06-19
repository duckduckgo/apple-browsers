//
//  SubscriptionEndpointServiceV2Tests.swift
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
import SubscriptionTestingUtilities
import NetworkingTestingUtils
import Common

final class SubscriptionEndpointServiceV2Tests: XCTestCase {
    private var apiService: MockAPIService!
    private var endpointService: DefaultSubscriptionEndpointServiceV2!
    private let baseURL = SubscriptionEnvironment.ServiceEnvironment.staging.url
    private let disposableCache = UserDefaultsCache<PrivacyProSubscription>(key: UserDefaultsCacheKeyKest.subscriptionTest,
                                                                            settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20)))
    private enum UserDefaultsCacheKeyKest: String, UserDefaultsCacheKeyStore {
        case subscriptionTest = "com.duckduckgo.bsk.subscription.info.testing"
    }
    private var encoder: JSONEncoder!

    override func setUp() {
        super.setUp()
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        apiService = MockAPIService()
        endpointService = DefaultSubscriptionEndpointServiceV2(apiService: apiService,
                                                               baseURL: baseURL,
                                                               subscriptionCache: disposableCache)
    }

    override func tearDown() {
        disposableCache.reset()
        apiService = nil
        endpointService = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func createSubscriptionResponseData() throws -> Data {
        let date = Date(timeIntervalSince1970: 123456789)
        let subscription = PrivacyProSubscription(
            productId: "prod123",
            name: "Pro Plan",
            billingPeriod: .yearly,
            startedAt: date,
            expiresOrRenewsAt: date.addingTimeInterval(30 * 24 * 60 * 60),
            platform: .apple,
            status: .autoRenewable,
            activeOffers: []
        )
        return try encoder.encode(subscription)
    }

    private func createAPIResponse(statusCode: Int, data: Data?) -> APIResponseV2 {
        let response = HTTPURLResponse(
            url: baseURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return APIResponseV2(data: data, httpResponse: response)
    }

    // MARK: - getSubscription Tests

    func testGetSubscriptionReturnsCachedSubscription() async throws {
        let date = Date(timeIntervalSince1970: 123456789)
        let cachedSubscription = PrivacyProSubscription(
            productId: "prod123",
            name: "Pro Plan",
            billingPeriod: .monthly,
            startedAt: date,
            expiresOrRenewsAt: date.addingTimeInterval(30 * 24 * 60 * 60),
            platform: .google,
            status: .autoRenewable,
            activeOffers: []
        )
        endpointService.updateCache(with: cachedSubscription)

        let subscription = try await endpointService.getSubscription(accessToken: "token", cachePolicy: .returnCacheDataDontLoad)
        XCTAssertEqual(subscription, cachedSubscription)
    }

    func testGetSubscriptionFetchesRemoteSubscriptionWhenNoCache() async throws {
        // mock subscription response
        let subscriptionData = try createSubscriptionResponseData()
        let apiResponse = createAPIResponse(statusCode: 200, data: subscriptionData)
        let request = SubscriptionRequest.getSubscription(baseURL: baseURL, accessToken: "token")!.apiRequest

        // mock features
        SubscriptionAPIMockResponseFactory.mockGetFeatures(destinationMockAPIService: apiService, success: true, subscriptionID: "prod123")

        apiService.set(response: apiResponse, forRequest: request)

        let subscription = try await endpointService.getSubscription(accessToken: "token", cachePolicy: .returnCacheDataElseLoad)
        XCTAssertEqual(subscription.productId, "prod123")
        XCTAssertEqual(subscription.name, "Pro Plan")
        XCTAssertEqual(subscription.billingPeriod, .yearly)
        XCTAssertEqual(subscription.platform, .apple)
        XCTAssertEqual(subscription.status, .autoRenewable)
    }

    func testGetSubscriptionThrowsNoDataWhenNoCacheAndFetchFails() async {
        do {
            _ = try await endpointService.getSubscription(accessToken: "token", cachePolicy: .returnCacheDataDontLoad)
            XCTFail("Expected noData error")
        } catch SubscriptionEndpointServiceError.noData {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - getProducts Tests

    func testGetProductsReturnsListOfProducts() async throws {
        let productItems = [
            GetProductsItem(
                productId: "prod1",
                productLabel: "Product 1",
                billingPeriod: "Monthly",
                price: "9.99",
                currency: "USD"
            ),
            GetProductsItem(
                productId: "prod2",
                productLabel: "Product 2",
                billingPeriod: "Yearly",
                price: "99.99",
                currency: "USD"
            )
        ]
        let productData = try encoder.encode(productItems)
        let apiResponse = createAPIResponse(statusCode: 200, data: productData)
        let request = SubscriptionRequest.getProducts(baseURL: baseURL)!.apiRequest

        apiService.set(response: apiResponse, forRequest: request)

        let products = try await endpointService.getProducts()
        XCTAssertEqual(products, productItems)
    }

    func testGetProductsThrowsInvalidResponse() async {
        let request = SubscriptionRequest.getProducts(baseURL: baseURL)!.apiRequest
        let apiResponse = createAPIResponse(statusCode: 200, data: nil)
        apiService.set(response: apiResponse, forRequest: request)
        do {
            _ = try await endpointService.getProducts()
            XCTFail("Expected invalidResponse error")
        } catch Networking.APIRequestV2.Error.emptyResponseBody {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - getCustomerPortalURL Tests

    func testGetCustomerPortalURLReturnsCorrectURL() async throws {
        let portalResponse = GetCustomerPortalURLResponse(customerPortalUrl: "https://portal.example.com")
        let portalData = try encoder.encode(portalResponse)
        let apiResponse = createAPIResponse(statusCode: 200, data: portalData)
        let request = SubscriptionRequest.getCustomerPortalURL(baseURL: baseURL, accessToken: "token", externalID: "id")!.apiRequest

        apiService.set(response: apiResponse, forRequest: request)

        let customerPortalURL = try await endpointService.getCustomerPortalURL(accessToken: "token", externalID: "id")
        XCTAssertEqual(customerPortalURL, portalResponse)
    }

    // MARK: - confirmPurchase Tests

    func testConfirmPurchaseReturnsCorrectResponse() async throws {
        let date = Date(timeIntervalSince1970: 123456789)
        let confirmResponse = ConfirmPurchaseResponseV2(
            email: "user@example.com",
            subscription: PrivacyProSubscription(
                productId: "prod123",
                name: "Pro Plan",
                billingPeriod: .monthly,
                startedAt: date,
                expiresOrRenewsAt: date.addingTimeInterval(30 * 24 * 60 * 60),
                platform: .stripe,
                status: .gracePeriod,
                activeOffers: []
            )
        )
        let confirmData = try encoder.encode(confirmResponse)
        let apiResponse = createAPIResponse(statusCode: 200, data: confirmData)
        let request = SubscriptionRequest.confirmPurchase(baseURL: baseURL, accessToken: "token", signature: "signature", additionalParams: nil)!.apiRequest

        apiService.set(response: apiResponse, forRequest: request)

        let purchaseResponse = try await endpointService.confirmPurchase(accessToken: "token", signature: "signature", additionalParams: nil)
        XCTAssertEqual(purchaseResponse.email, confirmResponse.email)
        XCTAssertEqual(purchaseResponse.subscription, confirmResponse.subscription)
    }

    // MARK: - Cache Tests

    func testUpdateCacheStoresSubscription() async throws {
        let date = Date(timeIntervalSince1970: 123456789)
        let subscription = PrivacyProSubscription(
            productId: "prod123",
            name: "Pro Plan",
            billingPeriod: .monthly,
            startedAt: date,
            expiresOrRenewsAt: date.addingTimeInterval(30 * 24 * 60 * 60),
            platform: .google,
            status: .autoRenewable,
            activeOffers: []
        )
        endpointService.updateCache(with: subscription)

        let cachedSubscription = try await endpointService.getSubscription(accessToken: "token", cachePolicy: .returnCacheDataDontLoad)
        XCTAssertEqual(cachedSubscription, subscription)
    }

    func testClearSubscriptionRemovesCachedSubscription() async throws {
        let date = Date(timeIntervalSince1970: 123456789)
        let subscription = PrivacyProSubscription(
            productId: "prod123",
            name: "Pro Plan",
            billingPeriod: .monthly,
            startedAt: date,
            expiresOrRenewsAt: date.addingTimeInterval(30 * 24 * 60 * 60),
            platform: .apple,
            status: .autoRenewable,
            activeOffers: []
        )
        endpointService.updateCache(with: subscription)

        endpointService.clearSubscription()
        do {
            _ = try await endpointService.getSubscription(accessToken: "token", cachePolicy: .returnCacheDataDontLoad)
        } catch SubscriptionEndpointServiceError.noData {
            // Success
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}

/*
final class SubscriptionEndpointServiceV2Tests: XCTestCase {

    private struct Constants {
//        static let tokenContainer = OAuthTokensFactory.makeValidTokenContainer()
//        static let accessToken = UUID().uuidString
//        static let externalID = UUID().uuidString
//        static let email = "dax@duck.com"

        static let mostRecentTransactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="

        static let subscription = SubscriptionMockFactory.subscription

        static let customerPortalURL = "https://billing.stripe.com/p/session/test_ABC"

        static let authorizationHeader = ["Authorization": "Bearer TOKEN"]

//        static let unknownServerError = APIServiceError.serverError(statusCode: 401, error: "unknown_error")
    }

    var apiService: MockAPIService!
    var subscriptionService: SubscriptionEndpointServiceV2!

    override func setUpWithError() throws {
        apiService = MockAPIService()
        subscriptionService = DefaultSubscriptionEndpointService(apiService: apiService, baseURL: URL(string: "https://something_tests.com")!)
    }

    override func tearDownWithError() throws {
        apiService = nil
        subscriptionService = nil
    }

    // MARK: - Tests for

    func testGetSubscriptionCall() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, _) = parameters

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "subscription")
            XCTAssertEqual(headers, Constants.authorizationHeader)
        }

        // When
        _ = await subscriptionService.getSubscription(accessToken: Constants.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetSubscriptionSuccess() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockResponseJSONData = """
        {
            "productId": "\(Constants.subscription.productId)",
            "name": "\(Constants.subscription.name)",
            "billingPeriod": "\(Constants.subscription.billingPeriod.rawValue)",
            "startedAt": \(Constants.subscription.startedAt.timeIntervalSince1970*1000),
            "expiresOrRenewsAt": \(Constants.subscription.expiresOrRenewsAt.timeIntervalSince1970*1000),
            "platform": "\(Constants.subscription.platform.rawValue)",
            "status": "\(Constants.subscription.status.rawValue)"
        }
        """.data(using: .utf8)!

        // When
        let result = await subscriptionService.getSubscription(accessToken: Constants.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.productId, Constants.subscription.productId)
            XCTAssertEqual(success.name, Constants.subscription.name)
            XCTAssertEqual(success.billingPeriod, Constants.subscription.billingPeriod)
            XCTAssertEqual(success.startedAt.timeIntervalSince1970,
                           Constants.subscription.startedAt.timeIntervalSince1970,
                           accuracy: 0.001)
            XCTAssertEqual(success.expiresOrRenewsAt.timeIntervalSince1970,
                           Constants.subscription.expiresOrRenewsAt.timeIntervalSince1970,
                           accuracy: 0.001)
            XCTAssertEqual(success.platform, Constants.subscription.platform)
            XCTAssertEqual(success.status, Constants.subscription.status)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetSubscriptionError() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockAPICallError = Constants.unknownServerError

        // When
        let result = await subscriptionService.getSubscription(accessToken: Constants.accessToken, cachePolicy: .reloadIgnoringLocalCacheData)

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    // MARK: - Tests for getProducts

    func testGetProductsCall() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, _) = parameters

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "products")
            XCTAssertNil(headers)
        }

        // When
        _ = await subscriptionService.getProducts()

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetProductsSuccess() async throws {
        // Given
        apiService.mockResponseJSONData = """
        [
            {
                "productId":"ddg-privacy-pro-sandbox-monthly-renews-us",
                "productLabel":"Monthly Subscription",
                "billingPeriod":"Monthly",
                "price":"9.99",
                "currency":"USD"
            },
            {
                "productId":"ddg-privacy-pro-sandbox-yearly-renews-us",
                "productLabel":"Yearly Subscription",
                "billingPeriod":"Yearly",
                "price":"99.99",
                "currency":"USD"
            }
        ]
        """.data(using: .utf8)!

        // When
        let result = await subscriptionService.getProducts()

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.count, 2)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetProductsError() async throws {
        // Given
        apiService.mockAPICallError = Constants.unknownServerError

        // When
        let result = await subscriptionService.getProducts()

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    // MARK: - Tests for getCustomerPortalURL

    func testGetCustomerPortalURLCall() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, _) = parameters

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "checkout/portal")
            XCTAssertEqual(headers?.count, 2)
            XCTAssertEqual(headers?["externalAccountId"], Constants.externalID)

            if let (authorizationHeaderKey, authorizationHeaderValue) = Constants.authorizationHeader.first {
                XCTAssertEqual(headers?[authorizationHeaderKey], authorizationHeaderValue)
            }
        }

        // When
        _ = await subscriptionService.getCustomerPortalURL(accessToken: Constants.accessToken, externalID: Constants.externalID)

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetCustomerPortalURLSuccess() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockResponseJSONData = """
        {
            "customerPortalUrl":"\(Constants.customerPortalURL)"
        }
        """.data(using: .utf8)!

        // When
        let result = await subscriptionService.getCustomerPortalURL(accessToken: Constants.accessToken, externalID: Constants.externalID)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.customerPortalUrl, Constants.customerPortalURL)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetCustomerPortalURLError() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockAPICallError = Constants.unknownServerError

        // When
        let result = await subscriptionService.getCustomerPortalURL(accessToken: Constants.accessToken, externalID: Constants.externalID)

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    // MARK: - Tests for confirmPurchase

    func testConfirmPurchaseCall() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, body) = parameters

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "POST")
            XCTAssertEqual(endpoint, "purchase/confirm/apple")
            XCTAssertEqual(headers, Constants.authorizationHeader)
            XCTAssertNotNil(body)

            if let bodyDict = try? JSONDecoder().decode([String: String].self, from: body!) {
                XCTAssertEqual(bodyDict["signedTransactionInfo"], Constants.mostRecentTransactionJWS)
                XCTAssertEqual(bodyDict["extraParamKey"], "extraParamValue")
            } else {
                XCTFail("Failed to decode body")
            }
        }

        // When
        let additionalParams = ["extraParamKey": "extraParamValue"]
        _ = await subscriptionService.confirmPurchase(
            accessToken: Constants.accessToken,
            signature: Constants.mostRecentTransactionJWS,
            additionalParams: additionalParams
        )

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testConfirmPurchaseSuccess() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockResponseJSONData = """
        {
            "email":"",
            "entitlements":
            [
                {"product":"Data Broker Protection","name":"subscriber"},
                {"product":"Identity Theft Restoration","name":"subscriber"},
                {"product":"Network Protection","name":"subscriber"}
            ],
            "subscription":
            {
                "productId": "\(Constants.subscription.productId)",
                "name": "\(Constants.subscription.name)",
                "billingPeriod": "\(Constants.subscription.billingPeriod.rawValue)",
                "startedAt": \(Constants.subscription.startedAt.timeIntervalSince1970*1000),
                "expiresOrRenewsAt": \(Constants.subscription.expiresOrRenewsAt.timeIntervalSince1970*1000),
                "platform": "\(Constants.subscription.platform.rawValue)",
                "status": "\(Constants.subscription.status.rawValue)"
            }
        }
        """.data(using: .utf8)!

        // When
        let result = await subscriptionService.confirmPurchase(accessToken: Constants.accessToken, signature: Constants.mostRecentTransactionJWS, additionalParams: nil)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.entitlements.count, 3)
            XCTAssertEqual(success.subscription.productId, Constants.subscription.productId)
            XCTAssertEqual(success.subscription.name, Constants.subscription.name)
            XCTAssertEqual(success.subscription.billingPeriod, Constants.subscription.billingPeriod)
            XCTAssertEqual(success.subscription.startedAt.timeIntervalSince1970,
                           Constants.subscription.startedAt.timeIntervalSince1970,
                           accuracy: 0.001)
            XCTAssertEqual(success.subscription.expiresOrRenewsAt.timeIntervalSince1970,
                           Constants.subscription.expiresOrRenewsAt.timeIntervalSince1970,
                           accuracy: 0.001)
            XCTAssertEqual(success.subscription.platform, Constants.subscription.platform)
            XCTAssertEqual(success.subscription.status, Constants.subscription.status)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testConfirmPurchaseWithAdditionalParams() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (_, _, _, body) = parameters

            apiServiceCalledExpectation.fulfill()
            if let bodyDict = try? JSONDecoder().decode([String: String].self, from: body!) {
                XCTAssertEqual(bodyDict["signedTransactionInfo"], Constants.mostRecentTransactionJWS)
                XCTAssertEqual(bodyDict["extraParamKey1"], "extraValue1")
                XCTAssertEqual(bodyDict["extraParamKey2"], "extraValue2")
            } else {
                XCTFail("Failed to decode body")
            }
        }

        // When
        let additionalParams = [
            "extraParamKey1": "extraValue1",
            "extraParamKey2": "extraValue2"
        ]
        _ = await subscriptionService.confirmPurchase(
            accessToken: Constants.accessToken,
            signature: Constants.mostRecentTransactionJWS,
            additionalParams: additionalParams
        )

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testConfirmPurchaseWithConflictingKeys() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (_, _, _, body) = parameters

            apiServiceCalledExpectation.fulfill()
            if let bodyDict = try? JSONDecoder().decode([String: String].self, from: body!) {
                XCTAssertEqual(bodyDict["signedTransactionInfo"], Constants.mostRecentTransactionJWS)
                XCTAssertEqual(bodyDict["extraParamKey"], "extraValue")
            } else {
                XCTFail("Failed to decode body")
            }
        }

        // When
        let additionalParams = [
            "signedTransactionInfo": "overriddenValue",
            "extraParamKey": "extraValue"
        ]
        _ = await subscriptionService.confirmPurchase(
            accessToken: Constants.accessToken,
            signature: Constants.mostRecentTransactionJWS,
            additionalParams: additionalParams
        )

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testConfirmPurchaseError() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockAPICallError = Constants.unknownServerError

        // When
        let result = await subscriptionService.confirmPurchase(accessToken: Constants.accessToken, signature: Constants.mostRecentTransactionJWS, additionalParams: nil)

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }
}
*/

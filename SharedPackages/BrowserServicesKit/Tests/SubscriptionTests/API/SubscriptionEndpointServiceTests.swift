//
//  SubscriptionEndpointServiceTests.swift
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

final class SubscriptionEndpointServiceTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"

        static let mostRecentTransactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="

        static let subscription = SubscriptionMockFactory.appleSubscription

        static let customerPortalURL = "https://billing.stripe.com/p/session/test_ABC"

        static let authorizationHeader = ["Authorization": "Bearer TOKEN"]

        static let unknownServerError = APIServiceError.serverError(statusCode: 401, errorCode: "unknown_error")
    }

    var apiService: APIServiceMock!
    var subscriptionService: SubscriptionEndpointService!

    override func setUpWithError() throws {
        apiService = APIServiceMock()
        subscriptionService = DefaultSubscriptionEndpointService(currentServiceEnvironment: .staging, apiService: apiService)
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
            "status": "\(Constants.subscription.status.rawValue)",
            "activeOffers": []
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
                "status": "\(Constants.subscription.status.rawValue)",
                "activeOffers": []
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

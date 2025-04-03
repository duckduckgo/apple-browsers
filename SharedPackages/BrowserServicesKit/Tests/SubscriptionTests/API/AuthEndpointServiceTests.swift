//
//  AuthEndpointServiceTests.swift
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

final class AuthEndpointServiceTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"

        static let mostRecentTransactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="

        static let authorizationHeader = ["Authorization": "Bearer TOKEN"]

        static let invalidTokenError = APIServiceError.serverError(statusCode: 401, error: "invalid_token")
    }

    var apiService: APIServiceMock!
    var authService: AuthEndpointService!

    override func setUpWithError() throws {
        apiService = APIServiceMock()
        authService = DefaultAuthEndpointService(currentServiceEnvironment: .staging, apiService: apiService)
    }

    override func tearDownWithError() throws {
        apiService = nil
        authService = nil
    }

    // MARK: - Tests for getAccessToken

    func testGetAccessTokenCall() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, _) = parameters

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "access-token")
            XCTAssertEqual(headers, Constants.authorizationHeader)
        }

        // When
        _ = await authService.getAccessToken(token: Constants.authToken)

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testGetAccessTokenSuccess() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockResponseJSONData = """
        {
            "accessToken": "\(Constants.accessToken)",
        }
        """.data(using: .utf8)!

        // When
        let result = await authService.getAccessToken(token: Constants.authToken)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.accessToken, Constants.accessToken)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testGetAccessTokenError() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockAPICallError = Constants.invalidTokenError

        // When
        let result = await authService.getAccessToken(token: Constants.authToken)

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    // MARK: - Tests for validateToken

    func testValidateTokenCall() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, _) = parameters

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "GET")
            XCTAssertEqual(endpoint, "validate-token")
            XCTAssertEqual(headers, Constants.authorizationHeader)
        }

        // When
        _ = await authService.validateToken(accessToken: Constants.accessToken)

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testValidateTokenSuccess() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockResponseJSONData = """
        {
            "account": {
                "id": 149718,
                "external_id": "\(Constants.externalID)",
                "email": "\(Constants.email)",
                "entitlements": [
                    {"id":24, "name":"subscriber", "product":"Network Protection"},
                    {"id":25, "name":"subscriber", "product":"Data Broker Protection"},
                    {"id":26, "name":"subscriber", "product":"Identity Theft Restoration"}
                ]
            }
        }
        """.data(using: .utf8)!

        // When
        let result = await authService.validateToken(accessToken: Constants.accessToken)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.account.externalID, Constants.externalID)
            XCTAssertEqual(success.account.email, Constants.email)
            XCTAssertEqual(success.account.entitlements.count, 3)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testValidateTokenError() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockAPICallError = Constants.invalidTokenError

        // When
        let result = await authService.validateToken(accessToken: Constants.accessToken)

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    // MARK: - Tests for createAccount

    func testCreateAccountCall() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, _) = parameters

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "POST")
            XCTAssertEqual(endpoint, "account/create")
            XCTAssertNil(headers)
        }

        // When
        _ = await authService.createAccount(emailAccessToken: nil)

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testCreateAccountSuccess() async throws {
        // Given
        apiService.mockResponseJSONData = """
        {
            "auth_token": "\(Constants.authToken)",
            "external_id": "\(Constants.externalID)",
            "status": "created"
        }
        """.data(using: .utf8)!

        // When
        let result = await authService.createAccount(emailAccessToken: nil)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.authToken, Constants.authToken)
            XCTAssertEqual(success.externalID, Constants.externalID)
            XCTAssertEqual(success.status, "created")
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testCreateAccountError() async throws {
        // Given
        apiService.mockAuthHeaders = Constants.authorizationHeader
        apiService.mockAPICallError = Constants.invalidTokenError

        // When
        let result = await authService.createAccount(emailAccessToken: nil)

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    // MARK: - Tests for storeLogin

    func testStoreLoginCall() async throws {
        // Given
        let apiServiceCalledExpectation = expectation(description: "apiService")

        apiService.onExecuteAPICall = { parameters in
            let (method, endpoint, headers, body) = parameters

            apiServiceCalledExpectation.fulfill()
            XCTAssertEqual(method, "POST")
            XCTAssertEqual(endpoint, "store-login")
            XCTAssertNil(headers)

            if let bodyDict = try? JSONDecoder().decode([String: String].self, from: body!) {
                XCTAssertEqual(bodyDict["signature"], Constants.mostRecentTransactionJWS)
                XCTAssertEqual(bodyDict["store"], "apple_app_store")
            } else {
                XCTFail("Failed to decode body")
            }
        }

        // When
        _ = await authService.storeLogin(signature: Constants.mostRecentTransactionJWS)

        // Then
        await fulfillment(of: [apiServiceCalledExpectation], timeout: 0.1)
    }

    func testStoreLoginSuccess() async throws {
        // Given
        apiService.mockResponseJSONData = """
        {
            "auth_token": "\(Constants.authToken)",
            "email": "\(Constants.email)",
            "external_id": "\(Constants.externalID)",
            "id": 1,
            "status": "ok"
        }
        """.data(using: .utf8)!

        // When
        let result = await authService.storeLogin(signature: Constants.mostRecentTransactionJWS)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.authToken, Constants.authToken)
            XCTAssertEqual(success.email, Constants.email)
            XCTAssertEqual(success.externalID, Constants.externalID)
            XCTAssertEqual(success.id, 1)
            XCTAssertEqual(success.status, "ok")
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func testStoreLoginError() async throws {
        // Given
        apiService.mockAPICallError = Constants.invalidTokenError

        // When
        let result = await authService.storeLogin(signature: Constants.mostRecentTransactionJWS)

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }
}

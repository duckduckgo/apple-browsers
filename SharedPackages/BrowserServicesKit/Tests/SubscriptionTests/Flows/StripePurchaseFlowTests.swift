//
//  StripePurchaseFlowTests.swift
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

final class StripePurchaseFlowTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"

        static let unknownServerError = APIServiceError.serverError(statusCode: 401, error: "unknown_error")
    }

    var accountManager: AccountManagerMock!
    var subscriptionService: SubscriptionEndpointServiceMock!
    var authEndpointService: AuthEndpointServiceMock!

    var stripePurchaseFlow: StripePurchaseFlow!

    override func setUpWithError() throws {
        accountManager = AccountManagerMock()
        subscriptionService = SubscriptionEndpointServiceMock()
        authEndpointService = AuthEndpointServiceMock()

        stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionEndpointService: subscriptionService,
                                                       authEndpointService: authEndpointService,
                                                       accountManager: accountManager)
    }

    override func tearDownWithError() throws {
        accountManager = nil
        subscriptionService = nil
        authEndpointService = nil

        stripePurchaseFlow = nil
    }

    // MARK: - Tests for subscriptionOptions

    func testSubscriptionOptionsSuccess() async throws {
        // Given
        subscriptionService .getProductsResult = .success(SubscriptionMockFactory.productsItems)

        // When
        let result = await stripePurchaseFlow.subscriptionOptions()

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.platform, SubscriptionPlatformName.stripe)
            XCTAssertEqual(success.options.count, SubscriptionMockFactory.productsItems.count)
            XCTAssertEqual(success.features.count, 3)
            let allFeatures = [Entitlement.ProductName.networkProtection, Entitlement.ProductName.dataBrokerProtection, Entitlement.ProductName.identityTheftRestoration]
            let allNames = success.features.compactMap({ feature in feature.name })

            for feature in allFeatures {
                XCTAssertTrue(allNames.contains(feature))
            }
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testSubscriptionOptionsErrorWhenNoProductsAreFetched() async throws {
        // Given
        subscriptionService.getProductsResult = .failure(.unknownServerError)

        // When
        let result = await stripePurchaseFlow.subscriptionOptions()

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .noProductsFound)
        }
    }

    // MARK: - Tests for prepareSubscriptionPurchase

    func testPrepareSubscriptionPurchaseSuccess() async throws {
        // Given
        authEndpointService.createAccountResult = .success(CreateAccountResponse(authToken: Constants.authToken,
                                                                                 externalID: Constants.externalID,
                                                                                 status: "created"))
        XCTAssertFalse(accountManager.isUserAuthenticated)

        // When
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: nil)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.type, "redirect")
            XCTAssertEqual(success.token, Constants.authToken)

            XCTAssertTrue(authEndpointService.createAccountCalled)
            XCTAssertEqual(accountManager.authToken, Constants.authToken)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testPrepareSubscriptionPurchaseSuccessWhenSignedInAndSubscriptionExpired() async throws {
        // Given
        let subscription = SubscriptionMockFactory.expiredSubscription

        accountManager.accessToken = Constants.accessToken

        subscriptionService.getSubscriptionResult = .success(subscription)
        subscriptionService.getProductsResult = .success(SubscriptionMockFactory.productsItems)

        XCTAssertTrue(accountManager.isUserAuthenticated)
        XCTAssertFalse(subscription.isActive)

        // When
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: nil)

        // Then
        switch result {
        case .success(let success):
            XCTAssertEqual(success.type, "redirect")
            XCTAssertEqual(success.token, Constants.accessToken)

            XCTAssertTrue(subscriptionService.signOutCalled)
            XCTAssertFalse(authEndpointService.createAccountCalled)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testPrepareSubscriptionPurchaseErrorWhenAccountCreationFailed() async throws {
        // Given
        authEndpointService.createAccountResult = .failure(Constants.unknownServerError)
        XCTAssertFalse(accountManager.isUserAuthenticated)

        // When
        let result = await stripePurchaseFlow.prepareSubscriptionPurchase(emailAccessToken: nil)

        // Then
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            XCTAssertEqual(error, .accountCreationFailed)
        }
    }

    // MARK: - Tests for completeSubscriptionPurchase

    func testCompleteSubscriptionPurchaseSuccessOnInitialPurchase() async throws {
        // Given
        // Initial purchase flow: authToken is present but no accessToken yet
        accountManager.authToken = Constants.authToken
        XCTAssertNil(accountManager.accessToken)

        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.onExchangeAuthTokenToAccessToken = { authToken in
            XCTAssertEqual(authToken, Constants.authToken)
        }

        accountManager.fetchAccountDetailsResult = .success(AccountManager.AccountDetails(email: nil, externalID: Constants.externalID))
        accountManager.onFetchAccountDetails = { accessToken in
            XCTAssertEqual(accessToken, Constants.accessToken)
        }

        accountManager.onStoreAuthToken = { authToken in
            XCTAssertEqual(authToken, Constants.authToken)
        }

        accountManager.onStoreAccount = { accessToken, email, externalID in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(externalID, Constants.externalID)
            XCTAssertNil(email)
        }

        accountManager.onCheckForEntitlements = { wait, retry in
            XCTAssertEqual(wait, 2.0)
            XCTAssertEqual(retry, 5)
            return true
        }

        XCTAssertFalse(accountManager.isUserAuthenticated)
        XCTAssertNotNil(accountManager.authToken)

        // When
        await stripePurchaseFlow.completeSubscriptionPurchase()

        // Then
        XCTAssertTrue(subscriptionService.signOutCalled)
        XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
        XCTAssertTrue(accountManager.fetchAccountDetailsCalled)
        XCTAssertTrue(accountManager.storeAuthTokenCalled)
        XCTAssertTrue(accountManager.storeAccountCalled)
        XCTAssertTrue(accountManager.checkForEntitlementsCalled)

        XCTAssertTrue(accountManager.isUserAuthenticated)
        XCTAssertEqual(accountManager.accessToken, Constants.accessToken)
        XCTAssertEqual(accountManager.externalID, Constants.externalID)
    }

    func testCompleteSubscriptionPurchaseSuccessOnRepurchase() async throws {
        // Given
        // Repurchase flow: authToken, accessToken and externalID are present
        accountManager.authToken = Constants.authToken
        accountManager.accessToken = Constants.accessToken
        accountManager.externalID = Constants.externalID

        accountManager.fetchAccountDetailsResult = .success(AccountManager.AccountDetails(email: Constants.email, externalID: Constants.externalID))

        accountManager.onCheckForEntitlements = { wait, retry in
            XCTAssertEqual(wait, 2.0)
            XCTAssertEqual(retry, 5)
            return true
        }

        XCTAssertTrue(accountManager.isUserAuthenticated)

        // When
        await stripePurchaseFlow.completeSubscriptionPurchase()

        // Then
        XCTAssertTrue(subscriptionService.signOutCalled)
        XCTAssertFalse(accountManager.exchangeAuthTokenToAccessTokenCalled)
        XCTAssertFalse(accountManager.fetchAccountDetailsCalled)
        XCTAssertFalse(accountManager.storeAuthTokenCalled)
        XCTAssertFalse(accountManager.storeAccountCalled)
        XCTAssertTrue(accountManager.checkForEntitlementsCalled)

        XCTAssertTrue(accountManager.isUserAuthenticated)
        XCTAssertEqual(accountManager.accessToken, Constants.accessToken)
        XCTAssertEqual(accountManager.externalID, Constants.externalID)
    }
}

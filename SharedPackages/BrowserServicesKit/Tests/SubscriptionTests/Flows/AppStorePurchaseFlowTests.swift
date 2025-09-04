//
//  AppStorePurchaseFlowTests.swift
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

final class AppStorePurchaseFlowTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"

        static let productID = UUID().uuidString
        static let transactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="

        static let unknownServerError = APIServiceError.serverError(statusCode: 401, errorCode: "unknown_error")
    }

    var accountManager: AccountManagerMock!
    var subscriptionService: SubscriptionEndpointServiceMock!
    var authService: AuthEndpointServiceMock!
    var storePurchaseManager: StorePurchaseManagerMock!
    var appStoreRestoreFlow: AppStoreRestoreFlowMock!

    var appStorePurchaseFlow: AppStorePurchaseFlow!

    override func setUpWithError() throws {
        subscriptionService = SubscriptionEndpointServiceMock()
        storePurchaseManager = StorePurchaseManagerMock()
        accountManager = AccountManagerMock()
        appStoreRestoreFlow = AppStoreRestoreFlowMock()
        authService = AuthEndpointServiceMock()

        appStorePurchaseFlow = DefaultAppStorePurchaseFlow(subscriptionEndpointService: subscriptionService,
                                                           storePurchaseManager: storePurchaseManager,
                                                           accountManager: accountManager,
                                                           appStoreRestoreFlow: appStoreRestoreFlow,
                                                           authEndpointService: authService)
    }

    override func tearDownWithError() throws {
        subscriptionService = nil
        storePurchaseManager = nil
        accountManager = nil
        appStoreRestoreFlow = nil
        authService = nil

        appStorePurchaseFlow = nil
    }

    // MARK: - Tests for purchaseSubscription

    func testPurchaseSubscriptionSuccess() async throws {
        // Given
        XCTAssertFalse(accountManager.isUserAuthenticated)

        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .success(CreateAccountResponse(authToken: Constants.authToken,
                                                                         externalID: Constants.externalID,
                                                                         status: "created"))
        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.fetchAccountDetailsResult = .success((email: "", externalID: Constants.externalID))
        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success(let success):
            // Then
            XCTAssertTrue(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.storeAuthTokenCalled)
            XCTAssertTrue(accountManager.storeAccountCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(success, Constants.transactionJWS)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testPurchaseSubscriptionSuccessRepurchaseForAppStoreSubscription() async throws {
        // Given
        accountManager.authToken = Constants.authToken
        accountManager.accessToken = Constants.accessToken
        accountManager.externalID = Constants.externalID
        accountManager.email = Constants.email

        let expiredSubscription = SubscriptionMockFactory.expiredSubscription

        XCTAssertFalse(expiredSubscription.isActive)
        XCTAssertEqual(expiredSubscription.platform, .apple)
        XCTAssertTrue(accountManager.isUserAuthenticated)

        subscriptionService.getSubscriptionResult = .success(expiredSubscription)
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.subscriptionExpired(accountDetails: .init(authToken: Constants.authToken,
                                                                                                                       accessToken: Constants.accessToken,
                                                                                                                       externalID: Constants.externalID,
                                                                                                                       email: Constants.email)))
        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success(let success):
            // Then
            XCTAssertTrue(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
            XCTAssertFalse(authService.createAccountCalled)
            XCTAssertFalse(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(success, Constants.transactionJWS)
            XCTAssertEqual(accountManager.externalID, Constants.externalID)
            XCTAssertEqual(accountManager.email, Constants.email)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testPurchaseSubscriptionSuccessRepurchaseForNonAppStoreSubscription() async throws {
        // Given
        accountManager.authToken = Constants.authToken
        accountManager.accessToken = Constants.accessToken
        accountManager.externalID = Constants.externalID

        let subscription = SubscriptionMockFactory.expiredStripeSubscription

        XCTAssertFalse(subscription.isActive)
        XCTAssertNotEqual(subscription.platform, .apple)
        XCTAssertTrue(accountManager.isUserAuthenticated)

        subscriptionService.getSubscriptionResult = .success(subscription)
        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            // Then
            XCTAssertFalse(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
            XCTAssertFalse(authService.createAccountCalled)
            XCTAssertEqual(accountManager.externalID, Constants.externalID)
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testPurchaseSubscriptionErrorWhenActiveSubscriptionRestoredFromAppStore() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .success(Void())

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertFalse(authService.createAccountCalled)
            XCTAssertFalse(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .activeSubscriptionAlreadyPresent)
        }
    }

    func testPurchaseSubscriptionErrorWhenAccountCreationFails() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .failure(.unknownServerError)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertFalse(storePurchaseManager.purchaseSubscriptionCalled)
            switch error {
            case .accountCreationFailed:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPurchaseSubscriptionErrorWhenAppStorePurchaseFails() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .success(CreateAccountResponse(authToken: Constants.authToken,
                                                                         externalID: Constants.externalID,
                                                                         status: "created"))
        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.fetchAccountDetailsResult = .success((email: "", externalID: Constants.externalID))
        storePurchaseManager.purchaseSubscriptionResult = .failure(.productNotFound)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            switch error {
            case .purchaseFailed:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPurchaseSubscriptionErrorWhenAppStorePurchaseCancelledByUser() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        authService.createAccountResult = .success(CreateAccountResponse(authToken: Constants.authToken,
                                                                         externalID: Constants.externalID,
                                                                         status: "created"))
        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
        accountManager.fetchAccountDetailsResult = .success((email: "", externalID: Constants.externalID))
        storePurchaseManager.purchaseSubscriptionResult = .failure(.purchaseCancelledByUser)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID, emailAccessToken: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(authService.createAccountCalled)
            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
            XCTAssertEqual(error, .cancelledByUser)
        }
    }

    // MARK: - Tests for completeSubscriptionPurchase

    func testCompleteSubscriptionPurchaseSuccess() async throws {
        // Given
        accountManager.accessToken = Constants.accessToken
        subscriptionService.confirmPurchaseResult = .success(
            ConfirmPurchaseResponse(
                email: nil,
                entitlements: [],
                subscription: SubscriptionMockFactory.appleSubscription
            )
        )

        let expectedAdditionalParams = ["key1": "value1", "key2": "value2"]

        subscriptionService.onConfirmPurchase = { accessToken, signature, additionalParams in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(signature, Constants.transactionJWS)
            XCTAssertEqual(additionalParams, expectedAdditionalParams)
        }

        subscriptionService.onUpdateCache = { subscription in
            XCTAssertEqual(subscription, SubscriptionMockFactory.appleSubscription)
        }

        // When
        switch await appStorePurchaseFlow.completeSubscriptionPurchase(
            with: Constants.transactionJWS,
            additionalParams: expectedAdditionalParams
        ) {
        case .success(let success):
            // Then
            XCTAssertTrue(subscriptionService.updateCacheWithSubscriptionCalled)
            XCTAssertTrue(accountManager.updateCacheWithEntitlementsCalled)
            XCTAssertEqual(success.type, "completed")
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testCompleteSubscriptionPurchaseWithNilAdditionalParams() async throws {
        // Given
        accountManager.accessToken = Constants.accessToken
        subscriptionService.confirmPurchaseResult = .success(
            ConfirmPurchaseResponse(
                email: nil,
                entitlements: [],
                subscription: SubscriptionMockFactory.appleSubscription
            )
        )

        subscriptionService.onConfirmPurchase = { accessToken, signature, additionalParams in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(signature, Constants.transactionJWS)
            XCTAssertNil(additionalParams)
        }

        subscriptionService.onUpdateCache = { subscription in
            XCTAssertEqual(subscription, SubscriptionMockFactory.appleSubscription)
        }

        // When
        switch await appStorePurchaseFlow.completeSubscriptionPurchase(
            with: Constants.transactionJWS,
            additionalParams: nil
        ) {
        case .success(let success):
            // Then
            XCTAssertTrue(subscriptionService.updateCacheWithSubscriptionCalled)
            XCTAssertTrue(accountManager.updateCacheWithEntitlementsCalled)
            XCTAssertEqual(success.type, "completed")
        case .failure(let error):
            XCTFail("Unexpected failure: \(String(reflecting: error))")
        }
    }

    func testCompleteSubscriptionPurchaseErrorDueToMissingAccessToken() async throws {
        // Given
        XCTAssertNil(accountManager.accessToken)

        // When
        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: Constants.transactionJWS, additionalParams: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertEqual(error, .missingEntitlements)
        }
    }

    func testCompleteSubscriptionPurchaseErrorWithAdditionalParams() async throws {
        // Given
        accountManager.accessToken = Constants.accessToken
        subscriptionService.confirmPurchaseResult = .failure(Constants.unknownServerError)

        let additionalParams = ["key1": "value1"]

        subscriptionService.onConfirmPurchase = { accessToken, signature, additionalParams in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(signature, Constants.transactionJWS)
            XCTAssertEqual(additionalParams, additionalParams)
        }

        // When
        switch await appStorePurchaseFlow.completeSubscriptionPurchase(
            with: Constants.transactionJWS,
            additionalParams: additionalParams
        ) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertEqual(error, .missingEntitlements)
        }
    }

    func testCompleteSubscriptionPurchaseErrorDueToFailedPurchaseConfirmation() async throws {
        // Given
        accountManager.accessToken = Constants.accessToken
        subscriptionService.confirmPurchaseResult = .failure(Constants.unknownServerError)

        // When
        switch await appStorePurchaseFlow.completeSubscriptionPurchase(with: Constants.transactionJWS, additionalParams: nil) {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertEqual(error, .missingEntitlements)
        }
    }
}

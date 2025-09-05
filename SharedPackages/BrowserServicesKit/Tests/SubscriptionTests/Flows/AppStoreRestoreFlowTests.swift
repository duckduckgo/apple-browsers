//
//  AppStoreRestoreFlowTests.swift
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

final class AppStoreRestoreFlowTests: XCTestCase {

    private struct Constants {
        static let authToken = UUID().uuidString
        static let accessToken = UUID().uuidString
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"

        static let mostRecentTransactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="
        static let storeLoginResponse = StoreLoginResponse(authToken: Constants.authToken,
                                                           email: Constants.email,
                                                           externalID: Constants.externalID,
                                                           id: 1,
                                                           status: "authenticated")

        static let unknownServerError = APIServiceError.serverError(statusCode: 401, statusDescription: "unknown_error")
    }

    var accountManager: AccountManagerMock!
    var storePurchaseManager: StorePurchaseManagerMock!
    var subscriptionService: SubscriptionEndpointServiceMock!
    var authService: AuthEndpointServiceMock!

    var appStoreRestoreFlow: AppStoreRestoreFlow!

    override func setUpWithError() throws {
        accountManager = AccountManagerMock()
        storePurchaseManager = StorePurchaseManagerMock()
        subscriptionService = SubscriptionEndpointServiceMock()
        authService = AuthEndpointServiceMock()

        appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                                         storePurchaseManager: storePurchaseManager,
                                                         subscriptionEndpointService: subscriptionService,
                                                         authEndpointService: authService)
    }

    override func tearDownWithError() throws {
        accountManager = nil
        subscriptionService = nil
        authService = nil
        storePurchaseManager = nil

        appStoreRestoreFlow = nil
    }

    // MARK: - Tests for restoreAccountFromPastPurchase

    func testRestoreAccountFromPastPurchaseSuccess() async throws {
        // Given
        XCTAssertFalse(accountManager.isUserAuthenticated)

        storePurchaseManager.mostRecentTransactionResult = Constants.mostRecentTransactionJWS

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)

        accountManager.fetchAccountDetailsResult = .success(AccountManager.AccountDetails(email: Constants.email,
                                                                                          externalID: Constants.externalID))
        accountManager.onFetchAccountDetails = { accessToken in
            XCTAssertEqual(accessToken, Constants.accessToken)
        }

        let subscription = SubscriptionMockFactory.appleSubscription
        subscriptionService.getSubscriptionResult = .success(subscription)

        XCTAssertTrue(subscription.isActive)

        accountManager.onStoreAuthToken = { authToken in
            XCTAssertEqual(authToken, Constants.authToken)
        }

        accountManager.onStoreAccount = { accessToken, email, externalID in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(externalID, Constants.externalID)
        }

        // When
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            // Then
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.fetchAccountDetailsCalled)
            XCTAssertTrue(accountManager.storeAuthTokenCalled)
            XCTAssertTrue(accountManager.storeAccountCalled)

            XCTAssertTrue(accountManager.isUserAuthenticated)
            XCTAssertEqual(accountManager.authToken, Constants.authToken)
            XCTAssertEqual(accountManager.accessToken, Constants.accessToken)
            XCTAssertEqual(accountManager.externalID, Constants.externalID)
            XCTAssertEqual(accountManager.email, Constants.email)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToSubscriptionBeingExpired() async throws {
        // Given
        XCTAssertFalse(accountManager.isUserAuthenticated)

        storePurchaseManager.mostRecentTransactionResult = Constants.mostRecentTransactionJWS

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)

        accountManager.fetchAccountDetailsResult = .success(AccountManager.AccountDetails(email: nil, externalID: Constants.externalID))
        accountManager.onFetchAccountDetails = { accessToken in
            XCTAssertEqual(accessToken, Constants.accessToken)
        }

        let subscription = SubscriptionMockFactory.expiredSubscription
        subscriptionService.getSubscriptionResult = .success(subscription)

        XCTAssertFalse(subscription.isActive)

        accountManager.onStoreAuthToken = { authToken in
            XCTAssertEqual(authToken, Constants.authToken)
        }

        accountManager.onStoreAccount = { accessToken, email, externalID in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(externalID, Constants.externalID)
        }

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        // When
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)

            guard case .subscriptionExpired(let accountDetails) = error else {
                XCTFail("Expected .subscriptionExpired error")
                return
            }

            XCTAssertEqual(accountDetails.authToken, Constants.authToken)
            XCTAssertEqual(accountDetails.accessToken, Constants.accessToken)
            XCTAssertEqual(accountDetails.externalID, Constants.externalID)

            XCTAssertFalse(accountManager.isUserAuthenticated)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorWhenNoRecentTransaction() async throws {
        // Given
        XCTAssertFalse(accountManager.isUserAuthenticated)

        storePurchaseManager.mostRecentTransactionResult = nil

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        // When
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertFalse(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertFalse(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .missingAccountOrTransactions)

            XCTAssertFalse(accountManager.isUserAuthenticated)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToStoreLoginFailure() async throws {
        // Given
        XCTAssertFalse(accountManager.isUserAuthenticated)

        storePurchaseManager.mostRecentTransactionResult = Constants.mostRecentTransactionJWS

        authService.storeLoginResult = .failure(Constants.unknownServerError)

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        // When
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertFalse(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertFalse(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .pastTransactionAuthenticationError)

            XCTAssertFalse(accountManager.isUserAuthenticated)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToStoreAuthTokenExchangeFailure() async throws {
        // Given
        XCTAssertFalse(accountManager.isUserAuthenticated)

        storePurchaseManager.mostRecentTransactionResult = Constants.mostRecentTransactionJWS

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.exchangeAuthTokenToAccessTokenResult = .failure(Constants.unknownServerError)

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        // When
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertFalse(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .failedToObtainAccessToken)

            XCTAssertFalse(accountManager.isUserAuthenticated)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToAccountDetailsFetchFailure() async throws {
        // Given
        XCTAssertFalse(accountManager.isUserAuthenticated)

        storePurchaseManager.mostRecentTransactionResult = Constants.mostRecentTransactionJWS

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)

        accountManager.fetchAccountDetailsResult = .failure(Constants.unknownServerError)
        accountManager.onFetchAccountDetails = { accessToken in
            XCTAssertEqual(accessToken, Constants.accessToken)
        }

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        // When
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .failedToFetchAccountDetails)

            XCTAssertFalse(accountManager.isUserAuthenticated)
        }
    }

    func testRestoreAccountFromPastPurchaseErrorDueToSubscriptionFetchFailure() async throws {
        // Given
        XCTAssertFalse(accountManager.isUserAuthenticated)

        storePurchaseManager.mostRecentTransactionResult = Constants.mostRecentTransactionJWS

        authService.storeLoginResult = .success(Constants.storeLoginResponse)

        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)

        accountManager.fetchAccountDetailsResult = .success(AccountManager.AccountDetails(email: nil, externalID: Constants.externalID))
        accountManager.onFetchAccountDetails = { accessToken in
            XCTAssertEqual(accessToken, Constants.accessToken)
        }

        subscriptionService.getSubscriptionResult = .failure(.apiError(Constants.unknownServerError))

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: accountManager,
                                              storePurchaseManager: storePurchaseManager,
                                              subscriptionEndpointService: subscriptionService,
                                              authEndpointService: authService)
        // When
        switch await appStoreRestoreFlow.restoreAccountFromPastPurchase() {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            // Then
            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
            XCTAssertTrue(accountManager.fetchAccountDetailsCalled)
            XCTAssertFalse(accountManager.storeAuthTokenCalled)
            XCTAssertFalse(accountManager.storeAccountCalled)
            XCTAssertEqual(error, .failedToFetchSubscriptionDetails)

            XCTAssertFalse(accountManager.isUserAuthenticated)
        }
    }
}

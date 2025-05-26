//
//  AppStorePurchaseFlowV2Tests.swift
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

@available(macOS 12.0, iOS 15.0, *)
final class AppStorePurchaseFlowV2Tests: XCTestCase {

    private var sut: DefaultAppStorePurchaseFlowV2!
    private var subscriptionManagerMock: SubscriptionManagerMockV2!
    private var storePurchaseManagerMock: StorePurchaseManagerMockV2!
    private var appStoreRestoreFlowMock: AppStoreRestoreFlowMockV2!

    override func setUp() {
        super.setUp()
        subscriptionManagerMock = SubscriptionManagerMockV2()
        storePurchaseManagerMock = StorePurchaseManagerMockV2()
        appStoreRestoreFlowMock = AppStoreRestoreFlowMockV2()
        sut = DefaultAppStorePurchaseFlowV2(
            subscriptionManager: subscriptionManagerMock,
            storePurchaseManager: storePurchaseManagerMock,
            appStoreRestoreFlow: appStoreRestoreFlowMock
        )
    }

    override func tearDown() {
        sut = nil
        subscriptionManagerMock = nil
        storePurchaseManagerMock = nil
        appStoreRestoreFlowMock = nil
        super.tearDown()
    }

    // MARK: - purchaseSubscription Tests

    func test_purchaseSubscription_withActiveSubscriptionAlreadyPresent_returnsError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .success("someTransactionJWS")

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertTrue(appStoreRestoreFlowMock.restoreAccountFromPastPurchaseCalled)
        XCTAssertEqual(result, .failure(.activeSubscriptionAlreadyPresent))
    }

    func test_purchaseSubscription_withNoProductsFound_returnsError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowErrorV2.missingAccountOrTransactions)

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertTrue(appStoreRestoreFlowMock.restoreAccountFromPastPurchaseCalled)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case AppStorePurchaseFlowError.accountCreationFailed:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_purchaseSubscription_successfulPurchase_returnsTransactionJWS() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowErrorV2.missingAccountOrTransactions)
        subscriptionManagerMock.resultCreateAccountTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        storePurchaseManagerMock.purchaseSubscriptionResult = .success("transactionJWS")

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertTrue(storePurchaseManagerMock.purchaseSubscriptionCalled)
        XCTAssertEqual(result, .success("transactionJWS"))
    }

    func test_purchaseSubscription_purchaseCancelledByUser_returnsCancelledError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowErrorV2.missingAccountOrTransactions)
        storePurchaseManagerMock.purchaseSubscriptionResult = .failure(StorePurchaseManagerError.purchaseCancelledByUser)
        subscriptionManagerMock.resultCreateAccountTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.appleSubscription

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertEqual(result, .failure(.cancelledByUser))
    }

    func test_purchaseSubscription_purchaseFailed_returnsPurchaseFailedError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowErrorV2.missingAccountOrTransactions)
        storePurchaseManagerMock.purchaseSubscriptionResult = .failure(StorePurchaseManagerError.purchaseFailed)
        subscriptionManagerMock.resultCreateAccountTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.appleSubscription

        let result = await sut.purchaseSubscription(with: "testSubscriptionID")

        XCTAssertEqual(result, .failure(.purchaseFailed(StorePurchaseManagerError.purchaseFailed)))
    }

    // MARK: - completeSubscriptionPurchase Tests

    func test_completeSubscriptionPurchase_withActiveSubscription_returnsSuccess() async {
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.appleSubscription
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscriptionManagerMock.resultSubscription!)

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS", additionalParams: nil)

        XCTAssertEqual(result, .success(.completed))
    }

    func test_completeSubscriptionPurchase_withMissingEntitlements_returnsMissingEntitlementsError() async {
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.appleSubscription
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscriptionManagerMock.resultSubscription!)

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS", additionalParams: nil)

        XCTAssertEqual(result, .failure(.missingEntitlements))
    }

    func test_completeSubscriptionPurchase_withExpiredSubscription_returnsPurchaseFailedError() async {
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.expiredSubscription
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscriptionManagerMock.resultSubscription!)

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS", additionalParams: nil)

        XCTAssertEqual(result, .failure(.purchaseFailed(AppStoreRestoreFlowErrorV2.subscriptionExpired)))
    }

    func test_completeSubscriptionPurchase_withConfirmPurchaseError_returnsPurchaseFailedError() async {
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.appleSubscription
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        subscriptionManagerMock.confirmPurchaseResponse = .failure(OAuthServiceError.invalidResponseCode(HTTPStatusCode.badRequest))

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS", additionalParams: nil)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure(let error):
            switch error {
            case .purchaseFailed:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

/*
final class AppStorePurchaseFlowTests: XCTestCase {

    private struct Constants {
        static let externalID = UUID().uuidString
        static let email = "dax@duck.com"

        static let productID = UUID().uuidString
        static let transactionJWS = "dGhpcyBpcyBub3QgYSByZWFsIEFw(...)cCBTdG9yZSB0cmFuc2FjdGlvbiBKV1M="
    }

     var mockSubscriptionManager: SubscriptionManagerMockV2!
     var mockStorePurchaseManager: StorePurchaseManagerMockV2!
     var mockAppStoreRestoreFlow: AppStoreRestoreFlowMockV2!

    var appStorePurchaseFlow: AppStorePurchaseFlowV2!

    override func setUpWithError() throws {
        mockSubscriptionManager = SubscriptionManagerMockV2()
        mockStorePurchaseManager = StorePurchaseManagerMockV2()
        mockAppStoreRestoreFlow = AppStoreRestoreFlowMockV2()

        appStorePurchaseFlow = DefaultAppStorePurchaseFlowV2(subscriptionManager: mockSubscriptionManager,
                                                           storePurchaseManager: mockStorePurchaseManager,
                                                           appStoreRestoreFlow: mockAppStoreRestoreFlow)
    }

    override func tearDownWithError() throws {
        mockSubscriptionManager = nil
        mockStorePurchaseManager = nil
        mockAppStoreRestoreFlow = nil
        appStorePurchaseFlow = nil
    }

    // MARK: - Tests for purchaseSubscription

    func testPurchaseSubscriptionSuccess() async throws {
        // Given

        mockAppStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
//        authService.createAccountResult = .success(CreateAccountResponse(authToken: Constants.authToken,
//                                                                         externalID: Constants.externalID,
//                                                                         status: "created"))
//        accountManager.exchangeAuthTokenToAccessTokenResult = .success(Constants.accessToken)
//        accountManager.fetchAccountDetailsResult = .success((email: "", externalID: Constants.externalID))
//        storePurchaseManager.purchaseSubscriptionResult = .success(Constants.transactionJWS)

        // When
        switch await appStorePurchaseFlow.purchaseSubscription(with: Constants.productID) {
        case .success(let success):
//            // Then
//            XCTAssertTrue(appStoreRestoreFlow.restoreAccountFromPastPurchaseCalled)
//            XCTAssertTrue(authService.createAccountCalled)
//            XCTAssertTrue(accountManager.exchangeAuthTokenToAccessTokenCalled)
//            XCTAssertTrue(accountManager.storeAuthTokenCalled)
//            XCTAssertTrue(accountManager.storeAccountCalled)
//            XCTAssertTrue(storePurchaseManager.purchaseSubscriptionCalled)
//            XCTAssertEqual(success, Constants.transactionJWS)
            break
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
            XCTAssertEqual(error, .accountCreationFailed)
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
            XCTAssertEqual(error, .purchaseFailed)
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
            ConfirmPurchaseResponseV2(
                email: nil,
                entitlements: [],
                subscription: SubscriptionMockFactory.subscription
            )
        )

        let expectedAdditionalParams = ["key1": "value1", "key2": "value2"]

        subscriptionService.onConfirmPurchase = { accessToken, signature, additionalParams in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(signature, Constants.transactionJWS)
            XCTAssertEqual(additionalParams, expectedAdditionalParams)
        }

        subscriptionService.onUpdateCache = { subscription in
            XCTAssertEqual(subscription, SubscriptionMockFactory.subscription)
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
            ConfirmPurchaseResponseV2(
                email: nil,
                entitlements: [],
                subscription: SubscriptionMockFactory.subscription
            )
        )

        subscriptionService.onConfirmPurchase = { accessToken, signature, additionalParams in
            XCTAssertEqual(accessToken, Constants.accessToken)
            XCTAssertEqual(signature, Constants.transactionJWS)
            XCTAssertNil(additionalParams)
        }

        subscriptionService.onUpdateCache = { subscription in
            XCTAssertEqual(subscription, SubscriptionMockFactory.subscription)
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
*/

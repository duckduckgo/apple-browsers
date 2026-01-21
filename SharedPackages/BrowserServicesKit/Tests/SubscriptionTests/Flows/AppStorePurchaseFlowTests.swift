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
@testable import Networking
import SubscriptionTestingUtilities
import NetworkingTestingUtils
import PixelKitTestingUtilities

@available(macOS 12.0, iOS 15.0, *)
final class AppStorePurchaseFlowTests: XCTestCase {

    private var sut: DefaultAppStorePurchaseFlow!
    private var subscriptionManagerMock: SubscriptionManagerMock!
    private var storePurchaseManagerMock: StorePurchaseManagerMock!
    private var appStoreRestoreFlowMock: AppStoreRestoreFlowMock!
    private var wideEventMock: WideEventMock!
    private var pendingTransactionHandlerMock: MockPendingTransactionHandler!

    override func setUp() {
        super.setUp()
        subscriptionManagerMock = SubscriptionManagerMock()
        storePurchaseManagerMock = StorePurchaseManagerMock()
        appStoreRestoreFlowMock = AppStoreRestoreFlowMock()
        wideEventMock = WideEventMock()
        pendingTransactionHandlerMock = MockPendingTransactionHandler()
        sut = DefaultAppStorePurchaseFlow(
            subscriptionManager: subscriptionManagerMock,
            storePurchaseManager: storePurchaseManagerMock,
            appStoreRestoreFlow: appStoreRestoreFlowMock,
            wideEvent: wideEventMock,
            pendingTransactionHandler: pendingTransactionHandlerMock
        )
    }

    override func tearDown() {
        sut = nil
        subscriptionManagerMock = nil
        storePurchaseManagerMock = nil
        appStoreRestoreFlowMock = nil
        wideEventMock = nil
        pendingTransactionHandlerMock = nil
        super.tearDown()
    }

    // MARK: - purchaseSubscription Tests

    func test_purchaseSubscription_withActiveSubscriptionAlreadyPresent_returnsError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .success("someTransactionJWS")

        let result = await sut.purchaseSubscription(with: "testSubscriptionID", includeProTier: false)

        XCTAssertTrue(appStoreRestoreFlowMock.restoreAccountFromPastPurchaseCalled)
        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .activeSubscriptionAlreadyPresent)
        case .success:
            XCTFail("Unexpected success")
        }
    }

    func test_purchaseSubscription_withNoProductsFound_returnsError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowError.missingAccountOrTransactions)

        let result = await sut.purchaseSubscription(with: "testSubscriptionID", includeProTier: false)

        XCTAssertTrue(appStoreRestoreFlowMock.restoreAccountFromPastPurchaseCalled)
        switch result {
        case .success:
            XCTFail("Unexpected success")
        case .failure:
            break
        }
    }

    func test_purchaseSubscription_successfulPurchase_returnsTransactionJWS() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowError.missingAccountOrTransactions)
        subscriptionManagerMock.resultCreateAccountTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        storePurchaseManagerMock.purchaseSubscriptionResult = .success("transactionJWS")

        let result = await sut.purchaseSubscription(with: "testSubscriptionID", includeProTier: false)

        XCTAssertTrue(storePurchaseManagerMock.purchaseSubscriptionCalled)
        switch result {
        case .success(let payload):
            XCTAssertEqual(payload.transactionJWS, "transactionJWS")
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }
    }

    func test_purchaseSubscription_purchaseCancelledByUser_returnsCancelledError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowError.missingAccountOrTransactions)
        storePurchaseManagerMock.purchaseSubscriptionResult = .failure(StorePurchaseManagerError.purchaseCancelledByUser)
        subscriptionManagerMock.resultCreateAccountTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        let result = await sut.purchaseSubscription(with: "testSubscriptionID", includeProTier: false)

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .cancelledByUser)
        case .success:
            XCTFail("Unexpected success")
        }
    }

    func test_purchaseSubscription_purchaseFailed_returnsPurchaseFailedError() async {
        appStoreRestoreFlowMock.restoreAccountFromPastPurchaseResult = .failure(AppStoreRestoreFlowError.missingAccountOrTransactions)
        let underlyingError = NSError(domain: "test", code: 1)
        storePurchaseManagerMock.purchaseSubscriptionResult = .failure(StorePurchaseManagerError.purchaseFailed(underlyingError))
        subscriptionManagerMock.resultCreateAccountTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        let result = await sut.purchaseSubscription(with: "testSubscriptionID", includeProTier: false)

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .purchaseFailed(underlyingError))
        case .success:
            XCTFail("Unexpected success")
        }
    }

    // MARK: - completeSubscriptionPurchase Tests

    func test_completeSubscriptionPurchase_withActiveSubscription_returnsSuccess() async {
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        let subscription = SubscriptionMockFactory.appleSubscription
        subscriptionManagerMock.resultSubscription = .success(subscription)
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscription)

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS", additionalParams: nil)

        XCTAssertEqual(result, .success(.completed))
    }

    func test_completeSubscriptionPurchase_withMissingEntitlements_returnsMissingEntitlementsError() async {
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        let subscription = SubscriptionMockFactory.appleSubscription
        subscriptionManagerMock.resultSubscription = .success(subscription)
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscription)

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS", additionalParams: nil)

        XCTAssertEqual(result, .failure(.missingEntitlements))
    }

    func test_completeSubscriptionPurchase_withExpiredSubscription_returnsPurchaseFailedError() async {
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        let expiredSubscription = SubscriptionMockFactory.expiredSubscription
        subscriptionManagerMock.resultSubscription = .success(expiredSubscription)
        subscriptionManagerMock.confirmPurchaseResponse = .success(expiredSubscription)

        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS", additionalParams: nil)

        XCTAssertEqual(result, .failure(.purchaseFailed(AppStoreRestoreFlowError.subscriptionExpired)))
    }

    func test_completeSubscriptionPurchase_withConfirmPurchaseError_returnsPurchaseFailedError() async {
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)
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

    // MARK: - PendingTransactionHandler Tests

    func test_completeSubscriptionPurchase_withSuccess_callsHandleSubscriptionActivated() async {
        // Given
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        let subscription = SubscriptionMockFactory.appleSubscription
        subscriptionManagerMock.resultSubscription = .success(subscription)
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscription)

        // When
        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS", additionalParams: nil)

        // Then
        XCTAssertEqual(result, .success(.completed))
        XCTAssertTrue(pendingTransactionHandlerMock.handleSubscriptionActivatedCalled)
    }

    func test_completeSubscriptionPurchase_withFailure_doesNotCallHandleSubscriptionActivated() async {
        // Given
        subscriptionManagerMock.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        let subscription = SubscriptionMockFactory.appleSubscription
        subscriptionManagerMock.resultSubscription = .success(subscription)
        subscriptionManagerMock.confirmPurchaseResponse = .success(subscription)

        // When
        let result = await sut.completeSubscriptionPurchase(with: "transactionJWS", additionalParams: nil)

        // Then
        XCTAssertEqual(result, .failure(.missingEntitlements))
        XCTAssertFalse(pendingTransactionHandlerMock.handleSubscriptionActivatedCalled)
    }
}

// MARK: - Mock

@available(macOS 12.0, iOS 15.0, *)
private final class MockPendingTransactionHandler: PendingTransactionHandling {
    var markPurchasePendingCalled = false
    var handleSubscriptionActivatedCalled = false
    var handlePendingTransactionApprovedCalled = false

    func markPurchasePending() {
        markPurchasePendingCalled = true
    }

    func handleSubscriptionActivated() {
        handleSubscriptionActivatedCalled = true
    }

    func handlePendingTransactionApproved() {
        handlePendingTransactionApprovedCalled = true
    }
}

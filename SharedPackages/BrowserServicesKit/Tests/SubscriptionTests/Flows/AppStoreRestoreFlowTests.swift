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
@testable import Networking
import NetworkingTestingUtils

@available(macOS 12.0, iOS 15.0, *)
final class AppStoreRestoreFlowTests: XCTestCase {

    private var sut: DefaultAppStoreRestoreFlow!
    private var subscriptionManagerMock: SubscriptionManagerMock!
    private var storePurchaseManagerMock: StorePurchaseManagerMock!
    private var pendingTransactionHandlerMock: MockPendingTransactionHandler!

    override func setUp() {
        super.setUp()
        subscriptionManagerMock = SubscriptionManagerMock()
        storePurchaseManagerMock = StorePurchaseManagerMock()
        pendingTransactionHandlerMock = MockPendingTransactionHandler()
        sut = DefaultAppStoreRestoreFlow(
            subscriptionManager: subscriptionManagerMock,
            storePurchaseManager: storePurchaseManagerMock,
            pendingTransactionHandler: pendingTransactionHandlerMock
        )
    }

    override func tearDown() {
        sut = nil
        subscriptionManagerMock = nil
        storePurchaseManagerMock = nil
        pendingTransactionHandlerMock = nil
        super.tearDown()
    }

    // MARK: - restoreAccountFromPastPurchase Tests

    func test_restoreAccountFromPastPurchase_withNoTransaction_returnsMissingAccountOrTransactionsError() async {
        storePurchaseManagerMock.mostRecentTransactionResult = nil

        let result = await sut.restoreAccountFromPastPurchase()

        XCTAssertTrue(storePurchaseManagerMock.mostRecentTransactionCalled)
        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .missingAccountOrTransactions)
        case .success:
            XCTFail("Unexpected success")
        }
    }

    func test_restoreAccountFromPastPurchase_withExpiredSubscription_returnsSubscriptionExpiredError() async {
        storePurchaseManagerMock.mostRecentTransactionResult = "lastTransactionJWS"
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.expiredSubscription)

        let result = await sut.restoreAccountFromPastPurchase()

        XCTAssertTrue(storePurchaseManagerMock.mostRecentTransactionCalled)
        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .subscriptionExpired)
        case .success:
            XCTFail("Unexpected success")
        }
    }

    func test_restoreAccountFromPastPurchase_withPastTransactionAuthenticationError_returnsAuthenticationError() async {
        storePurchaseManagerMock.mostRecentTransactionResult = "lastTransactionJWS"
        subscriptionManagerMock.resultSubscription = nil // Triggers an error when calling getSubscriptionFrom()

        let result = await sut.restoreAccountFromPastPurchase()

        XCTAssertTrue(storePurchaseManagerMock.mostRecentTransactionCalled)
        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .pastTransactionAuthenticationError)
        case .success:
            XCTFail("Unexpected success")
        }
    }

    func test_restoreAccountFromPastPurchase_withActiveSubscription_returnsSuccess() async {
        storePurchaseManagerMock.mostRecentTransactionResult = "lastTransactionJWS"
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        let result = await sut.restoreAccountFromPastPurchase()

        XCTAssertTrue(storePurchaseManagerMock.mostRecentTransactionCalled)
        switch result {
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        case .success:
            break
        }
    }

    // MARK: - PendingTransactionHandler Tests

    func test_restoreAccountFromPastPurchase_withSuccess_callsHandleSubscriptionActivated() async {
        // Given
        storePurchaseManagerMock.mostRecentTransactionResult = "lastTransactionJWS"
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        // When
        let result = await sut.restoreAccountFromPastPurchase()

        // Then
        switch result {
        case .success:
            XCTAssertTrue(pendingTransactionHandlerMock.handleSubscriptionActivatedCalled)
        case .failure:
            XCTFail("Unexpected failure")
        }
    }

    func test_restoreAccountFromPastPurchase_withMissingTransaction_doesNotCallHandleSubscriptionActivated() async {
        // Given
        storePurchaseManagerMock.mostRecentTransactionResult = nil

        // When
        let result = await sut.restoreAccountFromPastPurchase()

        // Then
        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .missingAccountOrTransactions)
            XCTAssertFalse(pendingTransactionHandlerMock.handleSubscriptionActivatedCalled)
        case .success:
            XCTFail("Unexpected success")
        }
    }

    func test_restoreAccountFromPastPurchase_withExpiredSubscription_doesNotCallHandleSubscriptionActivated() async {
        // Given
        storePurchaseManagerMock.mostRecentTransactionResult = "lastTransactionJWS"
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.expiredSubscription)

        // When
        let result = await sut.restoreAccountFromPastPurchase()

        // Then
        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .subscriptionExpired)
            XCTAssertFalse(pendingTransactionHandlerMock.handleSubscriptionActivatedCalled)
        case .success:
            XCTFail("Unexpected success")
        }
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

//
//  AppStoreRestoreFlowV2Tests.swift
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
final class AppStoreRestoreFlowV2Tests: XCTestCase {

    private var sut: DefaultAppStoreRestoreFlowV2!
    private var subscriptionManagerMock: SubscriptionManagerMockV2!
    private var storePurchaseManagerMock: StorePurchaseManagerMockV2!

    override func setUp() {
        super.setUp()
        subscriptionManagerMock = SubscriptionManagerMockV2()
        storePurchaseManagerMock = StorePurchaseManagerMockV2()
        sut = DefaultAppStoreRestoreFlowV2(
            subscriptionManager: subscriptionManagerMock,
            storePurchaseManager: storePurchaseManagerMock
        )
    }

    override func tearDown() {
        sut = nil
        subscriptionManagerMock = nil
        storePurchaseManagerMock = nil
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
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.expiredSubscription

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
        subscriptionManagerMock.resultSubscription = SubscriptionMockFactory.appleSubscription

        let result = await sut.restoreAccountFromPastPurchase()

        XCTAssertTrue(storePurchaseManagerMock.mostRecentTransactionCalled)
        switch result {
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        case .success:
            break
        }
    }
}

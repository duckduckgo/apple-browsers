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
import StoreKit
@testable import Subscription
import SubscriptionTestingUtilities
@_spi(Testing) @testable import Networking

@available(iOS 15.0, *)
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

    // MARK: - syncAndRestoreAccountFromPastPurchase Tests

    func test_syncAndRestoreAccountFromPastPurchase_whenTransactionOnlyAppearsAfterSync_returnsSuccess() async {
        // Given the device has no local transaction until the App Store sync delivers it
        storePurchaseManagerMock.mostRecentTransactionResult = nil
        storePurchaseManagerMock.onSyncAppleIDAccount = { [storePurchaseManagerMock] in
            storePurchaseManagerMock?.mostRecentTransactionResult = "syncedTransactionJWS"
        }
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        // When
        let result = await sut.syncAndRestoreAccountFromPastPurchase(wideEventData: nil)

        // Then
        XCTAssertTrue(storePurchaseManagerMock.syncAppleIDAccountCalled)
        XCTAssertEqual(try? result.get(), "syncedTransactionJWS")
    }

    func test_syncAndRestoreAccountFromPastPurchase_syncsBeforeReadingTransactions() async {
        // Given
        var mostRecentTransactionReadBeforeSync: Bool?
        storePurchaseManagerMock.onSyncAppleIDAccount = { [storePurchaseManagerMock] in
            mostRecentTransactionReadBeforeSync = storePurchaseManagerMock?.mostRecentTransactionCalled
        }
        storePurchaseManagerMock.mostRecentTransactionResult = "lastTransactionJWS"
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        // When
        await sut.syncAndRestoreAccountFromPastPurchase(wideEventData: nil)

        // Then
        XCTAssertEqual(mostRecentTransactionReadBeforeSync, false)
        XCTAssertTrue(storePurchaseManagerMock.mostRecentTransactionCalled)
    }

    func test_syncAndRestoreAccountFromPastPurchase_whenSyncFails_restoresFromLocalTransaction() async {
        // Given
        storePurchaseManagerMock.syncAppleIDAccountResultError = StoreKitError.networkError(URLError(.notConnectedToInternet))
        storePurchaseManagerMock.mostRecentTransactionResult = "localTransactionJWS"
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        // When
        let result = await sut.syncAndRestoreAccountFromPastPurchase(wideEventData: nil)

        // Then
        XCTAssertTrue(storePurchaseManagerMock.syncAppleIDAccountCalled)
        XCTAssertEqual(try? result.get(), "localTransactionJWS")
        XCTAssertTrue(pendingTransactionHandlerMock.handleSubscriptionActivatedCalled)
    }

    func test_syncAndRestoreAccountFromPastPurchase_whenUserCancelsSyncAndNoLocalTransaction_returnsMissingAccountOrTransactionsError() async {
        // Given
        storePurchaseManagerMock.syncAppleIDAccountResultError = StoreKitError.userCancelled
        storePurchaseManagerMock.mostRecentTransactionResult = nil

        // When
        let result = await sut.syncAndRestoreAccountFromPastPurchase(wideEventData: nil)

        // Then
        XCTAssertTrue(storePurchaseManagerMock.mostRecentTransactionCalled)
        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .missingAccountOrTransactions)
        case .success:
            XCTFail("Unexpected success")
        }
    }

    func test_syncAndRestoreAccountFromPastPurchase_whenSyncSucceeds_recordsSuccessOnWideEvent() async {
        // Given
        let wideEventData = SubscriptionRestoreWideEventData(restorePlatform: .appleAccount)
        storePurchaseManagerMock.mostRecentTransactionResult = "lastTransactionJWS"
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        // When
        await sut.syncAndRestoreAccountFromPastPurchase(wideEventData: wideEventData)

        // Then
        XCTAssertEqual(wideEventData.appStoreSyncResult, .success)
        XCTAssertNil(wideEventData.appStoreSyncErrorDomain)
        XCTAssertNil(wideEventData.appStoreSyncErrorCode)
    }

    func test_syncAndRestoreAccountFromPastPurchase_whenSyncFails_recordsFailureWithErrorOnWideEvent() async {
        // Given
        let wideEventData = SubscriptionRestoreWideEventData(restorePlatform: .appleAccount)
        let syncError = NSError(domain: "TestSyncDomain", code: 42)
        storePurchaseManagerMock.syncAppleIDAccountResultError = syncError
        storePurchaseManagerMock.mostRecentTransactionResult = "localTransactionJWS"
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        // When
        let result = await sut.syncAndRestoreAccountFromPastPurchase(wideEventData: wideEventData)

        // Then
        XCTAssertEqual(try? result.get(), "localTransactionJWS")
        XCTAssertEqual(wideEventData.appStoreSyncResult, .failure)
        XCTAssertEqual(wideEventData.appStoreSyncErrorDomain, "TestSyncDomain")
        XCTAssertEqual(wideEventData.appStoreSyncErrorCode, 42)
    }

    func test_syncAndRestoreAccountFromPastPurchase_whenUserCancelsSync_recordsUserCancelledOnWideEvent() async {
        // Given
        let wideEventData = SubscriptionRestoreWideEventData(restorePlatform: .appleAccount)
        storePurchaseManagerMock.syncAppleIDAccountResultError = StoreKitError.userCancelled
        storePurchaseManagerMock.mostRecentTransactionResult = nil

        // When
        await sut.syncAndRestoreAccountFromPastPurchase(wideEventData: wideEventData)

        // Then
        XCTAssertEqual(wideEventData.appStoreSyncResult, .userCancelled)
        XCTAssertEqual(wideEventData.appStoreSyncErrorDomain, (StoreKitError.userCancelled as NSError).domain)
    }

    func test_restoreAccountFromPastPurchase_doesNotSyncWithAppStore() async {
        // Given
        storePurchaseManagerMock.mostRecentTransactionResult = "lastTransactionJWS"
        subscriptionManagerMock.resultSubscription = .success(SubscriptionMockFactory.appleSubscription)

        // When
        await sut.restoreAccountFromPastPurchase()

        // Then
        XCTAssertFalse(storePurchaseManagerMock.syncAppleIDAccountCalled)
    }
}

// MARK: - Mock

@available(iOS 15.0, *)
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

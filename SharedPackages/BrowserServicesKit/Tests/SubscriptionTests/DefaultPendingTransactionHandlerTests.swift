//
//  DefaultPendingTransactionHandlerTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

final class DefaultPendingTransactionHandlerTests: XCTestCase {

    private var sut: DefaultPendingTransactionHandler!
    private var mockPixelHandler: MockSubscriptionPixelHandler!
    private var testUserDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testUserDefaults = UserDefaults(suiteName: "DefaultPendingTransactionHandlerTests")!
        testUserDefaults.removePersistentDomain(forName: "DefaultPendingTransactionHandlerTests")
        mockPixelHandler = MockSubscriptionPixelHandler()
        sut = DefaultPendingTransactionHandler(
            userDefaults: testUserDefaults,
            pixelHandler: mockPixelHandler
        )
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: "DefaultPendingTransactionHandlerTests")
        testUserDefaults = nil
        mockPixelHandler = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - markPurchasePending

    func testMarkPurchasePending_SetsFlag() {
        // Given
        XCTAssertFalse(testUserDefaults.hasPurchasePendingTransaction)

        // When
        sut.markPurchasePending()

        // Then
        XCTAssertTrue(testUserDefaults.hasPurchasePendingTransaction)
    }

    // MARK: - handleSubscriptionActivated

    func testHandleSubscriptionActivated_WhenFlagIsSet_FiresPixelAndClearsFlag() {
        // Given
        testUserDefaults.hasPurchasePendingTransaction = true

        // When
        sut.handleSubscriptionActivated()

        // Then
        XCTAssertEqual(mockPixelHandler.handledPixels, [.purchaseSuccessAfterPendingTransaction])
        XCTAssertFalse(testUserDefaults.hasPurchasePendingTransaction)
    }

    func testHandleSubscriptionActivated_WhenFlagIsNotSet_DoesNotFirePixel() {
        // Given
        testUserDefaults.hasPurchasePendingTransaction = false

        // When
        sut.handleSubscriptionActivated()

        // Then
        XCTAssertTrue(mockPixelHandler.handledPixels.isEmpty)
        XCTAssertFalse(testUserDefaults.hasPurchasePendingTransaction)
    }

    func testHandleSubscriptionActivated_CalledMultipleTimes_FiresPixelOnlyOnce() {
        // Given
        testUserDefaults.hasPurchasePendingTransaction = true

        // When
        sut.handleSubscriptionActivated()
        sut.handleSubscriptionActivated()
        sut.handleSubscriptionActivated()

        // Then
        XCTAssertEqual(mockPixelHandler.handledPixels, [.purchaseSuccessAfterPendingTransaction])
        XCTAssertFalse(testUserDefaults.hasPurchasePendingTransaction)
    }

    // MARK: - handlePendingTransactionApproved

    func testHandlePendingTransactionApproved_WhenFlagIsSet_FiresPixel() {
        // Given
        testUserDefaults.hasPurchasePendingTransaction = true

        // When
        sut.handlePendingTransactionApproved()

        // Then
        XCTAssertEqual(mockPixelHandler.handledPixels, [.pendingTransactionApproved])
    }

    func testHandlePendingTransactionApproved_WhenFlagIsNotSet_DoesNotFirePixel() {
        // Given
        testUserDefaults.hasPurchasePendingTransaction = false

        // When
        sut.handlePendingTransactionApproved()

        // Then
        XCTAssertTrue(mockPixelHandler.handledPixels.isEmpty)
    }

    func testHandlePendingTransactionApproved_DoesNotClearFlag() {
        // Given
        testUserDefaults.hasPurchasePendingTransaction = true

        // When
        sut.handlePendingTransactionApproved()

        // Then
        XCTAssertTrue(testUserDefaults.hasPurchasePendingTransaction)
    }

    // MARK: - Full Flow

    func testFullFlow_MarkPendingThenActivate_FiresPixelAndClearsFlag() {
        // Given
        XCTAssertFalse(testUserDefaults.hasPurchasePendingTransaction)

        // When
        sut.markPurchasePending()
        XCTAssertTrue(testUserDefaults.hasPurchasePendingTransaction)

        sut.handleSubscriptionActivated()

        // Then
        XCTAssertEqual(mockPixelHandler.handledPixels, [.purchaseSuccessAfterPendingTransaction])
        XCTAssertFalse(testUserDefaults.hasPurchasePendingTransaction)
    }

    func testFullFlow_MarkPendingThenApprovedThenActivate_FiresBothPixels() {
        // Given
        XCTAssertFalse(testUserDefaults.hasPurchasePendingTransaction)

        // When
        sut.markPurchasePending()
        sut.handlePendingTransactionApproved()
        sut.handleSubscriptionActivated()

        // Then
        XCTAssertEqual(mockPixelHandler.handledPixels, [.pendingTransactionApproved, .purchaseSuccessAfterPendingTransaction])
        XCTAssertFalse(testUserDefaults.hasPurchasePendingTransaction)
    }
}

// MARK: - Mock

private final class MockSubscriptionPixelHandler: SubscriptionPixelHandling {
    var handledPixels: [SubscriptionPixelType] = []
    var handledKeychainPixels: [KeychainManager.Pixel] = []

    func handle(pixel: SubscriptionPixelType) {
        handledPixels.append(pixel)
    }

    func handle(pixel: KeychainManager.Pixel) {
        handledKeychainPixels.append(pixel)
    }
}

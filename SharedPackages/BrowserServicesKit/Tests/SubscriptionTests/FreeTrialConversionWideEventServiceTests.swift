//
//  FreeTrialConversionWideEventServiceTests.swift
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
import Common
import PixelKit
import PixelKitTestingUtilities
@testable import Subscription

final class FreeTrialConversionWideEventServiceTests: XCTestCase {

    private var sut: DefaultFreeTrialConversionWideEventService!
    private var mockWideEvent: WideEventMock!
    private var notificationCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        mockWideEvent = WideEventMock()
        notificationCenter = NotificationCenter()
        sut = DefaultFreeTrialConversionWideEventService(wideEvent: mockWideEvent, notificationCenter: notificationCenter)
        sut.startObservingSubscriptionChanges()
    }

    override func tearDown() {
        sut = nil
        mockWideEvent = nil
        notificationCenter = nil
        super.tearDown()
    }

    // MARK: - Start Flow Tests

    func testWhenUserStartsFreeTrial_ItStartsTheFlow() {
        // Given
        let subscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let expectation = expectation(description: "Flow started")
        mockWideEvent.onStart = { _ in expectation.fulfill() }

        // When
        postSubscriptionChange(subscription)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockWideEvent.started.count, 1)
        let startedData = mockWideEvent.started.first as? FreeTrialConversionWideEventData
        XCTAssertNotNil(startedData)
    }

    func testWhenUserIsAlreadyInFreeTrialWithExistingFlow_ItDoesNotStartANewFlow() {
        // Given
        let subscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let firstFlowExpectation = expectation(description: "First flow started")
        mockWideEvent.onStart = { _ in firstFlowExpectation.fulfill() }

        // Start first flow
        postSubscriptionChange(subscription)
        wait(for: [firstFlowExpectation], timeout: 1.0)
        XCTAssertEqual(mockWideEvent.started.count, 1)

        // When - another subscription change while still in trial
        // The second notification should not trigger startFlow, so we wait briefly
        let secondFlowExpectation = expectation(description: "Second flow should not start")
        secondFlowExpectation.isInverted = true
        mockWideEvent.onStart = { _ in secondFlowExpectation.fulfill() }

        postSubscriptionChange(subscription)
        wait(for: [secondFlowExpectation], timeout: 0.2)

        // Then - should still be only one flow
        XCTAssertEqual(mockWideEvent.started.count, 1)
    }

    // MARK: - Complete Flow Tests

    func testWhenUserConvertsToPaid_ItCompletesTheFlowWithSuccess() {
        // Given - start a trial flow first
        let trialSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let startExpectation = expectation(description: "Flow started")
        mockWideEvent.onStart = { _ in startExpectation.fulfill() }

        postSubscriptionChange(trialSubscription)
        wait(for: [startExpectation], timeout: 1.0)
        XCTAssertEqual(mockWideEvent.started.count, 1)

        // When - user converts to paid (active but no trial offer)
        let completeExpectation = expectation(description: "Flow completed")
        mockWideEvent.onComplete = { _, _ in completeExpectation.fulfill() }

        let paidSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: false)
        postSubscriptionChange(paidSubscription)
        wait(for: [completeExpectation], timeout: 1.0)

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        XCTAssertEqual(mockWideEvent.completions.first?.1, .success)
    }

    func testWhenTrialExpires_ItCompletesTheFlowWithFailure() {
        // Given - start a trial flow first
        let trialSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let startExpectation = expectation(description: "Flow started")
        mockWideEvent.onStart = { _ in startExpectation.fulfill() }

        postSubscriptionChange(trialSubscription)
        wait(for: [startExpectation], timeout: 1.0)
        XCTAssertEqual(mockWideEvent.started.count, 1)

        // When - trial expires (not active)
        let completeExpectation = expectation(description: "Flow completed")
        mockWideEvent.onComplete = { _, _ in completeExpectation.fulfill() }

        let expiredSubscription = makeSubscription(status: .expired, hasTrialOffer: false)
        postSubscriptionChange(expiredSubscription)
        wait(for: [completeExpectation], timeout: 1.0)

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        XCTAssertEqual(mockWideEvent.completions.first?.1, .failure)
    }

    func testWhenNoExistingFlow_ItDoesNotCompleteTheFlow() {
        // Given - no flow started

        // When - subscription changes to paid (but no flow was ever started)
        let completeExpectation = expectation(description: "Flow should not complete")
        completeExpectation.isInverted = true
        mockWideEvent.onComplete = { _, _ in completeExpectation.fulfill() }

        let paidSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: false)
        postSubscriptionChange(paidSubscription)
        wait(for: [completeExpectation], timeout: 0.2)

        // Then - no flow should be completed
        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    // MARK: - VPN/PIR Activation Tests

    func testWhenVPNActivated_ItUpdatesTheFlow() {
        // Given - start a trial flow first
        let trialSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let startExpectation = expectation(description: "Flow started")
        mockWideEvent.onStart = { _ in startExpectation.fulfill() }

        postSubscriptionChange(trialSubscription)
        wait(for: [startExpectation], timeout: 1.0)

        // When
        sut.markVPNActivated()

        // Then
        XCTAssertEqual(mockWideEvent.updates.count, 1)
        let updatedData = mockWideEvent.updates.first as? FreeTrialConversionWideEventData
        XCTAssertNotNil(updatedData)
    }

    func testWhenPIRActivated_ItUpdatesTheFlow() {
        // Given - start a trial flow first
        let trialSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let startExpectation = expectation(description: "Flow started")
        mockWideEvent.onStart = { _ in startExpectation.fulfill() }

        postSubscriptionChange(trialSubscription)
        wait(for: [startExpectation], timeout: 1.0)

        // When
        sut.markPIRActivated()

        // Then
        XCTAssertEqual(mockWideEvent.updates.count, 1)
        let updatedData = mockWideEvent.updates.first as? FreeTrialConversionWideEventData
        XCTAssertNotNil(updatedData)
    }

    func testWhenVPNActivatedWithNoExistingFlow_ItDoesNotUpdateTheFlow() {
        // Given - no flow started

        // When
        sut.markVPNActivated()

        // Then
        XCTAssertEqual(mockWideEvent.updates.count, 0)
    }

    func testWhenPIRActivatedWithNoExistingFlow_ItDoesNotUpdateTheFlow() {
        // Given - no flow started

        // When
        sut.markPIRActivated()

        // Then
        XCTAssertEqual(mockWideEvent.updates.count, 0)
    }

    // MARK: - Feature Flag Tests

    func testWhenFeatureFlagDisabled_ItDoesNotStartFlow() {
        // Given
        let disabledMockWideEvent = WideEventMock()
        let disabledNotificationCenter = NotificationCenter()
        let disabledSut = DefaultFreeTrialConversionWideEventService(
            wideEvent: disabledMockWideEvent,
            notificationCenter: disabledNotificationCenter,
            isFeatureEnabled: { false }
        )
        disabledSut.startObservingSubscriptionChanges()

        let subscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)

        // Set up inverted expectation - flow should NOT start
        let startExpectation = expectation(description: "Flow should not start")
        startExpectation.isInverted = true
        disabledMockWideEvent.onStart = { _ in startExpectation.fulfill() }

        // When
        disabledNotificationCenter.post(
            name: .subscriptionDidChange,
            object: nil,
            userInfo: [UserDefaultsCacheKey.subscription: subscription]
        )

        // Then
        wait(for: [startExpectation], timeout: 0.2)
        XCTAssertEqual(disabledMockWideEvent.started.count, 0)
    }

    // MARK: - Helpers

    private func makeSubscription(
        status: DuckDuckGoSubscription.Status,
        hasTrialOffer: Bool
    ) -> DuckDuckGoSubscription {
        let activeOffers: [DuckDuckGoSubscription.Offer] = hasTrialOffer
            ? [DuckDuckGoSubscription.Offer(type: .trial)]
            : []
        return DuckDuckGoSubscription.make(withStatus: status, activeOffers: activeOffers)
    }

    private func postSubscriptionChange(_ subscription: DuckDuckGoSubscription) {
        notificationCenter.post(
            name: .subscriptionDidChange,
            object: nil,
            userInfo: [UserDefaultsCacheKey.subscription: subscription]
        )
    }
}

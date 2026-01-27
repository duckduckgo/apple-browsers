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
@testable import Subscription

final class FreeTrialConversionWideEventServiceTests: XCTestCase {

    private var sut: DefaultFreeTrialConversionWideEventService!
    private var mockWideEvent: MockWideEventManaging!
    private var notificationCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        mockWideEvent = MockWideEventManaging()
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
        mockWideEvent.onStartFlow = { expectation.fulfill() }

        // When
        postSubscriptionChange(subscription)

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockWideEvent.startedFlows.count, 1)
        let startedData = mockWideEvent.startedFlows.first as? FreeTrialConversionWideEventData
        XCTAssertNotNil(startedData)
        XCTAssertEqual(startedData?.freeTrialPlan, subscription.productId)
    }

    func testWhenUserIsAlreadyInFreeTrialWithExistingFlow_ItDoesNotStartANewFlow() {
        // Given
        let subscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let firstFlowExpectation = expectation(description: "First flow started")
        mockWideEvent.onStartFlow = { firstFlowExpectation.fulfill() }

        // Start first flow
        postSubscriptionChange(subscription)
        wait(for: [firstFlowExpectation], timeout: 1.0)
        XCTAssertEqual(mockWideEvent.startedFlows.count, 1)

        // When - another subscription change while still in trial
        // The second notification should not trigger startFlow, so we wait briefly
        let secondFlowExpectation = expectation(description: "Second flow should not start")
        secondFlowExpectation.isInverted = true
        mockWideEvent.onStartFlow = { secondFlowExpectation.fulfill() }

        postSubscriptionChange(subscription)
        wait(for: [secondFlowExpectation], timeout: 0.2)

        // Then - should still be only one flow
        XCTAssertEqual(mockWideEvent.startedFlows.count, 1)
    }

    // MARK: - Complete Flow Tests

    func testWhenUserConvertsToPaid_ItCompletesTheFlowWithSuccess() {
        // Given - start a trial flow first
        let trialSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let startExpectation = expectation(description: "Flow started")
        mockWideEvent.onStartFlow = { startExpectation.fulfill() }

        postSubscriptionChange(trialSubscription)
        wait(for: [startExpectation], timeout: 1.0)
        XCTAssertEqual(mockWideEvent.startedFlows.count, 1)

        // When - user converts to paid (active but no trial offer)
        let completeExpectation = expectation(description: "Flow completed")
        mockWideEvent.onCompleteFlow = { completeExpectation.fulfill() }

        let paidSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: false)
        postSubscriptionChange(paidSubscription)
        wait(for: [completeExpectation], timeout: 1.0)

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        XCTAssertEqual(mockWideEvent.completions.first?.status, .success)
    }

    func testWhenTrialExpires_ItCompletesTheFlowWithFailure() {
        // Given - start a trial flow first
        let trialSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let startExpectation = expectation(description: "Flow started")
        mockWideEvent.onStartFlow = { startExpectation.fulfill() }

        postSubscriptionChange(trialSubscription)
        wait(for: [startExpectation], timeout: 1.0)
        XCTAssertEqual(mockWideEvent.startedFlows.count, 1)

        // When - trial expires (not active)
        let completeExpectation = expectation(description: "Flow completed")
        mockWideEvent.onCompleteFlow = { completeExpectation.fulfill() }

        let expiredSubscription = makeSubscription(status: .expired, hasTrialOffer: false)
        postSubscriptionChange(expiredSubscription)
        wait(for: [completeExpectation], timeout: 1.0)

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        XCTAssertEqual(mockWideEvent.completions.first?.status, .failure)
    }

    func testWhenNoExistingFlow_ItDoesNotCompleteTheFlow() {
        // Given - no flow started

        // When - subscription changes to paid (but no flow was ever started)
        let completeExpectation = expectation(description: "Flow should not complete")
        completeExpectation.isInverted = true
        mockWideEvent.onCompleteFlow = { completeExpectation.fulfill() }

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
        mockWideEvent.onStartFlow = { startExpectation.fulfill() }

        postSubscriptionChange(trialSubscription)
        wait(for: [startExpectation], timeout: 1.0)

        // When
        sut.markVPNActivated()

        // Then
        XCTAssertEqual(mockWideEvent.updatedFlows.count, 1)
        let updatedData = mockWideEvent.updatedFlows.first as? FreeTrialConversionWideEventData
        XCTAssertNotNil(updatedData)
    }

    func testWhenPIRActivated_ItUpdatesTheFlow() {
        // Given - start a trial flow first
        let trialSubscription = makeSubscription(status: .autoRenewable, hasTrialOffer: true)
        let startExpectation = expectation(description: "Flow started")
        mockWideEvent.onStartFlow = { startExpectation.fulfill() }

        postSubscriptionChange(trialSubscription)
        wait(for: [startExpectation], timeout: 1.0)

        // When
        sut.markPIRActivated()

        // Then
        XCTAssertEqual(mockWideEvent.updatedFlows.count, 1)
        let updatedData = mockWideEvent.updatedFlows.first as? FreeTrialConversionWideEventData
        XCTAssertNotNil(updatedData)
    }

    func testWhenVPNActivatedWithNoExistingFlow_ItDoesNotUpdateTheFlow() {
        // Given - no flow started

        // When
        sut.markVPNActivated()

        // Then
        XCTAssertEqual(mockWideEvent.updatedFlows.count, 0)
    }

    func testWhenPIRActivatedWithNoExistingFlow_ItDoesNotUpdateTheFlow() {
        // Given - no flow started

        // When
        sut.markPIRActivated()

        // Then
        XCTAssertEqual(mockWideEvent.updatedFlows.count, 0)
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

// MARK: - Mock WideEventManaging

/// A mock that properly tracks flow state for testing
private final class MockWideEventManaging: WideEventManaging {

    var startedFlows: [WideEventData] = []
    var updatedFlows: [WideEventData] = []
    var completions: [(data: WideEventData, status: WideEventStatus)] = []
    var discardedFlows: [WideEventData] = []

    var onStartFlow: (() -> Void)?
    var onCompleteFlow: (() -> Void)?

    func startFlow<T: WideEventData>(_ data: T) {
        startedFlows.append(data)
        onStartFlow?()
    }

    func updateFlow<T: WideEventData>(_ data: T) {
        updatedFlows.append(data)
    }

    func updateFlow<T: WideEventData>(globalID: String, update: (inout T) -> Void) {
        // Not needed for these tests
    }

    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus, onComplete: @escaping PixelKit.CompletionBlock) {
        completions.append((data: data, status: status))
        // Remove from started flows to simulate completion
        startedFlows.removeAll { ($0 as? T)?.globalData.id == data.globalData.id }
        onComplete(true, nil)
        onCompleteFlow?()
    }

    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus) async throws -> Bool {
        completions.append((data: data, status: status))
        // Remove from started flows to simulate completion
        startedFlows.removeAll { ($0 as? T)?.globalData.id == data.globalData.id }
        onCompleteFlow?()
        return true
    }

    func discardFlow<T: WideEventData>(_ data: T) {
        discardedFlows.append(data)
        startedFlows.removeAll { ($0 as? T)?.globalData.id == data.globalData.id }
    }

    func getFlowData<T: WideEventData>(_ type: T.Type, globalID: String) -> T? {
        return startedFlows.first { ($0 as? T)?.globalData.id == globalID } as? T
    }

    func getAllFlowData<T: WideEventData>(_ type: T.Type) -> [T] {
        return startedFlows.compactMap { $0 as? T }
    }
}

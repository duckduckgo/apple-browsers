//
//  WideEventServiceTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Foundation
import XCTest
import PixelKitTestingUtilities
import SubscriptionTestingUtilities
import Common
import BrowserServicesKit
import PixelKit

@testable import DuckDuckGo_Privacy_Browser
@testable import Subscription

final class WideEventServiceTests: XCTestCase {

    private var sut: WideEventService!
    private var mockWideEvent: WideEventMock!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockSubscriptionBridge: SubscriptionAuthV1toV2BridgeMock!

    override func setUp() {
        super.setUp()
        mockWideEvent = WideEventMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockSubscriptionBridge = SubscriptionAuthV1toV2BridgeMock()
        sut = WideEventService(
            wideEvent: mockWideEvent,
            featureFlagger: mockFeatureFlagger,
            subscriptionBridge: mockSubscriptionBridge
        )
    }

    override func tearDown() {
        sut = nil
        mockWideEvent = nil
        mockFeatureFlagger = nil
        mockSubscriptionBridge = nil
        super.tearDown()
    }

    // MARK: - sendPendingEvents - Feature Flag Gating

    func test_sendPendingEvents_bothFlagsDisabled_returnsEarlyWithoutProcessing() async {
        mockFeatureFlagger.enabledFeatureFlags = []

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    func test_sendPendingEvents_onlyPurchasePixelFlagEnabled_processesPurchasePixelsOnly() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        let purchaseData = makeAbandonedPurchaseData()
        mockWideEvent.started.append(purchaseData)
        let restoreData = makeAbandonedRestoreData()
        mockWideEvent.started.append(restoreData)

        await sut.sendPendingEvents()

        let completedPurchaseData = mockWideEvent.completions.compactMap { $0.0 as? SubscriptionPurchaseWideEventData }
        let completedRestoreData = mockWideEvent.completions.compactMap { $0.0 as? SubscriptionRestoreWideEventData }
        XCTAssertEqual(completedPurchaseData.count, 1)
        XCTAssertEqual(completedRestoreData.count, 0)
    }

    func test_sendPendingEvents_onlyRestorePixelFlagEnabled_processesRestorePixelsOnly() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionRestoreWidePixelMeasurement]
        let purchaseData = makeAbandonedPurchaseData()
        mockWideEvent.started.append(purchaseData)
        let restoreData = makeAbandonedRestoreData()
        mockWideEvent.started.append(restoreData)

        await sut.sendPendingEvents()

        let completedPurchaseData = mockWideEvent.completions.compactMap { $0.0 as? SubscriptionPurchaseWideEventData }
        let completedRestoreData = mockWideEvent.completions.compactMap { $0.0 as? SubscriptionRestoreWideEventData }
        XCTAssertEqual(completedPurchaseData.count, 0)
        XCTAssertEqual(completedRestoreData.count, 1)
    }

    func test_sendPendingEvents_bothFlagsEnabled_processesBothPixelTypes() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement, .subscriptionRestoreWidePixelMeasurement]
        let purchaseData = makeAbandonedPurchaseData()
        mockWideEvent.started.append(purchaseData)
        let restoreData = makeAbandonedRestoreData()
        mockWideEvent.started.append(restoreData)

        await sut.sendPendingEvents()

        let completedPurchaseData = mockWideEvent.completions.compactMap { $0.0 as? SubscriptionPurchaseWideEventData }
        let completedRestoreData = mockWideEvent.completions.compactMap { $0.0 as? SubscriptionRestoreWideEventData }
        XCTAssertEqual(completedPurchaseData.count, 1)
        XCTAssertEqual(completedRestoreData.count, 1)
    }

    // MARK: - processSubscriptionPurchasePixels - Happy Path

    func test_processSubscriptionPurchasePixels_noPendingEvents_completesWithoutErrors() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    func test_processSubscriptionPurchasePixels_inProgressWithEntitlements_completesWithSuccessAndDelayedActivationReason() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        let data = makeInProgressPurchaseDataWithoutEnd()
        mockWideEvent.started.append(data)
        mockSubscriptionBridge.subscriptionFeatures = [.networkProtection]

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (completedData, status) = mockWideEvent.completions[0]
        XCTAssertTrue(completedData is SubscriptionPurchaseWideEventData)
        if case .success(let reason) = status {
            XCTAssertEqual(reason, "missing_entitlements_delayed_activation")
        } else {
            XCTFail("Expected success status")
        }
    }

    func test_processSubscriptionPurchasePixels_inProgressWithoutEntitlementsWithinTimeout_leavesPending() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        let data = makeInProgressPurchaseDataWithoutEnd()
        mockWideEvent.started.append(data)
        mockSubscriptionBridge.subscriptionFeatures = []

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    // MARK: - processSubscriptionPurchasePixels - Error Cases

    func test_processSubscriptionPurchasePixels_inProgressWithoutEntitlementsPastTimeout_completesWithUnknownAndMissingEntitlementsReason() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        let data = makeInProgressPurchaseDataWithoutEnd(startDate: Date().addingTimeInterval(-TimeInterval.hours(5)))
        mockWideEvent.started.append(data)
        mockSubscriptionBridge.subscriptionFeatures = []

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (_, status) = mockWideEvent.completions[0]
        if case .unknown(let reason) = status {
            XCTAssertEqual(reason, "missing_entitlements")
        } else {
            XCTFail("Expected unknown status")
        }
    }

    func test_processSubscriptionPurchasePixels_abandonedPixelNoActivationInterval_completesWithUnknownAndPartialDataReason() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        let data = makeAbandonedPurchaseData()
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (_, status) = mockWideEvent.completions[0]
        if case .unknown(let reason) = status {
            XCTAssertEqual(reason, "partial_data")
        } else {
            XCTFail("Expected unknown status")
        }
    }

    func test_processSubscriptionPurchasePixels_abandonedPixelHasStartButNoActivationDuration_completesWithUnknownAndPartialDataReason() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        let data = SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: "test.subscription",
            freeTrialEligible: true,
            createAccountDuration: WideEvent.MeasuredInterval(start: Date(), end: Date()),
            contextData: WideEventContextData()
        )
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (_, status) = mockWideEvent.completions[0]
        if case .unknown(let reason) = status {
            XCTAssertEqual(reason, "partial_data")
        } else {
            XCTFail("Expected unknown status")
        }
    }

    // MARK: - processSubscriptionRestorePixels - Happy Path

    func test_processSubscriptionRestorePixels_noPendingEvents_completesWithoutErrors() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionRestoreWidePixelMeasurement]

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    func test_processSubscriptionRestorePixels_appleRestoreInProgressWithinTimeout_leavesPending() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionRestoreWidePixelMeasurement]
        let data = makeInProgressAppleRestoreData()
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    func test_processSubscriptionRestorePixels_emailRestoreInProgressWithinTimeout_leavesPending() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionRestoreWidePixelMeasurement]
        let data = makeInProgressEmailRestoreData()
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    // MARK: - processSubscriptionRestorePixels - Timeout Cases

    func test_processSubscriptionRestorePixels_appleRestoreInProgressPastTimeout_completesWithUnknownAndTimeoutReason() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionRestoreWidePixelMeasurement]
        let data = makeInProgressAppleRestoreData(startDate: Date().addingTimeInterval(-TimeInterval.minutes(20)))
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (_, status) = mockWideEvent.completions[0]
        if case .unknown(let reason) = status {
            XCTAssertEqual(reason, "timeout")
        } else {
            XCTFail("Expected unknown status")
        }
    }

    func test_processSubscriptionRestorePixels_emailRestoreInProgressPastTimeout_completesWithUnknownAndTimeoutReason() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionRestoreWidePixelMeasurement]
        let data = makeInProgressEmailRestoreData(startDate: Date().addingTimeInterval(-TimeInterval.minutes(20)))
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (_, status) = mockWideEvent.completions[0]
        if case .unknown(let reason) = status {
            XCTAssertEqual(reason, "timeout")
        } else {
            XCTFail("Expected unknown status")
        }
    }

    func test_processSubscriptionRestorePixels_abandonedPixel_completesWithUnknownAndPartialDataReason() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionRestoreWidePixelMeasurement]
        let data = makeAbandonedRestoreData()
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (_, status) = mockWideEvent.completions[0]
        if case .unknown(let reason) = status {
            XCTAssertEqual(reason, "partial_data")
        } else {
            XCTFail("Expected unknown status")
        }
    }

    // MARK: - checkForCurrentEntitlements - Helper Method

    func test_checkForCurrentEntitlements_subscriptionBridgeReturnsNonEmptyEntitlements_returnsTrue() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        mockSubscriptionBridge.subscriptionFeatures = [.networkProtection, .dataBrokerProtection]
        let data = makeInProgressPurchaseDataWithoutEnd()
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let (_, status) = mockWideEvent.completions[0]
        if case .success = status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected success status when entitlements are present")
        }
    }

    func test_checkForCurrentEntitlements_subscriptionBridgeReturnsEmptyArray_returnsFalse() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        mockSubscriptionBridge.subscriptionFeatures = []
        let data = makeInProgressPurchaseDataWithoutEnd()
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    func test_checkForCurrentEntitlements_subscriptionBridgeThrowsError_returnsFalse() async {
        mockFeatureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        mockSubscriptionBridge.accessTokenResult = .failure(NSError(domain: "test", code: 1))
        let data = makeInProgressPurchaseDataWithoutEnd()
        mockWideEvent.started.append(data)

        await sut.sendPendingEvents()

        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    // MARK: - Helpers

    private func makeAbandonedPurchaseData() -> SubscriptionPurchaseWideEventData {
        return SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: "subscription",
            freeTrialEligible: true,
            contextData: WideEventContextData()
        )
    }

    private func makeInProgressPurchaseDataWithoutEnd(startDate: Date = Date()) -> SubscriptionPurchaseWideEventData {
        return SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: "subscription",
            freeTrialEligible: true,
            activateAccountDuration: WideEvent.MeasuredInterval(start: startDate, end: nil),
            contextData: WideEventContextData()
        )
    }

    private func makeAbandonedRestoreData() -> SubscriptionRestoreWideEventData {
        return SubscriptionRestoreWideEventData(
            restorePlatform: .appleAccount,
            contextData: WideEventContextData()
        )
    }

    private func makeInProgressAppleRestoreData(startDate: Date = Date()) -> SubscriptionRestoreWideEventData {
        return SubscriptionRestoreWideEventData(
            restorePlatform: .appleAccount,
            appleAccountRestoreDuration: WideEvent.MeasuredInterval(start: startDate, end: nil),
            contextData: WideEventContextData()
        )
    }

    private func makeInProgressEmailRestoreData(startDate: Date = Date()) -> SubscriptionRestoreWideEventData {
        return SubscriptionRestoreWideEventData(
            restorePlatform: .emailAddress,
            emailAddressRestoreDuration: WideEvent.MeasuredInterval(start: startDate, end: nil),
            contextData: WideEventContextData()
        )
    }
}

//
//  WideEventServiceTests.swift
//  DuckDuckGo
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

import XCTest
import Common
import PixelKit
import Subscription
import PixelKitTestingUtilities
import SubscriptionTestingUtilities
import BrowserServicesKit
@testable import DuckDuckGo

final class WideEventServiceTests: XCTestCase {

    private var wideEventMock: WideEventMock!
    private var featureFlagger: MockFeatureFlagger!
    private var subscriptionManager: SubscriptionManagerMock!
    private var service: WideEventService!

    override func setUp() {
        super.setUp()
        wideEventMock = WideEventMock()
        featureFlagger = MockFeatureFlagger()
        subscriptionManager = SubscriptionManagerMock()
        service = WideEventService(wideEvent: wideEventMock, featureFlagger: featureFlagger, subscriptionManager: subscriptionManager)
    }
    
    override func tearDown() {
        service = nil
        subscriptionManager = nil
        featureFlagger = nil
        wideEventMock = nil
        super.tearDown()
    }
    
    func testRunCleanup_withoutPendingData_completesImmediately() {
        let expectation = expectation(description: "Completion called")
        service.sendAbandonedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(wideEventMock.completions.isEmpty)
    }
    
    func testPerformCleanup_withActivateAccountDuration_recentStart_doesNotSendPixel() {
        let recentStart = Date().addingTimeInterval(-60)
        let interval = WideEvent.MeasuredInterval(start: recentStart, end: nil)
        let data = createMockWideEventData(activateAccountDuration: interval)
        wideEventMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendAbandonedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(wideEventMock.completions.isEmpty)
    }
    
    func testPerformCleanup_withActivateAccountDuration_oldStart_noEntitlements_sendsUnknownPixel() {
        subscriptionManager.resultFeatures = []

        let oldStart = Date().addingTimeInterval(-5 * 60 * 60)
        let interval = WideEvent.MeasuredInterval(start: oldStart, end: nil)
        let data = createMockWideEventData(activateAccountDuration: interval)
        wideEventMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendDelayedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(wideEventMock.completions.count, 1, "Expected one completion but got \(wideEventMock.completions.count)")
        let completion = wideEventMock.completions.first

        if case .unknown(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWideEventData.StatusReason.missingEntitlements.rawValue)
        } else {
            XCTFail("Expected unknown status with partial data reason")
        }
    }
    
    func testPerformCleanup_withActivateAccountDuration_hasEntitlements_sendsSuccessPixel() {
        subscriptionManager.resultFeatures = [.networkProtection]

        let oldStart = Date().addingTimeInterval(-3 * 60 * 60)
        let interval = WideEvent.MeasuredInterval(start: oldStart, end: nil)
        let data = createMockWideEventData(activateAccountDuration: interval)
        wideEventMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendDelayedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(wideEventMock.completions.count, 1)
        let completion = wideEventMock.completions.first

        if case .success(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWideEventData.StatusReason.missingEntitlementsDelayedActivation.rawValue)
        } else {
            XCTFail("Expected success status with delayed activation reason")
        }
    }
    
    func testPerformCleanup_withActivateAccountDuration_userNotAuthenticated_sendsUnknownPixel() {
        let oldStart = Date().addingTimeInterval(-5 * 60 * 60)
        let interval = WideEvent.MeasuredInterval(start: oldStart, end: nil)
        let data = createMockWideEventData(activateAccountDuration: interval)
        wideEventMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendDelayedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(wideEventMock.completions.count, 1)
        let completion = wideEventMock.completions.first

        if case .unknown(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWideEventData.StatusReason.missingEntitlements.rawValue)
        } else {
            XCTFail("Expected unknown status with missing entitlements reason")
        }
    }
    
    func testPerformCleanup_withActivateAccountDuration_entitlementsError_sendsUnknownPixel() {
        subscriptionManager.resultFeatures = []

        let oldStart = Date().addingTimeInterval(-5 * 60 * 60)
        let interval = WideEvent.MeasuredInterval(start: oldStart, end: nil)
        let data = createMockWideEventData(activateAccountDuration: interval)
        wideEventMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendDelayedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(wideEventMock.completions.count, 1)
        let completion = wideEventMock.completions.first

        if case .unknown(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWideEventData.StatusReason.missingEntitlements.rawValue)
        } else {
            XCTFail("Expected unknown status with missing entitlements reason")
        }
    }
    
    func testPerformCleanup_withoutActivateAccountDuration_sendsPartialDataPixel() {
        let data = createMockWideEventData()
        wideEventMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendAbandonedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(wideEventMock.completions.count, 1)
        let completion = wideEventMock.completions.first

        if case .unknown(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWideEventData.StatusReason.partialData.rawValue)
        } else {
            XCTFail("Expected unknown status with partial data reason")
        }
    }
    
    func testPerformCleanup_withMultipleData_processesAll() {
        subscriptionManager.resultFeatures = [.networkProtection]
        
        let start = Date().addingTimeInterval(-1 * 60 * 60)
        let interval = WideEvent.MeasuredInterval(start: start, end: nil)
        let dataWithActivation = createMockWideEventData(activateAccountDuration: interval)
        let dataWithoutActivation = createMockWideEventData()

        wideEventMock.started = [dataWithActivation, dataWithoutActivation]

        let abandonedPixelExpectation = expectation(description: "sendAbandonedPixels completion called")
        service.sendAbandonedPixels { abandonedPixelExpectation.fulfill() }
        wait(for: [abandonedPixelExpectation], timeout: 5.0)

        let delayedPixelExpectation = expectation(description: "sendDelayedPixels completion called")
        service.sendDelayedPixels { delayedPixelExpectation.fulfill() }
        wait(for: [delayedPixelExpectation], timeout: 5.0)
        
        XCTAssertEqual(wideEventMock.completions.count, 2)

        for completion in wideEventMock.completions {
            if case .success(let reason) = completion.1 {
                XCTAssertEqual(reason, SubscriptionPurchaseWideEventData.StatusReason.missingEntitlementsDelayedActivation.rawValue)
            } else if case .unknown(let reason) = completion.1 {
                XCTAssertEqual(reason, SubscriptionPurchaseWideEventData.StatusReason.partialData.rawValue)
            } else {
                XCTFail("Unhandled status")
            }
        }
    }
    
    private func createMockWideEventData(activateAccountDuration: WideEvent.MeasuredInterval? = nil) -> SubscriptionPurchaseWideEventData {
        return SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: "test",
            freeTrialEligible: false,
            activateAccountDuration: activateAccountDuration,
            contextData: WideEventContextData(),
            appData: WideEventAppData(),
            globalData: WideEventGlobalData()
        )
    }

}

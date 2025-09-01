//
//  WidePixelServiceTests.swift
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

final class WidePixelServiceTests: XCTestCase {
    
    private var widePixelMock: WidePixelMock!
    private var featureFlagger: MockFeatureFlagger!
    private var subscriptionBridge: SubscriptionAuthV1toV2BridgeMock!
    private var service: WidePixelService!
    
    override func setUp() {
        super.setUp()
        widePixelMock = WidePixelMock()
        featureFlagger = MockFeatureFlagger()
        subscriptionBridge = SubscriptionAuthV1toV2BridgeMock()
        service = WidePixelService(widePixel: widePixelMock, featureFlagger: featureFlagger, subscriptionBridge: subscriptionBridge)
    }
    
    override func tearDown() {
        service = nil
        subscriptionBridge = nil
        featureFlagger = nil
        widePixelMock = nil
        super.tearDown()
    }
    
    func testRunCleanup_whenFeatureFlagDisabled_completesImmediately() {
        featureFlagger.enabledFeatureFlags = []
        
        let expectation = expectation(description: "Completion called")
        service.sendAbandonedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(widePixelMock.completions.isEmpty)
    }
    
    func testRunCleanup_whenFeatureFlagEnabled_processesData() {
        featureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        
        let expectation = expectation(description: "Completion called")
        service.sendAbandonedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testPerformCleanup_withActivateAccountDuration_recentStart_doesNotSendPixel() {
        featureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        
        let recentStart = Date().addingTimeInterval(-60)
        let interval = WidePixel.MeasuredInterval(start: recentStart, end: nil)
        let data = createMockWidePixelData(activateAccountDuration: interval)
        widePixelMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendAbandonedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(widePixelMock.completions.isEmpty)
    }
    
    func testPerformCleanup_withActivateAccountDuration_oldStart_noEntitlements_sendsUnknownPixel() {
        featureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        subscriptionBridge.subscriptionFeatures = []
        
        let oldStart = Date().addingTimeInterval(-5 * 60 * 60)
        let interval = WidePixel.MeasuredInterval(start: oldStart, end: nil)
        let data = createMockWidePixelData(activateAccountDuration: interval)
        widePixelMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendDelayedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(widePixelMock.completions.count, 1, "Expected one completion but got \(widePixelMock.completions.count)")
        let completion = widePixelMock.completions.first

        if case .unknown(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWidePixelData.StatusReason.missingEntitlements.rawValue)
        } else {
            XCTFail("Expected unknown status with partial data reason")
        }
    }
    
    func testPerformCleanup_withActivateAccountDuration_hasEntitlements_sendsSuccessPixel() {
        featureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        subscriptionBridge.subscriptionFeatures = [.networkProtection]
        
        let oldStart = Date().addingTimeInterval(-3 * 60 * 60)
        let interval = WidePixel.MeasuredInterval(start: oldStart, end: nil)
        let data = createMockWidePixelData(activateAccountDuration: interval)
        widePixelMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendDelayedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(widePixelMock.completions.count, 1)
        let completion = widePixelMock.completions.first

        if case .success(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWidePixelData.StatusReason.missingEntitlementsDelayedActivation.rawValue)
        } else {
            XCTFail("Expected success status with delayed activation reason")
        }
    }
    
    func testPerformCleanup_withActivateAccountDuration_userNotAuthenticated_sendsUnknownPixel() {
        featureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        
        let oldStart = Date().addingTimeInterval(-5 * 60 * 60)
        let interval = WidePixel.MeasuredInterval(start: oldStart, end: nil)
        let data = createMockWidePixelData(activateAccountDuration: interval)
        widePixelMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendDelayedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(widePixelMock.completions.count, 1)
        let completion = widePixelMock.completions.first

        if case .unknown(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWidePixelData.StatusReason.missingEntitlements.rawValue)
        } else {
            XCTFail("Expected unknown status with missing entitlements reason")
        }
    }
    
    func testPerformCleanup_withActivateAccountDuration_entitlementsError_sendsUnknownPixel() {
        featureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        subscriptionBridge.subscriptionFeatures = []
        
        let oldStart = Date().addingTimeInterval(-5 * 60 * 60)
        let interval = WidePixel.MeasuredInterval(start: oldStart, end: nil)
        let data = createMockWidePixelData(activateAccountDuration: interval)
        widePixelMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendDelayedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(widePixelMock.completions.count, 1)
        let completion = widePixelMock.completions.first

        if case .unknown(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWidePixelData.StatusReason.missingEntitlements.rawValue)
        } else {
            XCTFail("Expected unknown status with missing entitlements reason")
        }
    }
    
    func testPerformCleanup_withoutActivateAccountDuration_sendsPartialDataPixel() {
        featureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        
        let data = createMockWidePixelData()
        widePixelMock.started = [data]

        let expectation = expectation(description: "Completion called")
        service.sendAbandonedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(widePixelMock.completions.count, 1)
        let completion = widePixelMock.completions.first

        if case .unknown(let reason) = completion?.1 {
            XCTAssertEqual(reason, SubscriptionPurchaseWidePixelData.StatusReason.partialData.rawValue)
        } else {
            XCTFail("Expected unknown status with partial data reason")
        }
    }
    
    func testPerformCleanup_withMultipleData_processesAll() {
        featureFlagger.enabledFeatureFlags = [.subscriptionPurchaseWidePixelMeasurement]
        subscriptionBridge.subscriptionFeatures = [.networkProtection]
        
        let start = Date().addingTimeInterval(-1 * 60 * 60)
        let interval = WidePixel.MeasuredInterval(start: start, end: nil)
        let dataWithActivation = createMockWidePixelData(activateAccountDuration: interval)
        let dataWithoutActivation = createMockWidePixelData()
        
        widePixelMock.started  = [dataWithActivation, dataWithoutActivation]

        let expectation = expectation(description: "Completion called")
        expectation.expectedFulfillmentCount = 2

        service.sendAbandonedPixels {
            expectation.fulfill()
        }

        service.sendDelayedPixels {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(widePixelMock.completions.count, 2)

        for completion in widePixelMock.completions {
            if case .success(let reason) = completion.1 {
                XCTAssertEqual(reason, SubscriptionPurchaseWidePixelData.StatusReason.missingEntitlementsDelayedActivation.rawValue)
            } else if case .unknown(let reason) = completion.1 {
                XCTAssertEqual(reason, SubscriptionPurchaseWidePixelData.StatusReason.partialData.rawValue)
            } else {
                XCTFail("Unhandled status")
            }
        }
    }
    
    private func createMockWidePixelData(activateAccountDuration: WidePixel.MeasuredInterval? = nil) -> SubscriptionPurchaseWidePixelData {
        return SubscriptionPurchaseWidePixelData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: "test",
            freeTrialEligible: false,
            activateAccountDuration: activateAccountDuration,
            contextData: WidePixelContextData(),
            appData: WidePixelAppData(),
            globalData: WidePixelGlobalData()
        )
    }

}

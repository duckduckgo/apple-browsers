//
//  FreeTrialConversionWideEventDataTests.swift
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

final class FreeTrialConversionWideEventDataTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialization_SetsDefaultValues() {
        // When
        let data = FreeTrialConversionWideEventData()

        // Then
        XCTAssertFalse(data.vpnActivatedD1)
        XCTAssertFalse(data.vpnActivatedD2ToD7)
        XCTAssertFalse(data.pirActivatedD1)
        XCTAssertFalse(data.pirActivatedD2ToD7)
        XCTAssertFalse(data.duckAIActivatedD1)
        XCTAssertFalse(data.duckAIActivatedD2ToD7)
    }

    // MARK: - VPN Activation Tests

    func testMarkVPNActivated_OnDay1_SetsD1Flag() {
        // Given - trial started now (day 1)
        let data = FreeTrialConversionWideEventData(trialStartDate: Date())

        // When
        data.markVPNActivated()

        // Then
        XCTAssertTrue(data.vpnActivatedD1)
        XCTAssertFalse(data.vpnActivatedD2ToD7)
    }

    func testMarkVPNActivated_OnDay2OrLater_SetsD2ToD7Flag() {
        // Given - trial started 2 days ago
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let data = FreeTrialConversionWideEventData(trialStartDate: twoDaysAgo)

        // When
        data.markVPNActivated()

        // Then
        XCTAssertFalse(data.vpnActivatedD1)
        XCTAssertTrue(data.vpnActivatedD2ToD7)
    }

    func testMarkVPNActivated_WhenAlreadyActivatedD1_DoesNotChange() {
        // Given - already activated on D1
        let data = FreeTrialConversionWideEventData()
        data.vpnActivatedD1 = true

        // When - try to activate again (simulating D2+)
        data.markVPNActivated()

        // Then - should not change
        XCTAssertTrue(data.vpnActivatedD1)
        XCTAssertFalse(data.vpnActivatedD2ToD7)
    }

    func testMarkVPNActivated_WhenAlreadyActivatedD2ToD7_DoesNotChange() {
        // Given - already activated on D2-D7
        let data = FreeTrialConversionWideEventData()
        data.vpnActivatedD2ToD7 = true

        // When - try to activate again
        data.markVPNActivated()

        // Then - should not change
        XCTAssertFalse(data.vpnActivatedD1)
        XCTAssertTrue(data.vpnActivatedD2ToD7)
    }

    // MARK: - PIR Activation Tests

    func testMarkPIRActivated_OnDay1_SetsD1Flag() {
        // Given - trial started now (day 1)
        let data = FreeTrialConversionWideEventData(trialStartDate: Date())

        // When
        data.markPIRActivated()

        // Then
        XCTAssertTrue(data.pirActivatedD1)
        XCTAssertFalse(data.pirActivatedD2ToD7)
    }

    func testMarkPIRActivated_OnDay2OrLater_SetsD2ToD7Flag() {
        // Given - trial started 2 days ago
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let data = FreeTrialConversionWideEventData(trialStartDate: twoDaysAgo)

        // When
        data.markPIRActivated()

        // Then
        XCTAssertFalse(data.pirActivatedD1)
        XCTAssertTrue(data.pirActivatedD2ToD7)
    }

    func testMarkPIRActivated_WhenAlreadyActivatedD1_DoesNotChange() {
        // Given - already activated on D1
        let data = FreeTrialConversionWideEventData()
        data.pirActivatedD1 = true

        // When - try to activate again
        data.markPIRActivated()

        // Then - should not change
        XCTAssertTrue(data.pirActivatedD1)
        XCTAssertFalse(data.pirActivatedD2ToD7)
    }

    // MARK: - Duck.ai Activation Tests

    func testMarkDuckAIActivated_OnDay1_SetsD1Flag() {
        // Given - trial started now (day 1)
        let data = FreeTrialConversionWideEventData(trialStartDate: Date())

        // When
        data.markDuckAIActivated()

        // Then
        XCTAssertTrue(data.duckAIActivatedD1)
        XCTAssertFalse(data.duckAIActivatedD2ToD7)
    }

    func testMarkDuckAIActivated_OnDay2OrLater_SetsD2ToD7Flag() {
        // Given - trial started 2 days ago
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let data = FreeTrialConversionWideEventData(trialStartDate: twoDaysAgo)

        // When
        data.markDuckAIActivated()

        // Then
        XCTAssertFalse(data.duckAIActivatedD1)
        XCTAssertTrue(data.duckAIActivatedD2ToD7)
    }

    func testMarkDuckAIActivated_WhenAlreadyActivatedD1_DoesNotChange() {
        // Given - already activated on D1
        let data = FreeTrialConversionWideEventData()
        data.duckAIActivatedD1 = true

        // When - try to activate again
        data.markDuckAIActivated()

        // Then - should not change
        XCTAssertTrue(data.duckAIActivatedD1)
        XCTAssertFalse(data.duckAIActivatedD2ToD7)
    }

    func testMarkDuckAIActivated_WhenAlreadyActivatedD2ToD7_DoesNotChange() {
        // Given - already activated on D2-D7
        let data = FreeTrialConversionWideEventData()
        data.duckAIActivatedD2ToD7 = true

        // When - try to activate again
        data.markDuckAIActivated()

        // Then - should not change
        XCTAssertFalse(data.duckAIActivatedD1)
        XCTAssertTrue(data.duckAIActivatedD2ToD7)
    }

    // MARK: - Should Fire Pixel Tests

    func testShouldFireVPNActivationPixel_WhenNotActivated_ReturnsTrue() {
        // Given
        let data = FreeTrialConversionWideEventData()

        // Then
        XCTAssertTrue(data.shouldFireVPNActivationPixel)
    }

    func testShouldFireVPNActivationPixel_WhenD1Activated_ReturnsFalse() {
        // Given
        let data = FreeTrialConversionWideEventData()
        data.vpnActivatedD1 = true

        // Then
        XCTAssertFalse(data.shouldFireVPNActivationPixel)
    }

    func testShouldFireVPNActivationPixel_WhenD2ToD7Activated_ReturnsFalse() {
        // Given
        let data = FreeTrialConversionWideEventData()
        data.vpnActivatedD2ToD7 = true

        // Then
        XCTAssertFalse(data.shouldFireVPNActivationPixel)
    }

    func testShouldFirePIRActivationPixel_WhenNotActivated_ReturnsTrue() {
        // Given
        let data = FreeTrialConversionWideEventData()

        // Then
        XCTAssertTrue(data.shouldFirePIRActivationPixel)
    }

    func testShouldFirePIRActivationPixel_WhenD1Activated_ReturnsFalse() {
        // Given
        let data = FreeTrialConversionWideEventData()
        data.pirActivatedD1 = true

        // Then
        XCTAssertFalse(data.shouldFirePIRActivationPixel)
    }

    func testShouldFireDuckAIActivationPixel_WhenNotActivated_ReturnsTrue() {
        // Given
        let data = FreeTrialConversionWideEventData()

        // Then
        XCTAssertTrue(data.shouldFireDuckAIActivationPixel)
    }

    func testShouldFireDuckAIActivationPixel_WhenD1Activated_ReturnsFalse() {
        // Given
        let data = FreeTrialConversionWideEventData()
        data.duckAIActivatedD1 = true

        // Then
        XCTAssertFalse(data.shouldFireDuckAIActivationPixel)
    }

    func testShouldFireDuckAIActivationPixel_WhenD2ToD7Activated_ReturnsFalse() {
        // Given
        let data = FreeTrialConversionWideEventData()
        data.duckAIActivatedD2ToD7 = true

        // Then
        XCTAssertFalse(data.shouldFireDuckAIActivationPixel)
    }

    // MARK: - Activation Day Tests

    func testActivationDay_OnDay1_ReturnsD1() {
        // Given - trial started now
        let data = FreeTrialConversionWideEventData(trialStartDate: Date())

        // Then
        XCTAssertEqual(data.activationDay(), .d1)
    }

    func testActivationDay_OnDay2OrLater_ReturnsD2ToD7() {
        // Given - trial started 2 days ago
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let data = FreeTrialConversionWideEventData(trialStartDate: twoDaysAgo)

        // Then
        XCTAssertEqual(data.activationDay(), .d2ToD7)
    }

    // MARK: - Pixel Parameters Tests

    func testPixelParameters_ContainsExpectedKeys() {
        // Given
        let data = FreeTrialConversionWideEventData()
        data.vpnActivatedD1 = true
        data.pirActivatedD2ToD7 = true
        data.duckAIActivatedD1 = true

        // When
        let params = data.pixelParameters()

        // Then
        XCTAssertEqual(params["feature.data.ext.step.vpn_activated_d1"], "true")
        XCTAssertEqual(params["feature.data.ext.step.vpn_activated_d2_to_d7"], "false")
        XCTAssertEqual(params["feature.data.ext.step.pir_activated_d1"], "false")
        XCTAssertEqual(params["feature.data.ext.step.pir_activated_d2_to_d7"], "true")
        XCTAssertEqual(params["feature.data.ext.step.duck_ai_activated_d1"], "true")
        XCTAssertEqual(params["feature.data.ext.step.duck_ai_activated_d2_to_d7"], "false")
    }
}

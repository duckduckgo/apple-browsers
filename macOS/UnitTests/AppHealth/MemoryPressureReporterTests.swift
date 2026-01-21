//
//  MemoryPressureReporterTests.swift
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

import Combine
import PrivacyConfig
import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class MemoryPressureReporterTests: XCTestCase {

    private var sut: MemoryPressureReporter!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockPixelFiring: MockPixelFiring!
    private var notificationCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPixelFiring = MockPixelFiring()
        notificationCenter = NotificationCenter()
    }

    override func tearDown() {
        sut = nil
        mockFeatureFlagger = nil
        mockPixelFiring = nil
        notificationCenter = nil
        super.tearDown()
    }

    // MARK: - Pixel Name Tests

    func testMemoryPressureWarningPixelName() {
        // Given/When
        let pixel = MemoryPressurePixel.memoryPressureWarning

        // Then
        XCTAssertEqual(pixel.name, "m_mac_memory_pressure_warning")
    }

    func testMemoryPressureCriticalPixelName() {
        // Given/When
        let pixel = MemoryPressurePixel.memoryPressureCritical

        // Then
        XCTAssertEqual(pixel.name, "m_mac_memory_pressure_critical")
    }

    func testMemoryPressurePixelParameters() {
        // Given/When
        let warningPixel = MemoryPressurePixel.memoryPressureWarning
        let criticalPixel = MemoryPressurePixel.memoryPressureCritical

        // Then
        XCTAssertNil(warningPixel.parameters)
        XCTAssertNil(criticalPixel.parameters)
        XCTAssertNil(warningPixel.standardParameters)
        XCTAssertNil(criticalPixel.standardParameters)
    }

    // MARK: - Notification + Pixel tests

    func testWhenWarningEventProcessed_ThenPostsWarningNotificationAndFiresWarningPixel() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.memoryPressureReporting]
        sut = MemoryPressureReporter(featureFlagger: mockFeatureFlagger,
                                     pixelFiring: mockPixelFiring,
                                     notificationCenter: notificationCenter)

        let notificationExpectation = expectation(forNotification: .memoryPressureWarning, object: nil, notificationCenter: notificationCenter) { notification in
            return notification.object as AnyObject? === self.sut
        }

        // When
        sut.processMemoryPressureEventForTesting(.warning)

        // Then
        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPixelFiring.firedPixels.count, 1)
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.name, "m_mac_memory_pressure_warning")
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.frequency, .dailyAndStandard)
    }

    func testWhenCriticalEventProcessed_ThenPostsCriticalNotificationAndFiresCriticalPixel() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.memoryPressureReporting]
        sut = MemoryPressureReporter(featureFlagger: mockFeatureFlagger,
                                     pixelFiring: mockPixelFiring,
                                     notificationCenter: notificationCenter)

        let notificationExpectation = expectation(forNotification: .memoryPressureCritical, object: nil, notificationCenter: notificationCenter) { notification in
            return notification.object as AnyObject? === self.sut
        }

        // When
        sut.processMemoryPressureEventForTesting(.critical)

        // Then
        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPixelFiring.firedPixels.count, 1)
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.event.name, "m_mac_memory_pressure_critical")
        XCTAssertEqual(mockPixelFiring.firedPixels.first?.frequency, .dailyAndStandard)
    }

    func testWhenNormalEventProcessed_ThenDoesNotPostNotificationsOrFirePixels() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.memoryPressureReporting]
        sut = MemoryPressureReporter(featureFlagger: mockFeatureFlagger,
                                     pixelFiring: mockPixelFiring,
                                     notificationCenter: notificationCenter)

        let warningNotificationExpectation = expectation(forNotification: .memoryPressureWarning, object: nil, notificationCenter: notificationCenter, handler: nil)
        warningNotificationExpectation.isInverted = true

        let criticalNotificationExpectation = expectation(forNotification: .memoryPressureCritical, object: nil, notificationCenter: notificationCenter, handler: nil)
        criticalNotificationExpectation.isInverted = true

        // When
        sut.processMemoryPressureEventForTesting(.normal)

        // Then
        wait(for: [warningNotificationExpectation, criticalNotificationExpectation], timeout: 0.2)
        XCTAssertTrue(mockPixelFiring.firedPixels.isEmpty)
    }
}

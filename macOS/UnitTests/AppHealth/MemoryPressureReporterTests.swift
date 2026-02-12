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
import PixelKitTestingUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class MemoryPressureReporterTests: XCTestCase {

    private var sut: MemoryPressureReporter!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockPixelFiring: PixelKitMock!
    private var mockMemoryUsageMonitor: MockPressureMemoryMonitor!
    private var notificationCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPixelFiring = PixelKitMock()
        mockMemoryUsageMonitor = MockPressureMemoryMonitor()
        notificationCenter = NotificationCenter()
    }

    override func tearDown() {
        sut = nil
        mockFeatureFlagger = nil
        mockPixelFiring = nil
        mockMemoryUsageMonitor = nil
        notificationCenter = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT() -> MemoryPressureReporter {
        MemoryPressureReporter(
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring,
            memoryUsageMonitor: mockMemoryUsageMonitor,
            windowContext: nil,
            isSyncEnabled: { nil },
            notificationCenter: notificationCenter
        )
    }

    // MARK: - Pixel Name Tests

    func testMemoryPressureCriticalPixelName() {
        // Given
        let context = MemoryReportingContext(
            browserMemoryMB: 1024,
            windows: nil,
            tabs: nil,
            architecture: "ARM",
            syncEnabled: nil
        )

        // When
        let pixel = MemoryPressurePixel.memoryPressureCritical(context: context)

        // Then
        XCTAssertEqual(pixel.name, "m_mac_memory_pressure_critical")
    }

    func testMemoryPressurePixelIncludesContextParameters() {
        // Given
        let context = MemoryReportingContext(
            browserMemoryMB: 2048,
            windows: 4,
            tabs: 21,
            architecture: "ARM",
            syncEnabled: true
        )

        // When
        let pixel = MemoryPressurePixel.memoryPressureCritical(context: context)

        // Then
        let params = pixel.parameters
        XCTAssertNotNil(params)
        XCTAssertEqual(params?["browser_memory_mb"], "2048")
        XCTAssertEqual(params?["windows"], "4")
        XCTAssertEqual(params?["tabs"], "21")
        XCTAssertEqual(params?["architecture"], "ARM")
        XCTAssertEqual(params?["sync_enabled"], "true")
    }

    func testMemoryPressurePixelReturnsUnknownForNilDependencies() {
        // Given
        let context = MemoryReportingContext(
            browserMemoryMB: 512,
            windows: nil,
            tabs: nil,
            architecture: "Intel",
            syncEnabled: nil
        )

        // When
        let pixel = MemoryPressurePixel.memoryPressureCritical(context: context)

        // Then
        let params = pixel.parameters
        XCTAssertEqual(params?["windows"], "unknown")
        XCTAssertEqual(params?["tabs"], "unknown")
        XCTAssertEqual(params?["sync_enabled"], "unknown")
    }

    // MARK: - Notification + Pixel tests

    @MainActor
    func testWhenCriticalEventProcessed_ThenPostsCriticalNotificationAndFiresCriticalPixel() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = [.memoryPressureReporting]
        sut = makeSUT()

        let notificationExpectation = expectation(forNotification: .memoryPressureCritical, object: nil, notificationCenter: notificationCenter) { notification in
            return notification.object as AnyObject? === self.sut
        }

        // When
        sut.processMemoryPressureEventForTesting(.critical)

        // Then
        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.name, "m_mac_memory_pressure_critical")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.frequency, .dailyAndStandard)
    }

    @MainActor
    func testWhenCriticalEventProcessed_ThenPixelIncludesContextParameters() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 5000
        mockFeatureFlagger.enabledFeatureFlags = [.memoryPressureReporting]
        sut = makeSUT()

        // When
        sut.processMemoryPressureEventForTesting(.critical)

        // Then
        let params = mockPixelFiring.actualFireCalls.first?.pixel.parameters
        XCTAssertEqual(params?["browser_memory_mb"], "4096") // 5000MB buckets to 4096
        XCTAssertEqual(params?["windows"], "unknown")
        XCTAssertEqual(params?["tabs"], "unknown")
        XCTAssertNotNil(params?["architecture"])
        XCTAssertEqual(params?["sync_enabled"], "unknown")
    }

    @MainActor
    func testWhenNormalEventProcessed_ThenDoesNotPostNotificationsOrFirePixels() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.memoryPressureReporting]
        sut = makeSUT()

        let criticalNotificationExpectation = expectation(forNotification: .memoryPressureCritical, object: nil, notificationCenter: notificationCenter, handler: nil)
        criticalNotificationExpectation.isInverted = true

        // When
        sut.processMemoryPressureEventForTesting(.normal)

        // Then
        wait(for: [criticalNotificationExpectation], timeout: 0.2)
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }
}

// MARK: - Mock

private class MockPressureMemoryMonitor: MemoryUsageMonitoring {
    var currentResidentMB: Double = 0
    var currentPhysFootprintMB: Double = 0

    func getCurrentMemoryUsage() -> MemoryUsageMonitor.MemoryReport {
        let residentBytes = UInt64(currentResidentMB * 1_048_576)
        let physFootprintBytes = UInt64(currentPhysFootprintMB * 1_048_576)
        return MemoryUsageMonitor.MemoryReport(
            residentBytes: residentBytes,
            physFootprintBytes: physFootprintBytes
        )
    }
}

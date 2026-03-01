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
    private var mockAllocationStats: MockPressureAllocationStatsProvider!
    private var notificationCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPixelFiring = PixelKitMock()
        mockMemoryUsageMonitor = MockPressureMemoryMonitor()
        mockAllocationStats = MockPressureAllocationStatsProvider()
        notificationCenter = NotificationCenter()
    }

    override func tearDown() {
        sut = nil
        mockFeatureFlagger = nil
        mockPixelFiring = nil
        mockMemoryUsageMonitor = nil
        mockAllocationStats = nil
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
            allocationStatsProvider: mockAllocationStats,
            notificationCenter: notificationCenter
        )
    }

    // MARK: - Pixel Name Tests

    func testMemoryPressureCriticalPixelName() {
        // Given
        let context = MemoryReportingContext(
            browserMemoryMB: 1024,
            windows: nil,
            standardTabs: nil,
            pinnedTabs: nil,
            architecture: "ARM",
            syncEnabled: nil,
            usedAllocationMB: nil,
            wcTotalMemoryMB: nil,
            uptimeMinutes: 0
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
            standardTabs: 21,
            pinnedTabs: 4,
            architecture: "ARM",
            syncEnabled: true,
            usedAllocationMB: 512,
            wcTotalMemoryMB: 4096,
            uptimeMinutes: 120
        )

        // When
        let pixel = MemoryPressurePixel.memoryPressureCritical(context: context)

        // Then
        let params = pixel.parameters
        XCTAssertNotNil(params)
        XCTAssertEqual(params?["browser_memory_mb"], "2048")
        XCTAssertEqual(params?["windows"], "4")
        XCTAssertEqual(params?["standard_tabs"], "21")
        XCTAssertEqual(params?["pinned_tabs"], "4")
        XCTAssertEqual(params?["architecture"], "ARM")
        XCTAssertEqual(params?["sync_enabled"], "true")
        XCTAssertEqual(params?["used_allocation"], "512")
        XCTAssertEqual(params?["wc_total_memory"], "4096")
        XCTAssertEqual(params?["uptime"], "120")
    }

    func testMemoryPressurePixelReturnsUnknownForNilDependencies() {
        // Given
        let context = MemoryReportingContext(
            browserMemoryMB: 512,
            windows: nil,
            standardTabs: nil,
            pinnedTabs: nil,
            architecture: "Intel",
            syncEnabled: nil,
            usedAllocationMB: nil,
            wcTotalMemoryMB: nil,
            uptimeMinutes: 5
        )

        // When
        let pixel = MemoryPressurePixel.memoryPressureCritical(context: context)

        // Then
        let params = pixel.parameters
        XCTAssertEqual(params?["windows"], "unknown")
        XCTAssertEqual(params?["standard_tabs"], "unknown")
        XCTAssertEqual(params?["pinned_tabs"], "unknown")
        XCTAssertEqual(params?["sync_enabled"], "unknown")
        XCTAssertEqual(params?["used_allocation"], "unknown")
        XCTAssertEqual(params?["wc_total_memory"], "unknown")
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
        XCTAssertEqual(params?["standard_tabs"], "unknown")
        XCTAssertEqual(params?["pinned_tabs"], "unknown")
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

// MARK: - Mocks

private class MockPressureMemoryMonitor: MemoryUsageMonitoring {
    var currentResidentMB: Double = 0
    var currentPhysFootprintMB: Double = 0

    func getCurrentMemoryUsage() -> MemoryUsageMonitor.MemoryReport {
        let residentBytes = UInt64(currentResidentMB * 1_048_576)
        let physFootprintBytes = UInt64(currentPhysFootprintMB * 1_048_576)
        return MemoryUsageMonitor.MemoryReport(
            residentBytes: residentBytes,
            physFootprintBytes: physFootprintBytes,
            webContentBytes: nil,
            webContentProcessCount: nil
        )
    }
}

private class MockPressureAllocationStatsProvider: MemoryAllocationStatsProviding {
    var totalUsedBytes: UInt64?

    func currentTotalUsedBytes() -> UInt64? {
        totalUsedBytes
    }
}

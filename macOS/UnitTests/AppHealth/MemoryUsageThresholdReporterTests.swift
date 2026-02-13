//
//  MemoryUsageThresholdReporterTests.swift
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

final class MemoryUsageThresholdReporterTests: XCTestCase {

    private var sut: MemoryUsageThresholdReporter!
    private var mockMemoryUsageMonitor: MockMemoryUsageMonitor!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockPixelFiring: PixelKitMock!

    override func setUp() {
        super.setUp()
        mockMemoryUsageMonitor = MockMemoryUsageMonitor()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPixelFiring = PixelKitMock()
    }

    override func tearDown() {
        sut = nil
        mockMemoryUsageMonitor = nil
        mockFeatureFlagger = nil
        mockPixelFiring = nil
        super.tearDown()
    }

    // MARK: - Pixel Name Tests

    func testMemoryUsagePixelNames() {
        // Given/When
        let pixels: [(MemoryUsagePixel, String)] = [
            (.less512, "m_mac_memory_usage_less_512"),
            (.range512_1023, "m_mac_memory_usage_512_1023"),
            (.range1024_2047, "m_mac_memory_usage_1024_2047"),
            (.range2048_4095, "m_mac_memory_usage_2048_4095"),
            (.range4096_8191, "m_mac_memory_usage_4096_8191"),
            (.range8192_16383, "m_mac_memory_usage_8192_16383"),
            (.range16384_more, "m_mac_memory_usage_16384_more")
        ]

        // Then
        for (pixel, expectedName) in pixels {
            XCTAssertEqual(pixel.name, expectedName, "Pixel name mismatch for \(pixel)")
        }
    }

    func testMemoryUsagePixelParameters() {
        // Given/When
        let allPixels: [MemoryUsagePixel] = [
            .less512, .range512_1023, .range1024_2047, .range2048_4095,
            .range4096_8191, .range8192_16383, .range16384_more
        ]

        // Then
        for pixel in allPixels {
            XCTAssertNil(pixel.parameters, "Pixel should have no parameters: \(pixel)")
        }
    }

    // MARK: - Pixel Selection Tests

    func testPixelSelection_ForVariousMemoryValues() {
        // Test bucket boundaries
        let testCases: [(Double, MemoryUsagePixel)] = [
            // Less than 512MB bucket
            (0, .less512),
            (100, .less512),
            (511, .less512),
            (511.9, .less512),

            // 512-1023MB bucket
            (512, .range512_1023),
            (700, .range512_1023),
            (1023, .range512_1023),
            (1023.9, .range512_1023),

            // 1-2GB bucket
            (1024, .range1024_2047),
            (1500, .range1024_2047),
            (2047, .range1024_2047),
            (2047.9, .range1024_2047),

            // 2-4GB bucket
            (2048, .range2048_4095),
            (3000, .range2048_4095),
            (4095, .range2048_4095),
            (4095.9, .range2048_4095),

            // 4-8GB bucket
            (4096, .range4096_8191),
            (6000, .range4096_8191),
            (8191, .range4096_8191),
            (8191.9, .range4096_8191),

            // 8-16GB bucket
            (8192, .range8192_16383),
            (12000, .range8192_16383),
            (16383, .range8192_16383),
            (16383.9, .range8192_16383),

            // 16GB+ bucket
            (16384, .range16384_more),
            (20000, .range16384_more),
            (32768, .range16384_more)
        ]

        for (memoryMB, expectedPixel) in testCases {
            // When
            let pixel = MemoryUsagePixel.pixel(forMB: memoryMB)

            // Then
            XCTAssertEqual(pixel, expectedPixel, "Memory \(memoryMB) MB should map to \(expectedPixel)")
        }
    }

    // MARK: - Feature Flag Tests

    func testWhenFeatureFlagDisabled_ThenDoesNotFirePixels() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenFeatureFlagEnabled_ThenFiresPixelImmediately() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockPixelFiring.expectedFireCalls = [.init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily)]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()

        // Then
        mockPixelFiring.verifyExpectations()
    }

    func testWhenFeatureFlagToggledOff_ThenStopsMonitoring() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockPixelFiring.expectedFireCalls = [.init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily)]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()
        mockPixelFiring.verifyExpectations()

        // Record how many calls we had
        let callCountBeforeToggle = mockPixelFiring.actualFireCalls.count

        // When - toggle feature flag off
        mockFeatureFlagger.enabledFeatureFlags = []
        mockFeatureFlagger.triggerUpdate()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))

        // Then - no new pixels fired after toggle
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, callCountBeforeToggle)
    }

    // MARK: - Memory Update Tests

    func testWhenMemoryChanges_ThenFiresCorrectThresholdPixel() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 400
        mockPixelFiring.expectedFireCalls = [.init(pixel: MemoryUsagePixel.less512, frequency: .daily)]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()

        // Then
        mockPixelFiring.verifyExpectations()
    }

    func testWhenMemoryIsHigh_ThenFiresCorrectBucketPixel() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 20000
        mockPixelFiring.expectedFireCalls = [.init(pixel: MemoryUsagePixel.range16384_more, frequency: .daily)]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()

        // Then
        mockPixelFiring.verifyExpectations()
    }

    func testUsesPhysicalFootprint_NotResident() {
        // Given
        mockMemoryUsageMonitor.currentResidentMB = 2000   // Would be 2-4GB bucket
        mockMemoryUsageMonitor.currentPhysFootprintMB = 700  // Should be 512-1023 bucket
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: MemoryUsagePixel.range512_1023, frequency: .daily)
        ]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()

        // Then - uses physical footprint for bucketing
        mockPixelFiring.verifyExpectations()
    }

    // MARK: - Deduplication Tests

    func testWhenSamePixelFiredTwice_ThenOnlyFiresOnce() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockPixelFiring.expectedFireCalls = [.init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily)]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When - start and then trigger additional checks in the same bucket
        sut.startMonitoringImmediately()
        sut.checkThresholdNow()
        sut.checkThresholdNow()
        sut.checkThresholdNow()

        // Then - pixel fired exactly once
        mockPixelFiring.verifyExpectations()
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
    }

    func testWhenMemoryChangesBucket_ThenFiresNewPixel() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 400
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: MemoryUsagePixel.less512, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily)
        ]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When - start in <512 bucket, then move to 1-2GB bucket
        sut.startMonitoringImmediately()
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1500
        sut.checkThresholdNow()

        // Then - both pixels fired
        mockPixelFiring.verifyExpectations()
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 2)
    }

    func testWhenMemoryReturnsToPreviousBucket_ThenDoesNotFireAgain() {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 400
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: MemoryUsagePixel.less512, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily)
        ]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When - go through <512 -> 1-2GB -> back to <512
        sut.startMonitoringImmediately()
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1500
        sut.checkThresholdNow()
        mockMemoryUsageMonitor.currentPhysFootprintMB = 300
        sut.checkThresholdNow()

        // Then - only 2 pixels fired (less512 not fired again)
        mockPixelFiring.verifyExpectations()
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 2)
    }

    // MARK: - Boundary Tests

    func testBucketBoundaries_ExactValues() {
        let boundaryTests: [(Double, MemoryUsagePixel)] = [
            (512, .range512_1023),
            (1024, .range1024_2047),
            (2048, .range2048_4095),
            (4096, .range4096_8191),
            (8192, .range8192_16383),
            (16384, .range16384_more),
        ]

        for (memoryMB, expectedPixel) in boundaryTests {
            // Given
            let monitor = MockMemoryUsageMonitor()
            monitor.currentPhysFootprintMB = memoryMB
            let pixelFiring = PixelKitMock()
            pixelFiring.expectedFireCalls = [.init(pixel: expectedPixel, frequency: .daily)]
            let featureFlagger = MockFeatureFlagger()
            featureFlagger.enabledFeatureFlags = [.memoryUsageReporting]

            let reporter = MemoryUsageThresholdReporter(
                memoryUsageMonitor: monitor,
                featureFlagger: featureFlagger,
                pixelFiring: pixelFiring
            )

            // When
            reporter.startMonitoringImmediately()

            // Then
            pixelFiring.verifyExpectations()
        }
    }
}

// MARK: - Mock MemoryUsageMonitor

private class MockMemoryUsageMonitor: MemoryUsageMonitoring {
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

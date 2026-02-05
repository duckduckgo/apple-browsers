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
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()
        mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: 1024)

        // Let the main queue process
        let expectation = XCTestExpectation(description: "Process main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenFeatureFlagEnabled_ThenFiresPixelsAfterDelay() {
        // Given
        mockPixelFiring.expectedFireCalls = [.init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily)]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()
        mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: 1024)

        // Let the main queue process the pixel firing
        let expectation = XCTestExpectation(description: "Process main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        mockPixelFiring.verifyExpectations()
    }

    func testWhenFeatureFlagToggledOff_ThenStopsMonitoring() {
        // Given
        mockPixelFiring.expectedFireCalls = [.init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily)]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()
        mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: 1024)

        // Let the main queue process the pixel firing
        let expectation1 = XCTestExpectation(description: "Process main queue")
        DispatchQueue.main.async {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 1.0)

        mockPixelFiring.verifyExpectations()

        // When - toggle feature flag off
        mockFeatureFlagger.enabledFeatureFlags = []
        mockFeatureFlagger.triggerUpdate()

        // Send another report
        mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: 2048)

        // Let the main queue process
        let expectation2 = XCTestExpectation(description: "Process main queue")
        DispatchQueue.main.async {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1.0)

        // Then - no new pixels fired
        mockPixelFiring.verifyExpectations()
    }

    // MARK: - Memory Update Tests

    func testWhenMemoryUpdates_ThenFiresCorrectThresholdPixel() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // Test different memory values
        let memoryValues: [Double] = [400, 800, 1500, 3000, 6000, 12000, 40000]

        mockPixelFiring.expectedFireCalls = [
            .init(pixel: MemoryUsagePixel.less512, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range512_1023, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range2048_4095, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range4096_8191, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range8192_16383, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range16384_more, frequency: .daily),
        ]

        // When
        sut.startMonitoringImmediately()
        for memoryMB in memoryValues {
            mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: memoryMB)
        }

        // Let the main queue process all pixel firings
        let expectation = XCTestExpectation(description: "Process main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        mockPixelFiring.verifyExpectations()
    }

    func testWhenMemoryStaysInSameBucket_ThenPixelStillFired() {
        // Given - PixelKit's .daily frequency handles deduplication
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily)
        ]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        // When
        sut.startMonitoringImmediately()
        mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: 1024) // 1-2GB
        mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: 1500) // 1-2GB
        mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: 1800) // 1-2GB
        mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: 1200) // 1-2GB

        // Let the main queue process all pixel firings
        let expectation = XCTestExpectation(description: "Process main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        mockPixelFiring.verifyExpectations()
    }

    func testUsesPhysicalFootprint_NotResident() {
        // Given
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
        mockMemoryUsageMonitor.sendMemoryReport(
            residentMB: 2000,  // Would be 2-4GB bucket
            physFootprintMB: 700  // Should be 512-1023 bucket
        )

        // Let the main queue process the pixel firing
        let expectation = XCTestExpectation(description: "Process main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        mockPixelFiring.verifyExpectations()
    }

    // MARK: - Boundary Tests

    func testBucketBoundaries_ExactValues() {
        // Test exact boundary values
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: MemoryUsagePixel.range512_1023, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range1024_2047, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range2048_4095, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range4096_8191, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range8192_16383, frequency: .daily),
            .init(pixel: MemoryUsagePixel.range16384_more, frequency: .daily),
        ]
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = MemoryUsageThresholdReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring
        )

        let boundaryMemoryValues: [Double] = [512, 1024, 2048, 4096, 8192, 16384]

        // When
        sut.startMonitoringImmediately()
        for boundaryMemory in boundaryMemoryValues {
            mockMemoryUsageMonitor.sendMemoryReport(physFootprintMB: boundaryMemory)
        }

        // Let the main queue process all pixel firings
        let expectation = XCTestExpectation(description: "Process main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        mockPixelFiring.verifyExpectations()
    }
}

// MARK: - Mock MemoryUsageMonitor

private class MockMemoryUsageMonitor: MemoryUsageMonitoring {
    private let memoryReportSubject = CurrentValueSubject<MemoryUsageMonitor.MemoryReport, Never>(
        MemoryUsageMonitor.MemoryReport(residentBytes: 0, physFootprintBytes: 0)
    )

    var memoryReportPublisher: AnyPublisher<DuckDuckGo_Privacy_Browser.MemoryUsageMonitor.MemoryReport, Never> {
        return memoryReportSubject.eraseToAnyPublisher()
    }

    func sendMemoryReport(residentMB: Double = 0, physFootprintMB: Double) {
        let residentBytes = UInt64(residentMB * 1_048_576)
        let physFootprintBytes = UInt64(physFootprintMB * 1_048_576)
        let report = MemoryUsageMonitor.MemoryReport(
            residentBytes: residentBytes,
            physFootprintBytes: physFootprintBytes
        )
        memoryReportSubject.send(report)
    }
}

//
//  MemoryUsageIntervalReporterTests.swift
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

import Combine
import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class MemoryUsageIntervalReporterTests: XCTestCase {

    private var sut: MemoryUsageIntervalReporter!
    private var mockMemoryUsageMonitor: MockIntervalMemoryMonitor!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockPixelFiring: PixelKitMock!

    override func setUp() {
        super.setUp()
        mockMemoryUsageMonitor = MockIntervalMemoryMonitor()
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

    // MARK: - Helpers

    private func makeSUT(checkInterval: TimeInterval = 60) -> MemoryUsageIntervalReporter {
        MemoryUsageIntervalReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring,
            windowContext: nil,
            isSyncEnabled: nil,
            checkInterval: checkInterval
        )
    }

    // MARK: - Startup Pixel

    func testWhenStarted_ThenFiresStartupPixel() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting()

        // When
        await sut.checkIntervalsNow()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
        let call = mockPixelFiring.actualFireCalls[0]
        XCTAssertEqual(call.pixel.name, "m_mac_memory_usage")
        XCTAssertEqual(call.pixel.parameters?["trigger"], "startup")
        XCTAssertEqual(call.frequency, .standard)
    }

    func testWhenStarted_ThenStartupPixelIncludesContextParameters() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 2500
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting()

        // When
        await sut.checkIntervalsNow()

        // Then
        let params = mockPixelFiring.actualFireCalls.first?.pixel.parameters
        XCTAssertEqual(params?["trigger"], "startup")
        XCTAssertEqual(params?["browser_memory_mb"], "2048")
        XCTAssertEqual(params?["windows"], "unknown")
        XCTAssertEqual(params?["tabs"], "unknown")
        XCTAssertEqual(params?["sync_enabled"], "unknown")
        XCTAssertNotNil(params?["architecture"])
    }

    // MARK: - Interval Triggering

    func testWhenOneHourElapsed_ThenFiresStartupAnd1hPixels() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 512
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-3601))

        // When
        await sut.checkIntervalsNow()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 2)
        let triggers = mockPixelFiring.actualFireCalls.compactMap { $0.pixel.parameters?["trigger"] }
        XCTAssertTrue(triggers.contains("startup"))
        XCTAssertTrue(triggers.contains("1h"))
    }

    func testWhenFourHoursElapsed_ThenFiresStartupAnd1hAnd2hAnd4hPixels() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 512
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-14401))

        // When
        await sut.checkIntervalsNow()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 4)
        let triggers = mockPixelFiring.actualFireCalls.compactMap { $0.pixel.parameters?["trigger"] }
        XCTAssertTrue(triggers.contains("startup"))
        XCTAssertTrue(triggers.contains("1h"))
        XCTAssertTrue(triggers.contains("2h"))
        XCTAssertTrue(triggers.contains("4h"))
    }

    func testWhen24HoursElapsed_ThenFiresAllTriggers() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-86401))

        // When
        await sut.checkIntervalsNow()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 6)
        let triggers = Set(mockPixelFiring.actualFireCalls.compactMap { $0.pixel.parameters?["trigger"] })
        XCTAssertEqual(triggers, Set(["startup", "1h", "2h", "4h", "8h", "24h"]))
    }

    func testWhenLessThanOneHourElapsed_ThenOnlyFiresStartup() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 512
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-1800)) // 30 min

        // When
        await sut.checkIntervalsNow()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["trigger"], "startup")
    }

    // MARK: - Deduplication

    func testWhenCheckCalledTwice_ThenEachTriggerFiresOnlyOnce() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 512
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-7201)) // 2h

        // When
        await sut.checkIntervalsNow()
        await sut.checkIntervalsNow()
        await sut.checkIntervalsNow()

        // Then - still only 3 pixels (startup, 1h, 2h) not 9
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 3)
    }

    func testWhenTriggersReset_ThenPixelsCanFireAgain() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 512
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting()

        // When - fire, reset, fire again
        await sut.checkIntervalsNow()
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)

        sut.resetFiredTriggers()
        await sut.checkIntervalsNow()

        // Then - startup fired again after reset
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 2)
    }

    // MARK: - Feature Flag

    func testWhenFeatureFlagDisabled_ThenDoesNotFirePixels() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = []
        sut = makeSUT()
        sut.startMonitoringForTesting()

        // When
        await sut.checkIntervalsNow()

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - Feature Flag Lifecycle (Production Combine Path)

    @MainActor
    func testWhenFeatureFlagEnabledViaPublisher_ThenStartsMonitoringAndFiresStartup() async throws {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT(checkInterval: 0.1)

        // Suspending the main actor allows:
        // 1. Combine sink to fire via DispatchQueue.main
        // 2. Background task to spawn and collect context via MainActor.run
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 500)

        // Then - startup pixel should have been fired via the production Combine path
        let startupFired = mockPixelFiring.actualFireCalls.contains { $0.pixel.parameters?["trigger"] == "startup" }
        XCTAssertTrue(startupFired, "Startup pixel should fire when feature flag is enabled via publisher")
    }

    @MainActor
    func testWhenFeatureFlagToggledOffThenOn_ThenSessionResetsAndStartupFiresAgain() async throws {
        // Given - start with flag ON
        mockMemoryUsageMonitor.currentPhysFootprintMB = 512
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT(checkInterval: 0.1)

        // Allow initial session to start and fire startup
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 500)

        let initialStartupCount = mockPixelFiring.actualFireCalls
            .filter { $0.pixel.parameters?["trigger"] == "startup" }.count
        XCTAssertEqual(initialStartupCount, 1, "Initial session should fire startup once")

        // When - toggle OFF (triggers stopMonitoring which resets state)
        mockFeatureFlagger.enabledFeatureFlags = []
        mockFeatureFlagger.triggerUpdate()
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 300)

        // When - toggle ON again (fresh session)
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        mockFeatureFlagger.triggerUpdate()
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 500)

        // Then - startup should have fired twice (once per session)
        let totalStartupFires = mockPixelFiring.actualFireCalls
            .filter { $0.pixel.parameters?["trigger"] == "startup" }.count
        XCTAssertEqual(totalStartupFires, 2, "Startup pixel should fire again after OFF->ON toggle (new session)")
    }

    // MARK: - Memory Bucketing in Context

    func testWhenMemoryChanges_ThenContextReflectsCurrentMemory() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 300
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-3601))

        // When
        await sut.checkIntervalsNow()

        // Then - startup fires with 300MB context, 1h fires with 300MB context
        let startupCall = mockPixelFiring.actualFireCalls.first { $0.pixel.parameters?["trigger"] == "startup" }
        XCTAssertEqual(startupCall?.pixel.parameters?["browser_memory_mb"], "0") // <512 bucket

        // Simulate memory increase before next check
        mockMemoryUsageMonitor.currentPhysFootprintMB = 5000
        sut.resetFiredTriggers()
        await sut.checkIntervalsNow()

        // Then - new checks reflect updated memory
        let secondStartup = mockPixelFiring.actualFireCalls.last { $0.pixel.parameters?["trigger"] == "startup" }
        XCTAssertEqual(secondStartup?.pixel.parameters?["browser_memory_mb"], "4096") // 4-8GB bucket
    }

    // MARK: - Pixel Frequency

    func testAllPixelsFiredWithStandardFrequency() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-86401))

        // When
        await sut.checkIntervalsNow()

        // Then - all pixels use .standard frequency
        for call in mockPixelFiring.actualFireCalls {
            XCTAssertEqual(call.frequency, .standard, "Trigger \(call.pixel.parameters?["trigger"] ?? "?") should use .standard frequency")
        }
    }

    // MARK: - Pixel Name

    func testAllPixelsHaveSameName() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-86401))

        // When
        await sut.checkIntervalsNow()

        // Then
        for call in mockPixelFiring.actualFireCalls {
            XCTAssertEqual(call.pixel.name, "m_mac_memory_usage")
        }
    }
}

// MARK: - Mock

private class MockIntervalMemoryMonitor: MemoryUsageMonitoring {
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

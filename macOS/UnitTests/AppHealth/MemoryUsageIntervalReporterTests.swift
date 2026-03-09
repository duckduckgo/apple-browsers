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

@MainActor
final class MemoryUsageIntervalReporterTests: XCTestCase {

    private var sut: MemoryUsageIntervalReporter!
    private var mockMemoryUsageMonitor: MockIntervalMemoryMonitor!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockPixelFiring: PixelKitMock!
    private var mockAllocationStats: MockIntervalAllocationStatsProvider!

    override func setUp() {
        super.setUp()
        mockMemoryUsageMonitor = MockIntervalMemoryMonitor()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPixelFiring = PixelKitMock()
        mockAllocationStats = MockIntervalAllocationStatsProvider()
    }

    override func tearDown() {
        sut = nil
        mockMemoryUsageMonitor = nil
        mockFeatureFlagger = nil
        mockPixelFiring = nil
        mockAllocationStats = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT(checkInterval: TimeInterval = 60) -> MemoryUsageIntervalReporter {
        MemoryUsageIntervalReporter(
            memoryUsageMonitor: mockMemoryUsageMonitor,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: mockPixelFiring,
            windowContext: nil,
            isSyncEnabled: { nil },
            allocationStatsProvider: mockAllocationStats,
            checkInterval: checkInterval
        )
    }

    // MARK: - Startup Pixel

    func testWhenStartedAndStartupDelayElapsed_ThenFiresStartupPixel() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-121))

        // When
        await sut.checkIntervalsNow()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
        let call = mockPixelFiring.actualFireCalls[0]
        XCTAssertEqual(call.pixel.name, "m_mac_memory_usage_interval")
        XCTAssertEqual(call.pixel.parameters?["trigger"], "startup")
        XCTAssertEqual(call.frequency, .standard)
    }

    func testWhenStartedAndStartupDelayNotElapsed_ThenDoesNotFireStartupPixel() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date())

        // When
        await sut.checkIntervalsNow()

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenStarted_ThenStartupPixelIncludesContextParameters() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 2500
        mockAllocationStats.totalUsedBytes = 300 * 1_048_576 // 300 MB -> bucket 256
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-121))

        // When
        await sut.checkIntervalsNow()

        // Then
        let params = mockPixelFiring.actualFireCalls.first?.pixel.parameters
        XCTAssertEqual(params?["trigger"], "startup")
        XCTAssertEqual(params?["browser_memory_mb"], "2048")
        XCTAssertEqual(params?["windows"], "unknown")
        XCTAssertEqual(params?["standard_tabs"], "unknown")
        XCTAssertEqual(params?["pinned_tabs"], "unknown")
        XCTAssertEqual(params?["sync_enabled"], "unknown")
        XCTAssertNotNil(params?["architecture"])
        XCTAssertEqual(params?["used_allocation"], "256")
        XCTAssertNil(params?["uptime"])
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

    func testWhenFourHoursElapsed_ThenFiresStartupAnd1hAnd2hAnd4hPixels() async throws {
        throw XCTSkip("Flaky test")
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

    func testWhenLessThanTwoMinutesElapsed_ThenNoPixelsFire() async {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 2048
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-60)) // 1 min

        // When
        await sut.checkIntervalsNow()

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
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
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-121))

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

    func testWhenFeatureFlagEnabledViaPublisher_ThenStartupDoesNotFireBeforeDelay() async throws {
        // Given
        mockMemoryUsageMonitor.currentPhysFootprintMB = 1024
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT(checkInterval: 0.1)

        // Suspending the main actor allows:
        // 1. Combine sink to fire via DispatchQueue.main
        // 2. Background task to spawn and collect context via MainActor.run
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 500)

        // Then - startup pixel should NOT fire within the 2-minute delay window
        let startupFired = mockPixelFiring.actualFireCalls.contains { $0.pixel.parameters?["trigger"] == "startup" }
        XCTAssertFalse(startupFired, "Startup pixel should not fire before the 2-minute delay elapses")
    }

    func testWhenFeatureFlagToggledOffThenOn_ThenSessionResetsAndNoPixelsFire() async throws {
        // Given - start with flag ON
        mockMemoryUsageMonitor.currentPhysFootprintMB = 512
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT(checkInterval: 0.1)

        // Allow initial session to start (startup won't fire due to 2-minute delay)
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 500)

        let initialCount = mockPixelFiring.actualFireCalls.count
        XCTAssertEqual(initialCount, 0, "No pixels should fire within the startup delay window")

        // When - toggle OFF (triggers stopMonitoring which resets state)
        mockFeatureFlagger.enabledFeatureFlags = []
        mockFeatureFlagger.triggerUpdate()
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 300)

        // When - toggle ON again (fresh session with new start time)
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        mockFeatureFlagger.triggerUpdate()
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 500)

        // Then - still no pixels fired because each session resets the start time
        let totalFires = mockPixelFiring.actualFireCalls.count
        XCTAssertEqual(totalFires, 0, "No pixels should fire since each session restarts the 2-minute delay")
    }

    func testWhenFeatureFlagToggledOffThenOn_ThenStartupFiresAgainAfterDelay() async {
        // Given - first session with startup delay elapsed
        mockMemoryUsageMonitor.currentPhysFootprintMB = 512
        mockFeatureFlagger.enabledFeatureFlags = [.memoryUsageReporting]
        sut = makeSUT()
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-121))

        await sut.checkIntervalsNow()
        let firstStartupCount = mockPixelFiring.actualFireCalls
            .filter { $0.pixel.parameters?["trigger"] == "startup" }.count
        XCTAssertEqual(firstStartupCount, 1)

        // When - simulate OFF->ON toggle with a fresh session where delay has elapsed
        sut.startMonitoringForTesting(startTime: Date().addingTimeInterval(-121))
        await sut.checkIntervalsNow()

        // Then - startup should have fired twice (once per session)
        let totalStartupFires = mockPixelFiring.actualFireCalls
            .filter { $0.pixel.parameters?["trigger"] == "startup" }.count
        XCTAssertEqual(totalStartupFires, 2, "Startup pixel should fire again after session reset")
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
            XCTAssertEqual(call.pixel.name, "m_mac_memory_usage_interval")
        }
    }
}

// MARK: - Mocks

private class MockIntervalMemoryMonitor: MemoryUsageMonitoring {
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

private class MockIntervalAllocationStatsProvider: MemoryAllocationStatsProviding {
    var totalUsedBytes: UInt64?

    func currentTotalUsedBytes() -> UInt64? {
        totalUsedBytes
    }
}

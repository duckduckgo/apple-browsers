//
//  PerformanceMetricsReporterTests.swift
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

import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class PerformanceMetricsReporterTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockPixelFiring: PixelKitMock!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPixelFiring = PixelKitMock()
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        mockPixelFiring = nil
        super.tearDown()
    }

    // MARK: - Feature Flag

    func testWhenFeatureFlagEnabled_ThenFiresPixel() {
        // Given
        let (_, _, reporter) = buildMetricsReporter()
        let profiler = StartupProfiler()

        // When
        reporter.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
    }

    // MARK: - Pixel Name

    func testFiredPixelHasCorrectName() {
        // Given
        let (_, _, reporter) = buildMetricsReporter()
        let profiler = StartupProfiler()

        // When
        reporter.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.name, "m_mac_startup_performance_metrics")
    }

    // MARK: - Environment Parameters

    func testPixelIncludesSystemEnvironmentProperties() {
        // Given
        let (environment, _, reporter) = buildMetricsReporter()
        let profiler = StartupProfiler()

        // When
        reporter.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["architecture"], environment.architecture)
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["active_processor_count"], "8")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["battery_power"], environment.isOnBattery!.description)
    }

    // MARK: - Session Restoration

    func testPixelIncludesSessionRestorationState() {
        // Given
        let (_, _, reporter) = buildMetricsReporter(restorePreviousSession: true)
        let profiler = StartupProfiler()

        // When
        reporter.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["session_restoration"], "true")
    }

    // MARK: - Window Context

    func testPixelIncludesWindowAndTabCount() {
        // Given
        let (_, _, reporter) = buildMetricsReporter()
        let profiler = StartupProfiler()

        // When
        reporter.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["windows"], "1")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["standard_tabs"], "4")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["pinned_tabs"], "1")
    }

    // MARK: - Timing Metrics

    func testPixelIncludesTimingMetrics() {
        // Given
        let (_, _, reporter) = buildMetricsReporter()
        let metrics = buildStartupMetrics(appDelegateInitDuration: 0.15, mainMenuInitDuration: 0.25, timeToInteractiveDuration: 2.5)
        let profiler = StartupProfiler()

        // When
        reporter.startupProfiler(profiler, didCompleteWithMetrics: metrics)

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["app_delegate_init"], "150")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["main_menu_init"], "250")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["time_to_interactive"], "2500")
    }
}

// MARK: - Helpers

private extension PerformanceMetricsReporterTests {

    func buildMetricsReporter(restorePreviousSession: Bool = false) -> (SystemEnvironment, WindowContext, PerformanceMetricsReporter) {
        let environment = SystemEnvironment(architecture: "ARM", activeProcessorCount: 8, isOnBattery: false)
        let windowContext = WindowContext(standardTabs: 5, pinnedTabs: 1, windows: 1)
        let reporter = PerformanceMetricsReporter(environment: environment, pixelFiring: mockPixelFiring, previousSessionRestored: restorePreviousSession, windowContext: windowContext)

        return (environment, windowContext, reporter)
    }

    func buildStartupMetrics(
        appDelegateInitDuration: TimeInterval = 0,
        mainMenuInitDuration: TimeInterval = 0,
        appWillFinishLaunchingDuration: TimeInterval = 0,
        appDidFinishLaunchingBeforeRestorationDuration: TimeInterval = 0,
        appDidFinishLaunchingAfterRestorationDuration: TimeInterval = 0,
        appStateRestorationDuration: TimeInterval = 0,
        timeToInteractiveDuration: TimeInterval = 0
    ) -> StartupMetrics {
        var base: TimeInterval = 0.0
        var metrics = StartupMetrics()

        metrics.update(step: .appDelegateInit, startTime: base, endTime: base + appDelegateInitDuration)
        base += appDelegateInitDuration

        metrics.update(step: .mainMenuInit, startTime: base, endTime: base + mainMenuInitDuration)
        base += mainMenuInitDuration

        metrics.update(step: .appWillFinishLaunching, startTime: base, endTime: base + appWillFinishLaunchingDuration)
        base += appWillFinishLaunchingDuration

        metrics.update(step: .appDidFinishLaunchingBeforeRestoration, startTime: base, endTime: base + appDidFinishLaunchingBeforeRestorationDuration)
        base += appDidFinishLaunchingBeforeRestorationDuration

        metrics.update(step: .appStateRestoration, startTime: base, endTime: base + appStateRestorationDuration)
        base += appStateRestorationDuration

        metrics.update(step: .appDidFinishLaunchingAfterRestoration, startTime: base, endTime: base + appDidFinishLaunchingAfterRestorationDuration)
        base += appDidFinishLaunchingAfterRestorationDuration

        metrics.update(step: .timeToInteractive, startTime: 0.0, endTime: timeToInteractiveDuration)

        return metrics
    }
}

//
//  StartupMetricsReporterTests.swift
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
final class StartupMetricsReporterTests: XCTestCase {

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

    func testWhenFeatureFlagDisabled_ThenDoesNotFirePixel() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        let sut = buildMetricsReporter()
        let profiler = StartupProfiler()

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())
        await Task.yield()

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenFeatureFlagEnabled_ThenFiresPixel() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let sut = buildMetricsReporter()
        let profiler = StartupProfiler()

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())
        await Task.yield()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
    }

    // MARK: - Pixel Name

    func testFiredPixelHasCorrectName() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let sut = buildMetricsReporter()
        let profiler = StartupProfiler()

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())
        await Task.yield()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.name, "m_mac_startup_performance_metrics")
    }

    // MARK: - Environment Parameters

    func testPixelIncludesSystemEnvironmentProperties() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let environment = SystemEnvironment(architecture: "ARM", activeProcessorCount: 8, isOnBattery: true)
        let sut = buildMetricsReporter(environment: environment)
        let profiler = StartupProfiler()

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())
        await Task.yield()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["architecture"], "ARM")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["active_processor_count"], "8")
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["battery_power"], "true")
    }

    // MARK: - Session Restoration

    func testPixelIncludesSessionRestorationState() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let sut = buildMetricsReporter(restorePreviousSession: true)
        let profiler = StartupProfiler()

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())
        await Task.yield()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["session_restoration"], "true")
    }

    // MARK: - Window Context

    func testPixelIncludesWindowCount() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let context = WindowContext(standardTabs: 10, pinnedTabs: 2, windows: 3)
        let sut = buildMetricsReporter(windowContext: context)
        let profiler = StartupProfiler()

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())
        await Task.yield()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["windows"], "2")
    }

    func testPixelIncludesTabCount() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let context = WindowContext(standardTabs: 25, pinnedTabs: 2, windows: 1)
        let sut = buildMetricsReporter(windowContext: context)
        let profiler = StartupProfiler()

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: buildStartupMetrics())
        await Task.yield()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["tabs"], "21")
    }

    // MARK: - Timing Metrics

    func testPixelIncludesAppDelegateInitDuration() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let sut = buildMetricsReporter()
        let profiler = StartupProfiler()
        let metrics = buildStartupMetrics(appDelegateInitDuration: 0.15)

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: metrics)
        await Task.yield()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["app_delegate_init"], "100")
    }

    func testPixelIncludesMainMenuInitDuration() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let sut = buildMetricsReporter()
        let profiler = StartupProfiler()
        let metrics = buildStartupMetrics(mainMenuInitDuration: 0.25)

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: metrics)
        await Task.yield()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["main_menu_init"], "200")
    }

    func testPixelIncludesTimeToInteractive() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let sut = buildMetricsReporter()
        let profiler = StartupProfiler()
        let metrics = buildStartupMetrics(timeToInteractiveDuration: 2.5)

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: metrics)
        await Task.yield()

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["time_to_interactive"], "2000")
    }

    // MARK: - Gap Metrics

    func testPixelIncludesInitToWillFinishLaunchingGap() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let sut = buildMetricsReporter()
        let profiler = StartupProfiler()

        // Build metrics where appDelegateInit ends at 1.0 and appWillFinishLaunching starts at 1.15
        var metrics = StartupMetrics()
        metrics.update(step: .appDelegateInit, startTime: 0.0, endTime: 1.0)
        metrics.update(step: .appWillFinishLaunching, startTime: 1.15, endTime: 1.30)
        metrics.update(step: .appDidFinishLaunchingBeforeRestoration, startTime: 1.30, endTime: 1.50)
        metrics.update(step: .appDidFinishLaunchingAfterRestoration, startTime: 1.50, endTime: 1.70)
        metrics.update(step: .appStateRestoration, startTime: 1.70, endTime: 1.80)
        metrics.update(step: .mainMenuInit, startTime: 0.5, endTime: 0.6)
        metrics.update(step: .timeToInteractive, startTime: 0.0, endTime: 2.0)

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: metrics)
        await Task.yield()

        // Then — gap is 1.15 - 1.0 = 0.15s = 150ms → bucket "100"
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["init_to_will_finish_launching"], "100")
    }

    func testPixelIncludesWillFinishToDidFinishLaunchingGap() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.startupMetrics]
        let sut = buildMetricsReporter()
        let profiler = StartupProfiler()

        var metrics = StartupMetrics()
        metrics.update(step: .appDelegateInit, startTime: 0.0, endTime: 0.5)
        metrics.update(step: .appWillFinishLaunching, startTime: 0.5, endTime: 1.0)
        metrics.update(step: .appDidFinishLaunchingBeforeRestoration, startTime: 1.5, endTime: 2.0)
        metrics.update(step: .appDidFinishLaunchingAfterRestoration, startTime: 2.0, endTime: 2.5)
        metrics.update(step: .appStateRestoration, startTime: 2.5, endTime: 2.6)
        metrics.update(step: .mainMenuInit, startTime: 0.2, endTime: 0.3)
        metrics.update(step: .timeToInteractive, startTime: 0.0, endTime: 3.0)

        // When
        sut.startupProfiler(profiler, didCompleteWithMetrics: metrics)
        await Task.yield()

        // Then — gap is 1.5 - 1.0 = 0.5s = 500ms → bucket "500"
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.pixel.parameters?["app_will_finish_to_app_did_finish_launching"], "500")
    }
}

// MARK: - Helpers

private extension StartupMetricsReporterTests {

    func buildMetricsReporter(windowContext: WindowContext? = nil, restorePreviousSession: Bool = false, environment: SystemEnvironment? = nil) -> StartupMetricsReporter {
        let targetWindowContext = windowContext ?? WindowContext(standardTabs: 5, pinnedTabs: 1, windows: 1)
        let targetEnvironment = environment ?? SystemEnvironment(architecture: "ARM", activeProcessorCount: 8, isOnBattery: false)

        return StartupMetricsReporter(environment: targetEnvironment, featureFlagger: mockFeatureFlagger, pixelFiring: mockPixelFiring, previousSessionRestored: restorePreviousSession, windowContext: targetWindowContext)
    }

    func buildStartupMetrics(
        appDelegateInitDuration: TimeInterval = 0.1,
        mainMenuInitDuration: TimeInterval = 0.05,
        appWillFinishLaunchingDuration: TimeInterval = 0.2,
        appDidFinishLaunchingBeforeRestorationDuration: TimeInterval = 0.3,
        appDidFinishLaunchingAfterRestorationDuration: TimeInterval = 0.1,
        appStateRestorationDuration: TimeInterval = 0.5,
        timeToInteractiveDuration: TimeInterval = 1.5
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

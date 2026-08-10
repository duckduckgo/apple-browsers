//
//  AppReturnInstrumentationTests.swift
//  DuckDuckGo
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

import Foundation
import Testing
import Core
@testable import DuckDuckGo

@Suite("App Return Instrumentation")
struct AppReturnInstrumentationTests {

    private final class PixelCollector {
        var fired: [(name: String, params: [String: String])] = []
    }

    private static let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeSUT(
        featureAvailable: Bool = true,
        effectiveOption: AfterInactivityOption = .newTab,
        thresholdSeconds: Int = 1800,
        unifiedInputAvailable: Bool = false,
        toggleEnabled: Bool = false
    ) -> (DefaultAppReturnInstrumentation, PixelCollector) {
        let eligibility = MockIdleReturnEligibilityManager()
        eligibility.isFeatureAvailableResult = featureAvailable
        eligibility.effectiveAfterInactivityOptionResult = effectiveOption
        eligibility.idleThresholdSecondsResult = thresholdSeconds
        let collector = PixelCollector()
        let sut = DefaultAppReturnInstrumentation(
            eligibilityManager: eligibility,
            isUnifiedInputAvailable: { unifiedInputAvailable },
            isToggleEnabled: { toggleEnabled },
            now: { Self.now },
            fireDailyAndCount: { event, params in
                collector.fired.append((event.name, params))
            })
        return (sut, collector)
    }

    private func backgroundDate(secondsAgo: TimeInterval) -> Date {
        Self.now.addingTimeInterval(-secondsAgo)
    }

    // MARK: - Firing is ungated

    @Test("When feature is unavailable then the pixel still fires with feature_eligible false")
    func whenFeatureUnavailableThenPixelStillFires() {
        let (sut, collector) = makeSUT(featureAvailable: false)

        sut.recordAppForeground(lastBackgroundDate: backgroundDate(secondsAgo: 120),
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false))

        #expect(collector.fired.count == 1)
        #expect(collector.fired.first?.name == "app_return")
        #expect(collector.fired.first?.params["feature_eligible"] == "false")
    }

    // MARK: - Time away buckets

    @Test("When there is no prior background date then the bucket is cold_start")
    func whenNoBackgroundDateThenColdStart() {
        let (sut, collector) = makeSUT()

        sut.recordAppForeground(lastBackgroundDate: nil,
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true))

        #expect(collector.fired.first?.params["time_away_bucket"] == "cold_start")
        #expect(collector.fired.first?.params["exceeded_idle_threshold"] == "false")
    }

    @Test("Bucket boundaries resolve to the expected values")
    func bucketBoundaries() {
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: nil) == "cold_start")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 59) == "lt_1m")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 60) == "1_5m")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 299) == "1_5m")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 300) == "5_15m")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 899) == "5_15m")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 900) == "15_30m")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 1799) == "15_30m")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 1800) == "30_60m")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 3599) == "30_60m")
        #expect(DefaultAppReturnInstrumentation.timeAwayBucket(for: 3600) == "gt_60m")
    }

    // MARK: - Idle threshold

    @Test("When time away meets the threshold then exceeded_idle_threshold is true even when ineligible")
    func whenTimeAwayMeetsThresholdThenExceededTrueEvenWhenIneligible() {
        let (sut, collector) = makeSUT(featureAvailable: false, thresholdSeconds: 1800)

        sut.recordAppForeground(lastBackgroundDate: backgroundDate(secondsAgo: 1800),
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false))

        #expect(collector.fired.first?.params["exceeded_idle_threshold"] == "true")
        #expect(collector.fired.first?.params["idle_threshold_seconds"] == "1800")
    }

    @Test("When time away is below the threshold then exceeded_idle_threshold is false")
    func whenTimeAwayBelowThresholdThenExceededFalse() {
        let (sut, collector) = makeSUT(thresholdSeconds: 1800)

        sut.recordAppForeground(lastBackgroundDate: backgroundDate(secondsAgo: 1799),
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false))

        #expect(collector.fired.first?.params["exceeded_idle_threshold"] == "false")
    }

    // MARK: - Setting and capability params

    @Test("The after-inactivity option is reported in snake_case")
    func afterInactivityOptionReportedSnakeCase() {
        let (newTabSUT, newTabCollector) = makeSUT(effectiveOption: .newTab)
        newTabSUT.recordAppForeground(lastBackgroundDate: nil,
                                      launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true))
        #expect(newTabCollector.fired.first?.params["after_inactivity_option"] == "new_tab")

        let (lutSUT, lutCollector) = makeSUT(effectiveOption: .lastUsedTab)
        lutSUT.recordAppForeground(lastBackgroundDate: nil,
                                   launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true))
        #expect(lutCollector.fired.first?.params["after_inactivity_option"] == "last_used_tab")
    }

    @Test("Capability flags reflect the injected providers")
    func capabilityFlagsReflectProviders() {
        let (sut, collector) = makeSUT(unifiedInputAvailable: true, toggleEnabled: true)

        sut.recordAppForeground(lastBackgroundDate: nil,
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true))

        #expect(collector.fired.first?.params["unified_input_available"] == "true")
        #expect(collector.fired.first?.params["toggle_enabled"] == "true")
    }

    // MARK: - Launch source

    @Test("Launch actions map to the expected launch_source values")
    func launchSourceMapping() throws {
        #expect(DefaultAppReturnInstrumentation.launchSource(for: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true)) == "standard")
        let url = try #require(URL(string: "https://duckduckgo.com"))
        #expect(DefaultAppReturnInstrumentation.launchSource(for: .openURL(url)) == "url")
        #expect(DefaultAppReturnInstrumentation.launchSource(for: .handleUserActivity(NSUserActivity(activityType: "test"))) == "user_activity")
    }
}

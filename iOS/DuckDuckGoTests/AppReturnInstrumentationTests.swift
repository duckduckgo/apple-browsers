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

    /// Runs the send as soon as it is handed over, so the existing expectations can stay synchronous.
    private final class ImmediateDelay: PixelTransmissionDelaying {
        func delaySend(_ send: @escaping () -> Void) {
            send()
        }
    }

    /// Holds the send until the test releases it, standing in for the randomised wait.
    private final class ManualDelay: PixelTransmissionDelaying {
        private var pending: (() -> Void)?

        func delaySend(_ send: @escaping () -> Void) {
            pending = send
        }

        func elapse() {
            pending?()
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeSUT(
        featureAvailable: Bool = true,
        effectiveOption: AfterInactivityOption = .newTab,
        thresholdSeconds: Int = 1800,
        unifiedInputAvailable: Bool = false,
        toggleEnabled: Bool = false,
        delay: PixelTransmissionDelaying = ImmediateDelay()
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
            delay: delay,
            fireDailyAndCount: { event, params in
                collector.fired.append((event.name, params))
            })
        return (sut, collector)
    }

    private func backgroundDate(secondsAgo: TimeInterval) -> Date {
        Self.now.addingTimeInterval(-secondsAgo)
    }

    // MARK: - Firing is ungated

    @available(iOS 16, *)
    @Test("When feature is unavailable then the pixel still fires with feature_eligible false", .timeLimit(.minutes(1)))
    func whenFeatureUnavailableThenPixelStillFires() {
        let (sut, collector) = makeSUT(featureAvailable: false)

        sut.recordAppForeground(lastBackgroundDate: backgroundDate(secondsAgo: 120),
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false))

        #expect(collector.fired.count == 1)
        #expect(collector.fired.first?.name == "app_return")
        #expect(collector.fired.first?.params["feature_eligible"] == "false")
    }

    // MARK: - Time away buckets

    @available(iOS 16, *)
    @Test("When there is no prior background date then the bucket is cold_start", .timeLimit(.minutes(1)))
    func whenNoBackgroundDateThenColdStart() {
        let (sut, collector) = makeSUT()

        sut.recordAppForeground(lastBackgroundDate: nil,
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true))

        #expect(collector.fired.first?.params["time_away_bucket"] == "cold_start")
        #expect(collector.fired.first?.params["exceeded_idle_threshold"] == "false")
    }

    @available(iOS 16, *)
    @Test("Bucket boundaries resolve to the expected values", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("When time away meets the threshold then exceeded_idle_threshold is true even when ineligible", .timeLimit(.minutes(1)))
    func whenTimeAwayMeetsThresholdThenExceededTrueEvenWhenIneligible() {
        let (sut, collector) = makeSUT(featureAvailable: false, thresholdSeconds: 1800)

        sut.recordAppForeground(lastBackgroundDate: backgroundDate(secondsAgo: 1800),
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false))

        #expect(collector.fired.first?.params["exceeded_idle_threshold"] == "true")
        #expect(collector.fired.first?.params["idle_threshold_seconds"] == "1800")
    }

    @available(iOS 16, *)
    @Test("When time away is below the threshold then exceeded_idle_threshold is false", .timeLimit(.minutes(1)))
    func whenTimeAwayBelowThresholdThenExceededFalse() {
        let (sut, collector) = makeSUT(thresholdSeconds: 1800)

        sut.recordAppForeground(lastBackgroundDate: backgroundDate(secondsAgo: 1799),
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false))

        #expect(collector.fired.first?.params["exceeded_idle_threshold"] == "false")
    }

    // MARK: - Setting and capability params

    @available(iOS 16, *)
    @Test("The after-inactivity option is reported in snake_case", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("Capability flags reflect the injected providers", .timeLimit(.minutes(1)))
    func capabilityFlagsReflectProviders() {
        let (sut, collector) = makeSUT(unifiedInputAvailable: true, toggleEnabled: true)

        sut.recordAppForeground(lastBackgroundDate: nil,
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true))

        #expect(collector.fired.first?.params["unified_input_available"] == "true")
        #expect(collector.fired.first?.params["toggle_enabled"] == "true")
    }

    // MARK: - Transmission delay

    @available(iOS 16, *)
    @Test("When the app foregrounds then the pixel is held back until the delay elapses", .timeLimit(.minutes(1)))
    func whenAppForegroundsThenPixelIsHeldBackUntilDelayElapses() {
        let delay = ManualDelay()
        let (sut, collector) = makeSUT(delay: delay)

        sut.recordAppForeground(lastBackgroundDate: backgroundDate(secondsAgo: 120),
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false))

        #expect(collector.fired.isEmpty)

        delay.elapse()

        #expect(collector.fired.count == 1)
        #expect(collector.fired.first?.params["time_away_bucket"] == "1_5m")
    }

    @available(iOS 16, *)
    @Test("When the delay elapses then the parameters are the ones captured at foreground time", .timeLimit(.minutes(1)))
    func whenDelayElapsesThenParametersAreCapturedAtForegroundTime() {
        let delay = ManualDelay()
        let (sut, collector) = makeSUT(thresholdSeconds: 900, delay: delay)

        sut.recordAppForeground(lastBackgroundDate: backgroundDate(secondsAgo: 1000),
                                launchAction: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: false))
        delay.elapse()

        #expect(collector.fired.first?.params["idle_threshold_seconds"] == "900")
        #expect(collector.fired.first?.params["exceeded_idle_threshold"] == "true")
    }

    // MARK: - Launch source

    @available(iOS 16, *)
    @Test("Launch actions map to the expected launch_source values", .timeLimit(.minutes(1)))
    func launchSourceMapping() throws {
        #expect(DefaultAppReturnInstrumentation.launchSource(for: .standardLaunch(lastBackgroundDate: nil, isFirstForeground: true)) == "standard")
        let url = try #require(URL(string: "https://duckduckgo.com"))
        #expect(DefaultAppReturnInstrumentation.launchSource(for: .openURL(url)) == "url")
        #expect(DefaultAppReturnInstrumentation.launchSource(for: .handleUserActivity(NSUserActivity(activityType: "test"))) == "user_activity")
    }
}

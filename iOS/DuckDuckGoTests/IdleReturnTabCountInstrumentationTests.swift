//
//  IdleReturnTabCountInstrumentationTests.swift
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

@Suite("Idle Return Tab Count Instrumentation")
struct IdleReturnTabCountInstrumentationTests {

    private final class PixelCollector {
        var fired: [(name: String, params: [String: String])] = []
    }

    private func makeSUT(
        featureAvailable: Bool = true,
        effectiveOption: AfterInactivityOption = .newTab
    ) -> (DefaultIdleReturnTabCountInstrumentation, PixelCollector) {
        let eligibility = MockIdleReturnEligibilityManager()
        eligibility.isFeatureAvailableResult = featureAvailable
        eligibility.effectiveAfterInactivityOptionResult = effectiveOption
        let collector = PixelCollector()
        let sut = DefaultIdleReturnTabCountInstrumentation(
            eligibilityManager: eligibility,
            fireDaily: { event, params in
                collector.fired.append((event.name, params))
            })
        return (sut, collector)
    }

    // MARK: - Eligibility gating

    @available(iOS 16, *)
    @Test("When feature unavailable then no pixel is fired", .timeLimit(.minutes(1)))
    func whenFeatureUnavailableThenFiresNothing() {
        let (sut, collector) = makeSUT(featureAvailable: false, effectiveOption: .newTab)
        sut.recordAppForeground(tabs: [Tab(), Tab()], browsingMode: "normal")
        #expect(collector.fired.isEmpty)
    }

    @available(iOS 16, *)
    @Test("When feature unavailable then last-used-tab setting also fires nothing", .timeLimit(.minutes(1)))
    func whenFeatureUnavailableLastUsedTabFiresNothing() {
        let (sut, collector) = makeSUT(featureAvailable: false, effectiveOption: .lastUsedTab)
        sut.recordAppForeground(tabs: [Tab(), Tab()], browsingMode: "normal")
        #expect(collector.fired.isEmpty)
    }

    // MARK: - Pixel selection by setting

    @available(iOS 16, *)
    @Test("When setting is New Tab then fires the idle_ntp pixel", .timeLimit(.minutes(1)))
    func whenSettingNewTabThenFiresNTPPixel() {
        let (sut, collector) = makeSUT(effectiveOption: .newTab)
        sut.recordAppForeground(tabs: [Tab()], browsingMode: "normal")
        #expect(collector.fired.count == 1)
        #expect(collector.fired.first?.name == Pixel.Event.appOpenTabCountIdleNTPDaily.name)
    }

    @available(iOS 16, *)
    @Test("When setting is Last Used Tab then fires the idle_last_tab pixel", .timeLimit(.minutes(1)))
    func whenSettingLastUsedTabThenFiresLastTabPixel() {
        let (sut, collector) = makeSUT(effectiveOption: .lastUsedTab)
        sut.recordAppForeground(tabs: [Tab()], browsingMode: "normal")
        #expect(collector.fired.count == 1)
        #expect(collector.fired.first?.name == Pixel.Event.appOpenTabCountIdleLastTabDaily.name)
    }

    // MARK: - Parameter content

    @available(iOS 16, *)
    @Test("Fires expected parameter keys and bucket values", .timeLimit(.minutes(1)))
    func paramsIncludeExpectedKeysAndBuckets() throws {
        let (sut, collector) = makeSUT(effectiveOption: .newTab)
        sut.recordAppForeground(tabs: [Tab(), Tab(), Tab()], browsingMode: "fire")

        let params = try #require(collector.fired.first?.params)
        #expect(params["tab_count"] == "2-5")
        #expect(params["new_tab_count"] == "2-10")
        #expect(params["tab_active_7d"] == "0")
        #expect(params["tab_inactive_1w"] == "0")
        #expect(params["tab_inactive_2w"] == "0")
        #expect(params["tab_inactive_3w"] == "0")
        #expect(params[PixelParameters.browsingMode] == "fire")
    }

    @available(iOS 16, *)
    @Test("Browsing mode parameter passes through verbatim", .timeLimit(.minutes(1)))
    func browsingModeParameterPassesThrough() {
        let (sut, collector) = makeSUT(effectiveOption: .lastUsedTab)
        sut.recordAppForeground(tabs: [Tab()], browsingMode: "normal")
        #expect(collector.fired.first?.params[PixelParameters.browsingMode] == "normal")
    }

    // MARK: - Multiple invocations (no throttling here — that's DailyPixel's job)

    @available(iOS 16, *)
    @Test("Each call fires once; daily throttling is delegated to DailyPixel", .timeLimit(.minutes(1)))
    func eachCallFiresOnceThrottlingIsDelegated() {
        let (sut, collector) = makeSUT(effectiveOption: .newTab)
        sut.recordAppForeground(tabs: [Tab()], browsingMode: "normal")
        sut.recordAppForeground(tabs: [Tab()], browsingMode: "normal")
        #expect(collector.fired.count == 2)
    }
}

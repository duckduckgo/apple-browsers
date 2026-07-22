//
//  EventHubTests.swift
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

import Testing
import Foundation
@testable import EventHub

@Suite("EventHub")
struct EventHubTests {
    static let pixel1 = "webTelemetry_testPixel1"

    static let dayConfig = """
    { "telemetry": { "webTelemetry_testPixel1": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 86400 } },
        "parameters": { "count": { "template": "counter", "source": "test", "buckets": {
            "0":     {"gte": 0,  "lt": 1},
            "1-2":   {"gte": 1,  "lt": 3},
            "3-5":   {"gte": 3,  "lt": 6},
            "6-10":  {"gte": 6,  "lt": 11},
            "11-20": {"gte": 11, "lt": 21},
            "21-39": {"gte": 21, "lt": 40},
            "40+":   {"gte": 40}
        } } }
    } } }
    """

    // MARK: Event handling

    @Test("handleWebEvent increments the matching counter")
    func handleWebEventIncrementsMatchingCounter() {
        let f = EventHubFixture.active(Self.dayConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())
        #expect(f.count(of: Self.pixel1) == 1)
    }

    @Test("handleWebEvent ignores an unknown event type")
    func handleWebEventIgnoresUnknownEventType() {
        let f = EventHubFixture.active(Self.dayConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("unrelated"), tabID: .new())
        #expect(f.count(of: Self.pixel1) == 0)
    }

    @Test("handleWebEvent ignores events while the feature is disabled")
    func handleWebEventIgnoresEventsWhenFeatureDisabled() {
        let f = EventHubFixture.active(Self.dayConfig)
        f.setEnabled(false)
        f.manager.onConfigChanged()
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())
        #expect(f.state(of: Self.pixel1) == nil)
    }

    @Test("handleWebEvent does not increment through the max bucket")
    func handleWebEventDoesNotIncrementThroughMaxBucket() throws {
        let f = EventHubFixture.active(Self.dayConfig)
        // 41 distinct-tab events drive the counter to the open-ended "40+" bucket and set stopCounting.
        for _ in 0..<41 {
            f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())
        }
        let state = try #require(f.state(of: Self.pixel1))
        #expect(state.params["count"]?.stopCounting == true)
        #expect(state.params["count"]?.value == 40)
    }

    @Test("firing resets the counter for the next period")
    func firingResetsTheCounterForTheNextPeriod() {
        let f = EventHubFixture.active(Self.dayConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())

        f.advance(by: 86400)

        #expect(f.count(of: Self.pixel1) == 0)
    }

    // MARK: Per-tab de-duplication

    @Test("same tab, same source is deduplicated")
    func sameTabSameSourceIsDeduplicated() {
        let f = EventHubFixture.active(Self.dayConfig)
        let tab = EventHubTabID.new()
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)
        #expect(f.count(of: Self.pixel1) == 1)
    }

    @Test("navigation to a new URL resets dedup")
    func navigationToNewURLResetsDedup() {
        let f = EventHubFixture.active(Self.dayConfig)
        let tab = EventHubTabID.new()
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)
        f.manager.onNavigationStarted(tabID: tab, url: "https://example.com/page1")
        f.manager.onNavigationStarted(tabID: tab, url: "https://example.com/page2")
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)
        #expect(f.count(of: Self.pixel1) == 2)
    }

    @Test("reloading the same URL does not reset dedup")
    func reloadSameURLDoesNotResetDedup() {
        let f = EventHubFixture.active(Self.dayConfig)
        let tab = EventHubTabID.new()
        f.manager.onNavigationStarted(tabID: tab, url: "https://example.com/page")
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)
        f.manager.onNavigationStarted(tabID: tab, url: "https://example.com/page")
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)
        #expect(f.count(of: Self.pixel1) == 1)
    }

    @Test("different tabs count independently")
    func differentTabsCountIndependently() {
        let f = EventHubFixture.active(Self.dayConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())
        #expect(f.count(of: Self.pixel1) == 2)
    }

    @Test("closing a tab clears its dedup state")
    func closingATabClearsItsDedupState() {
        let f = EventHubFixture.active(Self.dayConfig)
        let tab = EventHubTabID.new()
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab) // deduped within the tab

        f.manager.onTabClosed(tabID: tab)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)

        #expect(f.count(of: Self.pixel1) == 2)
    }

    // MARK: Firing, buckets and attributionPeriod

    @Test("timer fires the pixel with a bucketed count and attribution period")
    func timerFiresPixelWithBucketedCountAndAttributionPeriod() throws {
        let f = EventHubFixture.active(Self.dayConfig)
        let tab = EventHubTabID.new()
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab)
        f.manager.onNavigationStarted(tabID: tab, url: "https://example.com/2")
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: tab) // count = 2 -> bucket "1-2"

        f.advance(by: 86400)

        #expect(f.fired.count == 1)
        let pixel = try #require(f.fired.first)
        #expect(pixel.name == Self.pixel1)
        #expect(pixel.parameters["count"] == "1-2")
        #expect(pixel.parameters["attributionPeriod"] == EventHubFixture.expectedAttribution(periodSeconds: 86400))
    }

    @Test("does not fire before the period has elapsed")
    func doesNotFireBeforePeriodElapsed() {
        let f = EventHubFixture.active(Self.dayConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())
        f.advance(by: 86400 - 1)
        #expect(f.fired.isEmpty)
    }

    @Test("skips firing when no bucket matches")
    func skipsFiringWhenNoBucketMatches() {
        // Buckets start at 5, so a zero count matches nothing and no pixel is fired.
        let config = """
        { "telemetry": { "p": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 60 } },
            "parameters": { "count": { "template": "counter", "source": "test", "buckets": {"5-9": {"gte": 5, "lt": 10}} } }
        } } }
        """
        let f = EventHubFixture.active(config)
        f.advance(by: 60)
        #expect(f.fired.isEmpty)
    }

    @Test("resets state and starts a new period after firing")
    func resetsStateAndStartsNewPeriodAfterFiring() throws {
        let f = EventHubFixture.active(Self.dayConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())

        f.advance(by: 86400)

        // A new period exists at count 0, started from "now" (= the old period end).
        let state = try #require(f.state(of: Self.pixel1))
        #expect(state.params["count"]?.value == 0)
        #expect(state.periodStartMillis == Int64(EventHubFixture.start.addingTimeInterval(86400).timeIntervalSince1970 * 1000))
    }

    @Test("scheduled timer fires a zero-count pixel")
    func scheduledTimerFiresZeroCountPixel() throws {
        let f = EventHubFixture.active(Self.dayConfig)
        f.advance(by: 86400)
        // count 0 maps to the "0" bucket, so a pixel still fires.
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["count"] == "0")
    }

    @Test("attributionPeriod for an hourly period is the start of the hour")
    func attributionPeriodForHourlyPeriodIsStartOfHour() {
        let hourly = """
        { "telemetry": { "p": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 3600 } },
            "parameters": { "count": { "template": "counter", "source": "test", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """
        let f = EventHubFixture.active(hourly)
        f.advance(by: 3600)
        #expect(f.fired.first?.parameters["attributionPeriod"] == EventHubFixture.expectedAttribution(periodSeconds: 3600))
    }

    // MARK: Config-snapshot isolation

    @Test("a running period uses its stored config source, not the live one")
    func runningPeriodUsesStoredConfigSourceNotLive() {
        let f = EventHubFixture.active(Self.dayConfig)

        // Change the live config's source mid-period; the running period keeps the original "test" source.
        f.setSettings(Self.dayConfig.replacingOccurrences(of: "\"source\": \"test\"", with: "\"source\": \"changed\""))
        f.manager.onConfigChanged()

        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())
        f.manager.handleWebEvent(EventHubFixture.webEvent("changed"), tabID: .new())

        #expect(f.count(of: Self.pixel1) == 1)
    }

    @Test("a new period after firing uses the latest config")
    func newPeriodAfterFiringUsesLatestConfig() {
        let f = EventHubFixture.active(Self.dayConfig)

        f.setSettings(Self.dayConfig.replacingOccurrences(of: "\"source\": \"test\"", with: "\"source\": \"changed\""))
        f.manager.onConfigChanged()
        f.advance(by: 86400)

        f.manager.handleWebEvent(EventHubFixture.webEvent("changed"), tabID: .new())

        #expect(f.count(of: Self.pixel1) == 1)
    }

    // MARK: onConfigChanged lifecycle

    @Test("onConfigChanged initialises new pixels")
    func onConfigChangedInitialisesNewPixels() throws {
        let f = EventHubFixture.active(Self.dayConfig)
        let state = try #require(f.state(of: Self.pixel1))
        #expect(state.params["count"]?.value == 0)
    }

    @Test("onConfigChanged deletes all state when the feature is disabled")
    func onConfigChangedDeletesAllStateWhenFeatureDisabled() {
        let f = EventHubFixture.active(Self.dayConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())

        f.setEnabled(false)
        f.manager.onConfigChanged()

        #expect(f.manager.activePixelStates.isEmpty)
    }

    @Test("onConfigChanged does not register a disabled pixel")
    func onConfigChangedDoesNotRegisterDisabledPixel() {
        let disabledPixel = """
        { "telemetry": { "p": {
            "state": "disabled",
            "trigger": { "period": { "seconds": 60 } },
            "parameters": { "count": { "template": "counter", "source": "test", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """
        let f = EventHubFixture.active(disabledPixel)
        #expect(f.manager.activePixelStates.isEmpty)
    }

    @Test("onConfigChanged with no settings registers no pixels")
    func onConfigChangedWithNoSettingsRegistersNoPixels() {
        let f = EventHubFixture.active(Self.dayConfig, hasSettings: false)
        #expect(f.manager.activePixelStates.isEmpty)
    }

    // MARK: Foreground gating

    @Test("a new period is not started while backgrounded")
    func newPeriodIsNotStartedWhileBackgrounded() {
        let f = EventHubFixture.background(Self.dayConfig)
        f.manager.onConfigChanged() // config arrives while still backgrounded
        #expect(f.manager.activePixelStates.isEmpty)
    }

    @Test("a timer fires while backgrounded but only starts a new period on foreground")
    func timerFiresWhileBackgroundedButStartsNewPeriodOnlyOnForeground() {
        let f = EventHubFixture.active(Self.dayConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())

        f.manager.onAppBackgrounded()
        f.advance(by: 86400)

        // Pixel fired from the timer, but no new period yet (backgrounded).
        #expect(f.fired.count == 1)
        #expect(f.state(of: Self.pixel1) == nil)

        f.manager.onAppForegrounded()
        #expect(f.state(of: Self.pixel1) != nil)
    }

    // MARK: Restart durability

    @Test("state survives a restart")
    func stateSurvivesARestart() {
        let f = EventHubFixture.active(Self.dayConfig)
        f.manager.handleWebEvent(EventHubFixture.webEvent("test"), tabID: .new())

        // Simulate a restart: a brand-new manager over the same persisted store.
        let restarted = f.restart()

        #expect(restarted.count(of: Self.pixel1) == 1)
    }

    // MARK: Config removal / consent revocation

    @Test("removing a config tears down its active period and fires nothing")
    func removingAConfigTearsDownItsActivePeriodAndFiresNothing() throws {
        let json = """
        { "telemetry": { "gated_pixel": {
            "state": "enabled",
            "trigger": { "type": "period", "period": { "seconds": 86400 } },
            "parameters": { "count": { "template": "counter", "source": "youtube_adBlocker",
                "buckets": { "0": { "gte": 0, "lt": 1 }, "1+": { "gte": 1 } } } } } } }
        """
        let f = EventHubFixture.active(json)

        f.manager.handleWebEvent(EventHubFixture.webEvent("youtube_adBlocker"), tabID: .new())
        #expect(f.state(of: "gated_pixel") != nil)

        // Let the write-behind flush persist the period, so the post-teardown assertion is meaningful.
        f.advance(by: EventHubFixture.writeBehindFlush)
        #expect(f.repository.pixelState(named: "gated_pixel") != nil)

        // Config vanishes (consent withdrawn / removed remotely).
        f.setSettings(#"{ "telemetry": { } }"#)
        f.manager.onConfigChanged()

        #expect(f.state(of: "gated_pixel") == nil)                       // active state gone
        #expect(f.repository.pixelState(named: "gated_pixel") == nil)    // persisted state deleted

        // Advancing past the original period must not resurrect or fire it.
        f.advance(by: 86400 + 1)
        #expect(f.fired.isEmpty)
    }

    // MARK: Robustness

    @Test("a corrupt stored config is skipped on load and a fresh period starts")
    func corruptStoredConfigIsSkippedOnLoadAndAFreshPeriodStarts() throws {
        let f = EventHubFixture.background(Self.dayConfig)
        f.plantCorruptState(Self.pixel1)

        // On start the corrupt persisted state is skipped (not a crash); the manager recovers by
        // starting a fresh period at count 0.
        f.manager.onAppForegrounded()
        f.manager.onConfigChanged()

        #expect(f.state(of: Self.pixel1)?.params["count"]?.value == 0)
    }
}

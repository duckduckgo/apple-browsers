//
//  DeduplicationSpecTests.swift
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

/// Apple's coverage of the cross-platform de-duplication specification
/// (`docs/event-hub/tests/deduplication.md` in `duckduckgo/ddg-workflow`). Each case ID from that
/// document leads the test name so coverage is greppable and a failure names the spec case.
///
/// **Complete case roster.** Every ID the document defines appears below, so this file can be diffed
/// against the document in one place:
///
/// - One decision before fan-out — D-DEL-1, D-DEL-2, D-DEL-3, D-DEL-4, D-DEL-5, D-DEL-6
/// - Navigation resets the page — D-NAV-1, D-NAV-2, D-NAV-3, D-NAV-4
/// - Native events are exempt — D-NAT-1
///
/// The properties the cases evidence:
/// - **D-DEL-P1** — for every web event the hub makes exactly one de-duplication decision at
///   ingestion, keyed `(event type, event data, tab)` against the tab's current page, before any
///   handler is invoked. The first occurrence of a key on a page goes to every handler, later ones to
///   none. Payloads equal as JSON values are one key.
/// - **D-NAV-P1** — that state is scoped to a tab's *current* page: cleared on navigation to a
///   different URL, untouched by a same-URL reload, independent between tabs.
/// - **D-NAT-P1** — events with no tab context are never de-duplicated.
///
/// De-duplication is observed through telemetry pixels, per the suite's assertion-boundary
/// convention: the immediate pixels are the direct delivery observer (one pixel per delivered event)
/// and `dedupProbe_day` is a counter on the same stream, showing the fan-out sharing one decision.
@Suite("Spec: hub de-duplication")
struct DeduplicationSpecTests {

    /// The specification's fixture, verbatim. `dedupProbe_day` deliberately has **no zero bucket**, so
    /// it is silent in any case where nothing was counted.
    static let config = """
    { "telemetry": {
        "dedupProbe_immediate": {
            "state": "enabled",
            "trigger": { "type": "immediate_v2", "source": "probeDetected" },
            "parameters": { "reason": { "template": "data", "dataKey": "reason" } }
        },
        "dedupProbe_day": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "count": { "template": "counter", "source": "probeDetected", "buckets": {
                "1":  {"gte": 1, "lt": 2},
                "2":  {"gte": 2, "lt": 3},
                "3+": {"gte": 3}
            } } }
        },
        "dedupOther_immediate": {
            "state": "enabled",
            "trigger": { "type": "immediate_v2", "source": "otherDetected" },
            "parameters": { "reason": { "template": "data", "dataKey": "reason" } }
        },
        "dedupAppLaunch_immediate": {
            "state": "enabled",
            "trigger": { "type": "immediate_v2", "source": "appLaunch" },
            "parameters": { "launchType": { "template": "data", "dataKey": "launchType" } }
        }
    } }
    """

    static let periodSeconds: TimeInterval = 86400

    // MARK: One decision before fan-out

    @Test("D-DEL-1: repeated occurrences on one page are delivered once")
    func repeatedOccurrencesOnOnePageAreDeliveredOnce() {
        let f = SpecFixture(Self.config)
        let page = f.openPage()
        // Three frames of one page each report the same thing; the hub sees three identical events.
        f.send("probeDetected", reason: "overlay", on: page)
        f.send("probeDetected", reason: "overlay", on: page)
        f.send("probeDetected", reason: "overlay", on: page)

        f.endPeriod()

        #expect(f.fired == [
            "dedupProbe_day?count=1",
            #"dedupProbe_immediate?reason="overlay""#,
        ])
    }

    @Test("D-DEL-2: the payload is part of the key")
    func thePayloadIsPartOfTheKey() {
        let f = SpecFixture(Self.config)
        let page = f.openPage()
        f.send("probeDetected", reason: "overlay", on: page)
        f.send("probeDetected", reason: "redirect", on: page)

        f.endPeriod()

        #expect(f.fired == [
            "dedupProbe_day?count=2",
            #"dedupProbe_immediate?reason="overlay""#,
            #"dedupProbe_immediate?reason="redirect""#,
        ])
    }

    @Test("D-DEL-3: event types de-duplicate independently")
    func eventTypesDeduplicateIndependently() {
        let f = SpecFixture(Self.config)
        let page = f.openPage()
        f.send("probeDetected", reason: "overlay", on: page)
        f.send("otherDetected", reason: "overlay", on: page)
        f.send("probeDetected", reason: "overlay", on: page)

        f.endPeriod()

        #expect(f.fired == [
            #"dedupOther_immediate?reason="overlay""#,
            "dedupProbe_day?count=1",
            #"dedupProbe_immediate?reason="overlay""#,
        ])
    }

    @Test("D-DEL-4: every handler observes the same single delivery")
    func everyHandlerObservesTheSameSingleDelivery() {
        // The immediate pixel fires exactly once *and* the counter reports exactly one: both handlers
        // act on one decision rather than each taking their own. The metrics handler's leg of this
        // evidence is the metrics suite, M-DED-1.
        let f = SpecFixture(Self.config)
        let page = f.openPage()
        f.send("probeDetected", reason: "overlay", on: page)
        f.send("probeDetected", reason: "overlay", on: page)

        f.endPeriod()

        #expect(f.fired == [
            "dedupProbe_day?count=1",
            #"dedupProbe_immediate?reason="overlay""#,
        ])
    }

    @Test("D-DEL-5: payload member order does not change the key")
    func payloadMemberOrderDoesNotChangeTheKey() {
        // Built from two JSON strings whose members are written in opposite orders. Swift's
        // `[String: Any]` is unordered, so the *authored* order is already lost by the time the hub
        // sees it — but two dictionaries with the same contents and different insertion history can
        // still iterate differently, so this pins that the key is built from sorted members rather
        // than from iteration order.
        let f = SpecFixture(Self.config)
        let page = f.openPage()
        f.sendRaw("probeDetected", dataJSON: #"{ "reason": "overlay", "stage": 1 }"#, on: page)
        f.sendRaw("probeDetected", dataJSON: #"{ "stage": 1, "reason": "overlay" }"#, on: page)

        f.endPeriod()

        #expect(f.fired == [
            "dedupProbe_day?count=1",
            #"dedupProbe_immediate?reason="overlay""#,
        ])
    }

    @Test("D-DEL-6: an omitted payload and an empty payload are one key")
    func omittedAndEmptyPayloadAreOneKey() {
        let f = SpecFixture(Self.config)
        let page = f.openPage()
        f.sendWithoutData("probeDetected", on: page)
        f.sendRaw("probeDetected", dataJSON: "{}", on: page)

        f.endPeriod()

        // No immediate pixel fires: its only parameter reads `reason`, which resolves to nothing.
        #expect(f.fired == ["dedupProbe_day?count=1"])
    }

    // MARK: Navigation resets the page

    @Test("D-NAV-1: navigating to a different URL makes the next occurrence deliverable")
    func navigatingToADifferentURLMakesTheNextOccurrenceDeliverable() {
        let f = SpecFixture(Self.config)
        let page = f.openPage()
        f.send("probeDetected", reason: "overlay", on: page)
        f.navigate(page, to: "https://example.com/second")
        f.send("probeDetected", reason: "overlay", on: page)
        f.navigate(page, to: "https://example.com/third")
        f.send("probeDetected", reason: "overlay", on: page)

        f.endPeriod()

        #expect(f.fired == [
            "dedupProbe_day?count=3+",
            #"dedupProbe_immediate?reason="overlay""#,
            #"dedupProbe_immediate?reason="overlay""#,
            #"dedupProbe_immediate?reason="overlay""#,
        ])
    }

    @Test("D-NAV-2: a same-URL reload does not start a new page")
    func aSameURLReloadDoesNotStartANewPage() {
        let f = SpecFixture(Self.config)
        let page = f.openPage(url: "https://example.com/first")
        f.send("probeDetected", reason: "overlay", on: page)
        f.navigate(page, to: "https://example.com/first")
        f.send("probeDetected", reason: "overlay", on: page)

        f.endPeriod()

        #expect(f.fired == [
            "dedupProbe_day?count=1",
            #"dedupProbe_immediate?reason="overlay""#,
        ])
    }

    @Test("D-NAV-3: returning to a previously seen URL delivers again")
    func returningToAPreviouslySeenURLDeliversAgain() {
        // State is per current page, not per URL ever seen.
        let f = SpecFixture(Self.config)
        let page = f.openPage(url: "https://example.com/a")
        f.send("probeDetected", reason: "overlay", on: page)
        f.navigate(page, to: "https://example.com/b")
        f.navigate(page, to: "https://example.com/a")
        f.send("probeDetected", reason: "overlay", on: page)

        f.endPeriod()

        #expect(f.fired == [
            "dedupProbe_day?count=2",
            #"dedupProbe_immediate?reason="overlay""#,
            #"dedupProbe_immediate?reason="overlay""#,
        ])
    }

    @Test("D-NAV-4: separate tabs are independent")
    func separateTabsAreIndependent() {
        let f = SpecFixture(Self.config)
        let url = "https://example.com/shared"
        for _ in 0..<3 {
            f.send("probeDetected", reason: "overlay", on: f.openPage(url: url))
        }

        f.endPeriod()

        #expect(f.fired == [
            "dedupProbe_day?count=3+",
            #"dedupProbe_immediate?reason="overlay""#,
            #"dedupProbe_immediate?reason="overlay""#,
            #"dedupProbe_immediate?reason="overlay""#,
        ])
    }

    // MARK: Native events are exempt

    @Test("D-NAT-1: repeated native events are all delivered")
    func repeatedNativeEventsAreAllDelivered() {
        // No tab and no URL, so "once per page" has no meaning: every occurrence is delivered. The
        // counter is a web-event stream and has no zero bucket, so it stays silent.
        let f = SpecFixture(Self.config)
        f.sendNative("appLaunch", payload: ["launchType": "cold"])
        f.sendNative("appLaunch", payload: ["launchType": "warm"])

        f.endPeriod()

        #expect(f.fired == [
            #"dedupAppLaunch_immediate?launchType="cold""#,
            #"dedupAppLaunch_immediate?launchType="warm""#,
        ])
    }
}

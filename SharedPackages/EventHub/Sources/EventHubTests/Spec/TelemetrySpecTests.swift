//
//  TelemetrySpecTests.swift
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

/// Apple's coverage of the cross-platform telemetry specification
/// (`docs/event-hub/tests/telemetry.md` in `duckduckgo/ddg-workflow`), for the cases that exist
/// because telemetry now consumes the hub's de-duplicated stream.
///
/// The properties they evidence:
/// - **T-IMM-P1** — immediate pixels fire once per *delivered* event. Because the hub de-duplicates
///   before fan-out (D-DEL-P1), repeats of an event type carrying the same payload on one page fire
///   once, while each distinct payload fires.
/// - **T-DAT-P1** — a data parameter carries the payload value of the most recent delivered event
///   whose type equals its `source`. Every such event assigns, so an event whose payload lacks the
///   key leaves the parameter with no value, and a parameter with no value is omitted from the pixel.
///
/// The rest of this suite is not de-duplication behaviour and lands with the telemetry conformance
/// pass. Only IDs appearing in a `@Test` name are covered here.
@Suite("Spec: telemetry")
struct TelemetrySpecTests {

    /// The specification's fixture, less the two `state: disabled` entries, which only T-GEN-P1,
    /// T-CNT-4 and T-IMM-3 need. `webTelemetry_adwallDetection_day` deliberately has **no zero
    /// bucket**.
    static let config = """
    { "telemetry": {
        "webTelemetry_captchaDetection_day": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "count": { "template": "counter", "source": "captchaDetected", "buckets": {
                "0": {"gte": 0, "lt": 1}, "1-2": {"gte": 1, "lt": 3}, "3-5": {"gte": 3, "lt": 6}, "6+": {"gte": 6}
            } } }
        },
        "webTelemetry_captchaDetection_week": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 604800 } },
            "parameters": { "count": { "template": "counter", "source": "captchaDetected", "buckets": {
                "0": {"gte": 0, "lt": 1}, "1-2": {"gte": 1, "lt": 3}, "3-5": {"gte": 3, "lt": 6}, "6+": {"gte": 6}
            } } }
        },
        "webTelemetry_adwallDetection_day": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": {
                "count": { "template": "counter", "source": "adwallDetected", "buckets": {
                    "1-2": {"gte": 1, "lt": 3}, "3+": {"gte": 3}
                } },
                "reason": { "template": "data", "source": "adwallDetected", "dataKey": "reason" }
            }
        },
        "webTelemetry_adwallDetection_immediate": {
            "state": "enabled",
            "trigger": { "type": "immediate_v2", "source": "adwallDetected" },
            "parameters": { "reason": { "template": "data", "dataKey": "reason" } }
        }
    } }
    """

    /// Cases observe the day boundary, where the day pixels' current period ends exactly once.
    /// `webTelemetry_captchaDetection_week` is correctly still running at that point and so does not
    /// appear in any expected set below; the week leg of these cases arrives with the counter case
    /// that exercises day and week counters side by side.
    private static func fixture() -> SpecFixture {
        SpecFixture(config, periodSeconds: 86400)
    }

    @Test("T-IMM-1: one immediate pixel per event type and payload per page")
    func oneImmediatePixelPerEventTypeAndPayloadPerPage() {
        // The second occurrence is dropped at the hub (D-DEL-1), so the immediate pixel fires once and
        // the day pixel counts the page once.
        let f = Self.fixture()
        let page = f.openPage()
        f.send("adwallDetected", reason: "overlay", on: page)
        f.send("adwallDetected", reason: "overlay", on: page)

        f.endPeriod()

        #expect(f.fired == [
            #"webTelemetry_adwallDetection_day?count=1-2&reason="overlay""#,
            #"webTelemetry_adwallDetection_immediate?reason="overlay""#,
            "webTelemetry_captchaDetection_day?count=0",
        ])
    }

    @Test("T-IMM-4: distinct payloads on one page each fire")
    func distinctPayloadsOnOnePageEachFire() {
        // Both occurrences are delivered (D-DEL-2), and the day pixel's data parameter keeps the last.
        let f = Self.fixture()
        let page = f.openPage()
        f.send("adwallDetected", reason: "overlay", on: page)
        f.send("adwallDetected", reason: "redirect", on: page)

        f.endPeriod()

        #expect(f.fired == [
            #"webTelemetry_adwallDetection_day?count=1-2&reason="redirect""#,
            #"webTelemetry_adwallDetection_immediate?reason="overlay""#,
            #"webTelemetry_adwallDetection_immediate?reason="redirect""#,
            "webTelemetry_captchaDetection_day?count=0",
        ])
    }

    @Test("T-DAT-2: a matching event without the key leaves no value")
    func aMatchingEventWithoutTheKeyLeavesNoValue() {
        // On distinct pages, so de-duplication does not collapse the two. The second event assigns
        // like any other, and assigns nothing — so the day pixel reports no `reason` at all rather
        // than the first event's. Its own immediate pixel does not fire: the only parameter that
        // pixel declares produces no value.
        let f = Self.fixture()
        f.send("adwallDetected", reason: "overlay", on: f.openPage())
        f.sendRaw("adwallDetected", dataJSON: "{}", on: f.openPage())

        f.endPeriod()

        #expect(f.fired == [
            "webTelemetry_adwallDetection_day?count=1-2",
            #"webTelemetry_adwallDetection_immediate?reason="overlay""#,
            "webTelemetry_captchaDetection_day?count=0",
        ])
    }
}

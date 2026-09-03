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
/// (`docs/event-hub/tests/telemetry.md` in `duckduckgo/ddg-workflow`).
///
/// **Complete case roster.** Every ID the document defines appears below, so this file can be diffed
/// against the document in one place:
///
/// - Counters — T-CNT-1, T-CNT-2, T-CNT-3, T-CNT-4
/// - Data parameters — T-DAT-1, T-DAT-2, T-DAT-3, T-DAT-4, T-DAT-5
/// - Immediate pixels — T-IMM-1, T-IMM-2, T-IMM-3, T-IMM-4
///
/// Several of these arrived here from narrower unit tests, which were deleted rather than annotated in
/// place: keeping every case in one file is what lets the roster above be checked at a glance. Two
/// component-level tests were deliberately left behind in `EventHubDataParameterTests`, covering a
/// `null` data value and the "no parameter resolved, so no fire" guard — neither is a case here.
///
/// The properties they evidence:
/// - **T-GEN-P1** — only pixels enabled in the current config may fire, whatever their trigger type
///   (T-CNT-4, T-IMM-3).
/// - **T-CNT-P1** — counters count events as delivered by the hub, bucket at period end (first match
///   wins) and fire one pixel per period; a pixel whose parameters produce no values does not fire.
/// - **T-DAT-P1** — a data parameter carries the payload value of the most recent delivered event whose
///   type equals its `source`. Every such event assigns, so an event whose payload lacks the key leaves
///   the parameter with no value, and a parameter with no value is omitted.
/// - **T-DAT-P2** — the value survives the round trip: percent-decoding yields compact JSON, and
///   JSON-decoding that yields the payload value exactly.
/// - **T-IMM-P1** — immediate pixels fire once per *delivered* event. Because the hub de-duplicates
///   before fan-out (D-DEL-P1), repeats of an event type carrying the same payload on one page fire
///   once, while each distinct payload fires.
///
/// Out of scope here, and covered by platform unit tests instead: persistence and restart, foreground
/// gating of new periods, multi-period cadence, and mid-cycle config snapshots.
@Suite("Spec: telemetry")
struct TelemetrySpecTests {

    /// The specification's fixture, complete — including the two `state: disabled` entries that
    /// T-GEN-P1, T-CNT-4 and T-IMM-3 need. `webTelemetry_adwallDetection_day` deliberately has **no
    /// zero bucket**, so it is silent in any case where nothing was counted, and
    /// `webTelemetry_disabledPixel_day` deliberately has a catch-all one, so its silence can only be
    /// explained by its state.
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
        },
        "webTelemetry_disabledPixel_day": {
            "state": "disabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "count": { "template": "counter", "source": "captchaDetected", "buckets": {
                "0+": {"gte": 0}
            } } }
        },
        "webTelemetry_disabledPixel_immediate": {
            "state": "disabled",
            "trigger": { "type": "immediate_v2", "source": "adwallDetected" },
            "parameters": { "reason": { "template": "data", "dataKey": "reason" } }
        }
    } }
    """

    /// Both the day and the week period end once per `endPeriod()`, so every case states the week leg
    /// alongside the day leg and the expected set stays exhaustive.
    private static func fixture() -> SpecFixture {
        SpecFixture(config, longestPeriodSeconds: 604800)
    }

    /// The captcha counters' contribution when no `captchaDetected` was delivered. Both have a zero
    /// bucket, so both fire; the adwall day pixel has none, so it does not.
    private static let captchaZero = [
        "webTelemetry_captchaDetection_day?count=0",
        "webTelemetry_captchaDetection_week?count=0",
    ]

    /// The value as it reaches the endpoint: EventHub's output encoded once by the transport.
    ///
    /// Uses the same allowed set the pixel transports use — `CharacterSet.urlQueryAllowed` minus the
    /// reserved characters, as `Common`'s `urlQueryParameterAllowed` defines it — so that T-DAT-5 tests
    /// the real round trip rather than a restatement of the seam value. Spelled out here rather than
    /// imported so the test states exactly what it assumes of the transport.
    private static func onTheWire(_ value: String) -> String {
        let reserved = CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(reserved))!
    }

    // MARK: Counters — aggregation and bucketing

    @Test("T-CNT-1: occurrences across pages bucket at period end")
    func occurrencesAcrossPagesBucketAtPeriodEnd() {
        // Distinct pages, so de-duplication does not collapse them. Counters are independent per
        // pixel: the day and the week counter each see all three.
        let f = Self.fixture()
        f.send("captchaDetected", reason: "any", on: f.openPage())
        f.send("captchaDetected", reason: "any", on: f.openPage())
        f.send("captchaDetected", reason: "any", on: f.openPage())

        f.endPeriod()

        #expect(f.fired == [
            "webTelemetry_captchaDetection_day?count=3-5",
            "webTelemetry_captchaDetection_week?count=3-5",
        ])
    }

    @Test("T-CNT-2: a zero count fires when a zero bucket exists")
    func aZeroCountFiresWhenAZeroBucketExists() {
        let f = Self.fixture()

        f.endPeriod()

        #expect(f.fired == Self.captchaZero)
    }

    @Test("T-CNT-3: a count matching no bucket does not fire")
    func aCountMatchingNoBucketDoesNotFire() {
        // The adwall day pixel's lowest bucket starts at 1, so a zero count matches nothing and it
        // does not fire at all — not even with its `reason` parameter, which also resolved nothing.
        let f = Self.fixture()
        f.send("somethingUnrelated", reason: "any", on: f.openPage())

        f.endPeriod()

        #expect(f.fired == Self.captchaZero)
    }

    @Test("T-CNT-4: a disabled pixel never fires")
    func aDisabledPixelNeverFires() {
        // Evidence for T-GEN-P1: `webTelemetry_disabledPixel_day` counts the same source as the captcha
        // pixels and has a catch-all bucket, so only its state can explain its silence.
        let f = Self.fixture()
        f.send("captchaDetected", reason: "any", on: f.openPage())

        f.endPeriod()

        #expect(f.fired == [
            "webTelemetry_captchaDetection_day?count=1-2",
            "webTelemetry_captchaDetection_week?count=1-2",
        ])
    }

    // MARK: Data parameters

    @Test("T-DAT-1: the last matching event of the period supplies the value")
    func theLastMatchingEventOfThePeriodSuppliesTheValue() {
        let f = Self.fixture()
        f.send("adwallDetected", reason: "overlay", on: f.openPage())
        f.send("adwallDetected", reason: "redirect", on: f.openPage())

        f.endPeriod()

        #expect(f.fired == [
            #"webTelemetry_adwallDetection_day?count=1-2&reason="redirect""#,
            #"webTelemetry_adwallDetection_immediate?reason="overlay""#,
            #"webTelemetry_adwallDetection_immediate?reason="redirect""#,
        ] + Self.captchaZero)
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
        ] + Self.captchaZero)
    }

    @Test("T-DAT-3: a non-string value is carried as compact JSON")
    func aNonStringValueIsCarriedAsCompactJSON() {
        let f = Self.fixture()
        f.sendRaw("adwallDetected", dataJSON: #"{ "reason": { "a": true } }"#, on: f.openPage())

        f.endPeriod()

        #expect(f.fired == [
            #"webTelemetry_adwallDetection_day?count=1-2&reason={"a":true}"#,
            #"webTelemetry_adwallDetection_immediate?reason={"a":true}"#,
        ] + Self.captchaZero)
        // On the wire that value is `reason=%7B%22a%22%3Atrue%7D`.
        #expect(Self.onTheWire(#"{"a":true}"#) == "%7B%22a%22%3Atrue%7D")
    }

    @Test("T-DAT-4: events of other types leave the value alone")
    func eventsOfOtherTypesLeaveTheValueAlone() {
        // Only an event whose type equals the parameter's `source` assigns, so the captcha event
        // leaves `reason` holding the adwall event's value while still counting itself.
        let f = Self.fixture()
        f.send("adwallDetected", reason: "overlay", on: f.openPage())
        f.send("captchaDetected", reason: "any", on: f.openPage())

        f.endPeriod()

        #expect(f.fired == [
            #"webTelemetry_adwallDetection_day?count=1-2&reason="overlay""#,
            #"webTelemetry_adwallDetection_immediate?reason="overlay""#,
            "webTelemetry_captchaDetection_day?count=1-2",
            "webTelemetry_captchaDetection_week?count=1-2",
        ])
    }

    @Test("T-DAT-5: a value is encoded once on the wire")
    func aValueIsEncodedOnceOnTheWire() {
        // Evidence for T-DAT-P2, asserted as the two-step round trip the property states. EventHub
        // emits compact JSON and applies no encoding of its own, so the transport's single encoding is
        // the only one: percent-decoding what the endpoint receives yields the compact JSON, and
        // JSON-decoding that yields the payload value exactly.
        //
        // This is the case that caught the double encoding: `DataParameter` used to percent-encode as
        // well, and because `%` is absent from the transports' allowed set the escapes were re-escaped,
        // so `reason` arrived as `%2522overlay%2522` and one decode did not recover the payload.
        let f = Self.fixture()
        f.send("adwallDetected", reason: "overlay", on: f.openPage())

        f.endPeriod()

        #expect(f.fired == [
            #"webTelemetry_adwallDetection_day?count=1-2&reason="overlay""#,
            #"webTelemetry_adwallDetection_immediate?reason="overlay""#,
        ] + Self.captchaZero)
        // Step 1: percent-decoding the parameter the endpoint received yields the compact JSON.
        let onTheWire = Self.onTheWire(#""overlay""#)
        #expect(onTheWire == "%22overlay%22")
        #expect(onTheWire.removingPercentEncoding == #""overlay""#)
        // Step 2: JSON-decoding that yields the payload value from the event exactly.
        let decoded = try? JSONDecoder().decode(String.self, from: Data(#""overlay""#.utf8))
        #expect(decoded == "overlay")
    }

    // MARK: Immediate pixels

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
        ] + Self.captchaZero)
    }

    @Test("T-IMM-2: an event with no matching immediate trigger fires nothing immediately")
    func anEventWithNoMatchingImmediateTriggerFiresNothingImmediately() {
        // No immediate pixel is triggered by `captchaDetected`, and the expected set being exhaustive
        // is what asserts that: the counters report the event at period end and nothing fires inline.
        let f = Self.fixture()
        f.send("captchaDetected", reason: "any", on: f.openPage())

        f.endPeriod()

        #expect(f.fired == [
            "webTelemetry_captchaDetection_day?count=1-2",
            "webTelemetry_captchaDetection_week?count=1-2",
        ])
    }

    @Test("T-IMM-3: a disabled immediate pixel never fires")
    func aDisabledImmediatePixelNeverFires() {
        // Evidence for T-GEN-P1 on the immediate leg: `webTelemetry_disabledPixel_immediate` shares
        // the trigger and the parameter, so only its state can explain its silence.
        let f = Self.fixture()
        f.send("adwallDetected", reason: "overlay", on: f.openPage())

        f.endPeriod()

        #expect(f.fired == [
            #"webTelemetry_adwallDetection_day?count=1-2&reason="overlay""#,
            #"webTelemetry_adwallDetection_immediate?reason="overlay""#,
        ] + Self.captchaZero)
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
        ] + Self.captchaZero)
    }
}

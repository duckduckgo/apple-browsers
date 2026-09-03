//
//  EventHubNativeIngressTests.swift
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
@testable import EventHub

@Suite("EventHub native ingress")
struct EventHubNativeIngressTests {
    static let pixel1 = "webTelemetry_testPixel1"

    static let immediateConfig = """
    { "telemetry": { "webEvent_impression": {
        "state": "enabled",
        "trigger": { "type": "immediate_v2", "source": "impression" },
        "parameters": {}
    } } }
    """

    static let immediateDataConfig = """
    { "telemetry": { "webEvent_login": {
        "state": "enabled",
        "trigger": { "type": "immediate_v2", "source": "login" },
        "parameters": { "loginState": { "template": "data", "dataKey": "loginState" } }
    } } }
    """

    static let periodConfig = """
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

    // One immediate pixel and one period counter sharing the same source ("test"), so a single native
    // event can be shown to reach both trigger types.
    static let bothConfig = """
    { "telemetry": {
        "imm": { "state": "enabled", "trigger": { "type": "immediate_v2", "source": "test" }, "parameters": {} },
        "per": { "state": "enabled", "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "count": { "template": "counter", "source": "test", "buckets": { "0": {"gte": 0, "lt": 1}, "1+": {"gte": 1} } } } }
    } }
    """

    static let periodDataConfig = """
    { "telemetry": { "yt": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 60 } },
        "parameters": {
            "count": { "template": "counter", "source": "yt", "buckets": {"0-9": {"gte": 0, "lt": 10}, "10+": {"gte": 10}} },
            "loginState": { "template": "data", "source": "yt", "dataKey": "loginState" }
        }
    } } }
    """

    /// A native event payload, for the cases that check one reaches `data`-template parameters.
    private struct LoginPayload: Encodable { let loginState: String }

    /// A payload whose encoding throws, to exercise the serialisation fail-safe.
    private struct ThrowingData: Encodable {
        func encode(to encoder: Encoder) throws {
            throw NSError(domain: "EventHubNativeIngressTests", code: -1)
        }
    }

    @Test("handleNativeEvent fires the matching immediate pixel")
    func handleNativeEventFiresMatchingImmediatePixel() {
        let f = EventHubFixture.active(Self.immediateConfig)
        f.manager.handleNativeEvent("impression")
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.name == "webEvent_impression")
    }

    @Test("handleNativeEvent forwards the data object to data-template params")
    func handleNativeEventForwardsDataObject() {
        let f = EventHubFixture.active(Self.immediateDataConfig)
        f.manager.handleNativeEvent("login", data: LoginPayload(loginState: "logged-in"))
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["loginState"] == "%22logged-in%22")
    }

    @Test("handleNativeEvent reaches every handler")
    func handleNativeEventReachesEveryHandler() {
        // The positive statement of D-NAT-P1: a native occurrence is delivered to *every* handler, so
        // one call both fires the immediate pixel and counts the period counter. This replaces the pair
        // of tests that used to pin the opposite — that `handleImmediateEvent` skipped counters and
        // `handleAggregatedEvent` skipped immediate pixels — a split no caller ever used.
        let f = EventHubFixture.active(Self.bothConfig)
        f.manager.handleNativeEvent("test")
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.name == "imm")
        #expect(f.count(of: "per") == 1)
    }

    @Test("handleNativeEvent increments the matching counter")
    func handleNativeEventIncrementsMatchingCounter() {
        let f = EventHubFixture.active(Self.periodConfig)
        f.manager.handleNativeEvent("test")
        #expect(f.count(of: Self.pixel1) == 1)
    }

    @Test("handleNativeEvent counts every call with no per-tab dedup")
    func handleNativeEventCountsEveryCallNoDedup() {
        // No tab context means no page to de-duplicate against, so every occurrence counts (D-NAT-P1).
        let f = EventHubFixture.active(Self.periodConfig)
        f.manager.handleNativeEvent("test")
        f.manager.handleNativeEvent("test")
        f.manager.handleNativeEvent("test")
        #expect(f.count(of: Self.pixel1) == 3)
    }

    @Test("handleNativeEvent stops at the open-ended bucket")
    func handleNativeEventStopsAtOpenEndedBucket() throws {
        let f = EventHubFixture.active(Self.periodConfig)
        for _ in 0..<45 {
            f.manager.handleNativeEvent("test")
        }
        let state = try #require(f.state(of: Self.pixel1))
        #expect(state.params["count"]?.value == 40)
        #expect(state.params["count"]?.stopCounting == true)
    }

    @Test("handleNativeEvent records the last data value from a matching source")
    func handleNativeEventRecordsLastDataValue() {
        let f = EventHubFixture.active(Self.periodDataConfig)
        f.manager.handleNativeEvent("yt", data: LoginPayload(loginState: "a"))
        f.manager.handleNativeEvent("yt", data: LoginPayload(loginState: "b"))
        f.advance(by: 60)
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["loginState"] == "%22b%22")
    }

    @Test("handleNativeEvent does nothing when the feature is disabled")
    func handleNativeEventDoesNothingWhenDisabled() {
        let f = EventHubFixture.active(Self.bothConfig, enabled: false)
        f.manager.handleNativeEvent("test")
        #expect(f.fired.isEmpty)
        #expect(f.state(of: "per") == nil)
    }

    @Test("handleNativeEvent does nothing for an unknown or empty type", arguments: ["unknown", ""])
    func handleNativeEventDoesNothingForUnknownOrEmptyType(type: String) {
        let f = EventHubFixture.active(Self.bothConfig)
        f.manager.handleNativeEvent(type)
        #expect(f.fired.isEmpty)
        #expect(f.count(of: "per") == 0)
    }

    @Test("handleNativeEvent ignores unserialisable data and still fires")
    func handleNativeEventIgnoresUnserialisableDataAndStillFires() {
        let f = EventHubFixture.active(Self.immediateConfig)
        f.manager.handleNativeEvent("impression", data: ThrowingData())
        #expect(f.fired.count == 1)
    }
}

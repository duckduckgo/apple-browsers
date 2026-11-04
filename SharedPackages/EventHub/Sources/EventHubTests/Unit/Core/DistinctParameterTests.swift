//
//  DistinctParameterTests.swift
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

@Suite("Distinct parameter")
struct DistinctParameterTests {
    static let pixelName = "distinct_day"

    static let config = """
    { "telemetry": { "\(pixelName)": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 86400 } },
        "parameters": {
            "domains": { "template": "distinct", "source": "domain_seen", "dataKey": "domain", "buckets": {
                "0": {"gte": 0, "lt": 1}, "1-2": {"gte": 1, "lt": 3}, "3-5": {"gte": 3, "lt": 6}, "6+": {"gte": 6} } },
            "events": { "template": "counter", "source": "domain_seen", "buckets": {
                "0": {"gte": 0, "lt": 1}, "1-5": {"gte": 1, "lt": 6}, "6+": {"gte": 6} } }
        }
    } } }
    """

    private func send(_ domain: String, times: Int = 1, to f: EventHubFixture) {
        for _ in 0..<times { f.manager.handleNativeEvent("domain_seen", data: ["domain": domain]) }
    }

    @Test("A value that arrives many times counts once", .timeLimit(.minutes(1)))
    func repeatedValueCountsOnce() throws {
        let f = EventHubFixture.active(Self.config)
        send("a.example", times: 10, to: f)
        send("b.example", times: 4, to: f)

        f.advance(by: 86400)

        let pixel = try #require(f.fired.first { $0.name == Self.pixelName })
        #expect(pixel.parameters["domains"] == "1-2")
        #expect(pixel.parameters["events"] == "6+")
    }

    @Test("A day without events sends the 0 bucket", .timeLimit(.minutes(1)))
    func dayWithoutEvents() throws {
        let f = EventHubFixture.active(Self.config)

        f.advance(by: 86400)

        let pixel = try #require(f.fired.first { $0.name == Self.pixelName })
        #expect(pixel.parameters["domains"] == "0")
    }

    @Test("Events without a string value under the data key are ignored", .timeLimit(.minutes(1)))
    func eventsWithoutValueAreIgnored() throws {
        let f = EventHubFixture.active(Self.config)
        f.manager.handleNativeEvent("domain_seen")
        f.manager.handleNativeEvent("domain_seen", data: ["other": "a.example"])
        f.manager.handleNativeEvent("domain_seen", data: ["domain": 5])
        f.manager.handleNativeEvent("domain_seen", data: ["domain": ""])

        f.advance(by: 86400)

        let pixel = try #require(f.fired.first { $0.name == Self.pixelName })
        #expect(pixel.parameters["domains"] == "0")
    }

    @Test("The set stops growing at the top bucket", .timeLimit(.minutes(1)))
    func setStopsAtTopBucket() throws {
        let f = EventHubFixture.active(Self.config)
        for i in 0..<50 { send("site\(i).example", to: f) }

        let state = try #require(f.state(of: Self.pixelName)?.params["domains"])
        #expect(state.seenValues?.count == 6)
        f.advance(by: 86400)
        let pixel = try #require(f.fired.first { $0.name == Self.pixelName })
        #expect(pixel.parameters["domains"] == "6+")
    }

    @Test("The state keeps hashes, never the values", .timeLimit(.minutes(1)))
    func stateHoldsHashesOnly() throws {
        let f = EventHubFixture.active(Self.config)
        send("secret-site.example", to: f)

        let seen = try #require(f.state(of: Self.pixelName)?.params["domains"]?.seenValues)
        #expect(seen.count == 1)
        #expect(!seen[0].contains("secret"))
        #expect(seen[0].count == 16)
    }

    @Test("The set survives a restart and keeps de-duplicating", .timeLimit(.minutes(1)))
    func setSurvivesRestart() throws {
        let f = EventHubFixture.active(Self.config)
        send("a.example", to: f)
        send("b.example", to: f)
        f.advance(by: EventHubFixture.writeBehindFlush)

        let restarted = f.restart()
        send("a.example", to: restarted)
        send("c.example", to: restarted)

        #expect(restarted.state(of: Self.pixelName)?.params["domains"]?.seenValues?.count == 3)
    }

    @Test("A new period starts with an empty set", .timeLimit(.minutes(1)))
    func newPeriodStartsEmpty() throws {
        let f = EventHubFixture.active(Self.config)
        send("a.example", to: f)
        f.advance(by: 86400)

        send("a.example", to: f)

        #expect(f.state(of: Self.pixelName)?.params["domains"]?.seenValues?.count == 1)
    }

    @Test("State saved before the template existed still decodes", .timeLimit(.minutes(1)))
    func oldStateDecodes() throws {
        let json = #"{"value":3,"stopCounting":false}"#
        let state = try JSONDecoder().decode(ParamState.self, from: Data(json.utf8))
        #expect(state.value == 3)
        #expect(state.seenValues == nil)
    }

    @Test("A distinct parameter without a data key is dropped from the config", .timeLimit(.minutes(1)))
    func missingDataKeyIsDropped() {
        let config = """
        { "telemetry": { "\(Self.pixelName)": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": {
                "domains": { "template": "distinct", "source": "domain_seen", "buckets": { "0": {"gte": 0, "lt": 1}, "1+": {"gte": 1} } },
                "events": { "template": "counter", "source": "domain_seen", "buckets": { "0": {"gte": 0, "lt": 1}, "1+": {"gte": 1} } }
            }
        } } }
        """
        let f = EventHubFixture.active(config)

        #expect(f.state(of: Self.pixelName)?.params["domains"] == nil)
        #expect(f.state(of: Self.pixelName)?.params["events"] != nil)
    }
}

//
//  CPMCoverageTelemetryTests.swift
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

/// The CPM coverage telemetry as defined in the iOS and macOS privacy-configuration overrides (after the build turns
/// `days: 1` into seconds), fed by the native events that `CPMCoverageReporter` sends.
@available(iOS 16, macOS 13, *)
@Suite("CPM coverage telemetry")
struct CPMCoverageTelemetryTests {
    static let pixelName = "autoconsent_cpmCoverage_day"

    static let unhandledBuckets = """
    { "0": {"gte": 0, "lt": 1}, "1-5": {"gte": 1, "lt": 6}, "6-10": {"gte": 6, "lt": 11}, "11-30": {"gte": 11, "lt": 31}, "31+": {"gte": 31} }
    """

    static let pagesBuckets = """
    { "0": {"gte": 0, "lt": 1}, "1-9": {"gte": 1, "lt": 10}, "10-24": {"gte": 10, "lt": 25}, "25-49": {"gte": 25, "lt": 50},
      "50-99": {"gte": 50, "lt": 100}, "100-199": {"gte": 100, "lt": 200}, "200+": {"gte": 200} }
    """

    static let config = """
    { "telemetry": { "\(pixelName)": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 86400 } },
        "parameters": {
            "unhandled": { "template": "counter", "source": "autoconsent_unhandled", "buckets": \(unhandledBuckets) },
            "unhandled_top10k": { "template": "counter", "source": "autoconsent_unhandled_top10k", "buckets": \(unhandledBuckets) },
            "pages": { "template": "counter", "source": "autoconsent_page", "buckets": \(pagesBuckets) },
            "pages_top10k": { "template": "counter", "source": "autoconsent_page_top10k", "buckets": \(pagesBuckets) }
        }
    } } }
    """

    static let otherTelemetryConfig = """
    { "telemetry": { "webTelemetry_other_day": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 86400 } },
        "parameters": { "count": { "template": "counter", "source": "other", "buckets": { "0": {"gte": 0, "lt": 1}, "1+": {"gte": 1} } } }
    } } }
    """

    private func send(_ type: String, times: Int, to f: EventHubFixture) {
        for _ in 0..<times { f.manager.handleNativeEvent(type) }
    }

    @Test("A day without events sends the 0 bucket for every counter", .timeLimit(.minutes(1)))
    func dayWithoutEventsSendsZeroBuckets() throws {
        let f = EventHubFixture.active(Self.config)

        f.advance(by: 86400)

        let pixel = try #require(f.fired.first { $0.name == Self.pixelName })
        #expect(pixel.parameters["unhandled"] == "0")
        #expect(pixel.parameters["unhandled_top10k"] == "0")
        #expect(pixel.parameters["pages"] == "0")
        #expect(pixel.parameters["pages_top10k"] == "0")
    }

    @Test("A day with pages but no unhandled popups sends the 0 unhandled bucket", .timeLimit(.minutes(1)))
    func dayWithZeroUnhandledSendsZeroBucket() throws {
        let f = EventHubFixture.active(Self.config)
        send("autoconsent_page", times: 30, to: f)
        send("autoconsent_page_top10k", times: 12, to: f)

        f.advance(by: 86400)

        let pixel = try #require(f.fired.first { $0.name == Self.pixelName })
        #expect(pixel.parameters["unhandled"] == "0")
        #expect(pixel.parameters["unhandled_top10k"] == "0")
        #expect(pixel.parameters["pages"] == "25-49")
        #expect(pixel.parameters["pages_top10k"] == "10-24")
    }

    @Test("Each counter is bucketed from its own source", .timeLimit(.minutes(1)))
    func countersAreBucketedFromTheirOwnSource() throws {
        let f = EventHubFixture.active(Self.config)
        send("autoconsent_unhandled", times: 7, to: f)
        send("autoconsent_unhandled_top10k", times: 2, to: f)
        send("autoconsent_page", times: 250, to: f)
        send("autoconsent_page_top10k", times: 100, to: f)

        f.advance(by: 86400)

        let pixel = try #require(f.fired.first { $0.name == Self.pixelName })
        #expect(pixel.parameters["unhandled"] == "6-10")
        #expect(pixel.parameters["unhandled_top10k"] == "1-5")
        #expect(pixel.parameters["pages"] == "200+")
        #expect(pixel.parameters["pages_top10k"] == "100-199")
    }

    @Test("Without the telemetry definition the events are neither counted nor sent", .timeLimit(.minutes(1)))
    func withoutDefinitionNothingIsCountedOrSent() {
        let f = EventHubFixture.active(Self.otherTelemetryConfig)
        send("autoconsent_unhandled", times: 3, to: f)
        send("autoconsent_page", times: 3, to: f)

        #expect(f.state(of: Self.pixelName) == nil)
        #expect(f.count(of: "webTelemetry_other_day") == 0)

        f.advance(by: 86400)

        #expect(!f.fired.contains { $0.name == Self.pixelName })
    }
}

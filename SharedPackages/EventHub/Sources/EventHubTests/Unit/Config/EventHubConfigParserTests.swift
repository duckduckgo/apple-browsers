//
//  EventHubConfigParserTests.swift
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

@Suite("EventHubConfigParser")
struct EventHubConfigParserTests {
    static let settings = settingsDictionary("""
    {
        "telemetry": {
            "webTelemetry_testPixel1": {
                "state": "enabled",
                "trigger": {
                    "period": { "seconds": 86400 }
                },
                "parameters": {
                    "count": {
                        "template": "counter",
                        "source": "test",
                        "buckets": {
                            "0":     {"gte": 0,  "lt": 1},
                            "1-2":   {"gte": 1,  "lt": 3},
                            "3-5":   {"gte": 3,  "lt": 6},
                            "6-10":  {"gte": 6,  "lt": 11},
                            "11-20": {"gte": 11, "lt": 21},
                            "21-39": {"gte": 21, "lt": 40},
                            "40+":   {"gte": 40}
                        }
                    }
                }
            }
        }
    }
    """)

    let parser = EventHubConfigParser()

    @Test("settings JSON parses the pixel correctly")
    func settingsJSONParsesPixelCorrectly() {
        let telemetry = parser.parseTelemetry(Self.settings)

        #expect(telemetry.count == 1)
        let pixel = telemetry[0]
        #expect(pixel.isEnabled)
        #expect(pixel.trigger.periodSeconds == 86400)
    }

    @Test("counter parameter with map buckets is parsed correctly")
    func counterParameterWithMapBucketsParsedCorrectly() throws {
        let telemetry = parser.parseTelemetry(Self.settings)
        let param = try #require(telemetry.first?.parameters["count"])

        #expect(param.template == .counter)
        #expect(param.source == "test")
        #expect(param.buckets?.count == 7)
        #expect(param.buckets?.first(where: { $0.name == "0" })?.config == BucketConfig(gte: 0, lt: 1))
        #expect(param.buckets?.first(where: { $0.name == "40+" })?.config == BucketConfig(gte: 40, lt: nil))
    }

    @Test("seconds period parses correctly")
    func secondsPeriodParsesCorrectly() {
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 30 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """)

        #expect(parser.parseTelemetry(json).first?.trigger.periodSeconds == 30)
    }

    @Test("empty JSON returns empty telemetry")
    func emptyJSONReturnsEmptyTelemetry() {
        #expect(parser.parseTelemetry(settingsDictionary("{}")).isEmpty)
    }

    @Test("pixel missing state is skipped")
    func pixelMissingStateIsSkipped() {
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """)

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("bucket missing gte is skipped")
    func bucketMissingGteIsSkipped() {
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"bad": {"lt": 5}} } }
        } } }
        """)

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("buckets are ordered by range, not by JSON key order")
    func bucketsAreOrderedByRangeNotByJSONKeyOrder() throws {
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {
                "40+":   {"gte": 40},
                "0":     {"gte": 0,  "lt": 1},
                "3-5":   {"gte": 3,  "lt": 6},
                "1-2":   {"gte": 1,  "lt": 3}
            } } }
        } } }
        """)

        let buckets = try #require(parser.parseTelemetry(json).first?.parameters["c"]?.buckets)
        #expect(buckets.map(\.name) == ["0", "1-2", "3-5", "40+"])
    }

    @Test("an open-ended bucket is evaluated after a bounded bucket sharing its lower bound")
    func openEndedBucketIsEvaluatedAfterBoundedBucketSharingItsLowerBound() throws {
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {
                "40+":   {"gte": 40},
                "40-49": {"gte": 40, "lt": 50}
            } } }
        } } }
        """)

        let buckets = try #require(parser.parseTelemetry(json).first?.parameters["c"]?.buckets)
        #expect(buckets.map(\.name) == ["40-49", "40+"])
        #expect(BucketCounter.bucketCount(45, buckets: buckets) == "40-49")
    }

    @Test("telemetry that is not an object returns empty")
    func telemetryThatIsNotAnObjectReturnsEmpty() {
        #expect(parser.parseTelemetry([EventHubConfigParser.telemetryKey: "not an object"]).isEmpty)
    }

    @Test("telemetry holding a value JSON cannot represent returns empty")
    func telemetryHoldingUnrepresentableValueReturnsEmpty() {
        // Guards the `isValidJSONObject` check: serialising this would raise an ObjC exception, not throw.
        #expect(parser.parseTelemetry([EventHubConfigParser.telemetryKey: ["pixel": Date()]]).isEmpty)
    }

    @Test("missing telemetry key returns empty telemetry")
    func missingTelemetryKeyReturnsEmptyTelemetry() {
        #expect(parser.parseTelemetry(settingsDictionary(#"{"other": {}}"#)).isEmpty)
    }

    @Test("zero period returns no telemetry")
    func zeroPeriodReturnsNoTelemetry() {
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 0 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """)

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("negative period returns no telemetry")
    func negativePeriodReturnsNoTelemetry() {
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": -10 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """)

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("unknown template is skipped")
    func unknownTemplateIsSkipped() {
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "c": { "template": "unknown_template", "source": "e" } }
        } } }
        """)

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("the retired immediate trigger type is skipped")
    func retiredImmediateTriggerTypeIsSkipped() {
        // `immediate` was renamed to `immediate_v2` when web events began de-duplicating at the hub.
        // Config still written for the old name belongs to clients that fire on every occurrence, so
        // this client must not honour it — see `TelemetryTriggerType`.
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "type": "immediate", "source": "e" },
            "parameters": { "d": { "template": "data", "dataKey": "k" } }
        } } }
        """)

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("the immediate_v2 trigger type is parsed")
    func immediateV2TriggerTypeIsParsed() {
        let json = settingsDictionary("""
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "type": "immediate_v2", "source": "e" },
            "parameters": { "d": { "template": "data", "dataKey": "k" } }
        } } }
        """)

        #expect(parser.parseTelemetry(json).first?.trigger.type == .immediateV2)
    }

    @Test("parseSinglePixelConfig with malformed JSON returns nil")
    func parseSinglePixelConfigWithMalformedJSONReturnsNil() {
        #expect(parser.parseSinglePixelConfig(name: "test", json: "not json") == nil)
    }

    @Test("parseSinglePixelConfig with empty object returns nil")
    func parseSinglePixelConfigWithEmptyObjectReturnsNil() {
        #expect(parser.parseSinglePixelConfig(name: "test", json: "{}") == nil)
    }

    @Test("serializePixelConfig produces valid JSON that round trips")
    func serializePixelConfigProducesValidJSONThatRoundTrips() throws {
        let original = try #require(parser.parseTelemetry(Self.settings).first)

        let json = try #require(parser.serializePixelConfig(original))
        let restored = try #require(parser.parseSinglePixelConfig(name: original.name, json: json))

        #expect(restored.name == original.name)
        #expect(restored.state == original.state)
        #expect(restored.trigger.periodSeconds == original.trigger.periodSeconds)
        #expect(restored.parameters.count == original.parameters.count)
        #expect(restored.parameters["count"]?.source == original.parameters["count"]?.source)
        #expect(restored.parameters["count"]?.buckets?.count == original.parameters["count"]?.buckets?.count)
    }

    // The two below pin the *format*, which the round trip above cannot: it would keep passing if both
    // sides changed together. A config snapshot is persisted by one build and read back by the next, so
    // a change to how the trigger type or parameter template is spelled would discard every in-flight
    // period on upgrade — and these are also the strings remote config authors.
    @Test("parses a config snapshot written by an earlier build")
    func parsesConfigSnapshotWrittenByAnEarlierBuild() throws {
        let stored = """
        {"state":"enabled","trigger":{"type":"period","period":{"seconds":86400}},\
        "parameters":{"count":{"template":"counter","source":"adwall","buckets":{"0":{"gte":0,"lt":1},"1+":{"gte":1}}}}}
        """

        let restored = try #require(parser.parseSinglePixelConfig(name: "webTelemetry_adwalls_day", json: stored))

        #expect(restored.state == "enabled")
        #expect(restored.trigger.type == .period)
        #expect(restored.trigger.periodSeconds == 86400)
        #expect(restored.parameters["count"]?.template == .counter)
        #expect(restored.parameters["count"]?.source == "adwall")
        #expect(restored.parameters["count"]?.buckets?.count == 2)
    }

    @Test("serializes the trigger type and parameter template as the strings config authors")
    func serializesTriggerTypeAndTemplateAsAuthoredStrings() throws {
        let config = TelemetryPixelConfig(
            name: "test",
            state: "enabled",
            trigger: TelemetryTriggerConfig(type: .immediateV2, source: "e"),
            parameters: ["d": TelemetryParameterConfig(template: .data, dataKey: "k")])

        let json = try #require(parser.serializePixelConfig(config))

        #expect(json.contains("\"type\":\"immediate_v2\""))
        #expect(json.contains("\"template\":\"data\""))
    }

    @Test("serializePixelConfig returns non-nil for a valid config")
    func serializePixelConfigReturnsNonNilForValidConfig() {
        let config = TelemetryPixelConfig(
            name: "test",
            state: "enabled",
            trigger: TelemetryTriggerConfig(type: .period, periodSeconds: 86400),
            parameters: ["c": TelemetryParameterConfig(template: .counter, source: "e", buckets: [OrderedBucket(name: "0+", config: BucketConfig(gte: 0))])])

        #expect(parser.serializePixelConfig(config) != nil)
    }

    // MARK: parseMetrics

    /// A flattened request rendered as `metric/event/window/threshold`, so expectations read compactly.
    private func requests(_ json: String, experiment: String = "exp1") -> [String] {
        parser.parseMetrics(experiment: experiment, settingsJSON: json)
            .map { "\($0.metric)/\($0.event)/\($0.windowDays.lowerBound)-\($0.windowDays.upperBound)/\($0.threshold)" }
            .sorted()
    }

    @Test("parseMetrics multiplies windows by thresholds within a group and unions groups")
    func parseMetricsMultipliesWindowsByThresholds() {
        let json = """
        { "metrics": { "searchLike": { "event": "searchPerformed", "conversions": [
            { "windows": [[0, 0], [1, 1]], "thresholds": [1] },
            { "windows": [[0, 7]], "thresholds": [2, 3] } ] } } }
        """
        #expect(requests(json) == [
            "searchLike/searchPerformed/0-0/1",
            "searchLike/searchPerformed/0-7/2",
            "searchLike/searchPerformed/0-7/3",
            "searchLike/searchPerformed/1-1/1",
        ])
    }

    @Test("parseMetrics carries the declaring experiment on every request")
    func parseMetricsCarriesDeclaringExperiment() {
        let json = """
        { "metrics": { "m": { "event": "e", "conversions": [ { "windows": [[0, 7]], "thresholds": [1] } ] } } }
        """
        let parsed = parser.parseMetrics(experiment: "contentScopeExperiment1", settingsJSON: json)
        #expect(parsed == [MetricRequest(experiment: "contentScopeExperiment1", event: "e", metric: "m",
                                         windowDays: 0...7, threshold: 1)])
    }

    @Test("parseMetrics returns nothing when the settings declare no metrics")
    func parseMetricsReturnsNothingWithoutMetricsKey() {
        // The normal case: `metrics` is optional and most experiments declare none.
        #expect(requests("{}").isEmpty)
        #expect(requests(#"{ "controlUrl": "a.json", "treatmentUrl": "b.json" }"#).isEmpty)
    }

    @Test("parseMetrics ignores the other settings a TDS experiment carries")
    func parseMetricsIgnoresOtherSettings() {
        let json = """
        { "controlUrl": "a.json", "treatmentUrl": "b.json",
          "metrics": { "m": { "event": "e", "conversions": [ { "windows": [[0, 7]], "thresholds": [1] } ] } } }
        """
        #expect(requests(json) == ["m/e/0-7/1"])
    }

    @Test("parseMetrics returns nothing for settings that are not JSON")
    func parseMetricsReturnsNothingForMalformedJSON() {
        #expect(requests("not json at all").isEmpty)
    }

    @Test("parseMetrics skips a metric with no event and keeps its siblings")
    func parseMetricsSkipsMetricWithNoEvent() {
        let json = """
        { "metrics": {
            "broken": { "conversions": [ { "windows": [[0, 7]], "thresholds": [1] } ] },
            "fine": { "event": "e", "conversions": [ { "windows": [[0, 7]], "thresholds": [1] } ] }
        } }
        """
        #expect(requests(json) == ["fine/e/0-7/1"])
    }

    @Test("parseMetrics drops an unusable window and keeps the rest", arguments: [
        "[7, 0]",       // inverted: `ClosedRange` would trap
        "[-1, 7]",      // negative day bound
        "[0]",          // not a pair
        "[0, 1, 2]",    // not a pair
    ])
    func parseMetricsDropsUnusableWindow(window: String) {
        let json = """
        { "metrics": { "m": { "event": "e", "conversions": [
            { "windows": [\(window), [0, 7]], "thresholds": [1] } ] } } }
        """
        #expect(requests(json) == ["m/e/0-7/1"])
    }

    @Test("parseMetrics drops a threshold below one", arguments: [0, -1])
    func parseMetricsDropsThresholdBelowOne(threshold: Int) {
        // A threshold below 1 would have the framework convert on every occurrence, so a config typo
        // would become pixel spam.
        let json = """
        { "metrics": { "m": { "event": "e", "conversions": [
            { "windows": [[0, 7]], "thresholds": [\(threshold), 2] } ] } } }
        """
        #expect(requests(json) == ["m/e/0-7/2"])
    }
}

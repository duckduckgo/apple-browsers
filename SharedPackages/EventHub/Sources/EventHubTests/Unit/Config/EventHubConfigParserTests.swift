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

@Suite("EventHubConfigParser", .timeLimit(.minutes(1)))
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

    let parser: EventHubConfigParsing = EventHubConfigParser()

    @Test("settings JSON parses the pixel correctly")
    func settingsJSONParsesPixelCorrectly() {
        let telemetry = parser.parseTelemetry(Self.settings)

        #expect(telemetry.count == 1)
        let pixel = telemetry[0]
        #expect(pixel.isEnabled)
        #expect(pixel.trigger.period?.periodSeconds == 86400)
    }

    @Test("counter parameter with map buckets is parsed correctly")
    func counterParameterWithMapBucketsParsedCorrectly() throws {
        let telemetry = parser.parseTelemetry(Self.settings)
        let param = try #require(telemetry.first?.parameters["count"])

        #expect(param.isCounter)
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

        #expect(parser.parseTelemetry(json).first?.trigger.period?.periodSeconds == 30)
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
        #expect(restored.trigger.period?.periodSeconds == original.trigger.period?.periodSeconds)
        #expect(restored.parameters.count == original.parameters.count)
        #expect(restored.parameters["count"]?.source == original.parameters["count"]?.source)
        #expect(restored.parameters["count"]?.buckets?.count == original.parameters["count"]?.buckets?.count)
    }

    @Test("serializePixelConfig returns non-nil for a valid config")
    func serializePixelConfigReturnsNonNilForValidConfig() {
        let config = TelemetryPixelConfig(
            name: "test",
            state: "enabled",
            trigger: TelemetryTriggerConfig(type: "period", period: TelemetryPeriodConfig(seconds: 86400)),
            parameters: ["c": TelemetryParameterConfig(template: "counter", source: "e", buckets: [OrderedBucket(name: "0+", config: BucketConfig(gte: 0))])])

        #expect(parser.serializePixelConfig(config) != nil)
    }
}

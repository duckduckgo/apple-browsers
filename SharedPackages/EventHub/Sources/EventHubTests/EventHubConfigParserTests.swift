import Testing
import Foundation
@testable import EventHub

@Suite("EventHubConfigParser")
struct EventHubConfigParserTests {
    static let settingsJSON = """
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
    """.data(using: .utf8)!

    let parser: EventHubConfigParsing = EventHubConfigParser()

    @Test("settings JSON parses the pixel correctly")
    func settingsJSONParsesPixelCorrectly() {
        let telemetry = parser.parseTelemetry(Self.settingsJSON)

        #expect(telemetry.count == 1)
        let pixel = telemetry[0]
        #expect(pixel.isEnabled)
        #expect(pixel.trigger.period?.periodSeconds == 86400)
    }

    @Test("counter parameter with map buckets is parsed correctly")
    func counterParameterWithMapBucketsParsedCorrectly() throws {
        let telemetry = parser.parseTelemetry(Self.settingsJSON)
        let param = try #require(telemetry.first?.parameters["count"])

        #expect(param.isCounter)
        #expect(param.source == "test")
        #expect(param.buckets?.count == 7)
        #expect(param.buckets?.first(where: { $0.name == "0" })?.config == BucketConfig(gte: 0, lt: 1))
        #expect(param.buckets?.first(where: { $0.name == "40+" })?.config == BucketConfig(gte: 40, lt: nil))
    }

    @Test("seconds period parses correctly")
    func secondsPeriodParsesCorrectly() {
        let json = """
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 30 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """.data(using: .utf8)!

        #expect(parser.parseTelemetry(json).first?.trigger.period?.periodSeconds == 30)
    }

    @Test("empty JSON returns empty telemetry")
    func emptyJSONReturnsEmptyTelemetry() {
        #expect(parser.parseTelemetry("{}".data(using: .utf8)!).isEmpty)
    }

    @Test("pixel missing state is skipped")
    func pixelMissingStateIsSkipped() {
        let json = """
        { "telemetry": { "test": {
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """.data(using: .utf8)!

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("bucket missing gte is skipped")
    func bucketMissingGteIsSkipped() {
        let json = """
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"bad": {"lt": 5}} } }
        } } }
        """.data(using: .utf8)!

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("malformed JSON returns empty")
    func malformedJSONReturnsEmpty() {
        #expect(parser.parseTelemetry("not valid json".data(using: .utf8)!).isEmpty)
    }

    @Test("missing telemetry key returns empty telemetry")
    func missingTelemetryKeyReturnsEmptyTelemetry() {
        #expect(parser.parseTelemetry(#"{"other": {}}"#.data(using: .utf8)!).isEmpty)
    }

    @Test("zero period returns no telemetry")
    func zeroPeriodReturnsNoTelemetry() {
        let json = """
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 0 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """.data(using: .utf8)!

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("negative period returns no telemetry")
    func negativePeriodReturnsNoTelemetry() {
        let json = """
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": -10 } },
            "parameters": { "c": { "template": "counter", "source": "e", "buckets": {"0+": {"gte": 0}} } }
        } } }
        """.data(using: .utf8)!

        #expect(parser.parseTelemetry(json).isEmpty)
    }

    @Test("unknown template is skipped")
    func unknownTemplateIsSkipped() {
        let json = """
        { "telemetry": { "test": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "c": { "template": "unknown_template", "source": "e" } }
        } } }
        """.data(using: .utf8)!

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
        let original = try #require(parser.parseTelemetry(Self.settingsJSON).first)

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

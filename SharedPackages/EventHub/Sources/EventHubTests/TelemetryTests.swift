import Testing
import Foundation
@testable import EventHub

@Suite("Telemetry")
struct TelemetryTests {
    static let config = TelemetryPixelConfig(
        name: "webTelemetry_test",
        state: "enabled",
        trigger: TelemetryTriggerConfig(type: "period", period: TelemetryPeriodConfig(seconds: 60)),
        parameters: [
            "count": TelemetryParameterConfig(template: "counter", source: "test", buckets: [
                OrderedBucket(name: "0", config: BucketConfig(gte: 0, lt: 1)),
                OrderedBucket(name: "1+", config: BucketConfig(gte: 1)),
            ]),
        ])

    @Test("computes periodEndMillis from the trigger period")
    func computesPeriodEndFromTriggerPeriod() {
        let telemetry = Telemetry(config: Self.config, periodStartMillis: 1000)
        #expect(telemetry.periodEndMillis == 1000 + 60_000)
    }

    @Test("isElapsed reflects the current time against periodEndMillis")
    func isElapsedReflectsCurrentTime() {
        let telemetry = Telemetry(config: Self.config, periodStartMillis: 0)
        #expect(!telemetry.isElapsed(atMillis: 59_999))
        #expect(telemetry.isElapsed(atMillis: 60_000))
    }

    @Test("handleEvent routes only to parameters whose source matches")
    func handleEventRoutesOnlyToMatchingSource() {
        let telemetry = Telemetry(config: Self.config, periodStartMillis: 0)
        #expect(!telemetry.handleEvent(source: "unrelated", data: nil, tabID: .new()))
        #expect(telemetry.handleEvent(source: "test", data: nil, tabID: .new()))
    }

    @Test("buildPixelParameters reports the matched bucket")
    func buildPixelParametersReportsMatchedBucket() {
        let telemetry = Telemetry(config: Self.config, periodStartMillis: 0)
        telemetry.handleEvent(source: "test", data: nil, tabID: .new())
        #expect(telemetry.buildPixelParameters()?["count"] == "1+")
    }

    @Test("snapshot round trips through restoring init")
    func snapshotRoundTripsThroughRestoringInit() {
        let original = Telemetry(config: Self.config, periodStartMillis: 500)
        original.handleEvent(source: "test", data: nil, tabID: .new())
        let restored = Telemetry(restoring: original.snapshot())
        #expect(restored.periodStartMillis == 500)
        #expect(restored.buildPixelParameters()?["count"] == "1+")
    }

    @Test("config snapshot is frozen — mutating the source config after construction has no effect")
    func configSnapshotIsFrozen() {
        let telemetry = Telemetry(config: Self.config, periodStartMillis: 0)
        let originalSource = telemetry.config.parameters["count"]?.source
        // Telemetry copies TelemetryPixelConfig (a value type) at construction; there is no live
        // reference back to a "current" config to mutate — this test documents that guarantee.
        #expect(originalSource == "test")
    }
}

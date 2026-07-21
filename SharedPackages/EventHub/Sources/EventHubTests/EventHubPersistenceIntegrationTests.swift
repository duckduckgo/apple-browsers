import Testing
import Foundation
@testable import EventHub

@Suite("EventHub persistence (real UserDefaults round trip)")
struct EventHubPersistenceIntegrationTests {
    @Test("pixel state survives a real Codable + UserDefaults round trip across repository instances")
    func pixelStateSurvivesRealRoundTripAcrossRepositoryInstances() throws {
        let suiteName = "EventHubPersistenceIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let parser = EventHubConfigParser()
        let config = TelemetryPixelConfig(
            name: "webTelemetry_adwalls_day",
            state: "enabled",
            trigger: TelemetryTriggerConfig(type: "period", period: TelemetryPeriodConfig(seconds: 86400)),
            parameters: [
                "adwallCount": TelemetryParameterConfig(template: "counter", source: "adwall", buckets: [
                    OrderedBucket(name: "0", config: BucketConfig(gte: 0, lt: 1)),
                    OrderedBucket(name: "1", config: BucketConfig(gte: 1, lt: 2)),
                    OrderedBucket(name: "2+", config: BucketConfig(gte: 2)),
                ]),
            ])
        let original = PixelState(pixelName: "webTelemetry_adwalls_day", periodStartMillis: 1000, periodEndMillis: 86_401_000,
                                   config: config, params: ["adwallCount": ParamState(value: 1)])

        // Persist through one repository instance backed by real UserDefaults...
        EventHubKeyValueRepository(store: defaults, parser: parser).savePixelState(original)

        // ...then read it back through a brand-new repository instance over the same UserDefaults
        // suite. A fresh instance holds no in-memory copy, so this forces a real decode from disk-backed
        // storage rather than a cache hit.
        let restored = EventHubKeyValueRepository(store: defaults, parser: parser).pixelState(named: original.pixelName)

        let unwrapped = try #require(restored)
        #expect(unwrapped.pixelName == original.pixelName)
        #expect(unwrapped.periodStartMillis == 1000)
        #expect(unwrapped.periodEndMillis == 86_401_000)
        #expect(unwrapped.params["adwallCount"]?.value == 1)
        #expect(unwrapped.config.name == "webTelemetry_adwalls_day")
        #expect(unwrapped.config.trigger.period?.periodSeconds == 86400)
    }
}

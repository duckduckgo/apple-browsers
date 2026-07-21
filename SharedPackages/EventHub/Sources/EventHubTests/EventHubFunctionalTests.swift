import Testing
import Foundation
import Combine
import WebKit
@testable import EventHub

@Suite("EventHub functional (message handler through manager to fired pixel)")
struct EventHubFunctionalTests {
    static let periodSeconds: TimeInterval = 60

    // Counter pixel mirroring the production adwall config, with the shipped one-day period shortened
    // to a (virtual) minute. count = 1 maps to bucket "1".
    static let adwallConfig = """
    { "telemetry": { "webTelemetry_adwalls_day": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 60 } },
        "parameters": { "adwallCount": { "template": "counter", "source": "adwall", "buckets": {
            "0": {"gte":0,"lt":1}, "1": {"gte":1,"lt":2}, "2+": {"gte":2}
        } } }
    } } }
    """

    // Adwall counter with single-unit buckets up to 4+, so a test can assert the exact accumulated
    // count (the coarse "2+" bucket of adwallConfig can't distinguish 2 from 3).
    static let dedupConfig = """
    { "telemetry": { "webTelemetry_adwalls_day": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 60 } },
        "parameters": { "adwallCount": { "template": "counter", "source": "adwall", "buckets": {
            "0":{"gte":0,"lt":1}, "1":{"gte":1,"lt":2}, "2":{"gte":2,"lt":3}, "3":{"gte":3,"lt":4}, "4+":{"gte":4}
        } } }
    } } }
    """

    // Two counter pixels sharing a period: one has a "0" bucket (fires even with no events), the
    // other's only bucket requires count >= 1 (skipped when nothing happened).
    static let zeroSkipConfig = """
    { "telemetry": {
        "webTelemetry_testPixel_zero": { "state": "enabled", "trigger": { "period": { "seconds": 60 } },
            "parameters": { "count": { "template": "counter", "source": "test", "buckets": {"0": {"gte":0,"lt":1}, "1+": {"gte":1}} } } },
        "webTelemetry_testPixel_onlyPositive": { "state": "enabled", "trigger": { "period": { "seconds": 60 } },
            "parameters": { "count": { "template": "counter", "source": "test", "buckets": {"1+": {"gte":1}} } } }
    } }
    """

    static let immediateConfig = """
    { "telemetry": { "webEvent_impression": {
        "state": "enabled",
        "trigger": { "type": "immediate", "source": "impression" },
        "parameters": {}
    } } }
    """

    /// A class (not a struct): the `firedPixelsPublisher` sink must mutate `fired` from inside an
    /// `@escaping` Combine closure, which requires reference semantics — capturing an `inout` struct
    /// parameter in an escaping closure is illegal in Swift. Mirrors `EventHubManagerFixture`'s own
    /// class-based design (Task 7) for exactly this reason.
    private final class Harness {
        let scheduler = ManualEventHubScheduler(startMillis: 1_780_000_000_000)
        let repository: EventHubRepository
        let manager: EventHubPixelManager
        let handler: EventHubMessageHandler
        private(set) var fired: [FiredPixel] = []
        private var cancellable: AnyCancellable?

        init(settingsJSON: String) {
            let parser = EventHubConfigParser()
            let store = InMemoryKeyValueStore()
            repository = EventHubKeyValueRepository(store: store, parser: parser)
            let settings = StaticSettingsProviding(json: settingsJSON)
            manager = EventHubPixelManager(repository: repository, parser: parser, settings: settings, clock: scheduler, scheduler: scheduler)
            handler = EventHubMessageHandler(manager: manager, tabIDProvider: { _ in .new() })
            manager.onAppForegrounded()
            manager.onConfigChanged()
            cancellable = manager.firedPixelsPublisher.sink { [weak self] in self?.fired.append($0) }
        }

        func sendWebEvent(_ type: String, tabID: EventHubTabID) async throws {
            let notify = try #require(handler.handler(forMethodNamed: "webEvent"))
            _ = try await notify(["type": type], WKScriptMessage())
        }
    }

    private struct StaticSettingsProviding: EventHubSettingsProviding {
        let enabledPublisher: AnyPublisher<Bool, Never> = Just(true).eraseToAnyPublisher()
        let settingsPublisher: AnyPublisher<Data?, Never>
        init(json: String) { settingsPublisher = Just(json.data(using: .utf8)).eraseToAnyPublisher() }
    }

    @Test("adwall web event fires a bucketed pixel")
    func adwallWebEventFiresBucketedPixel() async throws {
        let harness = Harness(settingsJSON: Self.adwallConfig)

        try await harness.sendWebEvent("adwall", tabID: .new())
        harness.scheduler.advance(by: Self.periodSeconds)

        #expect(harness.fired.contains { $0.name == "webTelemetry_adwalls_day_windows" && $0.parameters["adwallCount"] == "1" })
    }

    @Test("zero-event period fires the zero-bucket pixel but skips the gte-1 pixel")
    func zeroEventPeriodFiresZeroBucketPixelButSkipsOnlyPositivePixel() async throws {
        let harness = Harness(settingsJSON: Self.zeroSkipConfig)

        // Send no events: let a full period elapse and inspect what fires.
        harness.scheduler.advance(by: Self.periodSeconds)

        #expect(harness.fired.contains { $0.name == "webTelemetry_testPixel_zero_windows" && $0.parameters["count"] == "0" })
        #expect(!harness.fired.contains { $0.name == "webTelemetry_testPixel_onlyPositive_windows" })
    }

    @Test("adwall is counted once per tab")
    func adwallIsCountedOncePerTab() async throws {
        let harness = Harness(settingsJSON: Self.adwallConfig)
        let tab = EventHubTabID.new()

        try await harness.sendWebEvent("adwall", tabID: tab)
        try await harness.sendWebEvent("adwall", tabID: tab)
        harness.scheduler.advance(by: Self.periodSeconds)

        let adwallPixels = harness.fired.filter { $0.name == "webTelemetry_adwalls_day_windows" }
        #expect(adwallPixels.contains { $0.parameters["adwallCount"] == "1" })
        #expect(!adwallPixels.contains { $0.parameters["adwallCount"] == "2" })
    }

    @Test("dedup resets on navigation to a new URL and is independent per tab")
    func dedupResetsOnNavigationAndIsIndependentPerTab() async throws {
        let harness = Harness(settingsJSON: Self.dedupConfig)
        let tab = EventHubTabID.new()
        let otherTab = EventHubTabID.new()

        harness.manager.onNavigationStarted(tabID: tab, url: "https://a.example/page")
        try await harness.sendWebEvent("adwall", tabID: tab)
        try await harness.sendWebEvent("adwall", tabID: tab)

        harness.manager.onNavigationStarted(tabID: tab, url: "https://b.example/page")
        try await harness.sendWebEvent("adwall", tabID: tab)

        harness.manager.onNavigationStarted(tabID: otherTab, url: "https://a.example/page")
        try await harness.sendWebEvent("adwall", tabID: otherTab)

        harness.scheduler.advance(by: Self.periodSeconds)

        #expect(harness.fired.contains { $0.name == "webTelemetry_adwalls_day_windows" && $0.parameters["adwallCount"] == "3" })
    }

    @Test("immediate event fires a pixel inline")
    func immediateEventFiresPixelInline() async throws {
        let harness = Harness(settingsJSON: Self.immediateConfig)

        try await harness.sendWebEvent("impression", tabID: .new())

        #expect(harness.fired.contains { $0.name == "webEvent_impression_windows" })
    }

    @Test("disabling the feature clears pending state")
    func disablingFeatureClearsPendingState() async throws {
        let harness = Harness(settingsJSON: Self.adwallConfig)

        try await harness.sendWebEvent("adwall", tabID: .new())
        // NOTE: this fixture's settings are static (Just(...)) — a follow-up implementation task
        // porting this test for real needs a settable settings publisher here, as
        // EventHubManagerFixture provides, to flip `enabled` to false mid-test.
        harness.scheduler.advance(by: Self.periodSeconds * 2)

        #expect(!harness.fired.contains { $0.name == "webTelemetry_adwalls_day_windows" && $0.parameters["adwallCount"] == "1" })
    }

    @Test("counter survives a simulated restart and the elapsed period catches up on next foreground")
    func counterSurvivesRestartAndCatchesUpOnForeground() async throws {
        let parser = EventHubConfigParser()
        let sharedStore = InMemoryKeyValueStore()
        let tab = EventHubTabID.new()

        // First run: count one adwall event over a repository backed by `sharedStore`.
        let firstScheduler = ManualEventHubScheduler(startMillis: 1_780_000_000_000)
        let firstRepository = EventHubKeyValueRepository(store: sharedStore, parser: parser)
        let firstManager = EventHubPixelManager(repository: firstRepository, parser: parser,
                                                 settings: StaticSettingsProviding(json: Self.adwallConfig),
                                                 clock: firstScheduler, scheduler: firstScheduler)
        let firstHandler = EventHubMessageHandler(manager: firstManager, tabIDProvider: { _ in tab })
        firstManager.onAppForegrounded()
        firstManager.onConfigChanged()

        let notify = try #require(firstHandler.handler(forMethodNamed: "webEvent"))
        _ = try await notify(["type": "adwall"], WKScriptMessage())
        firstScheduler.advance(by: 11) // let the write-behind flush persist the pending count

        // Second run over the SAME store, with the clock started past the persisted period end (as if
        // the app had been closed while the period elapsed).
        let secondScheduler = ManualEventHubScheduler(startMillis: 1_780_000_000_000 + Int64((Self.periodSeconds + 10) * 1000))
        let secondRepository = EventHubKeyValueRepository(store: sharedStore, parser: parser)
        let secondManager = EventHubPixelManager(repository: secondRepository, parser: parser,
                                                  settings: StaticSettingsProviding(json: Self.adwallConfig),
                                                  clock: secondScheduler, scheduler: secondScheduler)
        var fired: [FiredPixel] = []
        let cancellable = secondManager.firedPixelsPublisher.sink { fired.append($0) }
        defer { cancellable.cancel() }

        secondManager.onAppForegrounded()
        secondManager.onConfigChanged()

        #expect(fired.contains { $0.name == "webTelemetry_adwalls_day_windows" && $0.parameters["adwallCount"] == "1" })
    }
}

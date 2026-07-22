import Foundation
import Combine
@testable import EventHub

/// Shared test fixture for the EventHub pixel manager. Wires a real `EventHubKeyValueStore` over an
/// `InMemoryKeyValueStore`, a real `EventHubConfigParser`, a fake `EventHubSettingsProviding` whose
/// enabled-state and settings are controllable (and changeable mid-test), and a single
/// `ManualEventHubScheduler` that the manager uses for both time (`nowMillis()`) and period-end timers.
/// Fired pixels are captured in `fired`.
final class EventHubFixture {
    /// A fixed wall-clock (2026-01-02T00:01:00Z) so attributionPeriod values are deterministic.
    static let start = ISO8601DateFormatter().date(from: "2026-01-02T00:01:00Z")!

    /// How far to advance virtual time to let the write-behind persistence flush run.
    static let writeBehindFlush: TimeInterval = 15

    let store: InMemoryKeyValueStore
    let scheduler: ManualEventHubScheduler
    let repository: EventHubStore
    let manager: EventHub
    private(set) var fired: [FiredPixel] = []

    private let enabledSubject: CurrentValueSubject<Bool, Never>
    private let settingsSubject: CurrentValueSubject<Data?, Never>
    private let settingsJSON: String
    private var cancellable: AnyCancellable?

    private init(store: InMemoryKeyValueStore, settingsJSON: String, enabled: Bool, hasSettings: Bool) {
        self.store = store
        self.settingsJSON = settingsJSON
        self.scheduler = ManualEventHubScheduler(startMillis: Int64(Self.start.timeIntervalSince1970 * 1000))

        let parser = EventHubConfigParser()
        self.repository = EventHubKeyValueStore(store: store, parser: parser)
        self.enabledSubject = CurrentValueSubject(enabled)
        self.settingsSubject = CurrentValueSubject(hasSettings ? settingsJSON.data(using: .utf8) : nil)

        let settingsProvider = FakeEventHubSettingsProviding(enabled: enabledSubject.eraseToAnyPublisher(), settings: settingsSubject.eraseToAnyPublisher())

        self.manager = EventHub(repository: repository, parser: parser, settings: settingsProvider, clock: scheduler, scheduler: scheduler)
        self.cancellable = manager.firedPixelsPublisher.sink { [weak self] in self?.fired.append($0) }
    }

    /// A foregrounded fixture with config applied — the common "active period" starting point.
    static func active(_ settingsJSON: String, enabled: Bool = true, hasSettings: Bool = true) -> EventHubFixture {
        let fixture = EventHubFixture(store: InMemoryKeyValueStore(), settingsJSON: settingsJSON, enabled: enabled, hasSettings: hasSettings)
        fixture.manager.onAppForegrounded()
        fixture.manager.onConfigChanged()
        return fixture
    }

    /// A backgrounded fixture (config not yet applied) — for foreground-gating scenarios.
    static func background(_ settingsJSON: String, enabled: Bool = true, hasSettings: Bool = true) -> EventHubFixture {
        EventHubFixture(store: InMemoryKeyValueStore(), settingsJSON: settingsJSON, enabled: enabled, hasSettings: hasSettings)
    }

    static func webEvent(_ type: String) -> [String: Any] {
        ["type": type]
    }

    static func eventWithData(_ type: String, dataJSON: String) -> [String: Any] {
        let data = (try? JSONSerialization.jsonObject(with: dataJSON.data(using: .utf8)!)) ?? [String: Any]()
        return ["type": type, "data": data]
    }

    /// The expected attributionPeriod (interval-start unix seconds, as a string) for a period starting
    /// at `start`.
    static func expectedAttribution(periodSeconds: Int64) -> String {
        let epochSeconds = Int64(start.timeIntervalSince1970)
        return String(epochSeconds / periodSeconds * periodSeconds)
    }

    /// The manager's current in-memory state for a pixel (the source of truth during a period), or nil.
    func state(of pixelName: String) -> PixelState? {
        manager.activePixelStates.first { $0.pixelName == pixelName }
    }

    /// The current in-memory counter value for a pixel — fresh without a flush, unlike a repository read.
    func count(of pixelName: String) -> Int {
        state(of: pixelName)?.params["count"]?.value ?? 0
    }

    func setEnabled(_ value: Bool) { enabledSubject.send(value) }

    func setSettings(_ json: String) { settingsSubject.send(json.data(using: .utf8)) }

    func advance(by interval: TimeInterval) { scheduler.advance(by: interval) }

    /// Plants a corrupt persisted state directly into the store (an active period window, but an
    /// unparseable config snapshot) so load-time resilience can be exercised on the next start.
    func plantCorruptState(_ pixelName: String) {
        var stored = (try? JSONDecoder().decode([String: EventHubStoredPixelState].self, from: store.object(forKey: EventHubKeyValueStore.storageKey) as? Data ?? Data())) ?? [:]
        stored[pixelName] = EventHubStoredPixelState(periodStartMillis: 0, periodEndMillis: .max, paramsJSON: "{}", configJSON: "not valid json")
        store.set(try? JSONEncoder().encode(stored), forKey: EventHubKeyValueStore.storageKey)
    }

    /// Builds a fresh, foregrounded manager over the same persisted store (simulates a restart).
    func restart() -> EventHubFixture {
        // Backgrounding is a flush boundary, but the write-behind flush runs on the scheduler, so
        // advance virtual time to let it complete before "restarting" over the same persisted store.
        manager.onAppBackgrounded()
        scheduler.advance(by: Self.writeBehindFlush)

        let fixture = EventHubFixture(store: store, settingsJSON: settingsJSON, enabled: enabledSubject.value, hasSettings: true)
        fixture.manager.onAppForegrounded()
        fixture.manager.onConfigChanged()
        return fixture
    }

    private struct FakeEventHubSettingsProviding: EventHubSettingsProviding {
        let enabledPublisher: AnyPublisher<Bool, Never>
        let settingsPublisher: AnyPublisher<Data?, Never>
        init(enabled: AnyPublisher<Bool, Never>, settings: AnyPublisher<Data?, Never>) {
            self.enabledPublisher = enabled
            self.settingsPublisher = settings
        }
    }
}

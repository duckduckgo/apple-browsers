import Foundation
import Combine

/// The EventHub runtime. Receives web events and browser-native signals, routes them to the configured
/// telemetry, maintains aggregation state and period windows, and fires telemetry pixels. Lifecycle and
/// navigation signals are delivered by the (out-of-scope) wiring layer, which calls these methods.
public protocol EventHubManaging: AnyObject {
    /// Processes an incoming `webEvent` envelope (`{ "type": ..., "data": ... }`) from the tab
    /// identified by `tabID` against the active telemetry configs.
    func handleWebEvent(_ webEventData: [String: Any], tabID: EventHubTabID)

    /// Fires any enabled immediate-trigger telemetry whose `trigger.source` equals `type`. For
    /// browser-native events (not content-scope-scripts); there is no tab context.
    func handleImmediateEvent(_ type: String, data: Encodable?)

    /// Counts a browser-native event toward any enabled period/aggregated telemetry whose parameter
    /// `source` equals `type`. Unlike web events there is no per-tab dedup: each call is a genuine
    /// occurrence.
    func handleAggregatedEvent(_ type: String, data: Encodable?)

    /// Signals that the given tab has navigated to `url` (clears per-tab dedup on URL change).
    func onNavigationStarted(tabID: EventHubTabID, url: String)

    /// Signals that the given tab has closed (clears its per-tab dedup state).
    func onTabClosed(tabID: EventHubTabID)

    /// Notifies that the remote feature config (state and/or settings) has changed.
    func onConfigChanged()

    /// Returns whether the eventHub feature is currently enabled.
    func isEnabled() -> Bool

    /// Signals that the app has entered the foreground (catches up periods, re-arms timers).
    func onAppForegrounded()

    /// Signals that the app has entered the background (no new periods are started).
    func onAppBackgrounded()
}

public extension EventHubManaging {
    func handleImmediateEvent(_ type: String) { handleImmediateEvent(type, data: nil) }
    func handleAggregatedEvent(_ type: String) { handleAggregatedEvent(type, data: nil) }
}

/// Real `EventHubManaging` implementation. All mutable state is confined to one serial `DispatchQueue`
/// (`queue`) — never a per-pixel lock, never per-pixel timers. Every public entry point (and the
/// scheduler's fire callback) runs its body via `queue.sync`, so the serial queue acts as a mutex rather
/// than a fire-and-forget dispatch: by the time a call returns, any state change and any pixel fire it
/// caused have already happened and are visible to the caller. This is what lets tests built on
/// `ManualEventHubScheduler` (whose `advance(by:)` invokes the armed callback inline, on the calling
/// thread) observe fully-settled state immediately, with no additional synchronization.
public final class EventHub: EventHubManaging {
    /// How often pending (dirty) pixel state is persisted, absent a period boundary sooner than that.
    private static let flushInterval: Int64 = 10_000 // milliseconds

    /// Debug-only marker for the same-queue misconfiguration described on `init`'s and
    /// `DispatchQueueEventHubScheduler`'s doc comments. Dispatch doesn't expose a clean way to compare
    /// two `DispatchQueue` instances for identity from inside a closure running on one of them, so
    /// `init` associates this key with `queue` via `setSpecific`, and `assertSchedulerFiredOnADifferentQueue`
    /// checks whether that same value is visible on whichever queue the scheduler's callback is
    /// currently executing on.
    private static let ownQueueIdentityKey = DispatchSpecificKey<ObjectIdentifier>()

    private let store: EventHubStore
    private let parser: EventHubConfigParsing
    private let scheduler: EventHubScheduler
    private let pixelFiring: EventHubPixelFiring
    private let queue: DispatchQueue

    private var telemetries: [String: Telemetry] = [:]
    private var dirtyNames: Set<String> = []
    private var tabURLs: [EventHubTabID: String] = [:]
    private var latestConfigs: [TelemetryPixelConfig] = []
    private var latestEnabled = false
    private var isForeground = false
    private var subscriptions = Set<AnyCancellable>()

    /// `internal`, not `public` — visible to `@testable import EventHub`, mirroring the Windows
    /// `internal IReadOnlyCollection<PixelState> ActivePixelStates` marker (exposed to tests only).
    var activePixelStates: [PixelState] {
        queue.sync { telemetries.values.map { $0.snapshot() } }
    }

    /// - Important: if `scheduler` is a `DispatchQueueEventHubScheduler`, it must have been constructed
    ///   with a **different** `DispatchQueue` instance than `queue`. The scheduler's timer fires on its
    ///   own queue; `EventHub`'s scheduler-fire handler then calls `queue.sync { ... }` from inside that
    ///   callback. If both queues were the same instance, the timer would fire on `queue` and then
    ///   `.sync` onto itself — a silent deadlock. See `DispatchQueueEventHubScheduler`'s doc comment for
    ///   the same constraint from the scheduler's side.
    public init(
        store: EventHubStore,
        parser: EventHubConfigParsing,
        settings: EventHubSettingsProviding,
        scheduler: EventHubScheduler,
        pixelFiring: EventHubPixelFiring,
        queue: DispatchQueue = DispatchQueue(label: "com.duckduckgo.eventhub")
    ) {
        self.store = store
        self.parser = parser
        self.scheduler = scheduler
        self.pixelFiring = pixelFiring
        self.queue = queue
        queue.setSpecific(key: Self.ownQueueIdentityKey, value: ObjectIdentifier(queue))

        settings.enabledPublisher
            .sink { [weak self] enabled in self?.queue.sync { self?.latestEnabled = enabled } }
            .store(in: &subscriptions)
        settings.settingsPublisher
            .sink { [weak self] data in
                self?.queue.sync {
                    self?.latestConfigs = data.map { self?.parser.parseTelemetry($0) ?? [] } ?? []
                }
            }
            .store(in: &subscriptions)
    }

    public func handleWebEvent(_ webEventData: [String: Any], tabID: EventHubTabID) {
        queue.sync {
            guard latestEnabled, let type = webEventData["type"] as? String, !type.isEmpty else { return }
            let data = webEventData["data"] as? [String: Any]
            fireImmediateLocked(source: type, data: data)
            countPeriodLocked(source: type, data: data, tabID: tabID)
        }
    }

    public func handleImmediateEvent(_ type: String, data: Encodable?) {
        queue.sync {
            guard latestEnabled, !type.isEmpty else { return }
            fireImmediateLocked(source: type, data: Self.encode(data))
        }
    }

    public func handleAggregatedEvent(_ type: String, data: Encodable?) {
        queue.sync {
            guard latestEnabled, !type.isEmpty else { return }
            countPeriodLocked(source: type, data: Self.encode(data), tabID: .empty)
        }
    }

    private func fireImmediateLocked(source: String, data: [String: Any]?) {
        for config in latestConfigs where config.isEnabled && config.trigger.isImmediate && config.trigger.source == source {
            var params: [String: String] = [:]
            for (paramName, paramConfig) in config.parameters where paramConfig.isData {
                if let parameter = ParameterFactory.make(paramConfig), parameter.handle(data: data, tabID: .empty),
                   let value = parameter.queryValue() {
                    params[paramName] = value
                }
            }
            pixelFiring.enqueueFirePixel(named: config.name, parameters: params)
        }
    }

    /// Counts a matching event toward every enabled period telemetry. Persistence is deliberately NOT
    /// flushed here on every call — that would defeat write-behind coalescing (a burst of thousands of
    /// events would otherwise mean thousands of store writes). Marking `dirtyNames` and re-arming the
    /// scheduler is enough: the pending state is picked up by the next period boundary, the next
    /// `flushInterval` deadline, or an explicit `onAppBackgrounded()`.
    private func countPeriodLocked(source: String, data: [String: Any]?, tabID: EventHubTabID) {
        for config in latestConfigs where config.isEnabled && config.trigger.isPeriod {
            guard let telemetry = telemetries[config.name] else { continue }
            if telemetry.handleEvent(source: source, data: data, tabID: tabID) {
                dirtyNames.insert(config.name)
            }
        }
        rearmSchedulerLocked()
    }

    public func onConfigChanged() {
        queue.sync { applyConfigLocked() }
    }

    private func applyConfigLocked() {
        guard latestEnabled else { disableLocked(); return }
        let enabledNames = Set(latestConfigs.filter { $0.isEnabled && $0.trigger.isPeriod }.map(\.name))
        // Snapshot the keys: tearDownLocked mutates `telemetries` (removes the entry), so iterating a
        // live view of the same dictionary being mutated would be subtle even though Swift's COW makes
        // it memory-safe.
        for name in Array(telemetries.keys) where !enabledNames.contains(name) {
            tearDownLocked(name)
        }
        for config in latestConfigs where config.isEnabled && config.trigger.isPeriod && telemetries[config.name] == nil {
            startNewPeriodLocked(config)
        }
        rearmSchedulerLocked()
    }

    private func startNewPeriodLocked(_ config: TelemetryPixelConfig) {
        guard isForeground, latestEnabled, config.isEnabled, config.trigger.period != nil else { return }
        let telemetry = Telemetry(config: config, periodStartMillis: scheduler.nowMillis())
        telemetries[config.name] = telemetry
        dirtyNames.insert(config.name)
    }

    private func tearDownLocked(_ name: String) {
        telemetries.removeValue(forKey: name)
        dirtyNames.remove(name)
        store.deletePixelState(named: name)
    }

    private func disableLocked() {
        telemetries.removeAll()
        dirtyNames.removeAll()
        tabURLs.removeAll()
        store.deleteAllPixelStates()
        rearmSchedulerLocked()
    }

    public func isEnabled() -> Bool { queue.sync { latestEnabled } }

    public func onAppForegrounded() {
        queue.sync {
            isForeground = true
            checkPixelsLocked()
        }
    }

    public func onAppBackgrounded() {
        queue.sync {
            isForeground = false
            flushDirtyLocked()
        }
    }

    private func checkPixelsLocked() {
        guard latestEnabled else { return }
        for stored in store.allPixelStates() where telemetries[stored.pixelName] == nil {
            telemetries[stored.pixelName] = Telemetry(restoring: stored)
        }
        let now = scheduler.nowMillis()
        // Snapshot the values: fireLocked mutates `telemetries` (removes the fired entry and may add a
        // fresh one for the next period), so iterating a live view of the same dictionary being mutated
        // would be subtle even though Swift's COW makes it memory-safe.
        for telemetry in Array(telemetries.values) where telemetry.isElapsed(atMillis: now) {
            fireLocked(telemetry.name)
        }
        for config in latestConfigs where config.isEnabled && config.trigger.isPeriod && telemetries[config.name] == nil {
            startNewPeriodLocked(config)
        }
        flushDirtyLocked()
        rearmSchedulerLocked()
    }

    private func fireLocked(_ name: String) {
        guard latestEnabled, let telemetry = telemetries[name] else { return }
        guard latestConfigs.contains(where: { $0.name == name && $0.isEnabled && $0.trigger.isPeriod }) else {
            tearDownLocked(name); return
        }
        telemetries.removeValue(forKey: name)
        dirtyNames.remove(name)
        store.deletePixelState(named: name)

        if var params = telemetry.buildPixelParameters() {
            let attributionPeriod = EventHubAttribution.startOfIntervalSeconds(
                periodStartMillis: telemetry.periodStartMillis,
                periodSeconds: telemetry.config.trigger.period?.periodSeconds ?? 0)
            params["attributionPeriod"] = String(attributionPeriod)
            pixelFiring.enqueueFirePixel(named: name, parameters: params)
        }

        if let latest = latestConfigs.first(where: { $0.name == name }) {
            startNewPeriodLocked(latest)
        }
    }

    private func flushDirtyLocked() {
        guard !dirtyNames.isEmpty else { return }
        for name in dirtyNames {
            if let telemetry = telemetries[name] {
                store.savePixelState(telemetry.snapshot())
            }
        }
        dirtyNames.removeAll()
    }

    private func rearmSchedulerLocked() {
        let earliestPeriodEnd = telemetries.values.map(\.periodEndMillis).min()
        // Recomputed as `now + flushInterval` every time this is called (i.e. on every counted event),
        // so under a sustained real-time event burst the flush deadline keeps sliding forward and
        // persistence is deferred until a lull, a period boundary, or an explicit `onAppBackgrounded()`
        // — not strictly "at least every `flushInterval`". In-memory counts stay correct either way;
        // only crash-during-sustained-burst restart durability is affected.
        let nextFlush = dirtyNames.isEmpty ? nil : scheduler.nowMillis() + Self.flushInterval
        let candidates = [earliestPeriodEnd, nextFlush].compactMap { $0 }
        scheduler.arm(atMillis: candidates.min()) { [weak self] in
            self?.assertSchedulerFiredOnADifferentQueue()
            self?.queue.sync { self?.onSchedulerFiredLocked() }
        }
    }

    /// Debug-only guard for the same-queue misconfiguration described on `init`'s doc comment: if the
    /// scheduler's timer fires directly on `queue` (i.e. the integrator passed the same `DispatchQueue`
    /// instance to both `EventHub.init(queue:)` and `DispatchQueueEventHubScheduler.init(queue:)`), the
    /// `.sync` immediately below would deadlock. Compiled out entirely in release builds (the `assert`
    /// condition is an autoclosure that's never evaluated with `-O`), so this costs nothing there; the
    /// one-time `setSpecific` call in `init` is the only cost paid in release.
    private func assertSchedulerFiredOnADifferentQueue() {
        assert(DispatchQueue.getSpecific(key: Self.ownQueueIdentityKey) != ObjectIdentifier(queue),
               "EventHub's scheduler must fire on a different DispatchQueue than EventHub's own `queue` — " +
               "passing the same DispatchQueue instance to both EventHub.init(queue:) and " +
               "DispatchQueueEventHubScheduler.init(queue:) causes the timer to fire on `queue` and then " +
               "`.sync` onto itself, which deadlocks.")
    }

    private func onSchedulerFiredLocked() {
        let now = scheduler.nowMillis()
        // Snapshot the values: fireLocked mutates `telemetries` (removes the fired entry and may add a
        // fresh one for the next period), so iterating a live view of the same dictionary being mutated
        // would be subtle even though Swift's COW makes it memory-safe.
        for telemetry in Array(telemetries.values) where telemetry.isElapsed(atMillis: now) {
            fireLocked(telemetry.name)
        }
        flushDirtyLocked()
        rearmSchedulerLocked()
    }

    public func onNavigationStarted(tabID: EventHubTabID, url: String) {
        queue.sync {
            guard !url.isEmpty else { return }
            let previous = tabURLs[tabID]
            tabURLs[tabID] = url
            guard let previous, previous != url else { return }
            for telemetry in telemetries.values { telemetry.onNavigationStarted(tabID: tabID) }
        }
    }

    public func onTabClosed(tabID: EventHubTabID) {
        queue.sync {
            tabURLs.removeValue(forKey: tabID)
            for telemetry in telemetries.values { telemetry.onTabClosed(tabID: tabID) }
        }
    }

    private static func encode(_ data: Encodable?) -> [String: Any]? {
        guard let data else { return nil }
        guard let encoded = try? JSONEncoder().encode(data),
              let object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            return nil
        }
        return object
    }
}

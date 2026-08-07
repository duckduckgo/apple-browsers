//
//  EventHub.swift
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
import Combine
import os.log

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
/// (`queue`) — never a per-pixel lock, never per-pixel timers. Every public entry point dispatches its
/// body with `queue.async`, so no caller ever blocks on EventHub. That matters twice over: the entry
/// points are called on the main thread (web messages, navigation, app lifecycle) while the work behind
/// them includes key-value store I/O and a `PixelKit` fire; and the queue is never held across a call
/// out to an injected collaborator, so a `pixelFiring`/`store`/`eventMapping` conformance that calls
/// back into EventHub merely enqueues instead of deadlocking.
///
/// Because the body runs later, anything that must be sampled at the moment of the *call* is captured
/// before dispatching — see `nowMillis` in `handleWebEvent`/`handleAggregatedEvent`, and the payload
/// encoding in `handleImmediateEvent`.
///
/// The four remaining uses of `queue.sync` are deliberate. None can deadlock: none is reachable from
/// inside the queue, and a serial queue is FIFO, so a `sync` enqueued after the caller's own `async`
/// work runs after it.
/// - `onAppBackgrounded()`, EventHub's flush boundary: it must not return before pending state is
///   persisted, because the process may be suspended immediately afterwards.
/// - the tail of `init`, so construction returns with the replayed initial settings already recorded.
/// - `activePixelStates` and `settle()`, both test-facing: they are the fences that let tests built on
///   `ManualEventHubScheduler` observe fully-settled state.
public final class EventHub: EventHubManaging {
    /// How often pending (dirty) pixel state is persisted, absent a period boundary sooner than that.
    private static let flushInterval: Int64 = 10_000 // milliseconds

    private let store: EventHubStore
    private let parser: EventHubConfigParsing
    private let scheduler: EventHubScheduler
    private let pixelFiring: EventHubPixelFiring
    private let queue: DispatchQueue

    private var telemetries: [String: Telemetry] = [:]
    private var dirtyNames: Set<String> = []
    private var tabURLs: [EventHubTabID: String] = [:]
    /// Hub-lifetime so per-tab dedup outlives the `Telemetry` objects that consult it — a period
    /// rollover, and a period firing while backgrounded, both replace those. See `DedupStore`.
    private let dedupStore = DedupStore()
    private var latestConfigs: [TelemetryPixelConfig] = []
    private var latestEnabled = false
    private var isForeground = false
    private var subscriptions = Set<AnyCancellable>()

    /// `false` until `init` has consumed the settings publishers' initial replay. While `false` the
    /// subscriptions only record state without applying it: applying during `init` would let a
    /// transient `enabled == false` — e.g. remote config not loaded yet on a cold launch — reach
    /// `disableLocked()` and wipe persisted period state that a later `enabled == true` cannot recover.
    /// Startup instead applies config on the first `onAppForegrounded()`, which is also the earliest
    /// point a period is allowed to start.
    private var hasConsumedInitialSettings = false

    /// `internal`, not `public` — visible to `@testable import EventHub`, mirroring the Windows
    /// `internal IReadOnlyCollection<PixelState> ActivePixelStates` marker (exposed to tests only).
    var activePixelStates: [PixelState] {
        queue.sync { telemetries.values.map { $0.snapshot() } }
    }

    /// Blocks until the entry points the caller already invoked have finished. `internal`, like
    /// `activePixelStates`: tests need it because they read the pixel-firing spy and the key-value store
    /// directly, bypassing the queue. Production code has nothing to fence on.
    func settle() {
        queue.sync {}
    }

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

        // Both subscriptions re-apply the config themselves, so any change in enablement *or* in the
        // settings (including a consent grant/revoke, which `EventHubSettings` folds into the settings
        // JSON) takes effect immediately. Integrators do not need to call `onConfigChanged()`.
        settings.enabledPublisher
            .sink { [weak self] enabled in
                guard let self else { return }
                queue.async {
                    guard self.latestEnabled != enabled else { return }
                    self.latestEnabled = enabled
                    Logger.eventHub.info("feature enabled = \(enabled, privacy: .public)")
                    if self.hasConsumedInitialSettings { self.applyConfigLocked() }
                }
            }
            .store(in: &subscriptions)
        settings.settingsPublisher
            .sink { [weak self] settings in
                guard let self else { return }
                queue.async {
                    self.latestConfigs = settings.map { self.parser.parseTelemetry($0) } ?? []
                    Logger.eventHub.info("parsed \(self.latestConfigs.count, privacy: .public) telemetry config(s) from settings")
                    if self.hasConsumedInitialSettings { self.applyConfigLocked() }
                }
            }
            .store(in: &subscriptions)

        // `sync`, and last: both publishers replay their current value synchronously as they are
        // subscribed above, so those blocks are already queued ahead of this one and — the queue being
        // FIFO — have recorded the initial settings by the time the flag flips. `init` therefore returns
        // with the initial config consumed, exactly as it did when the subscriptions applied inline.
        queue.sync { hasConsumedInitialSettings = true }
    }

    public func handleWebEvent(_ webEventData: [String: Any], tabID: EventHubTabID) {
        guard let type = webEventData["type"] as? String, !type.isEmpty else { return }
        let data = webEventData["data"] as? [String: Any]
        // Sampled here, not in the block: `now` decides whether the event still belongs to the running
        // period, so it has to be the arrival time. Read on the queue it would be the drain time, and an
        // event arriving just before `periodEnd` could be dropped for landing in no period at all.
        let nowMillis = scheduler.nowMillis()
        queue.async { [self] in
            guard latestEnabled else { return }
            fireImmediateLocked(source: type, data: data)
            countPeriodLocked(source: type, data: data, tabID: tabID, nowMillis: nowMillis)
        }
    }

    public func handleImmediateEvent(_ type: String, data: Encodable?) {
        guard !type.isEmpty else { return }
        // Encoded here, not in the block: `data` is a caller-owned `Encodable` that may be a reference
        // type, and the caller is free to mutate it the moment this returns. The cost is encoding a
        // payload that a disabled feature then discards — native immediate events are rare enough that
        // this is cheaper than the alternatives for reading `latestEnabled` off-queue.
        let encoded = Self.encode(data)
        queue.async { [self] in
            guard latestEnabled else { return }
            fireImmediateLocked(source: type, data: encoded)
        }
    }

    public func handleAggregatedEvent(_ type: String, data: Encodable?) {
        guard !type.isEmpty else { return }
        let encoded = Self.encode(data)
        let nowMillis = scheduler.nowMillis()
        queue.async { [self] in
            guard latestEnabled else { return }
            countPeriodLocked(source: type, data: encoded, tabID: .empty, nowMillis: nowMillis)
        }
    }

    private func fireImmediateLocked(source: String, data: [String: Any]?) {
        for config in latestConfigs where config.isEnabled && config.trigger.isImmediate && config.trigger.source == source {
            var params: [String: String] = [:]
            for (paramName, paramConfig) in config.parameters where paramConfig.isData {
                if let parameter = ParameterFactory.makeData(paramConfig), parameter.handle(data: data, tabID: .empty),
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
    /// - Parameter nowMillis: the time the event *arrived*, sampled by the caller before dispatching
    ///   onto the queue. The timer is best-effort, so it can legitimately be past `periodEnd` before the
    ///   sweep has run (notably on macOS, where a period can end while the app runs unfocused). An event
    ///   arriving in that window belongs to no period and must not be counted into the elapsed one.
    private func countPeriodLocked(source: String, data: [String: Any]?, tabID: EventHubTabID, nowMillis now: Int64) {
        for config in latestConfigs where config.isEnabled && config.trigger.isPeriod {
            guard let telemetry = telemetries[config.name], !telemetry.isElapsed(atMillis: now) else { continue }
            if telemetry.handleEvent(source: source, data: data, tabID: tabID) {
                dirtyNames.insert(config.name)
            }
        }
        rearmSchedulerLocked()
    }

    public func onConfigChanged() {
        queue.async { [self] in applyConfigLocked() }
    }

    private func applyConfigLocked() {
        guard latestEnabled else { disableLocked(); return }
        // Tear down on *absence* from config, not on a pixel merely being disabled: per the Tech Design,
        // a config removed remotely stops immediately, whereas a disabled pixel still fires the period
        // it was already running and only then stops (the restart is gated separately, in
        // `startNewPeriodLocked`, which checks `config.isEnabled`).
        let presentNames = Set(latestConfigs.filter { $0.trigger.isPeriod }.map(\.name))
        // Snapshot the keys: tearDownLocked mutates `telemetries` (removes the entry), so iterating a
        // live view of the same dictionary being mutated would be subtle even though Swift's COW makes
        // it memory-safe.
        for name in Array(telemetries.keys) where !presentNames.contains(name) {
            tearDownLocked(name)
        }
        for config in latestConfigs where config.isEnabled && config.trigger.isPeriod && telemetries[config.name] == nil {
            startNewPeriodLocked(config)
        }
        rearmSchedulerLocked()
    }

    private func startNewPeriodLocked(_ config: TelemetryPixelConfig) {
        guard isForeground, latestEnabled, config.isEnabled, config.trigger.period != nil else { return }
        let telemetry = Telemetry(config: config, periodStartMillis: scheduler.nowMillis(), dedupStore: dedupStore)
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
        dedupStore.clearAll()
        store.deleteAllPixelStates()
        rearmSchedulerLocked()
    }

    public func onAppForegrounded() {
        queue.async { [self] in
            isForeground = true
            checkPixelsLocked()
        }
    }

    /// The one blocking entry point, deliberately: this is EventHub's flush boundary, and on iOS the
    /// process can be suspended as soon as it returns. Persisting has to have happened by then, so the
    /// caller waits. Anything the caller dispatched earlier is drained first — the queue is FIFO.
    public func onAppBackgrounded() {
        queue.sync {
            isForeground = false
            flushDirtyLocked()
        }
    }

    private func checkPixelsLocked() {
        guard latestEnabled else { return }
        for stored in store.allPixelStates() where telemetries[stored.pixelName] == nil {
            telemetries[stored.pixelName] = Telemetry(restoring: stored, dedupStore: dedupStore)
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
        // Defense-in-depth against a config removed between arming and elapsing. Deliberately checks
        // presence, not `isEnabled`: a pixel disabled mid-period must still fire this final period.
        guard latestConfigs.contains(where: { $0.name == name && $0.trigger.isPeriod }) else {
            tearDownLocked(name); return
        }
        telemetries.removeValue(forKey: name)
        dirtyNames.remove(name)
        store.deletePixelState(named: name)

        if var params = telemetry.buildPixelParameters() {
            // `periodSeconds` is the divisor in the attribution calculation, so a missing period would
            // trap. `EventHubConfigParser` rejects a period trigger without a positive `seconds`, on both
            // the live-config and restored-snapshot paths, so this only guards that invariant — if it ever
            // breaks, skip the fire rather than crash.
            if let periodSeconds = telemetry.config.trigger.period?.periodSeconds {
                params["attributionPeriod"] = String(EventHubAttribution.startOfIntervalSeconds(
                    periodStartMillis: telemetry.periodStartMillis, periodSeconds: periodSeconds))
                let rawCounts = telemetry.rawCounterValues
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                Logger.eventHub.debug("firing period pixel \(name, privacy: .public), raw counts [\(rawCounts, privacy: .private)]")
                pixelFiring.enqueueFirePixel(named: name, parameters: params)
            } else {
                Logger.eventHub.error("pixel \(name, privacy: .public) not fired, its period trigger has no period to attribute to")
            }
        }

        if let latest = latestConfigs.first(where: { $0.name == name }) {
            startNewPeriodLocked(latest)
        }
    }

    /// Names stay dirty when the store rejects the write, so the next flush — armed by
    /// `rearmSchedulerLocked` for as long as anything is pending — retries them.
    private func flushDirtyLocked() {
        guard !dirtyNames.isEmpty else { return }
        let states = dirtyNames.compactMap { telemetries[$0]?.snapshot() }
        guard store.savePixelStates(states) else { return }
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
        // `async`, so it does not matter whether the scheduler's timer happens to fire on `queue` itself:
        // the block queues up behind the current one instead of waiting on it.
        scheduler.arm(atMillis: candidates.min()) { [weak self] in
            guard let self else { return }
            queue.async { self.onSchedulerFiredLocked() }
        }
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
        guard !url.isEmpty else { return }
        queue.async { [self] in
            let previous = tabURLs[tabID]
            tabURLs[tabID] = url
            guard let previous, previous != url else { return }
            dedupStore.clear(tabID: tabID)
        }
    }

    public func onTabClosed(tabID: EventHubTabID) {
        queue.async { [self] in
            tabURLs.removeValue(forKey: tabID)
            dedupStore.clear(tabID: tabID)
        }
    }

    private static func encode(_ data: Encodable?) -> [String: Any]? {
        guard let data else { return nil }
        do {
            let encoded = try JSONEncoder().encode(data)
            guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                Logger.eventHub.error("native event payload is not a JSON object, payload dropped")
                return nil
            }
            return object
        } catch {
            Logger.eventHub.error("native event payload could not be serialised, payload dropped: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

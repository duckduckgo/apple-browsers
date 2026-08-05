//
//  EventHubStore.swift
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
import Common
import Persistence
import os.log

/// Persists per-pixel EventHub runtime state across app restarts. State survives the fire button and
/// is only cleared by EventHub itself (period fire, config disable). Backed by the key-value store.
public protocol EventHubStore {
    /// Returns the persisted state for the named pixel, or `nil` if absent or corrupt.
    func pixelState(named name: String) -> PixelState?

    /// Returns all persisted pixel states, skipping any whose stored config cannot be parsed.
    func allPixelStates() -> [PixelState]

    /// Persists (inserts or replaces) the state for a pixel.
    func savePixelState(_ state: PixelState)

    /// Removes the persisted state for the named pixel, if any.
    func deletePixelState(named name: String)

    /// Removes all persisted pixel state.
    func deleteAllPixelStates()
}

/// Backs `EventHubStore` with a `ThrowingKeyValueStoring`. All persisted pixel states live under a
/// single composite key (`storageKey`) as a `[String: EventHubStoredPixelState]` map, JSON-encoded to
/// `Data`. Read/write/parse failures are treated as absence rather than propagated: a corrupt entry is
/// skipped, not thrown — but every such boundary is logged to `Logger.eventHub`, and the ones that lose
/// state also fire `EventHubDebugEvent.pixelStatePersistenceFailed` through `eventMapping`.
public final class EventHubKeyValueStore: EventHubStore {
    /// The single key under which the map of pixel-name to `EventHubStoredPixelState` is stored.
    public static let storageKey = "eventhub_pixel_states"

    private let store: ThrowingKeyValueStoring
    private let parser: EventHubConfigParsing
    private let eventMapping: EventMapping<EventHubDebugEvent>?

    public init(
        store: ThrowingKeyValueStoring,
        parser: EventHubConfigParsing,
        eventMapping: EventMapping<EventHubDebugEvent>? = nil
    ) {
        self.store = store
        self.parser = parser
        self.eventMapping = eventMapping
    }

    public func pixelState(named name: String) -> PixelState? {
        readMap()[name].flatMap { toPixelState(name: name, entry: $0) }
    }

    public func allPixelStates() -> [PixelState] {
        readMap().compactMap { name, entry in toPixelState(name: name, entry: entry) }
    }

    public func savePixelState(_ state: PixelState) {
        guard let configJSON = parser.serializePixelConfig(state.config) else {
            Logger.eventHub.error("store: could not serialise the config snapshot for pixel \(state.pixelName, privacy: .public), state not saved")
            return
        }
        guard let paramsData = try? JSONEncoder().encode(state.params),
              let paramsJSON = String(bytes: paramsData, encoding: .utf8) else {
            Logger.eventHub.error("store: could not serialise params for pixel \(state.pixelName, privacy: .public), state not saved")
            return
        }
        var map = readMap()
        map[state.pixelName] = EventHubStoredPixelState(
            periodStartMillis: state.periodStartMillis, periodEndMillis: state.periodEndMillis,
            paramsJSON: paramsJSON, configJSON: configJSON)
        writeMap(map)
    }

    public func deletePixelState(named name: String) {
        var map = readMap()
        guard map.removeValue(forKey: name) != nil else { return }
        writeMap(map)
    }

    public func deleteAllPixelStates() {
        do {
            try store.removeObject(forKey: Self.storageKey)
        } catch {
            Logger.eventHub.error("store: could not delete all pixel state: \(error.localizedDescription, privacy: .public)")
            eventMapping?.fire(.pixelStatePersistenceFailed(operation: .delete), error: error)
        }
    }

    private func readMap() -> [String: EventHubStoredPixelState] {
        let stored: Any?
        do {
            stored = try store.object(forKey: Self.storageKey)
        } catch {
            Logger.eventHub.error("store: could not read pixel state: \(error.localizedDescription, privacy: .public)")
            eventMapping?.fire(.pixelStatePersistenceFailed(operation: .read), error: error)
            return [:]
        }
        // Nothing stored yet is the normal cold-start state, not a failure: no event, no error log.
        guard let stored else { return [:] }
        guard let data = stored as? Data else {
            Logger.eventHub.error("store: stored pixel state is not Data, treating as absent")
            eventMapping?.fire(.pixelStatePersistenceFailed(operation: .decode))
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: EventHubStoredPixelState].self, from: data)
        } catch {
            Logger.eventHub.error("store: stored pixel state could not be decoded, treating as absent: \(error.localizedDescription, privacy: .public)")
            eventMapping?.fire(.pixelStatePersistenceFailed(operation: .decode), error: error)
            return [:]
        }
    }

    private func writeMap(_ map: [String: EventHubStoredPixelState]) {
        guard let data = try? JSONEncoder().encode(map) else {
            Logger.eventHub.error("store: could not encode the pixel state map, nothing persisted")
            return
        }
        do {
            try store.set(data, forKey: Self.storageKey)
        } catch {
            Logger.eventHub.error("store: could not persist pixel state: \(error.localizedDescription, privacy: .public)")
            eventMapping?.fire(.pixelStatePersistenceFailed(operation: .write), error: error)
        }
    }

    private func toPixelState(name: String, entry: EventHubStoredPixelState) -> PixelState? {
        guard let config = parser.parseSinglePixelConfig(name: name, json: entry.configJSON) else {
            Logger.eventHub.error("store: stored config snapshot for pixel \(name, privacy: .public) is unusable, state discarded")
            return nil
        }
        let params: [String: ParamState]
        do {
            params = try JSONDecoder().decode([String: ParamState].self, from: Data(entry.paramsJSON.utf8))
        } catch {
            Logger.eventHub.error("store: stored params for pixel \(name, privacy: .public) are unusable, counters restart from zero: \(error.localizedDescription, privacy: .public)")
            params = [:]
        }
        return PixelState(pixelName: name, periodStartMillis: entry.periodStartMillis,
                           periodEndMillis: entry.periodEndMillis, config: config, params: params)
    }
}

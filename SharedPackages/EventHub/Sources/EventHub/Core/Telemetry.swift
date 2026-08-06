//
//  Telemetry.swift
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

/// One configured pixel's period window, config snapshot (frozen at period start so a mid-period
/// config change never mutates a running period), and its parameters.
final class Telemetry {
    let name: String
    private(set) var config: TelemetryPixelConfig
    private(set) var periodStartMillis: Int64
    private(set) var periodEndMillis: Int64
    private var parameters: [String: Parameter]

    /// Starts a fresh period from `config`, beginning at `periodStartMillis`.
    init(config: TelemetryPixelConfig, periodStartMillis: Int64, dedupStore: DedupStore) {
        self.name = config.name
        self.config = config
        self.periodStartMillis = periodStartMillis
        self.periodEndMillis = periodStartMillis + (config.trigger.period?.periodSeconds ?? 0) * 1000
        self.parameters = Self.makeParameters(config: config, dedupStore: dedupStore)
    }

    /// Rehydrates from persisted state (restart / foreground catch-up). Dedup is deliberately not
    /// restored: it is in-memory only, so after a restart a page legitimately counts once more.
    init(restoring persisted: PixelState, dedupStore: DedupStore) {
        self.name = persisted.pixelName
        self.config = persisted.config
        self.periodStartMillis = persisted.periodStartMillis
        self.periodEndMillis = persisted.periodEndMillis
        self.parameters = Self.makeParameters(config: persisted.config, dedupStore: dedupStore)
        for (paramName, parameter) in parameters {
            if let restored = persisted.params[paramName] {
                parameter.restoreState(restored)
            }
        }
    }

    /// Builds this pixel's parameters, giving each counter a dedup key scoped to pixel×param×source so
    /// two pixels sharing a parameter name and source still de-duplicate independently.
    private static func makeParameters(config: TelemetryPixelConfig, dedupStore: DedupStore) -> [String: Parameter] {
        var result: [String: Parameter] = [:]
        for (paramName, paramConfig) in config.parameters {
            let dedupKey = "\(config.name):\(paramName):\(paramConfig.source ?? "")"
            if let parameter = ParameterFactory.make(paramConfig, dedupKey: dedupKey, dedupStore: dedupStore) {
                result[paramName] = parameter
            }
        }
        return result
    }

    func isElapsed(atMillis now: Int64) -> Bool { now >= periodEndMillis }

    /// Routes a matching event to every parameter whose config `source` equals `source`. Returns
    /// `true` if any parameter's state changed.
    @discardableResult
    func handleEvent(source: String, data: [String: Any]?, tabID: EventHubTabID) -> Bool {
        var changed = false
        for (paramName, paramConfig) in config.parameters where paramConfig.source == source {
            guard let parameter = parameters[paramName] else { continue }
            if parameter.handle(data: data, tabID: tabID) { changed = true }
        }
        return changed
    }

    func snapshot() -> PixelState {
        PixelState(pixelName: name, periodStartMillis: periodStartMillis, periodEndMillis: periodEndMillis,
                    config: config, params: parameters.mapValues(\.state))
    }

    /// The query parameters to emit for this pixel, or `nil` if nothing meaningful was measured
    /// (e.g. no counter matched a bucket and no data parameter has a value).
    func buildPixelParameters() -> [String: String]? {
        var result: [String: String] = [:]
        for (paramName, parameter) in parameters {
            if let value = parameter.queryValue() { result[paramName] = value }
        }
        return result.isEmpty ? nil : result
    }
}

//
//  Parameter.swift
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
import os.log

/// A single pixel parameter's runtime behavior. `CounterParameter` owns its counter value and the
/// stop-at-max-bucket logic, and makes the per-tab dedup decision against the hub-owned `DedupStore`
/// (native/`.empty`-tab events are never deduped). `DataParameter` owns only its last-seen value.
protocol Parameter: AnyObject {
    /// Processes an event whose source already matched this parameter's config source (or, for an
    /// immediate-trigger's data param, the triggering event itself). Returns `true` if state changed.
    @discardableResult
    func handle(data: [String: Any]?, tabID: EventHubTabID) -> Bool

    var state: ParamState { get }
    func restoreState(_ state: ParamState)

    /// The value to emit for this parameter when the owning pixel fires, or `nil` if this parameter
    /// has nothing to report (e.g. a counter with no matching bucket).
    func queryValue() -> String?
}

enum ParameterFactory {
    /// Builds the parameter for a pixel's running period. `dedupKey` identifies this parameter within
    /// its pixel (pixel×param×source) for `dedupStore` lookups.
    static func make(_ config: TelemetryParameterConfig, dedupKey: String, dedupStore: DedupStore) -> Parameter? {
        if config.isCounter, let buckets = config.buckets {
            return CounterParameter(buckets: buckets, dedupKey: dedupKey, dedupStore: dedupStore)
        }
        if config.isData {
            return DataParameter(dataKey: config.dataKey)
        }
        return nil
    }

    /// Builds a transient `data` parameter for an immediate pixel, which has no period and no dedup —
    /// it reports the triggering event's own payload and is discarded straight after firing.
    static func makeData(_ config: TelemetryParameterConfig) -> Parameter? {
        guard config.isData else { return nil }
        return DataParameter(dataKey: config.dataKey)
    }
}

final class CounterParameter: Parameter {
    private let buckets: BucketList
    /// Identifies this parameter (pixel×param×source) inside the shared, tab-keyed `DedupStore`.
    private let dedupKey: String
    /// Hub-owned, so dedup outlives this parameter — see `DedupStore`.
    private let dedupStore: DedupStore
    private var value: Int
    private var stopCounting: Bool

    init(buckets: BucketList, dedupKey: String, dedupStore: DedupStore, initialState: ParamState = ParamState(value: 0)) {
        self.buckets = buckets
        self.dedupKey = dedupKey
        self.dedupStore = dedupStore
        self.value = initialState.value
        self.stopCounting = initialState.stopCounting
    }

    @discardableResult
    func handle(data: [String: Any]?, tabID: EventHubTabID) -> Bool {
        guard !stopCounting else { return false }
        // Native events (tabID == .empty) opt out of dedup: every call is a genuine occurrence.
        if tabID != .empty {
            guard dedupStore.markSeen(key: dedupKey, tabID: tabID) else { return false }
        }
        if BucketCounter.shouldStopCounting(value, buckets: buckets) {
            stopCounting = true
        } else {
            value += 1
        }
        return true
    }

    var state: ParamState { ParamState(value: value, stopCounting: stopCounting) }
    func restoreState(_ state: ParamState) { value = state.value; stopCounting = state.stopCounting }

    func queryValue() -> String? { BucketCounter.bucketCount(value, buckets: buckets) }
}

final class DataParameter: Parameter {
    /// RFC 3986 "unreserved" characters (alphanumerics plus `-._~`) are left unescaped; everything
    /// else — including `"`, `{`, `}`, `:`, and space — is percent-encoded. This matches the
    /// compact-JSON-then-percent-encode format the ported `EventHubDataParameterTests` expect once
    /// `DataParameter` is wired into `EventHub` (e.g. `"logged-in"` → `%22logged-in%22`,
    /// `{"a": true}` → `%7B%22a%22%3Atrue%7D`). `CharacterSet.alphanumerics` alone is not enough: it
    /// excludes `-`, which would wrongly turn `logged-in` into `logged%2Din`.
    private static let unreservedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    private let dataKey: String?
    private var lastValue: String?

    init(dataKey: String?, initialState: ParamState = ParamState(value: 0)) {
        self.dataKey = dataKey
        self.lastValue = initialState.lastDataValue
    }

    @discardableResult
    func handle(data: [String: Any]?, tabID: EventHubTabID) -> Bool {
        guard let dataKey, let data, let raw = data[dataKey] else { return false }
        guard let encoded = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]),
              let compact = String(data: encoded, encoding: .utf8) else {
            Logger.eventHub.error("data parameter for key \(dataKey, privacy: .public) is not JSON-serialisable, value dropped")
            return false
        }
        lastValue = compact.addingPercentEncoding(withAllowedCharacters: Self.unreservedCharacters)
        return true
    }

    var state: ParamState { ParamState(value: 0, lastDataValue: lastValue) }
    func restoreState(_ state: ParamState) { lastValue = state.lastDataValue }

    func queryValue() -> String? { lastValue }
}

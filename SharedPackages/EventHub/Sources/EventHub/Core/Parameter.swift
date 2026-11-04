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

import CryptoKit
import Foundation
import os.log

/// A single pixel parameter's runtime behavior. `CounterParameter` owns its counter value and the
/// stop-at-max-bucket logic; `DataParameter` owns only its last-seen value. Neither de-duplicates:
/// the hub takes that decision once at ingestion, so everything reaching a parameter is a delivery.
protocol Parameter: AnyObject {
    /// Processes an event whose source already matched this parameter's config source (or, for an
    /// immediate-trigger's data param, the triggering event itself). Returns `true` if state changed.
    @discardableResult
    func handle(data: [String: Any]?) -> Bool

    var state: ParamState { get }
    func restoreState(_ state: ParamState)

    /// The value to emit for this parameter when the owning pixel fires, or `nil` if this parameter
    /// has nothing to report (e.g. a counter with no matching bucket).
    func queryValue() -> String?
}

enum ParameterFactory {
    /// Builds the parameter for a pixel's running period.
    static func make(_ config: TelemetryParameterConfig) -> Parameter? {
        if config.template == .counter, let buckets = config.buckets {
            return CounterParameter(buckets: buckets)
        }
        if config.template == .data {
            return DataParameter(dataKey: config.dataKey)
        }
        if config.template == .distinct, let buckets = config.buckets, let dataKey = config.dataKey {
            return DistinctCounterParameter(buckets: buckets, dataKey: dataKey)
        }
        return nil
    }

}

final class CounterParameter: Parameter {
    private let buckets: BucketList
    private var value: Int
    private var stopCounting: Bool

    init(buckets: BucketList, initialState: ParamState = ParamState(value: 0)) {
        self.buckets = buckets
        self.value = initialState.value
        self.stopCounting = initialState.stopCounting
    }

    @discardableResult
    func handle(data: [String: Any]?) -> Bool {
        guard !stopCounting else { return false }
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

/// Counts the distinct string values that events carry under `dataKey`, so a value that arrives many times in
/// a period counts once.
///
/// Only a short hash of each value is kept, in memory and in the persisted state, so a stored period does not
/// contain the values themselves. Like `CounterParameter`, it stops once the count reaches the top bucket, which
/// also caps the number of hashes held.
final class DistinctCounterParameter: Parameter {
    private let buckets: BucketList
    private let dataKey: String
    private var seen: Set<String>
    private var stopCounting: Bool

    init(buckets: BucketList, dataKey: String, initialState: ParamState = ParamState(value: 0)) {
        self.buckets = buckets
        self.dataKey = dataKey
        self.seen = Set(initialState.seenValues ?? [])
        self.stopCounting = initialState.stopCounting
    }

    @discardableResult
    func handle(data: [String: Any]?) -> Bool {
        guard !stopCounting, let value = data?[dataKey] as? String, !value.isEmpty else { return false }
        guard seen.insert(Self.hash(value)).inserted else { return false }
        if BucketCounter.shouldStopCounting(seen.count, buckets: buckets) {
            stopCounting = true
        }
        return true
    }

    var state: ParamState { ParamState(value: seen.count, stopCounting: stopCounting, seenValues: seen.sorted()) }

    func restoreState(_ state: ParamState) {
        seen = Set(state.seenValues ?? [])
        stopCounting = state.stopCounting
    }

    func queryValue() -> String? { BucketCounter.bucketCount(seen.count, buckets: buckets) }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Carries a value forwarded from an event payload, as compact JSON (`overlay` → `"overlay"`,
/// `{"a": true}` → `{"a":true}`).
///
/// Percent-encoding belongs to the pixel transport, not here — `URL.appendingParameters` →
/// `URLQueryItem(percentEncodingName:)` on macOS, `APIRequestV2`'s `URLComponents.queryItems` on iOS.
/// Both encode with an allowed set that excludes `%`, so any escaping applied to the value here would
/// be escaped again and the endpoint would need two decodes to reach the payload.
final class DataParameter: Parameter {
    private let dataKey: String?
    private var lastValue: String?

    init(dataKey: String?, initialState: ParamState = ParamState(value: 0)) {
        self.dataKey = dataKey
        self.lastValue = initialState.lastDataValue
    }

    /// Every event of the parameter's source assigns, so an event whose payload lacks `dataKey`
    /// leaves the parameter with *no* value rather than the previous one — the pixel then reports what
    /// the latest event carried, not a stale reading from an earlier one.
    @discardableResult
    func handle(data: [String: Any]?) -> Bool {
        guard let dataKey else { return false }
        guard let raw = data?[dataKey] else { return clear() }
        guard let encoded = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]),
              let compact = String(data: encoded, encoding: .utf8) else {
            Logger.eventHub.error("data parameter for key \(dataKey, privacy: .public) is not JSON-serialisable, value dropped")
            return clear()
        }
        guard lastValue != compact else { return false }
        lastValue = compact
        return true
    }

    /// Drops any recorded value, reporting whether that was a change.
    private func clear() -> Bool {
        guard lastValue != nil else { return false }
        lastValue = nil
        return true
    }

    var state: ParamState { ParamState(value: 0, lastDataValue: lastValue) }
    func restoreState(_ state: ParamState) { lastValue = state.lastDataValue }

    func queryValue() -> String? { lastValue }
}

//
//  DuckAiUsageLimits.swift
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

/// One metering window from the Duck.ai usage snapshot.
public struct DuckAiUsageLimitWindow: Equatable {

    /// Percentage of the user's limit consumed, 0–100. Already clamped by the web app; fractional values are normal.
    /// The underlying used/limit counts are deliberately never exposed, so they can't be derived from this.
    public let percentUsed: Double

    /// The UTC instant at which this window resets. Always in the future — expired windows are dropped at decode time.
    public let resetsAt: Date

    public init(percentUsed: Double, resetsAt: Date) {
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
    }
}

/// Privacy-safe projection of the user's Duck.ai usage, written by the web app into the reserved
/// `usageLimits` native-storage entry and read on demand by native.
///
/// Both windows are optional and independent: a missing window means "no data for this window", never zero usage.
/// The snapshot is only refreshed while the Duck.ai web app is running, so a window may well be stale — `resetsAt`
/// is the only staleness signal there is, and `make(entryValue:now:)` uses it to drop windows that have already reset.
public struct DuckAiUsageLimits: Equatable {

    /// The backend's `day` window.
    public let daily: DuckAiUsageLimitWindow?

    /// The backend's `iso_week` window — a week starting Monday on UTC boundaries, not a rolling 7 days.
    public let weekly: DuckAiUsageLimitWindow?

    /// No usable usage information. Produced by an absent key, an empty snapshot (`"{}"`), a value that
    /// doesn't parse, and by every window having expired. All of those mean the same thing to a caller:
    /// we don't know the user's usage, so don't warn.
    public static let noData = DuckAiUsageLimits(daily: nil, weekly: nil)

    public var hasData: Bool { daily != nil || weekly != nil }

    public init(daily: DuckAiUsageLimitWindow?, weekly: DuckAiUsageLimitWindow?) {
        self.daily = daily
        self.weekly = weekly
    }

    /// Decodes the raw `usageLimits` entry value. Never throws — anything unexpected degrades to no-data rather
    /// than to an error, because a malformed snapshot must not be distinguishable from an absent one at the call site.
    ///
    /// The entries namespace mirrors the web app's `localStorage`, so the stored value is a JSON-encoded `String`.
    /// A dictionary is accepted too, defensively, in case a future writer stores the object directly.
    ///
    /// Windows are decoded independently: one malformed window doesn't discard the other. A window whose `resetsAt`
    /// is at or before `now` is dropped — a window that has already reset has unknown current usage, and reporting
    /// its last-seen percentage would show a stale "you're at your limit" long after the limit lifted.
    public static func make(entryValue: Any?, now: Date) -> DuckAiUsageLimits {
        guard let root = rootObject(from: entryValue) else { return .noData }
        return DuckAiUsageLimits(daily: window(from: root["daily"], now: now),
                                 weekly: window(from: root["weekly"], now: now))
    }

    private static func rootObject(from value: Any?) -> [String: Any]? {
        switch value {
        case let json as String:
            guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = json.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        case let object as [String: Any]:
            return object
        default:
            return nil
        }
    }

    private static func window(from value: Any?, now: Date) -> DuckAiUsageLimitWindow? {
        guard let object = value as? [String: Any],
              let percentUsed = percentUsed(from: object["percentUsed"]),
              let resetsAt = date(from: object["resetsAt"]),
              resetsAt > now else { return nil }
        return DuckAiUsageLimitWindow(percentUsed: percentUsed, resetsAt: resetsAt)
    }

    /// Read through `NSNumber` so both integer- and double-encoded percentages decode. Clamped defensively:
    /// the web app clamps already, but a value we can't render sensibly is worse than a slightly wrong one.
    /// The `CFBoolean` check rejects `true`/`false`, which would otherwise bridge to `1`/`0`.
    private static func percentUsed(from value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite else { return nil }
        return min(max(percent, 0), 100)
    }

    /// The web app writes `Date.toISOString()`, so fractional seconds are always present. The plain
    /// internet-date-time fallback costs nothing and keeps a hand-seeded or future timestamp from being dropped.
    private static func date(from value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

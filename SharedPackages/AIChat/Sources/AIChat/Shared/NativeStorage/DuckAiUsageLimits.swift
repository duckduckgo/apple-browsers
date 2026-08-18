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

public struct DuckAiUsageLimitWindow: Equatable {

    /// 0–100, clamped web-side. The underlying counts are deliberately never exposed.
    public let percentUsed: Double

    public let resetsAt: Date

    public init(percentUsed: Double, resetsAt: Date) {
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
    }
}

/// Usage snapshot the Duck.ai web app writes into the reserved `usageLimits` entry.
/// A missing window means "no data for this window", never zero usage.
public struct DuckAiUsageLimits: Equatable {

    public let daily: DuckAiUsageLimitWindow?

    /// The backend's `iso_week` window: Monday-start, UTC boundaries, not a rolling 7 days.
    public let weekly: DuckAiUsageLimitWindow?

    public static let noData = DuckAiUsageLimits(daily: nil, weekly: nil)

    public var hasData: Bool { daily != nil || weekly != nil }

    public init(daily: DuckAiUsageLimitWindow?, weekly: DuckAiUsageLimitWindow?) {
        self.daily = daily
        self.weekly = weekly
    }

    /// Anything unexpected degrades to no-data, so a malformed snapshot can't be told apart from an absent one.
    /// A window past its reset is dropped: its last-seen percentage would warn long after the limit lifted.
    public static func make(entryValue: Any?, now: Date) -> DuckAiUsageLimits {
        guard let root = rootObject(from: entryValue) else { return .noData }
        return DuckAiUsageLimits(daily: window(from: root["daily"], now: now),
                                 weekly: window(from: root["weekly"], now: now))
    }

    /// The entries namespace mirrors the web app's `localStorage`, so the value is a JSON-encoded string.
    /// A dictionary is accepted defensively, in case a future writer stores the object directly.
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

    /// The `CFBoolean` check rejects `true`/`false`, which would otherwise bridge to `1`/`0`.
    private static func percentUsed(from value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite else { return nil }
        return min(max(percent, 0), 100)
    }

    /// `Date.toISOString()` always carries fractional seconds; the fallback covers hand-seeded timestamps.
    private static func date(from value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

//
//  DailyUsagePayload.swift
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

struct DailyUsagePayload: Codable, Equatable {
    let usageDate: String
    let daysAgo: Int
    let open: String
    let active: String

    enum CodingKeys: String, CodingKey {
        case usageDate = "usage_date"
        case daysAgo = "days_ago"
        case open, active
    }

    init(record: UsageDayRecord, asOf date: Date) {
        let calendar = UsageTimeTracker.calendar
        let day = calendar.startOfDay(for: record.firstSignal)
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        usageDate = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        daysAgo = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: date)).day!
        open = Self.bucket(seconds: record.open)
        active = Self.bucket(seconds: record.active)
    }

    static func bucket(seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0" }
        let thresholds = [30, 60, 120, 180, 300, 420, 600]
        guard seconds >= 30 * 60 else { return "(0,30)" }
        for (lower, upper) in zip(thresholds, thresholds.dropFirst()) where seconds < Double(upper * 60) {
            return "[\(lower),\(upper))"
        }
        return "[600,+∞)"
    }
}

extension UsageDayRecord {
    func reportIfEligible(asOf date: Date) -> Delivery? {
        guard delivery == nil, date.timeIntervalSince(firstSignal) >= 86_400 else { return nil }
        let payload = DailyUsagePayload(record: self, asOf: date)
        guard (1...7).contains(payload.daysAgo) else { return nil }
        return Delivery(finalizedAt: date, payload: payload)
    }
}

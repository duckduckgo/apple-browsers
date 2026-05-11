//
//  RecurrenceRuleParser.swift
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

import EventKit
import Foundation

/// Parses an RRULE into an `EKRecurrenceRule`. Recognises the common subset documented in the
/// package README. Unsupported parts (BYSETPOS, BYWEEKNO, etc.) are silently ignored.
///
/// COUNT is converted to UNTIL when the math is unambiguous (no BY-rules, or a single
/// BYDAY/BYMONTHDAY/BYMONTH). Otherwise the rule keeps `EKRecurrenceEnd(occurrenceCount:)`.
enum RecurrenceRuleParser {

    static func parse(_ value: String, startDate: Date) throws -> EKRecurrenceRule {
        var freq: EKRecurrenceFrequency?
        var interval = 1
        var count: Int?
        var until: Date?
        var byDay: [EKRecurrenceDayOfWeek] = []
        var byMonthDay: [Int] = []
        var byMonth: [Int] = []

        for part in value.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { continue }
            let key = String(pieces[0]).uppercased()
            let rawValue = String(pieces[1])

            switch key {
            case "FREQ":
                freq = try parseFrequency(rawValue, original: value)
            case "INTERVAL":
                guard let intervalValue = Int(rawValue), intervalValue >= 1 else {
                    throw ICSParser.Error.malformedRecurrenceRule(raw: value)
                }
                interval = intervalValue
            case "COUNT":
                guard let countValue = Int(rawValue), countValue >= 1 else {
                    throw ICSParser.Error.malformedRecurrenceRule(raw: value)
                }
                count = countValue
            case "UNTIL":
                until = parseUntil(rawValue)
            case "BYDAY":
                byDay = rawValue.split(separator: ",").compactMap { parseByDay(String($0)) }
            case "BYMONTHDAY":
                byMonthDay = rawValue.split(separator: ",").compactMap { Int($0) }
            case "BYMONTH":
                byMonth = rawValue.split(separator: ",").compactMap { Int($0) }
            default:
                break
            }
        }

        guard let frequency = freq else {
            throw ICSParser.Error.malformedRecurrenceRule(raw: value)
        }

        let end = recurrenceEnd(
            count: count,
            until: until,
            frequency: frequency,
            interval: interval,
            byDay: byDay,
            byMonthDay: byMonthDay,
            byMonth: byMonth,
            startDate: startDate
        )

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: byDay.isEmpty ? nil : byDay,
            daysOfTheMonth: byMonthDay.isEmpty ? nil : byMonthDay.map { NSNumber(value: $0) },
            monthsOfTheYear: byMonth.isEmpty ? nil : byMonth.map { NSNumber(value: $0) },
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private static func parseFrequency(_ raw: String, original: String) throws -> EKRecurrenceFrequency {
        switch raw.uppercased() {
        case "DAILY": return .daily
        case "WEEKLY": return .weekly
        case "MONTHLY": return .monthly
        case "YEARLY": return .yearly
        default: throw ICSParser.Error.malformedRecurrenceRule(raw: original)
        }
    }

    /// Parses a single BYDAY token: bare weekday code (`MO`) or weekday with positional prefix
    /// (`1MO` for the first Monday, `-1FR` for the last Friday).
    private static func parseByDay(_ token: String) -> EKRecurrenceDayOfWeek? {
        let trimmed = token.trimmingCharacters(in: .whitespaces).uppercased()
        guard let firstLetterIndex = trimmed.firstIndex(where: { $0.isLetter }) else { return nil }
        let prefix = String(trimmed[..<firstLetterIndex])
        let dayCode = String(trimmed[firstLetterIndex...])

        let weekday: EKWeekday
        switch dayCode {
        case "SU": weekday = .sunday
        case "MO": weekday = .monday
        case "TU": weekday = .tuesday
        case "WE": weekday = .wednesday
        case "TH": weekday = .thursday
        case "FR": weekday = .friday
        case "SA": weekday = .saturday
        default: return nil
        }

        if prefix.isEmpty {
            return EKRecurrenceDayOfWeek(weekday)
        }
        // RFC 5545 §3.3.10: the BYDAY positional integer is in [-53, 53] excluding 0.
        guard let weekNumber = Int(prefix),
              weekNumber != 0,
              (-53...53).contains(weekNumber) else {
            return nil
        }
        return EKRecurrenceDayOfWeek(weekday, weekNumber: weekNumber)
    }

    /// Per RFC 5545 §3.3.10, UNTIL is UTC for time-anchored DTSTARTs. Date-only form accepted
    /// because some producers emit it.
    private static func parseUntil(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyyMMdd'T'HHmmss'Z'", "yyyyMMdd'T'HHmmss", "yyyyMMdd"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: raw) {
                return parsed
            }
        }
        return nil
    }

    private static func recurrenceEnd(
        count: Int?,
        until: Date?,
        frequency: EKRecurrenceFrequency,
        interval: Int,
        byDay: [EKRecurrenceDayOfWeek],
        byMonthDay: [Int],
        byMonth: [Int],
        startDate: Date
    ) -> EKRecurrenceEnd? {
        if let until {
            return EKRecurrenceEnd(end: until)
        }
        guard let count else {
            return nil
        }
        if let convertedDate = countToUntil(
            count: count,
            startDate: startDate,
            frequency: frequency,
            interval: interval,
            byDay: byDay,
            byMonthDay: byMonthDay,
            byMonth: byMonth
        ) {
            return EKRecurrenceEnd(end: convertedDate)
        }
        return EKRecurrenceEnd(occurrenceCount: count)
    }

    /// Returns the date of the Nth occurrence, or nil when BY-rules make the simple math wrong.
    private static func countToUntil(
        count: Int,
        startDate: Date,
        frequency: EKRecurrenceFrequency,
        interval: Int,
        byDay: [EKRecurrenceDayOfWeek],
        byMonthDay: [Int],
        byMonth: [Int]
    ) -> Date? {
        guard count >= 1, interval >= 1 else { return nil }
        if frequency == .weekly, byDay.count > 1 { return nil }
        // Monthly/yearly BYDAY positions (e.g. "1MO") shift the day-of-month each cycle, so
        // simple component arithmetic on DTSTART would land on the wrong date.
        if frequency == .monthly || frequency == .yearly, !byDay.isEmpty { return nil }
        if byMonthDay.count > 1 { return nil }
        if byMonth.count > 1 { return nil }

        let component: Calendar.Component
        switch frequency {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        @unknown default: return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let stepsToLast = (count - 1) * interval
        guard let lastOccurrence = calendar.date(byAdding: component, value: stepsToLast, to: startDate) else {
            return nil
        }
        return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastOccurrence) ?? lastOccurrence
    }
}

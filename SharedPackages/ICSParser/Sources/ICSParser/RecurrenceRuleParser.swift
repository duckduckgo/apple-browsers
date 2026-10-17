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

    /// Output of a successful RRULE parse: the EventKit rule plus any in-scope parts the
    /// parser dropped (BYSETPOS, BYWEEKNO, …).
    struct Parsed {
        let rule: EKRecurrenceRule
        let warnings: [ICSParser.Warning]
    }

    /// RRULE keys recognised by RFC 5545 that this parser does not honour. Their presence is
    /// surfaced as an `unsupportedRRulePart` warning so consumers can record telemetry.
    private static let unsupportedKeys: Set<String> = [
        "BYSETPOS", "BYWEEKNO", "BYYEARDAY", "BYHOUR", "BYMINUTE", "BYSECOND", "WKST"
    ]

    static func parse(_ value: String, startDate: Date) throws -> Parsed {
        var freq: EKRecurrenceFrequency?
        var interval = 1
        var count: Int?
        var until: Date?
        var byDay: [EKRecurrenceDayOfWeek] = []
        var byMonthDay: [Int] = []
        var byMonth: [Int] = []
        var warnings: [ICSParser.Warning] = []

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
                until = try parseUntil(rawValue, original: value)
            case "BYDAY":
                byDay = try rawValue.split(separator: ",").compactMap { try parseByDay(String($0), original: value) }
            case "BYMONTHDAY":
                byMonthDay = try integerList(rawValue, original: value)
            case "BYMONTH":
                byMonth = try integerList(rawValue, original: value)
            case let key where unsupportedKeys.contains(key):
                if !warnings.contains(.unsupportedRRulePart) {
                    warnings.append(.unsupportedRRulePart)
                }
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

        let rule = EKRecurrenceRule(
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
        return Parsed(rule: rule, warnings: warnings)
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
    /// (`1MO` for the first Monday, `-1FR` for the last Friday). Throws on syntactic garbage
    /// (no letters, unknown day code); returns nil for out-of-range positions (RFC says these
    /// are validated at expansion time, so we drop them rather than fail the whole rule).
    private static func parseByDay(_ token: String, original: String) throws -> EKRecurrenceDayOfWeek? {
        let trimmed = token.trimmingCharacters(in: .whitespaces).uppercased()
        guard let firstLetterIndex = trimmed.firstIndex(where: { $0.isLetter }) else {
            throw ICSParser.Error.malformedRecurrenceRule(raw: original)
        }
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
        default: throw ICSParser.Error.malformedRecurrenceRule(raw: original)
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

    /// Throws on any non-integer token so a malformed BYMONTH/BYMONTHDAY value doesn't silently
    /// drop entries and produce a different recurrence than the file specified.
    private static func integerList(_ raw: String, original: String) throws -> [Int] {
        try raw.split(separator: ",").map { token in
            guard let value = Int(token) else {
                throw ICSParser.Error.malformedRecurrenceRule(raw: original)
            }
            return value
        }
    }

    /// Per RFC 5545 §3.3.10, UNTIL is UTC for time-anchored DTSTARTs. Date-only form accepted
    /// because some producers emit it. Throws on unparseable input so a malformed UNTIL does
    /// not silently degrade a finite recurrence to an infinite one.
    private static func parseUntil(_ raw: String, original: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyyMMdd'T'HHmmss'Z'", "yyyyMMdd'T'HHmmss", "yyyyMMdd"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: raw) {
                return parsed
            }
        }
        throw ICSParser.Error.malformedRecurrenceRule(raw: original)
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

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current

        if shouldDeferToOccurrenceCount(
            frequency: frequency,
            startDate: startDate,
            byDay: byDay,
            byMonthDay: byMonthDay,
            byMonth: byMonth,
            calendar: calendar
        ) {
            return nil
        }

        let component: Calendar.Component
        switch frequency {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        @unknown default: return nil
        }

        let stepsToLast = (count - 1) * interval
        guard let lastOccurrence = calendar.date(byAdding: component, value: stepsToLast, to: startDate) else {
            return nil
        }
        return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastOccurrence) ?? lastOccurrence
    }

    /// True when +N component arithmetic on DTSTART would not match the RFC expansion, so the
    /// rule should retain `EKRecurrenceEnd(occurrenceCount:)` and let EventKit do the work.
    private static func shouldDeferToOccurrenceCount(
        frequency: EKRecurrenceFrequency,
        startDate: Date,
        byDay: [EKRecurrenceDayOfWeek],
        byMonthDay: [Int],
        byMonth: [Int],
        calendar: Calendar
    ) -> Bool {
        if byRuleStructureUnsafe(frequency: frequency, byDay: byDay, byMonthDay: byMonthDay, byMonth: byMonth) {
            return true
        }
        return dtstartMisalignsBYRules(
            frequency: frequency,
            startDate: startDate,
            byDay: byDay,
            byMonthDay: byMonthDay,
            byMonth: byMonth,
            calendar: calendar
        )
    }

    /// BY-rule shapes where component arithmetic is unsafe regardless of DTSTART alignment.
    private static func byRuleStructureUnsafe(
        frequency: EKRecurrenceFrequency,
        byDay: [EKRecurrenceDayOfWeek],
        byMonthDay: [Int],
        byMonth: [Int]
    ) -> Bool {
        // Daily + BYDAY filters which weekdays count, so +N days overshoots by skipped days.
        if frequency == .daily, !byDay.isEmpty { return true }
        if frequency == .weekly, byDay.count > 1 { return true }
        // Monthly/yearly BYDAY positions (e.g. "1MO") shift the day-of-month each cycle.
        if frequency == .monthly || frequency == .yearly, !byDay.isEmpty { return true }
        if byMonthDay.count > 1 { return true }
        if byMonth.count > 1 { return true }
        return false
    }

    /// BY-rule shapes where component arithmetic only works when DTSTART already matches the
    /// single-value BY-rule, plus the day-clamping cases for monthly/yearly arithmetic.
    private static func dtstartMisalignsBYRules(
        frequency: EKRecurrenceFrequency,
        startDate: Date,
        byDay: [EKRecurrenceDayOfWeek],
        byMonthDay: [Int],
        byMonth: [Int],
        calendar: Calendar
    ) -> Bool {
        let startWeekday = calendar.component(.weekday, from: startDate)
        let startDay = calendar.component(.day, from: startDate)
        let startMonth = calendar.component(.month, from: startDate)

        if frequency == .weekly, let only = byDay.first, startWeekday != only.dayOfTheWeek.rawValue {
            return true
        }
        // Monthly + single BYMONTHDAY: +N months keeps DTSTART's day, not the BYMONTHDAY day.
        if frequency == .monthly, let only = byMonthDay.first, startDay != only {
            return true
        }
        // Yearly + single BYMONTH/BYMONTHDAY: +N years keeps DTSTART's month and day; both
        // must already match the BY-rule values to land on the right occurrence.
        if frequency == .yearly, let only = byMonth.first, startMonth != only {
            return true
        }
        if frequency == .yearly, let only = byMonthDay.first, startDay != only {
            return true
        }
        // Calendar clamps day-of-month, so DTSTART on day 29/30/31 + N months can undershoot.
        if frequency == .monthly, startDay > 28 { return true }
        if frequency == .yearly, startMonth == 2, startDay == 29 { return true }
        return false
    }
}

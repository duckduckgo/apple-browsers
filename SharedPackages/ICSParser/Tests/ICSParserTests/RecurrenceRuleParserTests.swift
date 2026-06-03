//
//  RecurrenceRuleParserTests.swift
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
import Testing
@testable import ICSParser

@Suite("RecurrenceRuleParser")
struct RecurrenceRuleParserTests {

    @available(iOS 16, macOS 13, *)
    @Test("Parses basic FREQ + INTERVAL", .timeLimit(.minutes(1)))
    func parsesFrequencyAndInterval() throws {
        let parsed = try RecurrenceRuleParser.parse("FREQ=DAILY;INTERVAL=2", startDate: utcDate("2026-06-01T00:00:00Z"))
        #expect(parsed.rule.frequency == .daily)
        #expect(parsed.rule.interval == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses BYDAY with positional weekday", .timeLimit(.minutes(1)))
    func parsesPositionalByDay() throws {
        let parsed = try RecurrenceRuleParser.parse("FREQ=MONTHLY;BYDAY=1MO", startDate: utcDate("2026-06-01T00:00:00Z"))
        #expect(parsed.rule.frequency == .monthly)
        let days = parsed.rule.daysOfTheWeek ?? []
        try #require(days.count == 1)
        #expect(days[0].dayOfTheWeek == .monday)
        #expect(days[0].weekNumber == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses negative positional BYDAY (-1FR = last Friday)", .timeLimit(.minutes(1)))
    func parsesNegativePositionalByDay() throws {
        let parsed = try RecurrenceRuleParser.parse("FREQ=MONTHLY;BYDAY=-1FR", startDate: utcDate("2026-06-01T00:00:00Z"))
        let days = parsed.rule.daysOfTheWeek ?? []
        try #require(days.count == 1)
        #expect(days[0].dayOfTheWeek == .friday)
        #expect(days[0].weekNumber == -1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses UNTIL preserving the explicit end date", .timeLimit(.minutes(1)))
    func parsesUntil() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=DAILY;UNTIL=20260630T235959Z",
            startDate: utcDate("2026-06-01T09:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.endDate == utcDate("2026-06-30T23:59:59Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Converts COUNT to UNTIL for simple weekly+BYDAY rules", .timeLimit(.minutes(1)))
    func convertsCountToUntilForSimpleCases() throws {
        // Jun 1 is a Monday; 4 weekly Mondays => last on Jun 22.
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=WEEKLY;COUNT=4;BYDAY=MO",
            startDate: utcDate("2026-06-01T14:00:00Z")
        )
        let endDate = parsed.rule.recurrenceEnd?.endDate
        #expect(endDate == utcDate("2026-06-22T23:59:59Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Leaves COUNT as occurrenceCount when math is non-trivial (multi-BYDAY)", .timeLimit(.minutes(1)))
    func leavesCountWhenMultiByDay() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=WEEKLY;COUNT=4;BYDAY=MO,WE,FR",
            startDate: utcDate("2026-06-01T14:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 4)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    /// Daily + BYDAY filters expansion to specific weekdays (e.g. `FREQ=DAILY;BYDAY=MO` ≡
    /// "Mondays"). Simple +N days arithmetic would skip the gaps and undershoot. Keep COUNT.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT for daily RRULE with BYDAY filter", .timeLimit(.minutes(1)))
    func keepsCountForDailyWithByDay() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=DAILY;COUNT=4;BYDAY=MO",
            startDate: utcDate("2026-06-01T09:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 4)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    /// When DTSTART's weekday differs from the single BYDAY, +N weeks arithmetic lands on the
    /// wrong weekday, so EventKit would expand too few occurrences. Must fall back to COUNT.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT when weekly BYDAY does not match DTSTART weekday", .timeLimit(.minutes(1)))
    func keepsCountWhenWeeklyByDayMisalignedWithStart() throws {
        // 2026-06-03 is a Wednesday; BYDAY=MO is a different weekday.
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=WEEKLY;COUNT=4;BYDAY=MO",
            startDate: utcDate("2026-06-03T14:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 4)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    /// Calendar.date(byAdding: .month) clamps to the last valid day. DTSTART on Jan 31 + 1
    /// month yields Feb 28, so +N months arithmetic understates the real Nth occurrence.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT for monthly RRULE when DTSTART is on day 29/30/31", .timeLimit(.minutes(1)))
    func keepsCountForMonthlyHighDayOfMonth() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;COUNT=12",
            startDate: utcDate("2026-01-31T09:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 12)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    /// Yearly + DTSTART on Feb 29 clamps to Feb 28 in non-leap years, so +N years arithmetic
    /// undershoots the Nth real occurrence (only leap years).
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT for yearly RRULE when DTSTART is on Feb 29", .timeLimit(.minutes(1)))
    func keepsCountForYearlyLeapDayStart() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=YEARLY;COUNT=10",
            startDate: utcDate("2024-02-29T12:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 10)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule when FREQ is missing", .timeLimit(.minutes(1)))
    func throwsWithoutFrequency() {
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: "INTERVAL=1")) {
            try RecurrenceRuleParser.parse("INTERVAL=1", startDate: utcDate("2026-06-01T00:00:00Z"))
        }
    }

    /// RFC 5545 §3.3.10: INTERVAL must be a positive integer. A `0` value would otherwise
    /// silently fall through to the default `interval = 1`.
    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule for non-positive INTERVAL", .timeLimit(.minutes(1)))
    func throwsForZeroInterval() {
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: "FREQ=DAILY;INTERVAL=0")) {
            try RecurrenceRuleParser.parse("FREQ=DAILY;INTERVAL=0", startDate: utcDate("2026-06-01T00:00:00Z"))
        }
    }

    /// COUNT=0 would generate no occurrences; reject like other invalid RRULE values.
    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule for non-positive COUNT", .timeLimit(.minutes(1)))
    func throwsForZeroCount() {
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: "FREQ=DAILY;COUNT=0")) {
            try RecurrenceRuleParser.parse("FREQ=DAILY;COUNT=0", startDate: utcDate("2026-06-01T00:00:00Z"))
        }
    }

    /// `parseUntil` accepts the naive datetime form (no Z), used by floating-time RRULEs.
    @available(iOS 16, macOS 13, *)
    @Test("Parses UNTIL in naive datetime form (no Z suffix)", .timeLimit(.minutes(1)))
    func parsesUntilNaiveDateTimeForm() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=DAILY;UNTIL=20260630T235959",
            startDate: utcDate("2026-06-01T09:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.endDate == utcDate("2026-06-30T23:59:59Z"))
    }

    /// `parseUntil` accepts the date-only form some producers emit despite the RFC asking for
    /// a time-anchored value to match DTSTART's type.
    @available(iOS 16, macOS 13, *)
    @Test("Parses UNTIL in date-only form", .timeLimit(.minutes(1)))
    func parsesUntilDateOnlyForm() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=DAILY;UNTIL=20260630",
            startDate: utcDate("2026-06-01T09:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.endDate == utcDate("2026-06-30T00:00:00Z"))
    }

    /// Happy path for the daily COUNT-to-UNTIL shortcut: no BYDAY, DTSTART + (count-1) days.
    @available(iOS 16, macOS 13, *)
    @Test("Converts COUNT to UNTIL for plain daily rules", .timeLimit(.minutes(1)))
    func convertsCountToUntilForPlainDaily() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=DAILY;COUNT=5",
            startDate: utcDate("2026-06-01T09:00:00Z")
        )
        // 5 daily occurrences: Jun 1, 2, 3, 4, 5. Last at end-of-day Jun 5.
        #expect(parsed.rule.recurrenceEnd?.endDate == utcDate("2026-06-05T23:59:59Z"))
    }

    /// Happy path for the monthly COUNT-to-UNTIL shortcut with DTSTART day ≤ 28.
    @available(iOS 16, macOS 13, *)
    @Test("Converts COUNT to UNTIL for plain monthly rules on a safe day-of-month", .timeLimit(.minutes(1)))
    func convertsCountToUntilForPlainMonthly() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;COUNT=6",
            startDate: utcDate("2026-01-15T09:00:00Z")
        )
        // 6 monthly occurrences from Jan 15: last is Jun 15.
        #expect(parsed.rule.recurrenceEnd?.endDate == utcDate("2026-06-15T23:59:59Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule for unknown FREQ", .timeLimit(.minutes(1)))
    func throwsForUnknownFrequency() {
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: "FREQ=HOURLY")) {
            try RecurrenceRuleParser.parse("FREQ=HOURLY", startDate: utcDate("2026-06-01T00:00:00Z"))
        }
    }

    /// A malformed UNTIL must not be silently dropped: that would turn a finite recurrence
    /// into an infinite one. The parser must surface the error like other RRULE field errors.
    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule for unparseable UNTIL", .timeLimit(.minutes(1)))
    func throwsForMalformedUntil() {
        let raw = "FREQ=DAILY;UNTIL=2026-06-30"
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: raw)) {
            try RecurrenceRuleParser.parse(raw, startDate: utcDate("2026-06-01T09:00:00Z"))
        }
    }

    /// Silently dropping a bad BYMONTHDAY token would change the recurrence (e.g. `15,abc,31`
    /// would behave as `15,31`). Must surface the error.
    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule for non-integer BYMONTHDAY token", .timeLimit(.minutes(1)))
    func throwsForMalformedByMonthDay() {
        let raw = "FREQ=MONTHLY;BYMONTHDAY=15,abc,31"
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: raw)) {
            try RecurrenceRuleParser.parse(raw, startDate: utcDate("2026-01-15T09:00:00Z"))
        }
    }

    /// Unknown day codes are syntactic errors and must throw, matching how BYMONTHDAY/BYMONTH
    /// treat non-integer tokens. Out-of-range positional prefixes are a separate, lenient case.
    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule for unknown BYDAY day code", .timeLimit(.minutes(1)))
    func throwsForUnknownByDayCode() {
        let raw = "FREQ=WEEKLY;BYDAY=MO,XX,FR"
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: raw)) {
            try RecurrenceRuleParser.parse(raw, startDate: utcDate("2026-06-01T00:00:00Z"))
        }
    }

    /// Same shape as the BYMONTHDAY case: a non-integer token must throw, not be dropped.
    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule for non-integer BYMONTH token", .timeLimit(.minutes(1)))
    func throwsForMalformedByMonth() {
        let raw = "FREQ=YEARLY;BYMONTH=12,xyz"
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: raw)) {
            try RecurrenceRuleParser.parse(raw, startDate: utcDate("2026-12-25T09:00:00Z"))
        }
    }

    /// Monthly + single BYMONTHDAY: +N months keeps DTSTART's day. When BYMONTHDAY differs,
    /// our shortcut lands on the wrong day; keep COUNT semantics.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT when monthly BYMONTHDAY does not match DTSTART day", .timeLimit(.minutes(1)))
    func keepsCountWhenMonthlyByMonthDayMisaligned() throws {
        // DTSTART on day 10; BYMONTHDAY=15 picks a different day each month.
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;COUNT=12;BYMONTHDAY=15",
            startDate: utcDate("2026-06-10T09:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 12)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    /// Yearly + single BYMONTH: +N years keeps DTSTART's month. Misaligned BYMONTH shifts the
    /// effective month each cycle; defer to occurrence count.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT when yearly BYMONTH does not match DTSTART month", .timeLimit(.minutes(1)))
    func keepsCountWhenYearlyByMonthMisaligned() throws {
        // DTSTART in March; BYMONTH=6 picks June each year.
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=YEARLY;COUNT=5;BYMONTH=6",
            startDate: utcDate("2026-03-15T09:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 5)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    /// Yearly + single BYMONTHDAY similarly needs DTSTART's day to match.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT when yearly BYMONTHDAY does not match DTSTART day", .timeLimit(.minutes(1)))
    func keepsCountWhenYearlyByMonthDayMisaligned() throws {
        // DTSTART on day 10; BYMONTHDAY=20 shifts the day of the month each year.
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=YEARLY;COUNT=5;BYMONTHDAY=20",
            startDate: utcDate("2026-06-10T09:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 5)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Drops BYDAY tokens with invalid week numbers (0 or out of range)", .timeLimit(.minutes(1)))
    func dropsByDayTokensWithInvalidWeekNumbers() throws {
        // 0MO and 99MO are invalid; MO is valid. Only the valid token should survive.
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;BYDAY=0MO,99MO,MO",
            startDate: utcDate("2026-06-01T00:00:00Z")
        )
        let days = parsed.rule.daysOfTheWeek ?? []
        try #require(days.count == 1)
        #expect(days[0].dayOfTheWeek == .monday)
        #expect(days[0].weekNumber == 0) // EKRecurrenceDayOfWeek without weekNumber reports 0
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses BYMONTH and BYMONTHDAY", .timeLimit(.minutes(1)))
    func parsesByMonthAndByMonthDay() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25",
            startDate: utcDate("2026-12-25T00:00:00Z")
        )
        #expect(parsed.rule.frequency == .yearly)
        #expect(parsed.rule.monthsOfTheYear == [12])
        #expect(parsed.rule.daysOfTheMonth == [25])
    }

    /// RFC 5545 §3.3.10 forbids both COUNT and UNTIL in the same RRULE. Real-world files
    /// occasionally include both; we honour UNTIL and ignore COUNT to give a deterministic end.
    @available(iOS 16, macOS 13, *)
    @Test("UNTIL takes precedence over COUNT when both are present", .timeLimit(.minutes(1)))
    func untilWinsOverCountWhenBothPresent() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=DAILY;COUNT=10;UNTIL=20260131T235959Z",
            startDate: utcDate("2026-01-01T09:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.endDate == utcDate("2026-01-31T23:59:59Z"))
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 0)
    }

    /// RFC 5545 §3.3.10 restricts BYMONTHDAY to ±1..31. We pass values through to EventKit
    /// rather than validating; this test pins the lenient behaviour so a future tightening
    /// is an explicit decision.
    @available(iOS 16, macOS 13, *)
    @Test("Passes BYMONTHDAY values through to EventKit without bounds-checking", .timeLimit(.minutes(1)))
    func leavesBYMONTHDAYBoundsCheckingToEventKit() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;BYMONTHDAY=32",
            startDate: utcDate("2026-01-01T00:00:00Z")
        )
        #expect(parsed.rule.daysOfTheMonth == [32])
    }

    /// Positional BYDAY rules like `1MO` shift the actual day-of-month each cycle, so
    /// component arithmetic from DTSTART can't compute the Nth occurrence reliably. The rule
    /// must fall back to occurrenceCount semantics for monthly/yearly + BYDAY.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT semantics for monthly RRULE with positional BYDAY", .timeLimit(.minutes(1)))
    func keepsCountForMonthlyPositionalByDay() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;BYDAY=1MO;COUNT=12",
            startDate: utcDate("2026-06-01T16:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 12)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT semantics for yearly RRULE with positional BYDAY", .timeLimit(.minutes(1)))
    func keepsCountForYearlyPositionalByDay() throws {
        let parsed = try RecurrenceRuleParser.parse(
            "FREQ=YEARLY;BYDAY=-1FR;COUNT=5",
            startDate: utcDate("2026-12-25T00:00:00Z")
        )
        #expect(parsed.rule.recurrenceEnd?.occurrenceCount == 5)
        #expect(parsed.rule.recurrenceEnd?.endDate == nil)
    }

    // MARK: - Helpers

    private func utcDate(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

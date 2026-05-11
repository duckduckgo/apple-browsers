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
        let rule = try RecurrenceRuleParser.parse("FREQ=DAILY;INTERVAL=2", startDate: utcDate("2026-06-01T00:00:00Z"))
        #expect(rule.frequency == .daily)
        #expect(rule.interval == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses BYDAY with positional weekday", .timeLimit(.minutes(1)))
    func parsesPositionalByDay() throws {
        let rule = try RecurrenceRuleParser.parse("FREQ=MONTHLY;BYDAY=1MO", startDate: utcDate("2026-06-01T00:00:00Z"))
        #expect(rule.frequency == .monthly)
        let days = rule.daysOfTheWeek ?? []
        try #require(days.count == 1)
        #expect(days[0].dayOfTheWeek == .monday)
        #expect(days[0].weekNumber == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses negative positional BYDAY (-1FR = last Friday)", .timeLimit(.minutes(1)))
    func parsesNegativePositionalByDay() throws {
        let rule = try RecurrenceRuleParser.parse("FREQ=MONTHLY;BYDAY=-1FR", startDate: utcDate("2026-06-01T00:00:00Z"))
        let days = rule.daysOfTheWeek ?? []
        try #require(days.count == 1)
        #expect(days[0].dayOfTheWeek == .friday)
        #expect(days[0].weekNumber == -1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses UNTIL preserving the explicit end date", .timeLimit(.minutes(1)))
    func parsesUntil() throws {
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=DAILY;UNTIL=20260630T235959Z",
            startDate: utcDate("2026-06-01T09:00:00Z")
        )
        #expect(rule.recurrenceEnd?.endDate == utcDate("2026-06-30T23:59:59Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Converts COUNT to UNTIL for simple weekly+BYDAY rules", .timeLimit(.minutes(1)))
    func convertsCountToUntilForSimpleCases() throws {
        // Jun 1 is a Monday; 4 weekly Mondays => last on Jun 22.
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=WEEKLY;COUNT=4;BYDAY=MO",
            startDate: utcDate("2026-06-01T14:00:00Z")
        )
        let endDate = rule.recurrenceEnd?.endDate
        #expect(endDate == utcDate("2026-06-22T23:59:59Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Leaves COUNT as occurrenceCount when math is non-trivial (multi-BYDAY)", .timeLimit(.minutes(1)))
    func leavesCountWhenMultiByDay() throws {
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=WEEKLY;COUNT=4;BYDAY=MO,WE,FR",
            startDate: utcDate("2026-06-01T14:00:00Z")
        )
        #expect(rule.recurrenceEnd?.occurrenceCount == 4)
        #expect(rule.recurrenceEnd?.endDate == nil)
    }

    /// When DTSTART's weekday differs from the single BYDAY, +N weeks arithmetic lands on the
    /// wrong weekday, so EventKit would expand too few occurrences. Must fall back to COUNT.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT when weekly BYDAY does not match DTSTART weekday", .timeLimit(.minutes(1)))
    func keepsCountWhenWeeklyByDayMisalignedWithStart() throws {
        // 2026-06-03 is a Wednesday; BYDAY=MO is a different weekday.
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=WEEKLY;COUNT=4;BYDAY=MO",
            startDate: utcDate("2026-06-03T14:00:00Z")
        )
        #expect(rule.recurrenceEnd?.occurrenceCount == 4)
        #expect(rule.recurrenceEnd?.endDate == nil)
    }

    /// Calendar.date(byAdding: .month) clamps to the last valid day. DTSTART on Jan 31 + 1
    /// month yields Feb 28, so +N months arithmetic understates the real Nth occurrence.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT for monthly RRULE when DTSTART is on day 29/30/31", .timeLimit(.minutes(1)))
    func keepsCountForMonthlyHighDayOfMonth() throws {
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;COUNT=12",
            startDate: utcDate("2026-01-31T09:00:00Z")
        )
        #expect(rule.recurrenceEnd?.occurrenceCount == 12)
        #expect(rule.recurrenceEnd?.endDate == nil)
    }

    /// Yearly + DTSTART on Feb 29 clamps to Feb 28 in non-leap years, so +N years arithmetic
    /// undershoots the Nth real occurrence (only leap years).
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT for yearly RRULE when DTSTART is on Feb 29", .timeLimit(.minutes(1)))
    func keepsCountForYearlyLeapDayStart() throws {
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=YEARLY;COUNT=10",
            startDate: utcDate("2024-02-29T12:00:00Z")
        )
        #expect(rule.recurrenceEnd?.occurrenceCount == 10)
        #expect(rule.recurrenceEnd?.endDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule when FREQ is missing", .timeLimit(.minutes(1)))
    func throwsWithoutFrequency() {
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: "INTERVAL=1")) {
            try RecurrenceRuleParser.parse("INTERVAL=1", startDate: utcDate("2026-06-01T00:00:00Z"))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedRecurrenceRule for unknown FREQ", .timeLimit(.minutes(1)))
    func throwsForUnknownFrequency() {
        #expect(throws: ICSParser.Error.malformedRecurrenceRule(raw: "FREQ=HOURLY")) {
            try RecurrenceRuleParser.parse("FREQ=HOURLY", startDate: utcDate("2026-06-01T00:00:00Z"))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Drops BYDAY tokens with invalid week numbers (0 or out of range)", .timeLimit(.minutes(1)))
    func dropsByDayTokensWithInvalidWeekNumbers() throws {
        // 0MO and 99MO are invalid; MO is valid. Only the valid token should survive.
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;BYDAY=0MO,99MO,MO",
            startDate: utcDate("2026-06-01T00:00:00Z")
        )
        let days = rule.daysOfTheWeek ?? []
        try #require(days.count == 1)
        #expect(days[0].dayOfTheWeek == .monday)
        #expect(days[0].weekNumber == 0) // EKRecurrenceDayOfWeek without weekNumber reports 0
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses BYMONTH and BYMONTHDAY", .timeLimit(.minutes(1)))
    func parsesByMonthAndByMonthDay() throws {
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25",
            startDate: utcDate("2026-12-25T00:00:00Z")
        )
        #expect(rule.frequency == .yearly)
        #expect(rule.monthsOfTheYear == [12])
        #expect(rule.daysOfTheMonth == [25])
    }

    /// RFC 5545 §3.3.10 forbids both COUNT and UNTIL in the same RRULE. Real-world files
    /// occasionally include both; we honour UNTIL and ignore COUNT to give a deterministic end.
    @available(iOS 16, macOS 13, *)
    @Test("UNTIL takes precedence over COUNT when both are present", .timeLimit(.minutes(1)))
    func untilWinsOverCountWhenBothPresent() throws {
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=DAILY;COUNT=10;UNTIL=20260131T235959Z",
            startDate: utcDate("2026-01-01T09:00:00Z")
        )
        #expect(rule.recurrenceEnd?.endDate == utcDate("2026-01-31T23:59:59Z"))
        #expect(rule.recurrenceEnd?.occurrenceCount == 0)
    }

    /// RFC 5545 §3.3.10 restricts BYMONTHDAY to ±1..31. We pass values through to EventKit
    /// rather than validating; this test pins the lenient behaviour so a future tightening
    /// is an explicit decision.
    @available(iOS 16, macOS 13, *)
    @Test("Passes BYMONTHDAY values through to EventKit without bounds-checking", .timeLimit(.minutes(1)))
    func leavesBYMONTHDAYBoundsCheckingToEventKit() throws {
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;BYMONTHDAY=32",
            startDate: utcDate("2026-01-01T00:00:00Z")
        )
        #expect(rule.daysOfTheMonth == [32])
    }

    /// Positional BYDAY rules like `1MO` shift the actual day-of-month each cycle, so
    /// component arithmetic from DTSTART can't compute the Nth occurrence reliably. The rule
    /// must fall back to occurrenceCount semantics for monthly/yearly + BYDAY.
    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT semantics for monthly RRULE with positional BYDAY", .timeLimit(.minutes(1)))
    func keepsCountForMonthlyPositionalByDay() throws {
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=MONTHLY;BYDAY=1MO;COUNT=12",
            startDate: utcDate("2026-06-01T16:00:00Z")
        )
        #expect(rule.recurrenceEnd?.occurrenceCount == 12)
        #expect(rule.recurrenceEnd?.endDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Keeps COUNT semantics for yearly RRULE with positional BYDAY", .timeLimit(.minutes(1)))
    func keepsCountForYearlyPositionalByDay() throws {
        let rule = try RecurrenceRuleParser.parse(
            "FREQ=YEARLY;BYDAY=-1FR;COUNT=5",
            startDate: utcDate("2026-12-25T00:00:00Z")
        )
        #expect(rule.recurrenceEnd?.occurrenceCount == 5)
        #expect(rule.recurrenceEnd?.endDate == nil)
    }

    // MARK: - Helpers

    private func utcDate(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

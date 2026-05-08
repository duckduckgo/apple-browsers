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

    // MARK: - Helpers

    private func utcDate(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

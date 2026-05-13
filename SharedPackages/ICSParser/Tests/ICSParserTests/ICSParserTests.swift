//
//  ICSParserTests.swift
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
import Testing
@testable import ICSParser

@Suite("ICSParser API")
struct ICSParserTests {

    @available(iOS 16, macOS 13, *)
    @Test("Parses a single timed UTC event", .timeLimit(.minutes(1)))
    func parsesSingleTimedEvent() throws {
        let events = try ICSParser.parse(data: fixture("single-event")).events
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.title == "Single Event Test")
        #expect(event.location == "Test Location")
        #expect(event.url == URL(string: "https://duckduckgo.com"))
        #expect(event.notes == "Single event used to validate basic UTC date parsing.")
        #expect(event.isAllDay == false)
        #expect(event.startDate == iso("2026-06-01T14:00:00Z"))
        #expect(event.endDate == iso("2026-06-01T15:00:00Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses an all-day event with VALUE=DATE", .timeLimit(.minutes(1)))
    func parsesAllDayEvent() throws {
        let events = try ICSParser.parse(data: fixture("all-day")).events
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.title == "All Day Event")
        #expect(event.isAllDay == true)
        #expect(event.startDate == iso("2026-06-15T00:00:00Z"))
        // RFC 5545: end of an all-day event is exclusive, expressed as the next day at midnight.
        #expect(event.endDate == iso("2026-06-16T00:00:00Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unescapes commas, semicolons, and newlines in text values", .timeLimit(.minutes(1)))
    func unescapesTextValues() throws {
        let events = try ICSParser.parse(data: fixture("multi-line-description")).events
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.notes == "Line one.\nLine two with a comma, and a semicolon; included.\nLine three.")
        #expect(event.location == "Building A, Room 42")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Returns every parsed event when the file has multiple VEVENTs", .timeLimit(.minutes(1)))
    func returnsAllEventsForMultiVEvent() throws {
        let events = try ICSParser.parse(data: fixture("multi-vevent")).events
        #expect(events.count == 3)
        #expect(events.map(\.title) == ["First Event", "Second Event", "Third Event"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws notVCalendar for non-VCALENDAR input", .timeLimit(.minutes(1)))
    func throwsForNonVCalendar() {
        #expect(throws: ICSParser.Error.notVCalendar) {
            try ICSParser.parse(string: "not a calendar file")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Resolves IANA TZID to the correct UTC instant", .timeLimit(.minutes(1)))
    func resolvesIANATZID() throws {
        let events = try ICSParser.parse(data: fixture("timezone-iana")).events
        try #require(events.count == 1)
        let event = events[0]
        // DTSTART = 2026-06-01 14:00 in America/New_York. June is EDT (UTC-4), so 18:00 UTC.
        #expect(event.startDate == iso("2026-06-01T18:00:00Z"))
        #expect(event.endDate == iso("2026-06-01T19:00:00Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Resolves Outlook-style TZID via the CLDR mapping", .timeLimit(.minutes(1)))
    func resolvesOutlookTZID() throws {
        let events = try ICSParser.parse(data: fixture("timezone-outlook")).events
        try #require(events.count == 1)
        let event = events[0]
        // "Eastern Standard Time" maps to America/New_York. Same UTC instant as the IANA fixture.
        #expect(event.startDate == iso("2026-06-01T18:00:00Z"))
        #expect(event.endDate == iso("2026-06-01T19:00:00Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws unrecognizedTimeZone for unknown TZIDs", .timeLimit(.minutes(1)))
    func throwsForUnknownTZID() {
        #expect(throws: ICSParser.Error.unrecognizedTimeZone(tzid: "Definitely Not A Real Timezone")) {
            try ICSParser.parse(data: fixture("timezone-unrecognized"))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Derives endDate from DURATION when DTEND is missing", .timeLimit(.minutes(1)))
    func usesDurationWhenDTEndIsMissing() throws {
        let events = try ICSParser.parse(data: fixture("duration-timed")).events
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.startDate == iso("2026-06-01T14:00:00Z"))
        // DTSTART + PT1H30M
        #expect(event.endDate == iso("2026-06-01T15:30:00Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Derives endDate from DURATION for all-day Outlook-style events", .timeLimit(.minutes(1)))
    func usesDurationForAllDayEvents() throws {
        let events = try ICSParser.parse(data: fixture("duration-allday")).events
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.isAllDay == true)
        // DTSTART = 2026-06-15 (date-only), DURATION = P1D => +86400 seconds.
        #expect(event.endDate.timeIntervalSince(event.startDate) == 86_400)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Defaults to a 1-hour event when DTEND and DURATION are both missing", .timeLimit(.minutes(1)))
    func defaultsToOneHourWhenDurationMissing() throws {
        let events = try ICSParser.parse(data: fixture("duration-missing")).events
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.endDate.timeIntervalSince(event.startDate) == 3_600)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses weekly RRULE with COUNT and BYDAY (with COUNT→UNTIL conversion)", .timeLimit(.minutes(1)))
    func parsesWeeklyRecurrenceWithCountConversion() throws {
        let events = try ICSParser.parse(data: fixture("recurring-weekly")).events
        try #require(events.count == 1)
        let event = events[0]
        let rule = try #require(event.recurrenceRule)
        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 1)
        // Jun 1 is a Monday; 4 weekly Mondays => last on Jun 22.
        #expect(rule.recurrenceEnd?.endDate == iso("2026-06-22T23:59:59Z"))
        let days = rule.daysOfTheWeek ?? []
        try #require(days.count == 1)
        #expect(days[0].dayOfTheWeek == .monday)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses daily RRULE with explicit UNTIL", .timeLimit(.minutes(1)))
    func parsesDailyRecurrenceWithUntil() throws {
        let events = try ICSParser.parse(data: fixture("recurring-daily-until")).events
        try #require(events.count == 1)
        let event = events[0]
        let rule = try #require(event.recurrenceRule)
        #expect(rule.frequency == .daily)
        #expect(rule.recurrenceEnd?.endDate == iso("2026-06-30T23:59:59Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses monthly RRULE with positional BYDAY (first Monday)", .timeLimit(.minutes(1)))
    func parsesMonthlyPositionalRecurrence() throws {
        let events = try ICSParser.parse(data: fixture("recurring-monthly-positional")).events
        try #require(events.count == 1)
        let event = events[0]
        let rule = try #require(event.recurrenceRule)
        #expect(rule.frequency == .monthly)
        let days = rule.daysOfTheWeek ?? []
        try #require(days.count == 1)
        #expect(days[0].dayOfTheWeek == .monday)
        #expect(days[0].weekNumber == 1)
        // COUNT-to-UNTIL conversion is unsafe for monthly BYDAY because the day-of-month
        // shifts each cycle. The rule must keep COUNT semantics so EventKit expands correctly.
        #expect(rule.recurrenceEnd?.occurrenceCount == 12)
        #expect(rule.recurrenceEnd?.endDate == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses yearly RRULE with BYMONTH and BYMONTHDAY", .timeLimit(.minutes(1)))
    func parsesYearlyRecurrence() throws {
        let events = try ICSParser.parse(data: fixture("recurring-yearly")).events
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.isAllDay == true)
        #expect(event.startDate == iso("2026-12-25T00:00:00Z"))
        let rule = try #require(event.recurrenceRule)
        #expect(rule.frequency == .yearly)
        #expect(rule.monthsOfTheYear == [12])
        #expect(rule.daysOfTheMonth == [25])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Strips a leading UTF-8 BOM before parsing", .timeLimit(.minutes(1)))
    func stripsLeadingBOM() throws {
        let events = try ICSParser.parse(data: fixture("bom-prefixed")).events
        try #require(events.count == 1)
        #expect(events[0].title == "BOM-Prefixed File")
    }

    // MARK: - Error paths

    @available(iOS 16, macOS 13, *)
    @Test("Throws noVEvent for VCALENDAR with no VEVENT components", .timeLimit(.minutes(1)))
    func throwsForCalendarWithNoEvent() {
        #expect(throws: ICSParser.Error.noVEvent) {
            try ICSParser.parse(data: fixture("no-vevent"))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws missingRequiredField when DTSTART is absent", .timeLimit(.minutes(1)))
    func throwsForMissingDTSTART() {
        #expect(throws: ICSParser.Error.missingRequiredField(field: "DTSTART")) {
            try ICSParser.parse(data: fixture("missing-dtstart"))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedDate when DTSTART can't be parsed", .timeLimit(.minutes(1)))
    func throwsForMalformedDTSTART() {
        #expect(throws: ICSParser.Error.malformedDate(field: "DTSTART", raw: "not-a-real-date")) {
            try ICSParser.parse(data: fixture("malformed-date"))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedDuration when DURATION can't be parsed", .timeLimit(.minutes(1)))
    func throwsForMalformedDURATION() {
        #expect(throws: ICSParser.Error.malformedDuration(raw: "nonsense")) {
            try ICSParser.parse(data: fixture("malformed-duration"))
        }
    }

    /// RFC 5545 §3.3.5 requires HHMMSS for the time portion. A 4-digit HHMM form must not
    /// be silently accepted as 14:30:00 — that would corrupt event times.
    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedDate when DTSTART omits the seconds component", .timeLimit(.minutes(1)))
    func throwsForDateMissingSeconds() {
        #expect(throws: ICSParser.Error.malformedDate(field: "DTSTART", raw: "20260615T1430")) {
            try ICSParser.parse(data: fixture("malformed-truncated-time"))
        }
    }

    /// 2026 is not a leap year. DateFormatter (non-lenient) rejects Feb 29 instead of rolling
    /// over to Mar 1. This test pins that behaviour so a future formatter change can't silently
    /// shift events by a day.
    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedDate for Feb 29 in a non-leap year", .timeLimit(.minutes(1)))
    func throwsForFeb29InNonLeapYear() {
        #expect(throws: ICSParser.Error.malformedDate(field: "DTSTART", raw: "20260229T120000Z")) {
            try ICSParser.parse(data: fixture("malformed-leap-day"))
        }
    }

    /// RFC 5545 §3.2 lets parameter values be DQUOTE-wrapped to contain `:`. The parser must
    /// not split the line at the colon inside the quoted TZID; it should extract the literal
    /// TZID and surface unrecognizedTimeZone since the value is not resolvable.
    @available(iOS 16, macOS 13, *)
    @Test("Handles quoted TZID values containing a colon without splitting at the wrong colon", .timeLimit(.minutes(1)))
    func handlesQuotedTZIDWithColon() {
        #expect(throws: ICSParser.Error.unrecognizedTimeZone(tzid: "GMT+02:00 (Athens)")) {
            try ICSParser.parse(data: fixture("timezone-quoted-with-colon"))
        }
    }

    /// Current behaviour: a single malformed VEVENT aborts the entire parse. Pinned here so
    /// any future move toward tolerant parsing (return valid events, surface failures) is an
    /// explicit decision rather than an accidental change.
    @available(iOS 16, macOS 13, *)
    @Test("Aborts the whole parse if any VEVENT in the file is malformed", .timeLimit(.minutes(1)))
    func abortsOnMalformedEventInMultiVEventFile() {
        #expect(throws: ICSParser.Error.malformedDate(field: "DTSTART", raw: "not-a-real-date")) {
            try ICSParser.parse(data: fixture("multi-vevent-with-malformed"))
        }
    }

    /// Unknown / X-prefixed properties are skipped silently rather than failing the event.
    /// Pins the default branch of `PropertyParser`'s key switch.
    @available(iOS 16, macOS 13, *)
    @Test("Ignores unknown properties without failing the event", .timeLimit(.minutes(1)))
    func ignoresUnknownProperties() throws {
        let raw = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:x@example.com
        DTSTART:20260601T140000Z
        DTEND:20260601T150000Z
        SUMMARY:Has unknown props
        X-APPLE-FOO:something
        CATEGORIES:Work,Meeting
        ATTENDEE;CN=Bob:mailto:bob@example.com
        END:VEVENT
        END:VCALENDAR
        """
        let events = try ICSParser.parse(string: raw).events
        try #require(events.count == 1)
        #expect(events[0].title == "Has unknown props")
    }

    /// An empty URL value drops to nil instead of failing the event; pins the optional-metadata
    /// behaviour. (`URL(string:)` is otherwise very lenient and accepts most strings.)
    @available(iOS 16, macOS 13, *)
    @Test("Drops an empty URL value to nil without failing the event", .timeLimit(.minutes(1)))
    func dropsEmptyURLSilently() throws {
        let raw = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:badurl@example.com
        DTSTART:20260601T140000Z
        DTEND:20260601T150000Z
        SUMMARY:Empty URL
        URL:
        END:VEVENT
        END:VCALENDAR
        """
        let events = try ICSParser.parse(string: raw).events
        try #require(events.count == 1)
        #expect(events[0].url == nil)
        #expect(events[0].title == "Empty URL")
    }

    /// `VALUE=DATE` and `VALUE=DATE-TIME` are distinct RFC 5545 §3.2.20 token values. A naive
    /// substring check on the parameter would mis-classify `VALUE=DATE-TIME` as date-only.
    @available(iOS 16, macOS 13, *)
    @Test("Treats VALUE=DATE-TIME as a timed value, not date-only", .timeLimit(.minutes(1)))
    func valueDateTimeIsNotDateOnly() throws {
        let raw = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:dt@example.com
        DTSTART;VALUE=DATE-TIME:20260601T140000Z
        DTEND;VALUE=DATE-TIME:20260601T150000Z
        SUMMARY:Explicit DATE-TIME value type
        END:VEVENT
        END:VCALENDAR
        """
        let events = try ICSParser.parse(string: raw).events
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.isAllDay == false)
        #expect(event.startDate == iso("2026-06-01T14:00:00Z"))
        #expect(event.endDate == iso("2026-06-01T15:00:00Z"))
    }

    /// RRULE parts the parser ignores (BYSETPOS etc.) surface as an `unsupportedRRulePart`
    /// warning on the parse result, without failing the parse.
    @available(iOS 16, macOS 13, *)
    @Test("Surfaces unsupportedRRulePart warning for ignored RRULE parts", .timeLimit(.minutes(1)))
    func surfacesUnsupportedRRuleWarning() throws {
        let raw = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:bysetpos@example.com
        DTSTART:20260601T090000Z
        SUMMARY:Has BYSETPOS
        RRULE:FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1;COUNT=4
        END:VEVENT
        END:VCALENDAR
        """
        let result = try ICSParser.parse(string: raw)
        #expect(result.events.count == 1)
        #expect(result.warnings == [.unsupportedRRulePart])
    }

    /// A parse with no ignored content surfaces an empty warnings array.
    @available(iOS 16, macOS 13, *)
    @Test("Reports no warnings for fully-supported input", .timeLimit(.minutes(1)))
    func reportsNoWarningsForSupportedInput() throws {
        let result = try ICSParser.parse(data: fixture("single-event"))
        #expect(result.warnings.isEmpty)
    }

    // MARK: - Helpers

    private func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "ics", subdirectory: "Fixtures")!
        return (try? Data(contentsOf: url))!
    }

    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

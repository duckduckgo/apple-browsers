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

@Suite("ICSParser integration")
struct ICSParserTests {

    @available(iOS 16, macOS 13, *)
    @Test("Parses a single timed UTC event", .timeLimit(.minutes(1)))
    func parsesSingleTimedEvent() throws {
        let events = try ICSParser.parse(data: fixture("single-event"))
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
        let events = try ICSParser.parse(data: fixture("all-day"))
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.title == "All Day Event")
        #expect(event.isAllDay == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unescapes commas, semicolons, and newlines in text values", .timeLimit(.minutes(1)))
    func unescapesTextValues() throws {
        let events = try ICSParser.parse(data: fixture("multi-line-description"))
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.notes == "Line one.\nLine two with a comma, and a semicolon; included.\nLine three.")
        #expect(event.location == "Building A, Room 42")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Returns every parsed event when the file has multiple VEVENTs", .timeLimit(.minutes(1)))
    func returnsAllEventsForMultiVEvent() throws {
        let events = try ICSParser.parse(data: fixture("multi-vevent"))
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
        let events = try ICSParser.parse(data: fixture("timezone-iana"))
        try #require(events.count == 1)
        let event = events[0]
        // DTSTART = 2026-06-01 14:00 in America/New_York. June is EDT (UTC-4), so 18:00 UTC.
        #expect(event.startDate == iso("2026-06-01T18:00:00Z"))
        #expect(event.endDate == iso("2026-06-01T19:00:00Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Resolves Outlook-style TZID via the CLDR mapping", .timeLimit(.minutes(1)))
    func resolvesOutlookTZID() throws {
        let events = try ICSParser.parse(data: fixture("timezone-outlook"))
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
        let events = try ICSParser.parse(data: fixture("duration-timed"))
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.startDate == iso("2026-06-01T14:00:00Z"))
        // DTSTART + PT1H30M
        #expect(event.endDate == iso("2026-06-01T15:30:00Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Derives endDate from DURATION for all-day Outlook-style events", .timeLimit(.minutes(1)))
    func usesDurationForAllDayEvents() throws {
        let events = try ICSParser.parse(data: fixture("duration-allday"))
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.isAllDay == true)
        // DTSTART = 2026-06-15 (date-only), DURATION = P1D => +86400 seconds.
        #expect(event.endDate.timeIntervalSince(event.startDate) == 86_400)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Defaults to a 1-hour event when DTEND and DURATION are both missing", .timeLimit(.minutes(1)))
    func defaultsToOneHourWhenDurationMissing() throws {
        let events = try ICSParser.parse(data: fixture("duration-missing"))
        try #require(events.count == 1)
        let event = events[0]
        #expect(event.endDate.timeIntervalSince(event.startDate) == 3_600)
    }

    // MARK: - Helpers

    private func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "ics", subdirectory: "Resources")!
        return (try? Data(contentsOf: url))!
    }

    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}

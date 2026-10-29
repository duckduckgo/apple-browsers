//
//  ICSFileReaderTests.swift
//  DuckDuckGo
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
import ICSParser
import Testing
@testable import DuckDuckGo

@Suite("ICSFileReader")
struct ICSFileReaderTests {

    @available(iOS 16, *)
    @Test("Returns parseFailure when the file can't be read", .timeLimit(.minutes(1)))
    func returnsParseFailureForUnreadableFile() {
        let nonExistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".ics")
        let result = ICSFileReader.read(at: nonExistentURL)
        #expect(result.outcome == .parseFailure)
        #expect(result.warnings.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Returns parseFailure for malformed content", .timeLimit(.minutes(1)))
    func returnsParseFailureForMalformedContent() throws {
        let url = try writeICSFile("not even close to a calendar file")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ICSFileReader.read(at: url)
        #expect(result.outcome == .parseFailure)
    }

    @available(iOS 16, *)
    @Test("Returns singleEvent for a one-VEVENT file", .timeLimit(.minutes(1)))
    func returnsSingleEventForSingleVEvent() throws {
        let url = try writeICSFile(Fixtures.singleEvent)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ICSFileReader.read(at: url)
        guard case .singleEvent(let event) = result.outcome else {
            Issue.record("Expected .singleEvent outcome, got \(result.outcome)")
            return
        }
        #expect(event.title == "Single Event")
        #expect(result.warnings.isEmpty)
    }

    @available(iOS 16, *)
    @Test("Returns multipleEvents when the file contains more than one VEVENT", .timeLimit(.minutes(1)))
    func returnsMultipleEventsForMultiVEvent() throws {
        let url = try writeICSFile(Fixtures.multipleEvents)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ICSFileReader.read(at: url)
        #expect(result.outcome == .multipleEvents)
    }

    @available(iOS 16, *)
    @Test("Returns unrecognizedTimeZone when the parser rejects the TZID", .timeLimit(.minutes(1)))
    func returnsUnrecognizedTimeZoneForUnknownTZID() throws {
        let url = try writeICSFile(Fixtures.unrecognizedTimeZone)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ICSFileReader.read(at: url)
        #expect(result.outcome == .unrecognizedTimeZone)
    }

    @available(iOS 16, *)
    @Test("Surfaces unsupportedRRulePart warning for ignored RRULE parts", .timeLimit(.minutes(1)))
    func surfacesUnsupportedRRuleWarning() throws {
        let url = try writeICSFile(Fixtures.unsupportedRRulePart)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ICSFileReader.read(at: url)
        guard case .singleEvent = result.outcome else {
            Issue.record("Expected .singleEvent outcome, got \(result.outcome)")
            return
        }
        #expect(result.warnings.contains(.unsupportedRRulePart))
    }

    // MARK: - Helpers

    private func writeICSFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".ics")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private enum Fixtures {
        static let singleEvent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:single@example.com
        DTSTART:20260601T140000Z
        DTEND:20260601T150000Z
        SUMMARY:Single Event
        END:VEVENT
        END:VCALENDAR
        """

        static let multipleEvents = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:first@example.com
        DTSTART:20260601T140000Z
        DTEND:20260601T150000Z
        SUMMARY:First Event
        END:VEVENT
        BEGIN:VEVENT
        UID:second@example.com
        DTSTART:20260602T140000Z
        DTEND:20260602T150000Z
        SUMMARY:Second Event
        END:VEVENT
        END:VCALENDAR
        """

        static let unrecognizedTimeZone = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:badtz@example.com
        DTSTART;TZID=Definitely Not A Real Timezone:20260601T140000
        DTEND;TZID=Definitely Not A Real Timezone:20260601T150000
        SUMMARY:Unknown TZID
        END:VEVENT
        END:VCALENDAR
        """

        static let unsupportedRRulePart = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:bysetpos@example.com
        DTSTART:20260601T090000Z
        DTEND:20260601T100000Z
        SUMMARY:Has BYSETPOS
        RRULE:FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1;COUNT=4
        END:VEVENT
        END:VCALENDAR
        """
    }
}

// Test-only equality for ICSFileReader.Outcome (case-only). Comparing the ICSEvent payload
// would require EKRecurrenceRule conformance and isn't needed here.
extension ICSFileReader.Outcome: @retroactive Equatable {
    public static func == (lhs: ICSFileReader.Outcome, rhs: ICSFileReader.Outcome) -> Bool {
        switch (lhs, rhs) {
        case (.singleEvent, .singleEvent),
             (.multipleEvents, .multipleEvents),
             (.unrecognizedTimeZone, .unrecognizedTimeZone),
             (.parseFailure, .parseFailure):
            return true
        default:
            return false
        }
    }
}

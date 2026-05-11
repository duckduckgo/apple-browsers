//
//  PropertyParser.swift
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

/// Walks the lines inside a single VEVENT block (`KEY[;PARAMS]:VALUE` per line) and assembles
/// an `ICSEvent`. The recognised VEVENT subset is documented in the package README.
enum PropertyParser {

    static func parseEvent(from lines: [String]) throws -> ICSEvent {
        var title: String?
        var startDate: Date?
        var endDate: Date?
        var durationRaw: String?
        var rRuleRaw: String?
        var isAllDay = false
        var location: String?
        var notes: String?
        var url: URL?

        for line in lines {
            guard let colonIndex = unquotedColonIndex(in: line) else { continue }
            let keyPart = String(line[..<colonIndex])
            let value = String(line[line.index(after: colonIndex)...])
            let key = keyPart.split(separator: ";").first.map { String($0).uppercased() } ?? keyPart.uppercased()

            switch key {
            case "SUMMARY":
                title = TextUnescaper.unescape(value)
            case "DESCRIPTION":
                notes = TextUnescaper.unescape(value)
            case "LOCATION":
                location = TextUnescaper.unescape(value)
            case "URL":
                // Malformed URLs are dropped silently rather than failing the event: producers
                // sometimes emit unencoded values, and the URL field is optional metadata.
                url = URL(string: value)
            case "DTSTART":
                let parsed = try DateValueParser.parse(value: value, paramPart: keyPart, field: "DTSTART")
                startDate = parsed.date
                if parsed.isAllDay {
                    isAllDay = true
                }
            case "DTEND":
                let parsed = try DateValueParser.parse(value: value, paramPart: keyPart, field: "DTEND")
                endDate = parsed.date
            case "DURATION":
                durationRaw = value
            case "RRULE":
                rRuleRaw = value
            default:
                break
            }
        }

        guard let resolvedStart = startDate else {
            throw ICSParser.Error.missingRequiredField(field: "DTSTART")
        }
        let resolvedEnd = try resolveEndDate(
            start: resolvedStart,
            endDate: endDate,
            durationRaw: durationRaw,
            isAllDay: isAllDay
        )
        let recurrenceRule = try rRuleRaw.map {
            try RecurrenceRuleParser.parse($0, startDate: resolvedStart)
        }

        return ICSEvent(
            title: title,
            startDate: resolvedStart,
            endDate: resolvedEnd,
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            url: url,
            recurrenceRule: recurrenceRule
        )
    }

    /// Per RFC 5545 §3.2, parameter values may be DQUOTE-wrapped to contain `:`, `;`, or `,`.
    /// The first colon outside any quoted region separates the parameter section from the value.
    private static func unquotedColonIndex(in line: String) -> String.Index? {
        var inQuotes = false
        for index in line.indices {
            switch line[index] {
            case "\"":
                inQuotes.toggle()
            case ":" where !inQuotes:
                return index
            default:
                break
            }
        }
        return nil
    }

    /// RFC 5545 §3.6.1 fallback: DTEND, then DTSTART + DURATION, then a default duration.
    private static func resolveEndDate(
        start: Date,
        endDate: Date?,
        durationRaw: String?,
        isAllDay: Bool
    ) throws -> Date {
        if let endDate {
            return endDate
        }
        if let durationRaw {
            let interval = try DurationParser.parse(durationRaw)
            return start.addingTimeInterval(interval)
        }
        if isAllDay {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            // RFC 5545 §3.6.1: an all-day event's end is exclusive (next day at 00:00).
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        // RFC 5545 §3.6.1 specifies a 0-second duration when DTEND and DURATION are both absent
        // for timed events. We diverge to a 1-hour fallback to match Apple Calendar's behaviour
        // and avoid a UX where the event "starts and ends at the same instant".
        return start.addingTimeInterval(3_600)
    }
}

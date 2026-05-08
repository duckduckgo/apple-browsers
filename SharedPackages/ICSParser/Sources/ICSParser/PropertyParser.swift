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

/// Walks the lines inside a single VEVENT block and assembles an `ICSEvent`. Each line is of
/// the form `KEY[;PARAMS]:VALUE`; this parser recognises the VEVENT subset documented in the
/// package README.
///
/// RRULE support, TZID resolution, and DURATION fallback land in subsequent commits.
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
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
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

    /// RFC 5545 §3.6.1 fallback hierarchy: prefer DTEND if present, otherwise DTSTART + DURATION,
    /// otherwise a sensible default (1h for timed events, end-of-day for all-day events).
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
            return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: start) ?? start
        }
        return start.addingTimeInterval(3_600)
    }
}

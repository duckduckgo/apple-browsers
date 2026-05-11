//
//  DateValueParser.swift
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

/// Parses ICS date / date-time values from properties like DTSTART and DTEND.
///
/// Supports the four forms defined in RFC 5545 §3.3.4 and §3.3.5:
/// - Date only (`VALUE=DATE`, `YYYYMMDD`)
/// - UTC date-time (`YYYYMMDDTHHMMSSZ`)
/// - Floating local date-time (`YYYYMMDDTHHMMSS`)
/// - TZID-anchored date-time (`TZID=Region/City:YYYYMMDDTHHMMSS`)
///
/// TZID resolution goes through `TimeZoneResolver`, which handles IANA and Outlook-style names.
/// Unrecognised TZIDs surface as `ICSParser.Error.unrecognizedTimeZone`.
enum DateValueParser {

    struct Parsed {
        let date: Date
        let isAllDay: Bool
    }

    static func parse(value: String, paramPart: String, field: String) throws -> Parsed {
        let params = paramPart.split(separator: ";").map { $0.uppercased() }
        // Token-equal compare so VALUE=DATE-TIME is not misclassified as date-only.
        let isDateOnly = params.contains("VALUE=DATE") || (value.count == 8 && !value.contains("T"))

        let timeZone = try resolveTimeZone(value: value, paramPart: paramPart, isDateOnly: isDateOnly)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        let formats: [String] = isDateOnly
            ? ["yyyyMMdd"]
            : ["yyyyMMdd'T'HHmmss'Z'", "yyyyMMdd'T'HHmmss"]

        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: value) {
                return Parsed(date: parsed, isAllDay: isDateOnly)
            }
        }
        throw ICSParser.Error.malformedDate(field: field, raw: value)
    }

    private static func resolveTimeZone(value: String, paramPart: String, isDateOnly: Bool) throws -> TimeZone {
        // Anchor date-only values in UTC for deterministic parsing across devices. EventKit
        // displays them as all-day in the user's local timezone regardless.
        if isDateOnly || value.hasSuffix("Z") {
            return TimeZone(identifier: "UTC") ?? .current
        }
        if let tzid = TimeZoneResolver.extractTZID(from: paramPart) {
            return try TimeZoneResolver.resolve(tzid: tzid)
        }
        return .current
    }
}

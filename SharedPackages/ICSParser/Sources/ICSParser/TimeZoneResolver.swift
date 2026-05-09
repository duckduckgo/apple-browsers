//
//  TimeZoneResolver.swift
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

/// Resolves a TZID to a `TimeZone`. IANA names go through `TimeZone(identifier:)`;
/// Windows-style names fall back to the bundled CLDR mapping. Unrecognised TZIDs throw
/// rather than guess, since wrong-time events are worse than no event.
enum TimeZoneResolver {

    static func resolve(tzid: String) throws -> TimeZone {
        let trimmed = tzid.trimmingCharacters(in: .whitespaces)
        if let timeZone = TimeZone(identifier: trimmed) {
            return timeZone
        }
        if let iana = WindowsTimeZoneMapping.ianaIdentifier(for: trimmed),
           let timeZone = TimeZone(identifier: iana) {
            return timeZone
        }
        throw ICSParser.Error.unrecognizedTimeZone(tzid: trimmed)
    }

    /// Extracts the TZID parameter from a property's parameter portion, e.g.
    /// `DTSTART;TZID=America/New_York` → `America/New_York`. Returns nil if absent.
    static func extractTZID(from paramPart: String) -> String? {
        for component in paramPart.split(separator: ";") {
            let pieces = component.split(separator: "=", maxSplits: 1)
            if pieces.count == 2 && pieces[0].uppercased() == "TZID" {
                var raw = String(pieces[1])
                // RFC 5545 §3.2: parameter values may be DQUOTE-wrapped. Strip outer quotes.
                if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
                    raw = String(raw.dropFirst().dropLast())
                }
                return raw
            }
        }
        return nil
    }
}

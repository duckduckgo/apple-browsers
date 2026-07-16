//
//  DurationParser.swift
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

/// Parses RFC 5545 §3.3.6 DURATION values into a `TimeInterval` in seconds.
///
/// Recognises the two grammar branches:
/// - `[+|-]P{n}W` (week form, e.g. `P2W`)
/// - `[+|-]P[{n}D][T[{n}H][{n}M][{n}S]]` (day-time form, e.g. `P1DT12H`, `PT1H30M`, `PT45S`)
///
/// Returns a signed interval; negative durations rewind from a base date. Anything that doesn't
/// fit the grammar surfaces as `ICSParser.Error.malformedDuration`.
enum DurationParser {

    static func parse(_ raw: String) throws -> TimeInterval {
        let (sign, body) = stripSignAndPrefix(raw)
        guard !body.isEmpty else {
            throw ICSParser.Error.malformedDuration(raw: raw)
        }

        if body.last == "W" {
            let weeks = try integer(from: body.dropLast(), raw: raw)
            return sign * Double(weeks) * 7 * 86_400
        }

        let (datePart, timePart) = try splitDateAndTime(body, raw: raw)
        let days = try parseDays(datePart, raw: raw)
        let (hours, minutes, seconds) = try parseTimePart(timePart, raw: raw)

        let total = Double(days) * 86_400
            + Double(hours) * 3_600
            + Double(minutes) * 60
            + Double(seconds)
        return sign * total
    }

    private static func stripSignAndPrefix(_ raw: String) -> (Double, Substring) {
        var sign: Double = 1
        var input = Substring(raw.trimmingCharacters(in: .whitespaces))
        if input.first == "+" {
            input = input.dropFirst()
        } else if input.first == "-" {
            sign = -1
            input = input.dropFirst()
        }
        if input.first == "P" {
            input = input.dropFirst()
        } else {
            return (sign, "")
        }
        return (sign, input)
    }

    private static func splitDateAndTime(_ body: Substring, raw: String) throws -> (Substring, Substring) {
        guard let tIndex = body.firstIndex(of: "T") else {
            return (body, "")
        }
        let timePart = body[body.index(after: tIndex)...]
        if timePart.isEmpty {
            throw ICSParser.Error.malformedDuration(raw: raw)
        }
        return (body[..<tIndex], timePart)
    }

    private static func parseDays(_ datePart: Substring, raw: String) throws -> Int {
        guard !datePart.isEmpty else { return 0 }
        guard datePart.last == "D" else {
            throw ICSParser.Error.malformedDuration(raw: raw)
        }
        return try integer(from: datePart.dropLast(), raw: raw)
    }

    private static func parseTimePart(_ timePart: Substring, raw: String) throws -> (Int, Int, Int) {
        var hours = 0
        var minutes = 0
        var seconds = 0
        var digits = ""
        for character in timePart {
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard !digits.isEmpty, let unitValue = Int(digits) else {
                throw ICSParser.Error.malformedDuration(raw: raw)
            }
            digits = ""
            switch character {
            case "H": hours = unitValue
            case "M": minutes = unitValue
            case "S": seconds = unitValue
            default: throw ICSParser.Error.malformedDuration(raw: raw)
            }
        }
        if !digits.isEmpty {
            throw ICSParser.Error.malformedDuration(raw: raw)
        }
        return (hours, minutes, seconds)
    }

    private static func integer(from substring: Substring, raw: String) throws -> Int {
        guard !substring.isEmpty, let value = Int(substring) else {
            throw ICSParser.Error.malformedDuration(raw: raw)
        }
        return value
    }
}

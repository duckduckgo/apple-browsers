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
        var sign: Double = 1
        var input = Substring(raw.trimmingCharacters(in: .whitespaces))

        if input.first == "+" {
            input = input.dropFirst()
        } else if input.first == "-" {
            sign = -1
            input = input.dropFirst()
        }

        guard input.first == "P" else {
            throw ICSParser.Error.malformedDuration(raw: raw)
        }
        input = input.dropFirst()
        guard !input.isEmpty else {
            throw ICSParser.Error.malformedDuration(raw: raw)
        }

        // Week form: digits followed by exactly "W".
        if input.last == "W" {
            let weeks = try integer(from: input.dropLast(), raw: raw)
            return sign * Double(weeks) * 7 * 86_400
        }

        // Day-time form. Optional days, optional T-prefixed time component.
        var days = 0
        var hours = 0
        var minutes = 0
        var seconds = 0

        var datePart: Substring
        var timePart: Substring
        if let tIndex = input.firstIndex(of: "T") {
            datePart = input[..<tIndex]
            timePart = input[input.index(after: tIndex)...]
            if timePart.isEmpty {
                throw ICSParser.Error.malformedDuration(raw: raw)
            }
        } else {
            datePart = input
            timePart = ""
        }

        if !datePart.isEmpty {
            guard datePart.last == "D" else {
                throw ICSParser.Error.malformedDuration(raw: raw)
            }
            days = try integer(from: datePart.dropLast(), raw: raw)
        }

        var current = ""
        for character in timePart {
            if character.isNumber {
                current.append(character)
            } else {
                guard !current.isEmpty, let value = Int(current) else {
                    throw ICSParser.Error.malformedDuration(raw: raw)
                }
                current = ""
                switch character {
                case "H":
                    hours = value
                case "M":
                    minutes = value
                case "S":
                    seconds = value
                default:
                    throw ICSParser.Error.malformedDuration(raw: raw)
                }
            }
        }
        if !current.isEmpty {
            throw ICSParser.Error.malformedDuration(raw: raw)
        }

        let total = Double(days) * 86_400
            + Double(hours) * 3_600
            + Double(minutes) * 60
            + Double(seconds)
        return sign * total
    }

    private static func integer(from substring: Substring, raw: String) throws -> Int {
        guard !substring.isEmpty, let value = Int(substring) else {
            throw ICSParser.Error.malformedDuration(raw: raw)
        }
        return value
    }
}

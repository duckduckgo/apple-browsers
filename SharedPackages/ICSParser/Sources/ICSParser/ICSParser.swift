//
//  ICSParser.swift
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

/// Parses .ics (iCalendar) file content into one or more `ICSEvent` values.
///
/// Scope and out-of-scope items are documented in the package README.
public enum ICSParser {

    public enum Error: Swift.Error, Equatable {
        case decodingFailed
        case notVCalendar
        case noVEvent
        case missingRequiredField(field: String)
        case malformedDate(field: String, raw: String)
        case malformedDuration(raw: String)
        case unrecognizedTimeZone(tzid: String)
        case malformedRecurrenceRule(raw: String)
    }

    /// Parses the given .ics file data.
    ///
    /// - Parameter data: UTF-8-encoded contents of an .ics file.
    /// - Returns: A non-empty array of `ICSEvent`s in document order, one per VEVENT block.
    /// - Throws: `ICSParser.Error` describing the parse failure mode.
    public static func parse(data: Data) throws -> [ICSEvent] {
        guard let raw = String(data: data, encoding: .utf8) else {
            throw Error.decodingFailed
        }
        return try parse(string: raw)
    }

    /// Parses the given .ics file content from a string. Internal entry point for tests.
    static func parse(string raw: String) throws -> [ICSEvent] {
        // Windows .ics exports often include a UTF-8 BOM that survives UTF-8 decoding.
        let stripped = raw.first == "\u{FEFF}" ? String(raw.dropFirst()) : raw
        let lines = LineUnfolder.unfold(stripped)
        let blocks = try VEventExtractor.extract(from: lines)
        return try blocks.map { try PropertyParser.parseEvent(from: $0) }
    }
}

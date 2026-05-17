//
//  TimeZoneResolverTests.swift
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

@Suite("TimeZoneResolver")
struct TimeZoneResolverTests {

    @available(iOS 16, macOS 13, *)
    @Test("Resolves IANA identifiers via Foundation directly", .timeLimit(.minutes(1)))
    func resolvesIANA() throws {
        let timeZone = try TimeZoneResolver.resolve(tzid: "America/New_York")
        #expect(timeZone.identifier == "America/New_York")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Resolves Windows-style names via the CLDR mapping", .timeLimit(.minutes(1)))
    func resolvesWindowsNames() throws {
        let timeZone = try TimeZoneResolver.resolve(tzid: "Eastern Standard Time")
        #expect(timeZone.identifier == "America/New_York")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws unrecognizedTimeZone for unknown TZIDs", .timeLimit(.minutes(1)))
    func throwsForUnknownTZID() {
        #expect(throws: ICSParser.Error.unrecognizedTimeZone(tzid: "Definitely Not A Real Timezone")) {
            try TimeZoneResolver.resolve(tzid: "Definitely Not A Real Timezone")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Trims whitespace in TZID values before resolving", .timeLimit(.minutes(1)))
    func trimsWhitespace() throws {
        let timeZone = try TimeZoneResolver.resolve(tzid: "  America/New_York  ")
        #expect(timeZone.identifier == "America/New_York")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Extracts TZID from a property's parameter portion", .timeLimit(.minutes(1)))
    func extractsTZIDFromParamPart() {
        #expect(TimeZoneResolver.extractTZID(from: "DTSTART;TZID=America/New_York") == "America/New_York")
        #expect(TimeZoneResolver.extractTZID(from: "DTSTART;VALUE=DATE-TIME;TZID=Europe/Berlin") == "Europe/Berlin")
        #expect(TimeZoneResolver.extractTZID(from: "DTSTART") == nil)
    }
}

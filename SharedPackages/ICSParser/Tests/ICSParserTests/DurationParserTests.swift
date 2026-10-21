//
//  DurationParserTests.swift
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

@Suite("DurationParser")
struct DurationParserTests {

    @available(iOS 16, macOS 13, *)
    @Test("Parses week form", .timeLimit(.minutes(1)))
    func parsesWeekForm() throws {
        #expect(try DurationParser.parse("P2W") == 14 * 86_400)
        #expect(try DurationParser.parse("P1W") == 7 * 86_400)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses day form", .timeLimit(.minutes(1)))
    func parsesDayForm() throws {
        #expect(try DurationParser.parse("P1D") == 86_400)
        #expect(try DurationParser.parse("P3D") == 3 * 86_400)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses time-only form", .timeLimit(.minutes(1)))
    func parsesTimeOnlyForm() throws {
        #expect(try DurationParser.parse("PT1H") == 3_600)
        #expect(try DurationParser.parse("PT30M") == 1_800)
        #expect(try DurationParser.parse("PT45S") == 45)
        #expect(try DurationParser.parse("PT1H30M") == 5_400)
        #expect(try DurationParser.parse("PT1H30M15S") == 5_415)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Parses combined day and time form", .timeLimit(.minutes(1)))
    func parsesDayAndTimeForm() throws {
        let oneDayTwelveHours: TimeInterval = 86_400 + 12 * 3_600
        let twoDaysThreeHoursFortyFiveMinutes: TimeInterval = 2 * 86_400 + 3 * 3_600 + 45 * 60
        #expect(try DurationParser.parse("P1DT12H") == oneDayTwelveHours)
        #expect(try DurationParser.parse("P2DT3H45M") == twoDaysThreeHoursFortyFiveMinutes)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Handles signed durations", .timeLimit(.minutes(1)))
    func handlesSignedDurations() throws {
        #expect(try DurationParser.parse("+PT1H") == 3_600)
        #expect(try DurationParser.parse("-P1D") == -86_400)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Throws malformedDuration for invalid input", .timeLimit(.minutes(1)))
    func throwsForInvalidInput() {
        #expect(throws: ICSParser.Error.self) {
            try DurationParser.parse("garbage")
        }
        #expect(throws: ICSParser.Error.self) {
            try DurationParser.parse("P")
        }
        #expect(throws: ICSParser.Error.self) {
            try DurationParser.parse("PT")
        }
        #expect(throws: ICSParser.Error.self) {
            try DurationParser.parse("PT1X")
        }
        #expect(throws: ICSParser.Error.self) {
            try DurationParser.parse("P1H")
        }
    }
}

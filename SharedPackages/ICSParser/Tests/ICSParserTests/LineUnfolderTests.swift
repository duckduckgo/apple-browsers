//
//  LineUnfolderTests.swift
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

@Suite("LineUnfolder")
struct LineUnfolderTests {

    @available(iOS 16, macOS 13, *)
    @Test("Splits LF-separated lines without unfolding non-continuation lines", .timeLimit(.minutes(1)))
    func splitsLFLines() {
        let input = "BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR"
        let result = LineUnfolder.unfold(input)
        #expect(result == ["BEGIN:VCALENDAR", "VERSION:2.0", "END:VCALENDAR"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Normalises CRLF line endings", .timeLimit(.minutes(1)))
    func normalisesCRLF() {
        let input = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR"
        let result = LineUnfolder.unfold(input)
        #expect(result == ["BEGIN:VCALENDAR", "VERSION:2.0", "END:VCALENDAR"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Joins continuation lines starting with a space", .timeLimit(.minutes(1)))
    func joinsSpaceContinuation() {
        let input = "DESCRIPTION:line one\n part two\n part three"
        let result = LineUnfolder.unfold(input)
        #expect(result == ["DESCRIPTION:line onepart twopart three"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Joins continuation lines starting with a tab", .timeLimit(.minutes(1)))
    func joinsTabContinuation() {
        let input = "DESCRIPTION:line one\n\tpart two"
        let result = LineUnfolder.unfold(input)
        #expect(result == ["DESCRIPTION:line onepart two"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Treats a leading space on the first line as a literal line, not a continuation", .timeLimit(.minutes(1)))
    func leadingSpaceOnFirstLineIsLiteral() {
        let input = " orphaned continuation\nBEGIN:VCALENDAR"
        let result = LineUnfolder.unfold(input)
        #expect(result == [" orphaned continuation", "BEGIN:VCALENDAR"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Preserves empty lines between properties", .timeLimit(.minutes(1)))
    func preservesEmptyLines() {
        let input = "BEGIN:VCALENDAR\n\nEND:VCALENDAR"
        let result = LineUnfolder.unfold(input)
        #expect(result == ["BEGIN:VCALENDAR", "", "END:VCALENDAR"])
    }

    /// RFC 5545 §3.1: unfolding runs before escape decoding. An escaped backslash split
    /// across a fold should still decode to a single backslash, not get mangled.
    @available(iOS 16, macOS 13, *)
    @Test("Unfolds before escape decoding so an escape sequence spanning a fold is preserved", .timeLimit(.minutes(1)))
    func unfoldsBeforeEscapeDecoding() throws {
        let input = "SUMMARY:foo \\\n \\n bar"
        let unfolded = LineUnfolder.unfold(input)
        try #require(unfolded == ["SUMMARY:foo \\\\n bar"])
        let value = unfolded[0].split(separator: ":", maxSplits: 1).map(String.init)[1]
        #expect(TextUnescaper.unescape(value) == "foo \\n bar")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Tolerates mixed CRLF and LF terminators in the same input", .timeLimit(.minutes(1)))
    func tolerantOfMixedLineEndings() {
        let input = "BEGIN:VCALENDAR\r\nVERSION:2.0\nBEGIN:VEVENT\r\nEND:VEVENT\nEND:VCALENDAR"
        let result = LineUnfolder.unfold(input)
        #expect(result == ["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", "END:VEVENT", "END:VCALENDAR"])
    }
}

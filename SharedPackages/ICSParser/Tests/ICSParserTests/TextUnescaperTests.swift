//
//  TextUnescaperTests.swift
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

@Suite("TextUnescaper")
struct TextUnescaperTests {

    @available(iOS 16, macOS 13, *)
    @Test("Lowercase \\n becomes a newline", .timeLimit(.minutes(1)))
    func lowercaseN() {
        #expect(TextUnescaper.unescape(#"line one\nline two"#) == "line one\nline two")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Uppercase \\N also becomes a newline", .timeLimit(.minutes(1)))
    func uppercaseN() {
        #expect(TextUnescaper.unescape(#"line one\Nline two"#) == "line one\nline two")
    }

    @available(iOS 16, macOS 13, *)
    @Test("\\, and \\; preserve literal commas and semicolons", .timeLimit(.minutes(1)))
    func commaAndSemicolon() {
        #expect(TextUnescaper.unescape(#"foo\, bar"#) == "foo, bar")
        #expect(TextUnescaper.unescape(#"foo\; bar"#) == "foo; bar")
    }

    @available(iOS 16, macOS 13, *)
    @Test("\\\\ produces a single backslash", .timeLimit(.minutes(1)))
    func backslash() {
        #expect(TextUnescaper.unescape(#"path\\to\\file"#) == #"path\to\file"#)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unknown escape sequences are passed through verbatim", .timeLimit(.minutes(1)))
    func unknownEscapesPassthrough() {
        #expect(TextUnescaper.unescape(#"a\xb"#) == #"a\xb"#)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Trailing backslash with no following character is preserved", .timeLimit(.minutes(1)))
    func trailingBackslash() {
        #expect(TextUnescaper.unescape("foo\\") == "foo\\")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Empty input returns empty string", .timeLimit(.minutes(1)))
    func emptyInput() {
        #expect(TextUnescaper.unescape("") == "")
    }
}

//
//  UTF8PieceBufferTests.swift
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

import Testing
@testable import LlamaRuntime

@Suite("UTF8PieceBuffer")
struct UTF8PieceBufferTests {

    @available(iOS 16, macOS 13, *)
    @Test("ASCII passes straight through", .timeLimit(.minutes(1)))
    func asciiPassesThrough() {
        var buffer = UTF8PieceBuffer()
        #expect(buffer.append(Array("Duck".utf8)) == "Duck")
        #expect(buffer.flush() == "")
    }

    @available(iOS 16, macOS 13, *)
    @Test("An emoji split over three tokens arrives once, whole", .timeLimit(.minutes(1)))
    func emojiSplitAcrossTokens() {
        let bytes = Array("🦆".utf8)
        var buffer = UTF8PieceBuffer()
        #expect(buffer.append([bytes[0]]) == "")
        #expect(buffer.append([bytes[1], bytes[2]]) == "")
        #expect(buffer.append([bytes[3]]) + buffer.flush() == "🦆")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Text before a split character is sent right away", .timeLimit(.minutes(1)))
    func completeTextBeforeSplitCharacter() {
        let accented = Array("é".utf8)
        var buffer = UTF8PieceBuffer()
        #expect(buffer.append(Array("caf".utf8) + [accented[0]]) == "caf")
        #expect(buffer.append([accented[1]]) == "é")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A character left unfinished at the end becomes U+FFFD", .timeLimit(.minutes(1)))
    func unfinishedCharacterAtEnd() {
        var buffer = UTF8PieceBuffer()
        #expect(buffer.append(Array("a".utf8) + [0xE2, 0x82]) == "a")
        #expect(buffer.flush() == "\u{FFFD}")
    }
}

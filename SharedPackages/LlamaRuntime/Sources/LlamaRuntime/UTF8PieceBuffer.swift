//
//  UTF8PieceBuffer.swift
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

/// A token can end partway through a character, such as an emoji or an accented letter, and the
/// next token finishes it. This holds the unfinished bytes back until the character is whole.
struct UTF8PieceBuffer {

    private var pending: [UInt8] = []

    /// Adds a token's bytes and returns the text that is now complete.
    mutating func append(_ bytes: [UInt8]) -> String {
        pending.append(contentsOf: bytes)
        let complete = Self.completePrefixLength(of: pending)
        guard complete > 0 else { return "" }
        let text = Self.decode(pending[..<complete])
        pending.removeFirst(complete)
        return text
    }

    /// Returns whatever is left when generation ends. A broken character becomes U+FFFD.
    mutating func flush() -> String {
        defer { pending = [] }
        return Self.decode(pending)
    }

    /// Model output can contain invalid UTF-8. Replacing the bad bytes keeps the rest of the
    /// answer, where failing the whole conversion would lose it.
    static func decode(_ bytes: some Sequence<UInt8>) -> String {
        var scalars = String.UnicodeScalarView()
        var decoder = UTF8()
        var iterator = bytes.makeIterator()
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): scalars.append(scalar)
            case .error: scalars.append("\u{FFFD}")
            case .emptyInput: return String(scalars)
            }
        }
    }

    /// The length of `bytes` without a trailing character that is still missing bytes.
    static func completePrefixLength(of bytes: [UInt8]) -> Int {
        var index = bytes.count - 1
        var continuationBytes = 0
        while index >= 0, continuationBytes < 3, bytes[index] & 0b1100_0000 == 0b1000_0000 {
            index -= 1
            continuationBytes += 1
        }
        guard index >= 0 else { return bytes.count }

        let expectedLength: Int
        switch bytes[index] {
        case 0xC0..<0xE0: expectedLength = 2
        case 0xE0..<0xF0: expectedLength = 3
        case 0xF0..<0xF8: expectedLength = 4
        default: expectedLength = 1
        }
        return bytes.count - index < expectedLength ? index : bytes.count
    }
}

//
//  JSBloomFilter.swift
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

/// Read-only Bloom filter in the format of the `@duckduckgo/jsbloom` npm package (`checkEntry` only).
/// It uses the same hash functions and bit layout, so it gives the same answers as the DDG extension for the same data.
struct JSBloomFilter: Sendable {

    private let bits: [UInt8]
    private let hashRounds: Int

    private var bitCount: Int { bits.count * 8 }

    /// - Parameters:
    ///   - totalEntries: the number of entries the filter was built for (`totalEntries` in the exported data).
    ///   - bits: the exported filter bits.
    init?(totalEntries: Int, bits: [UInt8]) {
        guard totalEntries > 0, !bits.isEmpty else { return nil }
        self.bits = bits
        // jsbloom: HASH_ROUNDS = Math.round(Math.log(2.0) * BUFFER_LEN / items)
        hashRounds = Int((log(2.0) * Double(bits.count * 8) / Double(totalEntries) + 0.5).rounded(.down))
    }

    func contains(_ entry: String) -> Bool {
        let codeUnits = Array(entry.utf16)
        let h1 = Int(Self.djb2(codeUnits) % UInt32(bitCount))
        let h2 = Int(Self.sdbm(codeUnits) % UInt32(bitCount))
        for round in 0...hashRounds {
            let position: Int
            switch round {
            case 0: position = h1
            case 1: position = h2
            // `^` is XOR, as in jsbloom
            default: position = (h1 + round * h2 + (round ^ 2)) % bitCount
            }
            if !isSet(position) {
                return false
            }
        }
        return true
    }

    /// jsbloom maps position 0 of a byte to its lowest bit, and positions 1 to 7 to its bits from the highest down.
    private func isSet(_ position: Int) -> Bool {
        let offset = position % 8
        let mask: UInt8 = offset == 0 ? 1 : 128 >> (offset - 1)
        return bits[position / 8] & mask != 0
    }

    // jsbloom hashes UTF-16 code units, and its arithmetic overflows like 32-bit integers.
    // So wrapping UInt32 operations give the same values.

    static func djb2(_ codeUnits: [UInt16]) -> UInt32 {
        var hash: UInt32 = 5381
        for codeUnit in codeUnits {
            hash = (hash &* 33) ^ UInt32(codeUnit)
        }
        return hash
    }

    static func sdbm(_ codeUnits: [UInt16]) -> UInt32 {
        var hash: UInt32 = 0
        for codeUnit in codeUnits {
            hash = UInt32(codeUnit) &+ (hash << 6) &+ (hash << 16) &- hash
        }
        return hash
    }
}

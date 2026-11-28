//
//  BLAKE2s.swift
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

/// The sequential BLAKE2s construction from [RFC 7693](https://www.rfc-editor.org/rfc/rfc7693.html).
enum BLAKE2s {
    // BLAKE2s parameters: [RFC 7693 §2.1](https://www.rfc-editor.org/rfc/rfc7693.html#section-2.1).
    static let maximumDigestLength = 32
    static let blockLength = 64
    private static let blake2sRotations: (r1: UInt32, r2: UInt32, r3: UInt32, r4: UInt32) = (16, 12, 8, 7)
    // Sequential hashing fixes fanout and depth to one: [RFC 7693 §2.5](https://www.rfc-editor.org/rfc/rfc7693.html#section-2.5).
    private static let blake2sSequentialParameters: UInt32 = 0x0101_0000

    // Public SHA-256 IV words reused by BLAKE2s: [RFC 7693 §2.6](https://www.rfc-editor.org/rfc/rfc7693.html#section-2.6).
    private static let initializationVector: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    // SIGMA fixes the ten BLAKE2s rounds: [RFC 7693 §2.7](https://www.rfc-editor.org/rfc/rfc7693.html#section-2.7).
    private static let messageSchedule: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]
    ]

    /// Sequential keyed and unkeyed hashing follows [RFC 7693 §3.3](https://www.rfc-editor.org/rfc/rfc7693.html#section-3.3).
    static func hash(_ data: Data, key: Data = Data(), outputLength: Int = maximumDigestLength) -> Data {
        precondition((1...maximumDigestLength).contains(outputLength) && key.count <= maximumDigestLength)
        var state = initializationVector
        state[0] ^= blake2sSequentialParameters ^ UInt32(key.count << 8) ^ UInt32(outputLength)
        var input: [UInt8] = []
        if !key.isEmpty {
            input = [UInt8](key) + [UInt8](repeating: 0, count: blockLength - key.count)
        }
        input.append(contentsOf: data)
        var offset = 0
        // Leave the last complete block for finalization, including a key-only block.
        while offset + blockLength < input.count {
            compress(&state, block: Array(input[offset..<(offset + blockLength)]), count: UInt64(offset + blockLength), last: false)
            offset += blockLength
        }
        let remaining = input.count - offset
        let finalBlock = Array(input[offset...]) + [UInt8](repeating: 0, count: blockLength - remaining)
        compress(&state, block: finalBlock, count: UInt64(input.count), last: true)
        return Data(state.flatMap(littleEndianBytes).prefix(outputLength))
    }

    private static func compress(_ state: inout [UInt32], block: [UInt8], count: UInt64, last: Bool) {
        let words = (0..<16).map { littleEndianWord(block, at: $0 * 4) }
        var work = state + initializationVector
        work[12] ^= UInt32(truncatingIfNeeded: count)
        work[13] ^= UInt32(truncatingIfNeeded: count >> 32)
        if last { work[14] = ~work[14] }
        for schedule in messageSchedule {
            mix(&work, 0, 4, 8, 12, words[schedule[0]], words[schedule[1]])
            mix(&work, 1, 5, 9, 13, words[schedule[2]], words[schedule[3]])
            mix(&work, 2, 6, 10, 14, words[schedule[4]], words[schedule[5]])
            mix(&work, 3, 7, 11, 15, words[schedule[6]], words[schedule[7]])
            mix(&work, 0, 5, 10, 15, words[schedule[8]], words[schedule[9]])
            mix(&work, 1, 6, 11, 12, words[schedule[10]], words[schedule[11]])
            mix(&work, 2, 7, 8, 13, words[schedule[12]], words[schedule[13]])
            mix(&work, 3, 4, 9, 14, words[schedule[14]], words[schedule[15]])
        }
        for index in 0..<8 { state[index] ^= work[index] ^ work[index + 8] }
    }

    private static func mix(_ words: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
        words[a] = words[a] &+ words[b] &+ x
        words[d] = rotateRight(words[d] ^ words[a], by: blake2sRotations.r1)
        words[c] = words[c] &+ words[d]
        words[b] = rotateRight(words[b] ^ words[c], by: blake2sRotations.r2)
        words[a] = words[a] &+ words[b] &+ y
        words[d] = rotateRight(words[d] ^ words[a], by: blake2sRotations.r3)
        words[c] = words[c] &+ words[d]
        words[b] = rotateRight(words[b] ^ words[c], by: blake2sRotations.r4)
    }

    private static func rotateRight(_ word: UInt32, by count: UInt32) -> UInt32 {
        (word >> count) | (word << (32 - count))
    }

    private static func littleEndianWord(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func littleEndianBytes(_ word: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
    }
}

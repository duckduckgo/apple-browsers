//
//  HChaCha20.swift
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

/// HChaCha20 subkey derivation from the [XChaCha draft §2.2](https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#section-2.2).
enum HChaCha20 {
    enum Failure: Error {
        case invalidKeyLength
        case invalidNonceLength
    }

    // HChaCha20 takes a 256-bit key and 128-bit nonce (XChaCha draft §2.2).
    private static let keyLength = 32
    static let nonceLength = 16

    // Public "expand 32-byte k" words and 20 rounds: [RFC 8439 §2.3](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.3).
    private static let chachaConstants: [UInt32] = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
    private static let chachaDoubleRounds = 10
    // Right rotations equivalent to the left rotations in [RFC 8439 §2.1](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.1).
    private static let chachaRightRotations: (r1: UInt32, r2: UInt32, r3: UInt32, r4: UInt32) = (16, 20, 24, 25)

    /// No feedforward: this derives a subkey rather than a ChaCha20 keystream block.
    static func deriveSubkey(key: Data, nonce: Data) throws -> Data {
        guard key.count == keyLength else { throw Failure.invalidKeyLength }
        guard nonce.count == nonceLength else { throw Failure.invalidNonceLength }
        let keyBytes = [UInt8](key)
        let nonceBytes = [UInt8](nonce)
        var state = chachaConstants
        state += (0..<8).map { littleEndianWord(keyBytes, at: $0 * 4) }
        state += (0..<4).map { littleEndianWord(nonceBytes, at: $0 * 4) }
        for _ in 0..<chachaDoubleRounds {
            quarterRound(&state, 0, 4, 8, 12)
            quarterRound(&state, 1, 5, 9, 13)
            quarterRound(&state, 2, 6, 10, 14)
            quarterRound(&state, 3, 7, 11, 15)
            quarterRound(&state, 0, 5, 10, 15)
            quarterRound(&state, 1, 6, 11, 12)
            quarterRound(&state, 2, 7, 8, 13)
            quarterRound(&state, 3, 4, 9, 14)
        }
        return Data((Array(state[0..<4]) + Array(state[12..<16])).flatMap(littleEndianBytes))
    }

    private static func quarterRound(_ words: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        words[a] = words[a] &+ words[b]
        words[d] = rotateRight(words[d] ^ words[a], by: chachaRightRotations.r1)
        words[c] = words[c] &+ words[d]
        words[b] = rotateRight(words[b] ^ words[c], by: chachaRightRotations.r2)
        words[a] = words[a] &+ words[b]
        words[d] = rotateRight(words[d] ^ words[a], by: chachaRightRotations.r3)
        words[c] = words[c] &+ words[d]
        words[b] = rotateRight(words[b] ^ words[c], by: chachaRightRotations.r4)
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

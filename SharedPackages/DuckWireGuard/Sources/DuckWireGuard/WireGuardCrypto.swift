//
//  WireGuardCrypto.swift
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

import CryptoKit
import Foundation

/// The primitives and encodings used by Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s.
/// BLAKE2s follows RFC 7693 sections 2–3; HChaCha20 follows draft-irtf-cfrg-xchacha-03 section 2.2.
/// These Swift implementations are experimental and have not undergone a security audit.
enum WireGuardCrypto {
    enum Failure: Error {
        case invalidKeyLength
        case invalidNonceLength
        case truncatedCiphertext
    }

    static func hash(_ data: Data) -> Data {
        blake2s(data)
    }

    static func mac(key: Data, data: Data) -> Data {
        blake2s(data, key: key, outputLength: 16)
    }

    static func hmac(key: Data, data: Data) -> Data {
        let shortKey = key.count > 64 ? hash(key) : key
        let padded = [UInt8](shortKey) + [UInt8](repeating: 0, count: 64 - shortKey.count)
        let inner = Data(padded.map { $0 ^ 0x36 })
        let outer = Data(padded.map { $0 ^ 0x5c })
        return hash(outer + hash(inner + data))
    }

    /// WireGuard's HKDF expansion has empty info and returns one to three 32-byte outputs.
    static func kdf(key: Data, input: Data, count: Int) -> [Data] {
        precondition((1...3).contains(count))
        let temporaryKey = hmac(key: key, data: input)
        var outputs: [Data] = []
        var previous = Data()
        for index in 1...count {
            previous = hmac(key: temporaryKey, data: previous + Data([UInt8(index)]))
            outputs.append(previous)
        }
        return outputs
    }

    /// Returns ciphertext followed by the authentication tag, without a nonce prefix.
    static func seal(key: Data, counter: UInt64, plaintext: Data, authenticating: Data = Data()) throws -> Data {
        guard key.count == 32 else { throw Failure.invalidKeyLength }
        let sealed = try ChaChaPoly.seal(plaintext,
                                        using: SymmetricKey(data: key),
                                        nonce: nonce(counter: counter),
                                        authenticating: authenticating)
        return sealed.ciphertext + sealed.tag
    }

    static func open(key: Data, counter: UInt64, ciphertext: Data, authenticating: Data = Data()) throws -> Data {
        try open(key: key, nonce: nonce(counter: counter), ciphertext: ciphertext, authenticating: authenticating)
    }

    static func openCookie(key: Data, nonce: Data, ciphertext: Data, authenticating: Data) throws -> Data {
        guard nonce.count == 24 else { throw Failure.invalidNonceLength }
        let subkey = try hchacha20(key: key, nonce: Data(nonce.prefix(16)))
        let shortNonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + nonce.suffix(8))
        return try open(key: subkey, nonce: shortNonce, ciphertext: ciphertext, authenticating: authenticating)
    }

    private static func nonce(counter: UInt64) throws -> ChaChaPoly.Nonce {
        let counterBytes = (0..<8).map { UInt8(truncatingIfNeeded: counter >> ($0 * 8)) }
        return try ChaChaPoly.Nonce(data: Data([UInt8](repeating: 0, count: 4) + counterBytes))
    }

    private static func open(key: Data, nonce: ChaChaPoly.Nonce, ciphertext: Data, authenticating: Data) throws -> Data {
        guard key.count == 32 else { throw Failure.invalidKeyLength }
        guard ciphertext.count >= 16 else { throw Failure.truncatedCiphertext }
        let box = try ChaChaPoly.SealedBox(nonce: nonce,
                                           ciphertext: ciphertext.dropLast(16),
                                           tag: ciphertext.suffix(16))
        return try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: authenticating)
    }

    // MARK: - BLAKE2s

    private static let initializationVector: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

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

    static func blake2s(_ data: Data, key: Data = Data(), outputLength: Int = 32) -> Data {
        precondition((1...32).contains(outputLength) && key.count <= 32)
        var state = initializationVector
        state[0] ^= 0x01010000 ^ UInt32(key.count << 8) ^ UInt32(outputLength)
        var input: [UInt8] = []
        if !key.isEmpty {
            input = [UInt8](key) + [UInt8](repeating: 0, count: 64 - key.count)
        }
        input.append(contentsOf: data)
        var offset = 0
        // Leave the last complete block for finalization, including a key-only block.
        while offset + 64 < input.count {
            compress(&state, block: Array(input[offset..<(offset + 64)]), count: UInt64(offset + 64), last: false)
            offset += 64
        }
        let remaining = input.count - offset
        let finalBlock = Array(input[offset...]) + [UInt8](repeating: 0, count: 64 - remaining)
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
        words[d] = rotateRight(words[d] ^ words[a], by: 16)
        words[c] = words[c] &+ words[d]
        words[b] = rotateRight(words[b] ^ words[c], by: 12)
        words[a] = words[a] &+ words[b] &+ y
        words[d] = rotateRight(words[d] ^ words[a], by: 8)
        words[c] = words[c] &+ words[d]
        words[b] = rotateRight(words[b] ^ words[c], by: 7)
    }

    // MARK: - HChaCha20

    static func hchacha20(key: Data, nonce: Data) throws -> Data {
        guard key.count == 32 else { throw Failure.invalidKeyLength }
        guard nonce.count == 16 else { throw Failure.invalidNonceLength }
        let keyBytes = [UInt8](key)
        let nonceBytes = [UInt8](nonce)
        var state: [UInt32] = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
        state += (0..<8).map { littleEndianWord(keyBytes, at: $0 * 4) }
        state += (0..<4).map { littleEndianWord(nonceBytes, at: $0 * 4) }
        for _ in 0..<10 {
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
        words[d] = rotateRight(words[d] ^ words[a], by: 16)
        words[c] = words[c] &+ words[d]
        words[b] = rotateRight(words[b] ^ words[c], by: 20)
        words[a] = words[a] &+ words[b]
        words[d] = rotateRight(words[d] ^ words[a], by: 24)
        words[c] = words[c] &+ words[d]
        words[b] = rotateRight(words[b] ^ words[c], by: 25)
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

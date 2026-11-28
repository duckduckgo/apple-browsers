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

    // Primitive sizes from [WireGuard §5.4](https://www.wireguard.com/papers/wireguard.pdf#page=9).
    static let keyLength = 32
    static let macLength = 16
    static let hashLength = 32
    // Poly1305's tag is separate from WireGuard's BLAKE2s MAC: [RFC 8439 §2.8](https://www.rfc-editor.org/rfc/rfc8439.html#section-2.8).
    static let authenticationTagLength = 16

    // HMAC's public ipad/opad bytes: [RFC 2104 §2](https://www.rfc-editor.org/rfc/rfc2104.html#section-2).
    private static let hmacInnerPad: UInt8 = 0x36
    private static let hmacOuterPad: UInt8 = 0x5c
    // WireGuard uses KDF1, KDF2 or KDF3: [WireGuard §5.4](https://www.wireguard.com/papers/wireguard.pdf#page=10).
    private static let maximumKDFOutputs = 3

    // WireGuard's counter nonce: [§5.4](https://www.wireguard.com/papers/wireguard.pdf#page=9).
    private static let nonceZeroPrefixLength = 4
    private static let nonceCounterLength = 8
    // XChaCha splits its nonce for HChaCha and ChaCha: [draft §2.3](https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#section-2.3).
    private static let xchachaNonceLength = 24
    private static let xchachaNonceSuffixLength = 8

    static func hash(_ data: Data) -> Data {
        BLAKE2s.hash(data, outputLength: hashLength)
    }

    static func mac(key: Data, data: Data) -> Data {
        BLAKE2s.hash(data, key: key, outputLength: macLength)
    }

    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }

    static func hmac(key: Data, data: Data) -> Data {
        let shortKey = key.count > BLAKE2s.blockLength ? hash(key) : key
        let padded = [UInt8](shortKey) + [UInt8](repeating: 0, count: BLAKE2s.blockLength - shortKey.count)
        let inner = Data(padded.map { $0 ^ hmacInnerPad })
        let outer = Data(padded.map { $0 ^ hmacOuterPad })
        return hash(outer + hash(inner + data))
    }

    /// WireGuard's HKDF expansion has empty info and returns one to three 32-byte outputs.
    /// See the [KDF definition in WireGuard §5.4](https://www.wireguard.com/papers/wireguard.pdf#page=10).
    static func kdf(key: Data, input: Data, count: Int) -> [Data] {
        precondition((1...maximumKDFOutputs).contains(count))
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
        guard key.count == keyLength else { throw Failure.invalidKeyLength }
        let sealed = try ChaChaPoly.seal(plaintext,
                                        using: SymmetricKey(data: key),
                                        nonce: nonce(counter: counter),
                                        authenticating: authenticating)
        return sealed.ciphertext + sealed.tag
    }

    static func open(key: Data, counter: UInt64, ciphertext: Data, authenticating: Data = Data()) throws -> Data {
        try open(key: key, nonce: nonce(counter: counter), ciphertext: ciphertext, authenticating: authenticating)
    }

    /// Cookie replies need the random-nonce construction from [WireGuard §5.4.7](https://www.wireguard.com/papers/wireguard.pdf#page=13).
    /// Its subkey construction is specified in the [XChaCha draft §2.3](https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#section-2.3).
    static func openCookie(key: Data, nonce: Data, ciphertext: Data, authenticating: Data) throws -> Data {
        guard nonce.count == xchachaNonceLength else { throw Failure.invalidNonceLength }
        let subkey = try hchacha20(key: key, nonce: Data(nonce.prefix(HChaCha20.nonceLength)))
        let shortNonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: nonceZeroPrefixLength) + nonce.suffix(xchachaNonceSuffixLength))
        return try open(key: subkey, nonce: shortNonce, ciphertext: ciphertext, authenticating: authenticating)
    }

    private static func nonce(counter: UInt64) throws -> ChaChaPoly.Nonce {
        let counterBytes = (0..<nonceCounterLength).map { UInt8(truncatingIfNeeded: counter >> ($0 * 8)) }
        return try ChaChaPoly.Nonce(data: Data([UInt8](repeating: 0, count: nonceZeroPrefixLength) + counterBytes))
    }

    private static func open(key: Data, nonce: ChaChaPoly.Nonce, ciphertext: Data, authenticating: Data) throws -> Data {
        guard key.count == keyLength else { throw Failure.invalidKeyLength }
        guard ciphertext.count >= authenticationTagLength else { throw Failure.truncatedCiphertext }
        let box = try ChaChaPoly.SealedBox(nonce: nonce,
                                           ciphertext: ciphertext.dropLast(authenticationTagLength),
                                           tag: ciphertext.suffix(authenticationTagLength))
        return try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: authenticating)
    }

    /// Preserve the crypto facade's error contract while the primitive remains independent.
    static func hchacha20(key: Data, nonce: Data) throws -> Data {
        do {
            return try HChaCha20.deriveSubkey(key: key, nonce: nonce)
        } catch let failure as HChaCha20.Failure {
            switch failure {
            case .invalidKeyLength: throw Failure.invalidKeyLength
            case .invalidNonceLength: throw Failure.invalidNonceLength
            }
        }
    }
}

//
//  WireGuardCryptoTests.swift
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
import XCTest
@testable import DuckWireGuard

final class WireGuardCryptoTests: XCTestCase {
    func testBlake2sKnownDigestsAndBlockBoundaries() throws {
        // RFC 7693 BLAKE2s parameters; independently generated using Python hashlib.blake2s.
        let vectors: [(Int, String, String)] = [
            (0, "69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9", "9536f9b267655743dee97b8a670f9f53"),
            (63, "e57cb79487dd57902432b250733813bd96a84efce59f650fac26e6696aefafc3", "ece382a8bd5018f1de5da44b72cea75b"),
            (64, "56f34e8b96557e90c1f24b52d0c89d51086acf1b00f634cf1dde9233b8eaaa3e", "f1efa90d2547036841ecd3627fafbc36"),
            (65, "1b53ee94aaf34e4b159d48de352c7f0661d0a40edff95a0b1639b4090e974472", "811ff8686d23a435ecbd0bdafcd27b1b"),
            (128, "1fa877de67259d19863a2a34bcc6962a2b25fcbf5cbecd7ede8f1fa36688a796", "8c09f698d03eaf88abf69f8147865ef6"),
            (255, "f03f5789d3336b80d002d59fdf918bdb775b00956ed5528e86aa994acb38fe2d", "cd075928ab7e6883e697fe7fd3ac43ee")
        ]
        let key = Data((0..<32).map(UInt8.init))
        for (length, digest, mac) in vectors {
            let input = Data((0..<length).map(UInt8.init))
            XCTAssertEqual(WireGuardCrypto.hash(input), try bytes(digest), "unkeyed length \(length)")
            XCTAssertEqual(WireGuardCrypto.mac(key: key, data: input), try bytes(mac), "keyed length \(length)")
        }
        // The example message in RFC 7693 appendix B.
        XCTAssertEqual(WireGuardCrypto.hash(Data("abc".utf8)),
                       try bytes("508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982"))
        XCTAssertEqual(WireGuardCrypto.blake2s(Data(), key: key),
                       try bytes("48a8997da407876b3d79c0d92325ad3b89cbb754d86ab71aee047ad345fd2c49"))
    }

    func testHmacAndWireGuardKdfAgainstIndependentVectors() throws {
        // Generated with Python hmac.new(..., hashlib.blake2s), not the keyed BLAKE2s mode.
        let key = Data((0..<32).map(UInt8.init))
        let input = Data("wireguard-test".utf8)
        XCTAssertEqual(WireGuardCrypto.hmac(key: key, data: input),
                       try bytes("32dd4fa6a6240fd8b9708215287ea0a0856a109c05822ea13a3a62d1c0757b15"))
        XCTAssertEqual(WireGuardCrypto.hmac(key: Data((0..<100).map(UInt8.init)), data: input),
                       try bytes("32c0cc22ec6b74c0ec740ad66c02d317c3930983a1eef89959d28325154ae03d"))
        let expected = try [
            "2b624ee51163acaadc377e1d2601c8730004cb1791c8a0704bced9ba575725c0",
            "c1c02fb1ef9b836e16cf7daa308ebad4254137de5b5e328d1f45d0f7bb626c07",
            "bc2c25a6451e6a95032ebe87538c62805c8f4d28a53bfc4dfd57159f8428d2bb"
        ].map(bytes)
        for count in 1...3 {
            XCTAssertEqual(WireGuardCrypto.kdf(key: key, input: input, count: count), Array(expected.prefix(count)))
        }
    }

    func testChaChaPolyUsesWireGuardNonceAndExcludesNonceFromOutput() throws {
        let key = Data((0..<32).map(UInt8.init))
        let plaintext = Data("a test IP packet".utf8)
        let associatedData = Data("handshake hash".utf8)
        let counter: UInt64 = 0x0807060504030201
        let nonce = try ChaChaPoly.Nonce(data: bytes("000000000102030405060708"))
        let expected = try ChaChaPoly.seal(plaintext, using: SymmetricKey(data: key), nonce: nonce, authenticating: associatedData)
        let sealed = try WireGuardCrypto.seal(key: key, counter: counter, plaintext: plaintext, authenticating: associatedData)
        XCTAssertEqual(sealed, expected.ciphertext + expected.tag)
        XCTAssertEqual(sealed.count, plaintext.count + 16)
        XCTAssertEqual(try WireGuardCrypto.open(key: key, counter: counter, ciphertext: sealed, authenticating: associatedData), plaintext)
        XCTAssertThrowsError(try WireGuardCrypto.open(key: key, counter: counter + 1, ciphertext: sealed, authenticating: associatedData))
        XCTAssertThrowsError(try WireGuardCrypto.open(key: key, counter: counter, ciphertext: sealed, authenticating: Data()))
        var tampered = sealed
        tampered[tampered.startIndex] ^= 1
        XCTAssertThrowsError(try WireGuardCrypto.open(key: key, counter: counter, ciphertext: tampered, authenticating: associatedData))
    }

    func testHChaCha20DraftTestVector() throws {
        // https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#section-2.2.1
        let key = Data((0..<32).map(UInt8.init))
        let nonce = try bytes("000000090000004a0000000031415927")
        XCTAssertEqual(try WireGuardCrypto.hchacha20(key: key, nonce: nonce),
                       try bytes("82413b4227b27bfed30e42508a877d73a0f9e4d58a74a853c12ec41326d3ecdc"))
    }

    func testXChaCha20Poly1305DraftTestVector() throws {
        // https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#appendix-A.3.1
        let key = try bytes("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
        let nonce = try bytes("404142434445464748494a4b4c4d4e4f5051525354555657")
        let associatedData = try bytes("50515253c0c1c2c3c4c5c6c7")
        let ciphertext = try bytes(
            "bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb" +
            "731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b452" +
            "2f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff9" +
            "21f9664c97637da9768812f615c68b13b52e" +
            "c0875924c1c7987947deafd8780acf49"
        )
        let plaintext = Data("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".utf8)
        XCTAssertEqual(try WireGuardCrypto.openCookie(key: key, nonce: nonce, ciphertext: ciphertext, authenticating: associatedData), plaintext)
        XCTAssertThrowsError(try WireGuardCrypto.openCookie(key: key, nonce: nonce, ciphertext: ciphertext, authenticating: Data()))
    }

    func testMalformedCryptoInputsThrow() throws {
        let key = Data(repeating: 1, count: 32)
        XCTAssertThrowsError(try WireGuardCrypto.seal(key: Data(), counter: 0, plaintext: Data()))
        XCTAssertThrowsError(try WireGuardCrypto.open(key: key, counter: 0, ciphertext: Data(repeating: 0, count: 15)))
        XCTAssertThrowsError(try WireGuardCrypto.openCookie(key: key, nonce: Data(repeating: 0, count: 23), ciphertext: Data(), authenticating: Data()))
        XCTAssertThrowsError(try WireGuardCrypto.hchacha20(key: Data(), nonce: Data(repeating: 0, count: 16)))
    }

    private func bytes(_ hex: String) throws -> Data {
        try WireGuardTestData.hexBytes(hex)
    }
}

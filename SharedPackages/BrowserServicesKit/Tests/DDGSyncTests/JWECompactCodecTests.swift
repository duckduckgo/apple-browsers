//
//  JWECompactCodecTests.swift
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
import XCTest
@testable import DDGSync

final class JWECompactCodecTests: XCTestCase {

    private enum TestSupportError: Error {
        case malformedToken
        case failedToDecodeComponent
    }

    func testWhenEncryptingWithDirectModeThenProducesExpectedCompactShape() throws {
        let codec = JWECompactCodec()
        let payload = Data("third-party-secret".utf8)
        let contentEncryptionKey = Data(repeating: 0x4A, count: 32)
        let kid = "ddg"

        let token = try codec.encryptDirect(payload: payload,
                                            contentEncryptionKey: contentEncryptionKey,
                                            kid: kid)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        XCTAssertEqual(parts.count, 5)
        XCTAssertEqual(parts[0], JWECompactCodec.encodedDirectProtectedHeader(kid: kid))
        XCTAssertEqual(parts[1], "")
        XCTAssertFalse(parts[3].isEmpty)
        XCTAssertFalse(parts[4].isEmpty)

        guard let tag = base64URLDecode(parts[4]) else {
            throw TestSupportError.failedToDecodeComponent
        }
        XCTAssertEqual(tag.count, 16)
    }

    func testWhenRoundTrippingDirectModeThenRecoversPayload() throws {
        let codec = JWECompactCodec()
        let payload = Data(#"{"user_id":"user-1","credential_id":"3party"}"#.utf8)
        let contentEncryptionKey = Data(repeating: 0x2B, count: 32)

        let token = try codec.encryptDirect(payload: payload,
                                            contentEncryptionKey: contentEncryptionKey,
                                            kid: "3party")
        let decrypted = try codec.decryptDirect(token: token, contentEncryptionKey: contentEncryptionKey)

        XCTAssertEqual(decrypted, payload)
    }

    func testWhenRoundTrippingRSAOAEP256ModeThenRecoversPayloadAndProducesExpectedCompactShape() throws {
        let codec = JWECompactCodec()
        let keyPair = try RSAKeyPairGenerator.makeKeyPair()
        let payload = Data(#"{"type":"hello"}"#.utf8)
        let contentEncryptionKey = Data(repeating: 0x4C, count: 32)
        let iv = Data(repeating: 0x3D, count: 12)
        let kid = "sender-channel"

        let token = try codec.encryptRSAOAEP256(payload: payload,
                                                recipientPublicKey: keyPair.publicKey,
                                                kid: kid,
                                                contentEncryptionKey: contentEncryptionKey,
                                                iv: iv)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let decrypted = try codec.decryptRSAOAEP256(token: token,
                                                    privateKey: keyPair.privateKey,
                                                    expectedKid: kid)
        let decodedIV = try XCTUnwrap(base64URLDecode(parts[2]))

        XCTAssertEqual(parts.count, 5)
        XCTAssertEqual(parts[0], JWECompactCodec.encodedRSAOAEP256ProtectedHeader(kid: kid))
        XCTAssertFalse(parts[1].isEmpty)
        XCTAssertEqual(decodedIV, iv)
        XCTAssertFalse(parts[3].isEmpty)
        XCTAssertEqual(decrypted, payload)
    }

    func testWhenDecryptingRSAOAEP256TokenWithUnexpectedKidThenThrows() throws {
        let codec = JWECompactCodec()
        let keyPair = try RSAKeyPairGenerator.makeKeyPair()
        let token = try codec.encryptRSAOAEP256(payload: Data("payload".utf8),
                                                recipientPublicKey: keyPair.publicKey,
                                                kid: "expected-sender")

        XCTAssertThrowsError(try codec.decryptRSAOAEP256(token: token,
                                                         privateKey: keyPair.privateKey,
                                                         expectedKid: "other-sender")) { error in
            XCTAssertEqual(error as? JWECompactCodecError, .unsupportedProtectedHeader)
        }
    }

    func testWhenDecryptingDirectTokenWithWrongPartCountThenThrows() throws {
        let codec = JWECompactCodec()
        let contentEncryptionKey = Data(repeating: 0x2B, count: 32)

        XCTAssertThrowsError(try codec.decryptDirect(token: "a.b.c", contentEncryptionKey: contentEncryptionKey)) { error in
            XCTAssertEqual(error as? JWECompactCodecError, .invalidTokenPartCount(3))
        }
    }

    func testWhenDecryptingDirectTokenWithUnsupportedHeaderThenThrows() throws {
        let codec = JWECompactCodec()
        let payload = Data(#"{"hello":"world"}"#.utf8)
        let contentEncryptionKey = Data(repeating: 0x33, count: 32)

        let token = try codec.encryptDirect(payload: payload,
                                            contentEncryptionKey: contentEncryptionKey,
                                            kid: "ddg")
        var parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else {
            throw TestSupportError.malformedToken
        }
        parts[0] = base64URLEncode(Data(#"{"alg":"RSA-OAEP-256","enc":"A256GCM"}"#.utf8))
        let mutatedToken = parts.joined(separator: ".")

        XCTAssertThrowsError(try codec.decryptDirect(token: mutatedToken, contentEncryptionKey: contentEncryptionKey)) { error in
            XCTAssertEqual(error as? JWECompactCodecError, .unsupportedProtectedHeader)
        }
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - (base64.count % 4)) % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: base64)
    }

}

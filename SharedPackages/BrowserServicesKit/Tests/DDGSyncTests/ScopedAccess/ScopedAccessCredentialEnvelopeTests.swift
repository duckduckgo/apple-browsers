//
//  ScopedAccessCredentialEnvelopeTests.swift
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

final class ScopedAccessCredentialEnvelopeTests: XCTestCase {

    private enum Constants {
        static let formatErrorMessage = "3P access credential has invalid encrypted_3party_credential format"
        static let plaintextEncodingErrorMessage = "3P access credential has invalid encrypted_3party_credential plaintext encoding"
        static let kid = "ddg"
    }

    func testWhenEncryptingAndDecryptingScopedPasswordThenRoundtripReturnsOriginalValue() throws {
        let crypto = ScopedAccessCredentialEnvelope()
        let scopedPassword = deterministicData(startByte: 0x10)
        let mainKey = deterministicData(startByte: 0x80)

        let encryptedCredential = try crypto.encryptScopedPassword(scopedPassword, using: mainKey, kid: Constants.kid)
        let decryptedScopedPassword = try crypto.decryptScopedPassword(from: encryptedCredential, using: mainKey)

        XCTAssertEqual(decryptedScopedPassword, scopedPassword)
    }

    func testWhenEncryptingScopedPasswordThenProtectedHeaderContainsExpectedFields() throws {
        let crypto = ScopedAccessCredentialEnvelope()
        let encryptedCredential = try crypto.encryptScopedPassword(deterministicData(startByte: 0x10),
                                                                   using: deterministicData(startByte: 0x80),
                                                                   kid: Constants.kid)

        let compactParts = encryptedCredential.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(compactParts.count, 5)

        let protectedHeaderData = try XCTUnwrap(Base64URL.decode(compactParts[0]))
        let protectedHeaderJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: protectedHeaderData) as? [String: String])
        XCTAssertEqual(protectedHeaderJSON["alg"], "dir")
        XCTAssertEqual(protectedHeaderJSON["enc"], "A256GCM")
        XCTAssertEqual(protectedHeaderJSON["kid"], Constants.kid)
    }

    func testWhenDecryptingMalformedTokenThenThrowsInvalidDataInResponseWithFormatMessage() throws {
        let crypto = ScopedAccessCredentialEnvelope()
        let malformedToken = "a.b.c"

        do {
            _ = try crypto.decryptScopedPassword(from: malformedToken, using: deterministicData(startByte: 0x80))
            XCTFail("Expected decryptScopedPassword to throw")
        } catch SyncError.invalidDataInResponse(let message) {
            XCTAssertEqual(message, Constants.formatErrorMessage)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWhenDecryptedPlaintextIsNotBase64URLThenThrowsInvalidDataInResponseWithEncodingMessage() throws {
        let crypto = ScopedAccessCredentialEnvelope()
        let mainKey = deterministicData(startByte: 0x80)
        let tokenWithNonBase64URLPlaintext = try JWECompactCodec().encryptDirect(payload: Data("not-base64url*".utf8),
                                                                                  contentEncryptionKey: mainKey,
                                                                                  kid: Constants.kid)

        do {
            _ = try crypto.decryptScopedPassword(from: tokenWithNonBase64URLPlaintext, using: mainKey)
            XCTFail("Expected decryptScopedPassword to throw")
        } catch SyncError.invalidDataInResponse(let message) {
            XCTAssertEqual(message, Constants.plaintextEncodingErrorMessage)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func deterministicData(startByte: UInt8) -> Data {
        Data((0..<32).map { startByte &+ UInt8($0) })
    }
}

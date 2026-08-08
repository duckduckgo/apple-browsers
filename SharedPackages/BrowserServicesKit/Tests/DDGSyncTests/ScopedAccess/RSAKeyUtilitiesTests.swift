//
//  RSAKeyUtilitiesTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Security
import XCTest

@testable import DDGSync

final class RSAKeyUtilitiesTests: XCTestCase {

    func testWhenImportingRSA3072PKCS8ThenPublicAndPrivateKeysMatch() throws {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial(keySizeInBits: 3072)

        // RSA-3072 makes the outer PKCS#8 sequence use DER's multi-byte length form.
        XCTAssertNotEqual(keyMaterial.privateKeyPKCS8[1] & 0x80, 0)

        let publicKey = try RSAKeyImporter.makePublicKey(from: keyMaterial.publicKeyJWK)
        let privateKey = try RSAKeyImporter.makePrivateKey(fromPKCS8: keyMaterial.privateKeyPKCS8)
        let derivedPublicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let publicKeyData = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let derivedPublicKeyData = try XCTUnwrap(SecKeyCopyExternalRepresentation(derivedPublicKey, nil) as Data?)

        XCTAssertEqual(SecKeyGetBlockSize(privateKey), 384)
        XCTAssertEqual(derivedPublicKeyData, publicKeyData)
    }

    func testWhenImportingPublicKeyWithUnsupportedMetadataThenThrowsUnsupportedPublicKey() throws {
        let publicKey = try ScopedAccessKeyFactory.makeRSAKeyMaterial().publicKeyJWK
        let unsupportedPublicKeys = [
            ProtectedKeyPublicKey(alg: "RS256",
                                  e: publicKey.e,
                                  ext: publicKey.ext,
                                  keyOps: publicKey.keyOps,
                                  kty: publicKey.kty,
                                  n: publicKey.n,
                                  use: publicKey.use),
            ProtectedKeyPublicKey(alg: publicKey.alg,
                                  e: publicKey.e,
                                  ext: publicKey.ext,
                                  keyOps: publicKey.keyOps,
                                  kty: "EC",
                                  n: publicKey.n,
                                  use: publicKey.use),
            ProtectedKeyPublicKey(alg: publicKey.alg,
                                  e: publicKey.e,
                                  ext: publicKey.ext,
                                  keyOps: publicKey.keyOps,
                                  kty: publicKey.kty,
                                  n: publicKey.n,
                                  use: "sig"),
            ProtectedKeyPublicKey(alg: publicKey.alg,
                                  e: publicKey.e,
                                  ext: publicKey.ext,
                                  keyOps: ["verify"],
                                  kty: publicKey.kty,
                                  n: publicKey.n,
                                  use: publicKey.use)
        ]

        for unsupportedPublicKey in unsupportedPublicKeys {
            XCTAssertThrowsError(try RSAKeyImporter.makePublicKey(from: unsupportedPublicKey)) { error in
                XCTAssertEqual(error as? RSAKeyImportError, .unsupportedPublicKey)
            }
        }
    }

    func testWhenImportingPublicKeyWithMissingOrMalformedComponentsThenThrowsInvalidPublicKey() throws {
        let publicKey = try ScopedAccessKeyFactory.makeRSAKeyMaterial().publicKeyJWK
        let invalidPublicKeys = [
            ProtectedKeyPublicKey(alg: publicKey.alg,
                                  e: publicKey.e,
                                  ext: publicKey.ext,
                                  keyOps: publicKey.keyOps,
                                  kty: publicKey.kty,
                                  n: nil,
                                  use: publicKey.use),
            ProtectedKeyPublicKey(alg: publicKey.alg,
                                  e: publicKey.e,
                                  ext: publicKey.ext,
                                  keyOps: publicKey.keyOps,
                                  kty: publicKey.kty,
                                  n: "%",
                                  use: publicKey.use),
            ProtectedKeyPublicKey(alg: publicKey.alg,
                                  e: nil,
                                  ext: publicKey.ext,
                                  keyOps: publicKey.keyOps,
                                  kty: publicKey.kty,
                                  n: publicKey.n,
                                  use: publicKey.use),
            ProtectedKeyPublicKey(alg: publicKey.alg,
                                  e: "%",
                                  ext: publicKey.ext,
                                  keyOps: publicKey.keyOps,
                                  kty: publicKey.kty,
                                  n: publicKey.n,
                                  use: publicKey.use)
        ]

        for invalidPublicKey in invalidPublicKeys {
            XCTAssertThrowsError(try RSAKeyImporter.makePublicKey(from: invalidPublicKey)) { error in
                XCTAssertEqual(error as? RSAKeyImportError, .invalidPublicKey)
            }
        }
    }

    func testWhenImportingMalformedPKCS8ThenThrowsInvalidPrivateKey() {
        assertInvalidPrivateKey(Data([0x30, 0x82, 0x01]))
    }

    func testWhenImportingTruncatedPKCS8ThenThrowsInvalidPrivateKey() throws {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()

        assertInvalidPrivateKey(Data(keyMaterial.privateKeyPKCS8.dropLast()))
    }

    func testWhenImportingPKCS8WithTrailingBytesThenThrowsInvalidPrivateKey() throws {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()
        var privateKeyPKCS8 = keyMaterial.privateKeyPKCS8
        privateKeyPKCS8.append(0x00)

        assertInvalidPrivateKey(privateKeyPKCS8)
    }

    func testWhenEncodingUnsignedPublicKeyComponentsThenLeadingZerosAreCanonicalized() throws {
        let publicKeyPKCS1 = RSAKeyDER.makeRSAPublicKeyPKCS1(
            modulus: Data([0x00, 0x00, 0x80, 0x01]),
            exponent: Data([0x80, 0x01]))

        let components = try RSAKeyDER.parseRSAPublicKeyComponents(fromPKCS1DER: publicKeyPKCS1)

        XCTAssertEqual(components.modulus, Data([0x00, 0x80, 0x01]))
        XCTAssertEqual(components.exponent, Data([0x00, 0x80, 0x01]))
    }

    private func assertInvalidPrivateKey(_ privateKeyPKCS8: Data,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        XCTAssertThrowsError(try RSAKeyImporter.makePrivateKey(fromPKCS8: privateKeyPKCS8), file: file, line: line) { error in
            XCTAssertEqual(error as? RSAKeyImportError, .invalidPrivateKey, file: file, line: line)
        }
    }
}

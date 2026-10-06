//
//  RSAKeyUtilitiesTests.swift
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
import Security
import Testing

@testable import DDGSync

@Suite("RSA key utilities")
struct RSAKeyUtilitiesTests {

    @available(iOS 16, macOS 13, *)
    @Test("RSA-3072 PKCS#8 import produces matching public and private keys", .timeLimit(.minutes(1)))
    func testWhenImportingRSA3072PKCS8ThenPublicAndPrivateKeysMatch() throws {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial(keySizeInBits: 3072)

        // RSA-3072 makes the outer PKCS#8 sequence use DER's multi-byte length form.
        #expect(keyMaterial.privateKeyPKCS8[1] & 0x80 != 0)

        let publicKey = try RSAKeyImporter.makePublicKey(from: keyMaterial.publicKeyJWK)
        let privateKey = try RSAKeyImporter.makePrivateKey(fromPKCS8: keyMaterial.privateKeyPKCS8)
        let derivedPublicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let publicKeyData = try #require(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let derivedPublicKeyData = try #require(SecKeyCopyExternalRepresentation(derivedPublicKey, nil) as Data?)

        #expect(SecKeyGetBlockSize(privateKey) == 384)
        #expect(derivedPublicKeyData == publicKeyData)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Public keys with unsupported metadata are rejected", .timeLimit(.minutes(1)))
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
            #expect(throws: RSAKeyImportError.unsupportedPublicKey) {
                try RSAKeyImporter.makePublicKey(from: unsupportedPublicKey)
            }
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Public keys with missing or malformed components are rejected", .timeLimit(.minutes(1)))
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
            #expect(throws: RSAKeyImportError.invalidPublicKey) {
                try RSAKeyImporter.makePublicKey(from: invalidPublicKey)
            }
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Malformed PKCS#8 is rejected", .timeLimit(.minutes(1)))
    func testWhenImportingMalformedPKCS8ThenThrowsInvalidPrivateKey() {
        assertInvalidPrivateKey(Data([0x30, 0x82, 0x01]))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Truncated PKCS#8 is rejected", .timeLimit(.minutes(1)))
    func testWhenImportingTruncatedPKCS8ThenThrowsInvalidPrivateKey() throws {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()

        assertInvalidPrivateKey(Data(keyMaterial.privateKeyPKCS8.dropLast()))
    }

    @available(iOS 16, macOS 13, *)
    @Test("PKCS#8 with trailing bytes is rejected", .timeLimit(.minutes(1)))
    func testWhenImportingPKCS8WithTrailingBytesThenThrowsInvalidPrivateKey() throws {
        let keyMaterial = try ScopedAccessKeyFactory.makeRSAKeyMaterial()
        var privateKeyPKCS8 = keyMaterial.privateKeyPKCS8
        privateKeyPKCS8.append(0x00)

        assertInvalidPrivateKey(privateKeyPKCS8)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unsigned public-key components have canonical leading zeros", .timeLimit(.minutes(1)))
    func testWhenEncodingUnsignedPublicKeyComponentsThenLeadingZerosAreCanonicalized() throws {
        let publicKeyPKCS1 = RSAKeyDER.makeRSAPublicKeyPKCS1(
            modulus: Data([0x00, 0x00, 0x80, 0x01]),
            exponent: Data([0x80, 0x01]))

        let components = try RSAKeyDER.parseRSAPublicKeyComponents(fromPKCS1DER: publicKeyPKCS1)

        #expect(components.modulus == Data([0x00, 0x80, 0x01]))
        #expect(components.exponent == Data([0x00, 0x80, 0x01]))
    }

    private func assertInvalidPrivateKey(_ privateKeyPKCS8: Data) {
        #expect(throws: RSAKeyImportError.invalidPrivateKey) {
            try RSAKeyImporter.makePrivateKey(fromPKCS8: privateKeyPKCS8)
        }
    }
}

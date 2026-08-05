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

        XCTAssertNotEqual(keyMaterial.privateKeyPKCS8[1] & 0x80, 0)

        let publicKey = try RSAKeyImporter.makePublicKey(from: keyMaterial.publicKeyJWK)
        let privateKey = try RSAKeyImporter.makePrivateKey(fromPKCS8: keyMaterial.privateKeyPKCS8)
        let derivedPublicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let publicKeyData = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let derivedPublicKeyData = try XCTUnwrap(SecKeyCopyExternalRepresentation(derivedPublicKey, nil) as Data?)

        XCTAssertEqual(SecKeyGetBlockSize(privateKey), 384)
        XCTAssertEqual(derivedPublicKeyData, publicKeyData)
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

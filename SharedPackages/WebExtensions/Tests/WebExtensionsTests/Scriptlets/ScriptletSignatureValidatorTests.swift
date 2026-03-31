//
//  ScriptletSignatureValidatorTests.swift
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

import Security
import XCTest
@testable import WebExtensions

final class ScriptletSignatureValidatorTests: XCTestCase {

    private var privateKey: SecKey!
    private var publicKey: SecKey!

    override func setUp() {
        super.setUp()
        let (priv, pub) = Self.generateRSAKeyPair()
        privateKey = priv
        publicKey = pub
    }

    override func tearDown() {
        privateKey = nil
        publicKey = nil
        super.tearDown()
    }

    // MARK: - Valid Signatures

    func testWhenSignatureIsValidThenValidationSucceeds() throws {
        let validator = ScriptletSignatureValidator(publicKey: publicKey)
        let data = Data("console.log('hello')".utf8)
        let fetched = [try makeFetchedScriptlet(name: "script.js", data: data)]

        XCTAssertNoThrow(try validator.validate(fetched))
    }

    func testWhenMultipleScriptletsHaveValidSignaturesThenValidationSucceeds() throws {
        let validator = ScriptletSignatureValidator(publicKey: publicKey)
        let fetched = [
            try makeFetchedScriptlet(name: "a.js", data: Data("var a = 1;".utf8)),
            try makeFetchedScriptlet(name: "b.js", data: Data("var b = 2;".utf8))
        ]

        XCTAssertNoThrow(try validator.validate(fetched))
    }

    // MARK: - Invalid Signatures

    func testWhenSignatureIsInvalidThenThrowsSignatureVerificationFailed() throws {
        let validator = ScriptletSignatureValidator(publicKey: publicKey)

        let data = Data("console.log('hello')".utf8)
        let tamperedData = Data("console.log('tampered')".utf8)
        let signature = try sign(data)
        let fetched = [try makeFetchedScriptlet(name: "script.js", data: tamperedData, signature: signature)]

        XCTAssertThrowsError(try validator.validate(fetched)) { error in
            XCTAssertEqual(error as? ScriptletError, .signatureVerificationFailed(name: "script.js"))
        }
    }

    func testWhenSignatureIsFromDifferentKeyThenThrowsSignatureVerificationFailed() throws {
        let (otherPrivate, _) = Self.generateRSAKeyPair()
        let validator = ScriptletSignatureValidator(publicKey: publicKey)

        let data = Data("console.log('hello')".utf8)
        let wrongSignature = try Self.rsaSign(data, with: otherPrivate)
        let fetched = [try makeFetchedScriptlet(name: "script.js", data: data, signature: wrongSignature)]

        XCTAssertThrowsError(try validator.validate(fetched)) { error in
            XCTAssertEqual(error as? ScriptletError, .signatureVerificationFailed(name: "script.js"))
        }
    }

    // MARK: - Invalid Signature Format

    func testWhenSignatureIsNotBase64ThenThrowsInvalidSignatureFormat() {
        let validator = ScriptletSignatureValidator(publicKey: publicKey)
        let data = Data("console.log('hello')".utf8)
        let descriptor = ScriptletDescriptor(
            name: "script.js",
            url: URL(string: "https://example.com/script.js")!,
            signature: "not-valid-base64!!!")
        let fetched = [FetchedScriptlet(descriptor: descriptor, data: data)]

        XCTAssertThrowsError(try validator.validate(fetched)) { error in
            XCTAssertEqual(error as? ScriptletError, .invalidSignatureFormat(name: "script.js"))
        }
    }

    // MARK: - Encoding

    func testWhenDataIsNotUTF8ThenThrowsInvalidEncoding() throws {
        let validator = ScriptletSignatureValidator(publicKey: publicKey)
        let invalidData = Data([0xFF, 0xFE, 0x80, 0x81])
        let signature = try sign(invalidData)
        let descriptor = ScriptletDescriptor(
            name: "bad.js",
            url: URL(string: "https://example.com/bad.js")!,
            signature: signature)
        let fetched = [FetchedScriptlet(descriptor: descriptor, data: invalidData)]

        XCTAssertThrowsError(try validator.validate(fetched)) { error in
            XCTAssertEqual(error as? ScriptletError, .invalidEncoding(name: "bad.js"))
        }
    }

    // MARK: - Edge Cases

    func testWhenEmptyArrayThenValidationSucceeds() throws {
        let validator = ScriptletSignatureValidator(publicKey: publicKey)
        XCTAssertNoThrow(try validator.validate([]))
    }

    // MARK: - Helpers

    private func sign(_ data: Data) throws -> String {
        try Self.rsaSign(data, with: privateKey)
    }

    private static func rsaSign(_ data: Data, with key: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error) as Data? else {
            throw error?.takeRetainedValue() ?? NSError(domain: "TestError", code: -1)
        }
        return signatureData.base64EncodedString()
    }

    private func makeFetchedScriptlet(name: String, data: Data, signature: String? = nil) throws -> FetchedScriptlet {
        let sig = try signature ?? sign(data)
        let descriptor = ScriptletDescriptor(
            name: name,
            url: URL(string: "https://example.com/\(name)")!,
            signature: sig)
        return FetchedScriptlet(descriptor: descriptor, data: data)
    }

    private static func generateRSAKeyPair() -> (privateKey: SecKey, publicKey: SecKey) {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            fatalError("Failed to generate RSA test key pair: \(error?.takeRetainedValue() as Any)")
        }
        return (privateKey, publicKey)
    }
}

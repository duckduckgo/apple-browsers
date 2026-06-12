//
//  RSAKeyUtilities.swift
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

struct RSAKeyPair {
    let publicKey: SecKey
    let privateKey: SecKey
}

enum RSAKeyPairGeneratorError: Error {
    case keyGenerationFailed
    case publicKeyExtractionFailed
    case externalRepresentationFailed
}

enum RSAKeyPairGenerator {

    static func makeKeyPair(keySizeInBits: Int = 2048) throws -> RSAKeyPair {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: keySizeInBits,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]

        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
            throw RSAKeyPairGeneratorError.keyGenerationFailed
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw RSAKeyPairGeneratorError.publicKeyExtractionFailed
        }

        return RSAKeyPair(publicKey: publicKey, privateKey: privateKey)
    }

    static func copyExternalRepresentation(for key: SecKey) throws -> Data {
        guard let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            throw RSAKeyPairGeneratorError.externalRepresentationFailed
        }
        return keyData
    }
}

enum RSAKeyDERError: Error {
    case invalidDER
}

enum RSAKeyDER {

    private static let rsaEncryptionOID = Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    private static let null = Data([0x05, 0x00])
    private static let integerZero = Data([0x02, 0x01, 0x00])

    private static var rsaAlgorithmIdentifier: Data {
        ASN1DER.sequence([rsaEncryptionOID, null])
    }

    static func wrapRSAPublicKeyInSPKI(_ publicKeyPKCS1: Data) -> Data {
        ASN1DER.sequence([
            rsaAlgorithmIdentifier,
            ASN1DER.bitString(publicKeyPKCS1)
        ])
    }

    static func unwrapRSAPublicKeySPKI(_ spki: Data) throws -> Data {
        var cursor = DERCursor(bytes: [UInt8](spki))
        try cursor.expect(tag: 0x30)
        _ = try cursor.readLength()
        try cursor.expect(tag: 0x30)
        let algorithmIdentifierLength = try cursor.readLength()
        _ = try cursor.readBytes(count: algorithmIdentifierLength)
        try cursor.expect(tag: 0x03)
        let bitStringLength = try cursor.readLength()
        let bitString = try cursor.readBytes(count: bitStringLength)
        guard bitString.first == 0x00 else {
            throw RSAKeyDERError.invalidDER
        }
        return Data(bitString.dropFirst())
    }

    static func wrapRSAPrivateKeyInPKCS8(_ privateKeyPKCS1: Data) -> Data {
        ASN1DER.sequence([
            integerZero,
            rsaAlgorithmIdentifier,
            ASN1DER.octetString(privateKeyPKCS1)
        ])
    }

    static func parseRSAPublicKeyComponents(fromPKCS1DER der: Data) throws -> (modulus: Data, exponent: Data) {
        var cursor = DERCursor(bytes: [UInt8](der))

        try cursor.expect(tag: 0x30)
        _ = try cursor.readLength()

        try cursor.expect(tag: 0x02)
        let modulusLength = try cursor.readLength()
        let modulus = try cursor.readBytes(count: modulusLength)

        try cursor.expect(tag: 0x02)
        let exponentLength = try cursor.readLength()
        let exponent = try cursor.readBytes(count: exponentLength)

        return (Data(modulus), Data(exponent))
    }
}

private enum ASN1DER {

    static func sequence(_ parts: [Data]) -> Data {
        var contents = Data()
        parts.forEach { contents.append($0) }
        return wrap(tag: 0x30, contents: contents)
    }

    static func bitString(_ data: Data) -> Data {
        var contents = Data([0x00])
        contents.append(data)
        return wrap(tag: 0x03, contents: contents)
    }

    static func octetString(_ data: Data) -> Data {
        wrap(tag: 0x04, contents: data)
    }

    private static func wrap(tag: UInt8, contents: Data) -> Data {
        var output = Data([tag])
        output.append(lengthBytes(for: contents.count))
        output.append(contents)
        return output
    }

    private static func lengthBytes(for length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }

        var remainingLength = length
        var bytes: [UInt8] = []
        while remainingLength > 0 {
            bytes.insert(UInt8(remainingLength & 0xFF), at: 0)
            remainingLength >>= 8
        }

        var encoded = Data([0x80 | UInt8(bytes.count)])
        encoded.append(contentsOf: bytes)
        return encoded
    }
}

private struct DERCursor {
    let bytes: [UInt8]
    var index = 0

    mutating func expect(tag: UInt8) throws {
        guard index < bytes.count, bytes[index] == tag else {
            throw RSAKeyDERError.invalidDER
        }
        index += 1
    }

    mutating func readLength() throws -> Int {
        guard index < bytes.count else {
            throw RSAKeyDERError.invalidDER
        }

        let first = bytes[index]
        index += 1

        if first & 0x80 == 0 {
            return Int(first)
        }

        let byteCount = Int(first & 0x7F)
        guard byteCount > 0, byteCount <= 4 else {
            throw RSAKeyDERError.invalidDER
        }

        var length = 0
        for _ in 0..<byteCount {
            guard index < bytes.count else {
                throw RSAKeyDERError.invalidDER
            }
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, index + count <= bytes.count else {
            throw RSAKeyDERError.invalidDER
        }

        let value = Array(bytes[index..<(index + count)])
        index += count
        return value
    }
}

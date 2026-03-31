//
//  ScriptletSigningKeys.swift
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

public enum ScriptletSigningKeys {

    // Base64 component of the ssh-rsa public key used to sign scriptlet payloads
    private static let publicKeyBase64 = "AAAAB3NzaC1yc2EAAAADAQABAAABAQDGnuwJGdV2U/Qan1FCQxmH+iE17DENxZw6djfOur4mvEHL7fwVRvaw2sT8LUqzamMG01rR/gjH/5TC5dA7ovf1TOXl4gk99E6DdC53IJj5fVBPbafEcIU3dASnEYyyzVWsDj3PrJ1uZ5rRBGI5PSbvtrIyt61WhvCzUgVeyC4Kne2BJ7MX5R2eTk51aqNt+9Cv0JNQ/XCoJ7vFyGEP/x9sYptIOUzdgXkLJNXp6x/lYtezoCkoiKPyf2KJl3gfbcNz+4bMKnDygsfVEgxeifQOOjIrKdK6hZBlJohQLyNUVG2BfOr4W2W9AdAGbvxb3teoKK3YXKYImFldGDpzo5FP"

    public static var publicKey: SecKey {
        guard let keyData = Data(base64Encoded: publicKeyBase64) else {
            fatalError("Invalid scriptlet signing public key encoding")
        }
        guard let secKey = secKeyFromSSHRSA(keyData) else {
            fatalError("Failed to parse SSH RSA public key")
        }
        return secKey
    }

    // MARK: - SSH RSA Key Parsing

    /// Parses the binary SSH RSA public key blob into a SecKey.
    ///
    /// SSH RSA wire format:
    ///   [4-byte length]["ssh-rsa"]
    ///   [4-byte length][exponent bytes]
    ///   [4-byte length][modulus bytes]
    static func secKeyFromSSHRSA(_ data: Data) -> SecKey? {
        var offset = 0

        guard let keyType = readSSHString(from: data, offset: &offset),
              keyType == "ssh-rsa" else {
            return nil
        }

        guard let exponent = readSSHField(from: data, offset: &offset),
              let modulus = readSSHField(from: data, offset: &offset) else {
            return nil
        }

        let derKey = buildPKCS1DER(modulus: modulus, exponent: exponent)

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: modulus.count * 8
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(derKey as CFData, attributes as CFDictionary, &error) else {
            return nil
        }
        return secKey
    }

    // MARK: - SSH Field Reading

    private static func readSSHString(from data: Data, offset: inout Int) -> String? {
        guard let bytes = readSSHField(from: data, offset: &offset) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    private static func readSSHField(from data: Data, offset: inout Int) -> Data? {
        guard offset + 4 <= data.count else { return nil }
        let length = Int(data[offset]) << 24
            | Int(data[offset + 1]) << 16
            | Int(data[offset + 2]) << 8
            | Int(data[offset + 3])
        offset += 4
        guard length >= 0, offset + length <= data.count else { return nil }
        let field = data[offset..<(offset + length)]
        offset += length
        return Data(field)
    }

    // MARK: - DER Encoding

    /// Builds a PKCS#1 RSAPublicKey DER structure:
    ///   SEQUENCE { modulus INTEGER, publicExponent INTEGER }
    private static func buildPKCS1DER(modulus: Data, exponent: Data) -> Data {
        let modulusEncoded = derEncodeInteger(modulus)
        let exponentEncoded = derEncodeInteger(exponent)
        let content = modulusEncoded + exponentEncoded
        return derEncodeSequence(content)
    }

    private static func derEncodeInteger(_ value: Data) -> Data {
        var bytes = Array(value)

        while bytes.count > 1 && bytes[0] == 0 && bytes[1] & 0x80 == 0 {
            bytes.removeFirst()
        }
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }

        var result = Data([0x02])
        result.append(contentsOf: derEncodeLength(bytes.count))
        result.append(contentsOf: bytes)
        return result
    }

    private static func derEncodeSequence(_ content: Data) -> Data {
        var result = Data([0x30])
        result.append(contentsOf: derEncodeLength(content.count))
        result.append(content)
        return result
    }

    private static func derEncodeLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        } else if length < 0x100 {
            return Data([0x81, UInt8(length)])
        } else {
            return Data([0x82, UInt8(length >> 8), UInt8(length & 0xFF)])
        }
    }
}

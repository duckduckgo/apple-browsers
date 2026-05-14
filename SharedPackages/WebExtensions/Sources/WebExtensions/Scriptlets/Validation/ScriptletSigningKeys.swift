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

import CryptoKit
import Foundation

public enum ScriptletSigningKeys {

    // swiftlint:disable:next line_length
    private static let publicKeyBase64 = "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLqq4Z9s7T5z7fEMmyBrC6UTmEf8XCf7sNIzfOZHTEBSnQpMMTi2lO9LlUPs2fhdAdX4MfKnwF7rO5l1rCcQV64="

    public static var publicKey: P256.Signing.PublicKey {
        guard let keyData = Data(base64Encoded: publicKeyBase64) else {
            fatalError("Invalid scriptlet signing public key encoding")
        }
        guard let ecPoint = ecPointFromSSHECDSA(keyData) else {
            fatalError("Failed to parse SSH ECDSA public key blob")
        }
        do {
            return try P256.Signing.PublicKey(x963Representation: ecPoint)
        } catch {
            fatalError("Failed to create P256 public key: \(error)")
        }
    }

    // MARK: - SSH ECDSA Key Parsing

    /// Extracts the raw EC point from an SSH ECDSA public key blob.
    ///
    /// SSH ECDSA wire format (ecdsa-sha2-nistp256):
    ///   [4-byte length]["ecdsa-sha2-nistp256"]
    ///   [4-byte length]["nistp256"]
    ///   [4-byte length][uncompressed EC point: 04 || x || y]
    static func ecPointFromSSHECDSA(_ data: Data) -> Data? {
        var offset = 0

        guard let keyType = readSSHString(from: data, offset: &offset),
              keyType == "ecdsa-sha2-nistp256" else {
            return nil
        }

        guard let curveName = readSSHString(from: data, offset: &offset),
              curveName == "nistp256" else {
            return nil
        }

        guard let ecPoint = readSSHField(from: data, offset: &offset),
              ecPoint.count == 65,
              ecPoint[0] == 0x04 else {
            return nil
        }

        return ecPoint
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
}

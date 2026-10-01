//
//  CRXArchive.swift
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

import Foundation

/// Errors thrown while reading a CRX package.
public enum CRXArchiveError: Error, Equatable {
    case invalidMagic
    case unsupportedVersion(UInt32)
    case truncated
    case missingZipPayload
}

/// Splits a Chrome extension package (`.crx`) into its ZIP payload.
///
/// CRX3 is `"Cr24"`, a little-endian `uint32` version (3), a `uint32` header length, the header,
/// then the ZIP. CRX2 is `"Cr24"`, version 2, `uint32` public key length, `uint32` signature
/// length, the key, the signature, then the ZIP. The header and signatures are not verified here.
public enum CRXArchive {

    private static let magic = Data("Cr24".utf8)
    private static let zipMagic = Data("PK".utf8)

    /// Returns the ZIP data that follows the CRX header.
    public static func zipData(from crx: Data) throws -> Data {
        let crx = Data(crx) // normalize indices to start at 0
        guard crx.count >= magic.count, crx.prefix(magic.count) == magic else {
            throw CRXArchiveError.invalidMagic
        }

        let version = try readUInt32(from: crx, at: 4)
        let headerLength: UInt64
        let payloadOffset: Int

        switch version {
        case 3:
            headerLength = UInt64(try readUInt32(from: crx, at: 8))
            payloadOffset = 12
        case 2:
            let publicKeyLength = UInt64(try readUInt32(from: crx, at: 8))
            let signatureLength = UInt64(try readUInt32(from: crx, at: 12))
            headerLength = publicKeyLength + signatureLength
            payloadOffset = 16
        default:
            throw CRXArchiveError.unsupportedVersion(version)
        }

        guard headerLength <= UInt64(crx.count - payloadOffset) else {
            throw CRXArchiveError.truncated
        }

        let zip = crx.dropFirst(payloadOffset + Int(headerLength))
        guard zip.prefix(zipMagic.count) == zipMagic else {
            throw CRXArchiveError.missingZipPayload
        }
        return Data(zip)
    }

    private static func readUInt32(from data: Data, at offset: Int) throws -> UInt32 {
        guard data.count >= offset + 4 else {
            throw CRXArchiveError.truncated
        }
        return (0..<4).reduce(UInt32(0)) { value, index in
            value | UInt32(data[offset + index]) << (8 * UInt32(index))
        }
    }
}

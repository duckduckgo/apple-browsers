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
//

import CryptoKit
import Foundation

/// Errors thrown while reading a CRX package.
public enum CRXArchiveError: Error, Equatable {
    case invalidMagic
    case unsupportedVersion(UInt32)
    case truncated
    case missingZipPayload
}

/// Splits a Chrome extension package (`.crx`) into its ZIP payload and reads its developer public key.
///
/// The CRX3 format is defined in Chromium's `crx3.proto`:
/// https://chromium.googlesource.com/chromium/src/+/main/components/crx_file/crx3.proto
/// The older CRX2 layout is also accepted. Signatures are not verified here.
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

    /// Returns the developer's public key (DER `SubjectPublicKeyInfo`) from the CRX header, or `nil` when
    /// the header has none or is malformed.
    ///
    /// For CRX3 it is the proof key matching the header's `crx_id` (see `crx3.proto`); the other proofs
    /// are the Web Store's. For CRX2 it is the header's key.
    public static func publicKey(from crx: Data) -> Data? {
        let crx = Data(crx) // normalize indices to start at 0
        guard crx.count >= 12, crx.prefix(magic.count) == magic,
              let version = try? readUInt32(from: crx, at: 4) else {
            return nil
        }

        switch version {
        case 3:
            guard let headerLength = try? readUInt32(from: crx, at: 8),
                  UInt64(headerLength) <= UInt64(crx.count - 12) else {
                return nil
            }
            return developerKey(inCRX3Header: crx.subdata(in: 12..<12 + Int(headerLength)))
        case 2:
            guard let keyLength = try? readUInt32(from: crx, at: 8),
                  crx.count >= 16,
                  UInt64(keyLength) <= UInt64(crx.count - 16) else {
                return nil
            }
            return keyLength > 0 ? crx.subdata(in: 16..<16 + Int(keyLength)) : nil
        default:
            return nil
        }
    }

    private static func developerKey(inCRX3Header header: Data) -> Data? {
        var keys: [Data] = []
        var crxID: Data?

        for field in protobufFields(in: header) {
            switch field.number {
            case 2, 3:
                if let key = protobufFields(in: field.bytes).first(where: { $0.number == 1 })?.bytes {
                    keys.append(key)
                }
            case 10000:
                crxID = protobufFields(in: field.bytes).first(where: { $0.number == 1 })?.bytes
            default:
                break
            }
        }

        guard let crxID, !crxID.isEmpty else { return nil }
        return keys.first { Data(SHA256.hash(data: $0).prefix(crxID.count)) == crxID }
    }

    /// The length-delimited fields of a protobuf message. Other wire types are skipped, and parsing stops
    /// at the first malformed field, keeping what was read before it.
    private static func protobufFields(in message: Data) -> [(number: UInt64, bytes: Data)] {
        var fields: [(number: UInt64, bytes: Data)] = []
        var offset = message.startIndex

        func readVarint() -> UInt64? {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 7) {
                guard offset < message.endIndex else { return nil }
                let byte = message[offset]
                offset += 1
                value |= UInt64(byte & 0x7F) << UInt64(shift)
                if byte & 0x80 == 0 { return value }
            }
            return nil
        }

        func skip(_ count: UInt64) -> Bool {
            guard count <= UInt64(message.endIndex - offset) else { return false }
            offset += Int(count)
            return true
        }

        while offset < message.endIndex, let tag = readVarint() {
            switch tag & 7 {
            case 0:
                guard readVarint() != nil else { return fields }
            case 1:
                guard skip(8) else { return fields }
            case 5:
                guard skip(4) else { return fields }
            case 2:
                guard let length = readVarint(), length <= UInt64(message.endIndex - offset) else { return fields }
                fields.append((tag >> 3, message.subdata(in: offset..<offset + Int(length))))
                offset += Int(length)
            default:
                return fields
            }
        }
        return fields
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

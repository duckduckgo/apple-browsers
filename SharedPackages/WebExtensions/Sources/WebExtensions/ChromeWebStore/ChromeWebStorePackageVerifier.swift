//
//  ChromeWebStorePackageVerifier.swift
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
import Security
import ZIPFoundation

/// CRX3 signs a domain separator, the signed protobuf header, and the complete ZIP payload.
/// See Chromium's components/crx_file/crx3.proto and crx_verifier.cc.
public struct ChromeWebStorePackageVerifier {
    public init() {}

    public func verifiedArchive(in package: Data, extensionID: String) throws -> Data {
        guard package.count >= 12, package.count <= 64 * 1024 * 1024,
              package.prefix(4) == Data("Cr24".utf8), uint32(package, at: 4) == 3 else {
            throw ChromeWebStoreError.invalidPackage
        }
        let headerSize = Int(uint32(package, at: 8))
        guard headerSize <= 1024 * 1024, headerSize <= package.count - 12 else {
            throw ChromeWebStoreError.invalidPackage
        }
        let fields = try protobufFields(Data(package[12..<(12 + headerSize)]))
        guard let signedHeader = fields[10000]?.only,
              let identifier = try protobufFields(signedHeader)[1]?.only,
              identifier.count == 16, Self.extensionID(from: identifier) == extensionID else {
            throw ChromeWebStoreError.invalidPackage
        }
        let archive = Data(package.dropFirst(12 + headerSize))
        var signedData = Data("CRX3 SignedData\0".utf8)
        let size = UInt32(signedHeader.count)
        signedData.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: size >> ($0 * 8)) })
        signedData.append(signedHeader)
        signedData.append(archive)
        var hasDeveloperSignature = false
        for field in [2, 3] {
            for proof in fields[field] ?? [] {
                let parts = try protobufFields(proof)
                guard let publicKey = parts[1]?.only, let signature = parts[2]?.only else {
                    throw ChromeWebStoreError.invalidSignature
                }
                let keyIdentifier = Data(SHA256.hash(data: publicKey).prefix(16))
                guard keyIdentifier == identifier else { continue }
                hasDeveloperSignature = try verifySignature(signature, publicKey: publicKey, data: signedData, isRSA: field == 2)
                guard hasDeveloperSignature else { throw ChromeWebStoreError.invalidSignature }
            }
        }
        guard hasDeveloperSignature else { throw ChromeWebStoreError.invalidSignature }
        try validateArchive(archive)
        return archive
    }

    static func extensionID(from bytes: Data) -> String {
        String(bytes: bytes.flatMap { [97 + ($0 >> 4), 97 + ($0 & 15)] }, encoding: .utf8) ?? ""
    }

    private func verifySignature(_ signature: Data, publicKey: Data, data: Data, isRSA: Bool) throws -> Bool {
        if !isRSA {
            let key = try P256.Signing.PublicKey(derRepresentation: publicKey)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: signature)
            return key.isValidSignature(signature, for: data)
        }
        let keyData = try rsaKey(from: publicKey)
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil) else {
            throw ChromeWebStoreError.invalidSignature
        }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, signature as CFData, nil)
    }

    private func validateArchive(_ data: Data) throws {
        let archive = try Archive(data: data, accessMode: .read)
        var totalSize: UInt64 = 0
        var paths: Set<String> = []
        var manifestData = Data()
        for entry in archive {
            let path = entry.path
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            let canonicalPath = path.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard entry.type != .symlink, !path.hasPrefix("/"), !path.contains("\\"),
                  !path.contains("\0"), !components.contains(".."), !components.contains("."),
                  !components.dropLast().contains(""),
                  paths.insert(canonicalPath).inserted, paths.count <= 20_000,
                  entry.uncompressedSize <= 256 * 1024 * 1024 - totalSize else {
                throw ChromeWebStoreError.invalidPackage
            }
            totalSize += entry.uncompressedSize
            if path == "manifest.json", entry.uncompressedSize > 1024 * 1024 {
                throw ChromeWebStoreError.invalidPackage
            }
            var extractedSize: UInt64 = 0
            let checksum = try archive.extract(entry) { chunk in
                guard UInt64(chunk.count) <= entry.uncompressedSize - extractedSize else {
                    throw ChromeWebStoreError.invalidPackage
                }
                extractedSize += UInt64(chunk.count)
                if path == "manifest.json" { manifestData.append(chunk) }
            }
            guard extractedSize == entry.uncompressedSize, checksum == entry.checksum else {
                throw ChromeWebStoreError.invalidPackage
            }
        }
        guard let manifest = archive["manifest.json"], manifest.type == .file,
              manifest.uncompressedSize <= 1024 * 1024 else { throw ChromeWebStoreError.invalidPackage }
        guard let object = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let version = object["manifest_version"] as? Int, [2, 3].contains(version),
              object["name"] is String, object["version"] is String,
              object["app"] == nil, object["theme"] == nil else { throw ChromeWebStoreError.unsupportedManifest }
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }

    /// Only the length-delimited protobuf fields are needed; unknown scalar fields are skipped.
    private func protobufFields(_ data: Data) throws -> [Int: [Data]] {
        var cursor = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 70, by: 7) {
                guard cursor < data.count else { throw ChromeWebStoreError.invalidPackage }
                let byte = data[cursor]
                cursor += 1
                guard shift < 63 || byte <= 1 else { throw ChromeWebStoreError.invalidPackage }
                value |= UInt64(byte & 127) << shift
                if byte & 128 == 0 { return value }
            }
            throw ChromeWebStoreError.invalidPackage
        }
        var fields: [Int: [Data]] = [:]
        while cursor < data.count {
            let tag = try varint()
            guard tag >> 3 > 0, tag >> 3 <= 536_870_911 else { throw ChromeWebStoreError.invalidPackage }
            switch tag & 7 {
            case 0: _ = try varint()
            case 1, 5:
                let size = tag & 7 == 1 ? 8 : 4
                guard size <= data.count - cursor else { throw ChromeWebStoreError.invalidPackage }
                cursor += size
            case 2:
                let size = try varint()
                guard size <= UInt64(data.count - cursor) else { throw ChromeWebStoreError.invalidPackage }
                fields[Int(tag >> 3), default: []].append(Data(data[cursor..<(cursor + Int(size))]))
                cursor += Int(size)
            default: throw ChromeWebStoreError.invalidPackage
            }
        }
        return fields
    }

    /// Security expects the PKCS#1 RSA key inside the X.509 SubjectPublicKeyInfo.
    private func rsaKey(from spki: Data) throws -> Data {
        var cursor = 0
        func element(_ tag: UInt8, in data: Data) throws -> Data {
            guard cursor + 2 <= data.count, data[cursor] == tag else { throw ChromeWebStoreError.invalidSignature }
            cursor += 1
            var size = Int(data[cursor])
            cursor += 1
            if size & 128 != 0 {
                let byteCount = size & 127
                guard (1...4).contains(byteCount), cursor + byteCount <= data.count else {
                    throw ChromeWebStoreError.invalidSignature
                }
                size = 0
                for _ in 0..<byteCount { size = (size << 8) | Int(data[cursor]); cursor += 1 }
            }
            guard size <= data.count - cursor else { throw ChromeWebStoreError.invalidSignature }
            defer { cursor += size }
            return Data(data[cursor..<(cursor + size)])
        }
        let sequence = try element(0x30, in: spki)
        guard cursor == spki.count else { throw ChromeWebStoreError.invalidSignature }
        cursor = 0
        let algorithm = try element(0x30, in: sequence)
        guard algorithm == Data([0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]) else {
            throw ChromeWebStoreError.invalidSignature
        }
        let key = try element(0x03, in: sequence)
        guard cursor == sequence.count, key.first == 0 else { throw ChromeWebStoreError.invalidSignature }
        return Data(key.dropFirst())
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

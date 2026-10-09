//
//  ChromeWebStorePackageVerifierTests.swift
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
import Security
import XCTest
import ZIPFoundation
@testable import WebExtensions

final class ChromeWebStorePackageVerifierTests: XCTestCase {
    private let verifier = ChromeWebStorePackageVerifier(publisherKeyHash: ChromeWebStoreFixture.publisherKeyHash)

    func testValidECDSAPackage() throws {
        let fixture = try ChromeWebStoreFixture()
        let archive = try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier)
        XCTAssertEqual(archive.data, fixture.archive)
        XCTAssertEqual(archive.version, "1.0")
    }

    func testValidRSAPackage() throws {
        let fixture = try ChromeWebStoreFixture(rsa: true)
        let archive = try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier)
        XCTAssertEqual(archive.data, fixture.archive)
        XCTAssertEqual(archive.version, "1.0")
    }

    func testArchiveVersion() throws {
        for version in ["1", "1.2.3.4", "65535.65535.65535.65535"] {
            let fixture = try ChromeWebStoreFixture(manifest: ["manifest_version": 3, "name": "Test", "version": version])
            XCTAssertEqual(try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier).version, version)
        }
    }

    func testUnsafeOrInvalidArchiveVersionIsOmittedWithoutRejectingArchive() throws {
        for version in ["", "../escape", "1/2", "1:2", "1\\2", "1\0", "1\n", ".", "1..2", "1.2.3.4.5", "65536", String(repeating: "1", count: 256)] {
            let fixture = try ChromeWebStoreFixture(manifest: ["manifest_version": 3, "name": "Test", "version": version])
            let archive = try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier)
            XCTAssertEqual(archive.data, fixture.archive)
            XCTAssertNil(archive.version, version)
        }
    }

    func testMissingOrNonStringArchiveVersionIsOmittedWithoutRejectingArchive() throws {
        for version: Any? in [nil, 1, NSNull()] {
            var manifest: [String: Any] = ["manifest_version": 3, "name": "Test"]
            manifest["version"] = version
            let fixture = try ChromeWebStoreFixture(manifest: manifest)
            let archive = try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier)
            XCTAssertEqual(archive.data, fixture.archive)
            XCTAssertNil(archive.version)
        }
    }

    func testTamperedPayload() throws {
        let fixture = try ChromeWebStoreFixture()
        var package = fixture.package
        package[package.count - 1] ^= 1
        XCTAssertThrowsError(try verifier.verifiedArchive(in: package, extensionID: fixture.identifier))
    }

    func testWrongExtensionIdentity() throws {
        let fixture = try ChromeWebStoreFixture()
        XCTAssertThrowsError(try verifier.verifiedArchive(in: fixture.package, extensionID: String(repeating: "a", count: 32)))
    }

    func testTruncatedPackageAndMalformedHeaders() throws {
        let fixture = try ChromeWebStoreFixture()
        for length in [0, 1, 4, 11, 12, 20, fixture.package.count - 1] {
            XCTAssertThrowsError(try verifier.verifiedArchive(in: Data(fixture.package.prefix(length)), extensionID: fixture.identifier))
        }
        for offset in [0, 4, 8] {
            var package = fixture.package
            package[offset] = 255
            XCTAssertThrowsError(try verifier.verifiedArchive(in: package, extensionID: fixture.identifier))
        }
    }

    func testSignedArchivesWithUnsafePathsAreRejected() throws {
        for path in ["../escape", "/absolute", "a/../../escape", "a\\b", "./manifest.json", "a//b", "MANIFEST.JSON"] {
            let fixture = try ChromeWebStoreFixture(extraEntry: (path, .file))
            XCTAssertThrowsError(try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier), path)
        }
    }

    func testSignedSymlinkIsRejected() throws {
        let fixture = try ChromeWebStoreFixture(extraEntry: ("link", .symlink))
        XCTAssertThrowsError(try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier))
    }

    func testSignedThemeIsRejected() throws {
        let fixture = try ChromeWebStoreFixture(manifest: ["manifest_version": 3, "name": "Theme", "version": "1", "theme": [:]])
        XCTAssertThrowsError(try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier))
    }

    func testMissingPublisherProofIsRejected() throws {
        let fixture = try ChromeWebStoreFixture(publisher: nil)
        XCTAssertThrowsError(try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier))
    }

    func testInvalidPublisherSignatureIsRejected() throws {
        let fixture = try ChromeWebStoreFixture(publisher: .invalidSignature)
        XCTAssertThrowsError(try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier))
    }

    func testPackageWithoutProductionPublisherProofIsRejectedByDefault() throws {
        let fixture = try ChromeWebStoreFixture()
        XCTAssertThrowsError(try ChromeWebStorePackageVerifier().verifiedArchive(in: fixture.package, extensionID: fixture.identifier))
    }

    func testAdditionalValidProofIsAccepted() throws {
        let fixture = try ChromeWebStoreFixture(additionalProof: .valid)
        let archive = try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier)
        XCTAssertEqual(archive.data, fixture.archive)
    }

    func testAdditionalInvalidProofIsRejected() throws {
        let fixture = try ChromeWebStoreFixture(additionalProof: .invalidSignature)
        XCTAssertThrowsError(try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier))
    }

    func testSignedInvalidManifestIsRejected() throws {
        for manifest: [String: Any] in [[:], ["name": "Missing version"], ["manifest_version": 7, "name": "Future", "version": "1"]] {
            let fixture = try ChromeWebStoreFixture(manifest: manifest)
            XCTAssertThrowsError(try verifier.verifiedArchive(in: fixture.package, extensionID: fixture.identifier))
        }
    }
}

/// Creates real signed CRX3 files without network access or checked-in signing secrets.
struct ChromeWebStoreFixture {
    enum Proof {
        case valid
        case invalidSignature
    }

    /// Stands in for the Chrome Web Store publisher key. Inject `publisherKeyHash` into the verifier under test.
    private static let publisherKey = P256.Signing.PrivateKey()
    static let publisherKeyHash = Data(SHA256.hash(data: publisherKey.publicKey.derRepresentation))

    let package: Data
    let archive: Data
    let identifier: String

    init(rsa: Bool = false,
         publisher: Proof? = .valid,
         additionalProof: Proof? = nil,
         manifest: [String: Any] = ["manifest_version": 3, "name": "Store Test", "description": "Store fixture",
                                    "version": "1.0", "permissions": ["tabs"]],
         extraEntry: (String, Entry.EntryType)? = nil) throws {
        let zip = try Archive(data: Data(), accessMode: .create)
        let manifestData = try JSONSerialization.data(withJSONObject: manifest)
        try zip.addEntry(with: "manifest.json", type: .file, uncompressedSize: Int64(manifestData.count)) { position, size in
            manifestData.subdata(in: Int(position)..<(Int(position) + size))
        }
        if let (path, type) = extraEntry {
            let data = Data("fixture".utf8)
            try zip.addEntry(with: path, type: type, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        archive = try XCTUnwrap(zip.data)
        let publicKey: Data
        let sign: (Data) throws -> Data
        if rsa {
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
            let key = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
            let publicRSAKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
            let raw = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicRSAKey, nil)) as Data
            let algorithm = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
            publicKey = Self.der(0x30, algorithm + Self.der(0x03, Data([0]) + raw))
            sign = { try XCTUnwrap(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, $0 as CFData, nil)) as Data }
        } else {
            let key = P256.Signing.PrivateKey()
            publicKey = key.publicKey.derRepresentation
            sign = { try key.signature(for: $0).derRepresentation }
        }
        let id = Data(SHA256.hash(data: publicKey).prefix(16))
        identifier = ChromeWebStorePackageVerifier.extensionID(from: id)
        let signedHeader = Self.field(1, id)
        let signedData = Data("CRX3 SignedData\0".utf8) + Self.littleEndian(signedHeader.count) + signedHeader + archive
        let proof = Self.field(1, publicKey) + Self.field(2, try sign(signedData))
        var header = Self.field(rsa ? 2 : 3, proof)
        for (key, validity) in [(Self.publisherKey, publisher), (P256.Signing.PrivateKey(), additionalProof)] {
            guard let validity else { continue }
            let data = validity == .valid ? signedData : signedData + Data([0])
            header += Self.field(3, Self.field(1, key.publicKey.derRepresentation) + Self.field(2, try key.signature(for: data).derRepresentation))
        }
        header += Self.field(10000, signedHeader)
        package = Data("Cr24".utf8) + Self.littleEndian(3) + Self.littleEndian(header.count) + header + archive
    }

    private static func littleEndian(_ value: Int) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private static func varint(_ value: Int) -> Data {
        var value = value
        var bytes = Data()
        repeat {
            let byte = UInt8(value & 127)
            value >>= 7
            bytes.append(byte | (value == 0 ? 0 : 128))
        } while value != 0
        return bytes
    }

    private static func field(_ number: Int, _ data: Data) -> Data {
        varint(number * 8 + 2) + varint(data.count) + data
    }

    private static func der(_ tag: UInt8, _ data: Data) -> Data {
        if data.count < 128 { return Data([tag, UInt8(data.count)]) + data }
        return Data([tag, 0x82, UInt8(data.count >> 8), UInt8(data.count & 255)]) + data
    }
}

//
//  CRXArchiveTests.swift
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
import XCTest

@testable import WebExtensions

final class CRXArchiveTests: XCTestCase {

    private let zip = Data("PK\u{3}\u{4}payload".utf8)

    func testWhenCRX3_ThenHeaderIsStripped() throws {
        let header = Data(repeating: 0xAB, count: 10)
        let crx = Data("Cr24".utf8) + uint32(3) + uint32(10) + header + zip

        XCTAssertEqual(try CRXArchive.zipData(from: crx), zip)
    }

    func testWhenCRX2_ThenKeyAndSignatureAreStripped() throws {
        let keyAndSignature = Data(repeating: 0xCD, count: 7)
        let crx = Data("Cr24".utf8) + uint32(2) + uint32(3) + uint32(4) + keyAndSignature + zip

        XCTAssertEqual(try CRXArchive.zipData(from: crx), zip)
    }

    func testWhenMagicIsWrong_ThenThrowsInvalidMagic() {
        let crx = Data("Xr24".utf8) + uint32(3) + uint32(0) + zip

        XCTAssertThrowsError(try CRXArchive.zipData(from: crx)) {
            XCTAssertEqual($0 as? CRXArchiveError, .invalidMagic)
        }
    }

    func testWhenDataIsEmpty_ThenThrowsInvalidMagic() {
        XCTAssertThrowsError(try CRXArchive.zipData(from: Data())) {
            XCTAssertEqual($0 as? CRXArchiveError, .invalidMagic)
        }
    }

    func testWhenVersionIsUnsupported_ThenThrowsUnsupportedVersion() {
        let crx = Data("Cr24".utf8) + uint32(4) + uint32(0) + zip

        XCTAssertThrowsError(try CRXArchive.zipData(from: crx)) {
            XCTAssertEqual($0 as? CRXArchiveError, .unsupportedVersion(4))
        }
    }

    func testWhenFixedHeaderIsTruncated_ThenThrowsTruncated() {
        for crx in [Data("Cr24".utf8), Data("Cr24".utf8) + uint32(3), Data("Cr24".utf8) + uint32(3) + Data([1, 0]),
                    Data("Cr24".utf8) + uint32(2) + uint32(1)] {
            XCTAssertThrowsError(try CRXArchive.zipData(from: crx)) {
                XCTAssertEqual($0 as? CRXArchiveError, .truncated)
            }
        }
    }

    func testWhenCRX3HeaderLengthExceedsData_ThenThrowsTruncated() {
        let crx = Data("Cr24".utf8) + uint32(3) + uint32(1000) + zip

        XCTAssertThrowsError(try CRXArchive.zipData(from: crx)) {
            XCTAssertEqual($0 as? CRXArchiveError, .truncated)
        }
    }

    func testWhenCRX2LengthsExceedData_ThenThrowsTruncatedWithoutOverflow() {
        let crx = Data("Cr24".utf8) + uint32(2) + uint32(.max) + uint32(.max) + zip

        XCTAssertThrowsError(try CRXArchive.zipData(from: crx)) {
            XCTAssertEqual($0 as? CRXArchiveError, .truncated)
        }
    }

    func testWhenNothingFollowsHeader_ThenThrowsMissingZipPayload() {
        let crx = Data("Cr24".utf8) + uint32(3) + uint32(2) + Data([1, 2])

        XCTAssertThrowsError(try CRXArchive.zipData(from: crx)) {
            XCTAssertEqual($0 as? CRXArchiveError, .missingZipPayload)
        }
    }

    // MARK: - Public key

    private let developerKey = Data("developer-key".utf8)
    private let storeKeyA = Data("store-key-a".utf8)
    private let storeKeyB = Data("store-key-b".utf8)

    func testWhenCRX3HasMatchingProof_ThenReturnsDeveloperKey() {
        let header = crx3Header(rsaKeys: [storeKeyA, developerKey], ecdsaKeys: [storeKeyB], crxIDKey: developerKey)

        XCTAssertEqual(CRXArchive.publicKey(from: crx3(header: header)), developerKey)
    }

    func testWhenCRX3DeveloperKeyIsInEcdsaProof_ThenReturnsIt() {
        let header = crx3Header(rsaKeys: [storeKeyA], ecdsaKeys: [developerKey], crxIDKey: developerKey)

        XCTAssertEqual(CRXArchive.publicKey(from: crx3(header: header)), developerKey)
    }

    func testWhenNoCRX3ProofMatchesCrxID_ThenReturnsNil() {
        let header = crx3Header(rsaKeys: [storeKeyA, storeKeyB], ecdsaKeys: [storeKeyA], crxIDKey: developerKey)

        XCTAssertNil(CRXArchive.publicKey(from: crx3(header: header)))
    }

    func testWhenCRX3HasNoSignedHeaderData_ThenReturnsNil() {
        let header = field(2, field(1, developerKey) + field(2, Data([1])))

        XCTAssertNil(CRXArchive.publicKey(from: crx3(header: header)))
    }

    func testWhenCRX3HeaderIsMalformed_ThenReturnsNilWithoutCrashing() {
        let valid = crx3Header(rsaKeys: [storeKeyA, developerKey], ecdsaKeys: [], crxIDKey: developerKey)
        var headers = (0..<valid.count).map { Data(valid.prefix($0)) } // every truncation
        headers.append(Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])) // endless varint
        headers.append(Data([0x12, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F])) // length beyond data
        headers.append(Data([0x13, 0x01])) // group wire type
        headers.append(Data(repeating: 0xAA, count: 64))

        for header in headers {
            _ = CRXArchive.publicKey(from: crx3(header: header))
        }
        XCTAssertNil(CRXArchive.publicKey(from: crx3(header: Data(valid.prefix(valid.count - 1)))))
    }

    func testWhenCRX3HeaderLengthExceedsData_ThenPublicKeyIsNil() {
        let crx = Data("Cr24".utf8) + uint32(3) + uint32(1000) + Data([1, 2, 3])

        XCTAssertNil(CRXArchive.publicKey(from: crx))
    }

    func testWhenCRX2_ThenReturnsHeaderKey() {
        let signature = Data(repeating: 0xEE, count: 5)
        let crx = Data("Cr24".utf8) + uint32(2) + uint32(UInt32(developerKey.count)) + uint32(UInt32(signature.count))
            + developerKey + signature + zip

        XCTAssertEqual(CRXArchive.publicKey(from: crx), developerKey)
    }

    func testWhenCRX2IsTruncatedOrNotACRX_ThenPublicKeyIsNil() {
        XCTAssertNil(CRXArchive.publicKey(from: Data("Cr24".utf8) + uint32(2) + uint32(.max) + uint32(0)))
        XCTAssertNil(CRXArchive.publicKey(from: Data("Cr24".utf8) + uint32(2) + uint32(1)))
        XCTAssertNil(CRXArchive.publicKey(from: Data("Cr24".utf8) + uint32(9) + uint32(0)))
        XCTAssertNil(CRXArchive.publicKey(from: Data()))
        XCTAssertNil(CRXArchive.publicKey(from: Data("not a crx at all".utf8)))
    }

    // MARK: - Helpers

    private func crx3(header: Data) -> Data {
        Data("Cr24".utf8) + uint32(3) + uint32(UInt32(header.count)) + header + zip
    }

    /// A `CrxFileHeader`: RSA proofs (field 2), ECDSA proofs (field 3) and `signed_header_data` (field 10000).
    private func crx3Header(rsaKeys: [Data], ecdsaKeys: [Data], crxIDKey: Data) -> Data {
        let signature = field(2, Data(repeating: 7, count: 4))
        let crxID = Data(SHA256.hash(data: crxIDKey).prefix(16))
        return rsaKeys.reduce(Data()) { $0 + field(2, field(1, $1) + signature) }
            + ecdsaKeys.reduce(Data()) { $0 + field(3, field(1, $1) + signature) }
            + field(10000, field(1, crxID))
    }

    /// A length-delimited protobuf field.
    private func field(_ number: Int, _ bytes: Data) -> Data {
        varint(number << 3 | 2) + varint(bytes.count) + bytes
    }

    private func varint(_ value: Int) -> Data {
        var value = value
        var out = Data()
        while value >= 0x80 {
            out.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        out.append(UInt8(value))
        return out
    }

    private func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}

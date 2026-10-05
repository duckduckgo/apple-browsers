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

    private func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}

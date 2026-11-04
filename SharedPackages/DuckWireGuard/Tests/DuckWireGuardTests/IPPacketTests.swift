//
//  IPPacketTests.swift
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
import XCTest
@testable import DuckWireGuard

final class IPPacketTests: XCTestCase {
    func testIPv4MinimumHeaderAndBigEndianTotalLength() throws {
        let minimum = try ipv4Header()
        XCTAssertEqual(try IPPacket.length(of: minimum), 20)

        var packet = minimum + Data(repeating: 0xab, count: 238)
        packet[2] = 0x01
        packet[3] = 0x02
        XCTAssertEqual(try IPPacket.length(of: packet), 258)
    }

    func testIPv4OptionsRespectHeaderAndTotalLengths() throws {
        let options = try WireGuardTestData.hexBytes("460000180000000040110000c0000201c000020201020304")
        XCTAssertEqual(try IPPacket.length(of: options), 24)

        var maximumHeader = try ipv4Header() + Data(repeating: 0, count: 40)
        maximumHeader[0] = 0x4f
        maximumHeader[3] = 60
        XCTAssertEqual(try IPPacket.length(of: maximumHeader), 60)
        maximumHeader[3] = 59
        assertInvalidPacket(maximumHeader)
    }

    func testIPv4RejectsTruncatedHeadersAndInvalidLengths() throws {
        let header = try ipv4Header()
        for length in 0..<20 {
            assertInvalidPacket(Data(header.prefix(length)))
        }
        for first in [UInt8(0x40), 0x44, 0x4f] {
            var packet = header
            packet[0] = first
            assertInvalidPacket(packet)
        }
        for totalLength in [UInt8(0), 19, 21] {
            var packet = header
            packet[3] = totalLength
            assertInvalidPacket(packet)
        }
    }

    func testIPv6PayloadLengthIncludesTheFixedHeader() throws {
        let header = ipv6Header()
        XCTAssertEqual(try IPPacket.length(of: header), 40)

        var packet = header + Data([1, 2, 3])
        packet[5] = 3
        XCTAssertEqual(try IPPacket.length(of: packet), 43)

        var larger = header + Data(repeating: 0xab, count: 258)
        larger[4] = 0x01
        larger[5] = 0x02
        XCTAssertEqual(try IPPacket.length(of: larger), 298)
    }

    func testIPv6RejectsTruncatedHeadersAndPayloads() throws {
        let header = ipv6Header()
        for length in 0..<40 {
            assertInvalidPacket(Data(header.prefix(length)))
        }
        var truncatedPayload = header + Data([1, 2, 3])
        truncatedPayload[5] = 4
        assertInvalidPacket(truncatedPayload)
    }

    func testPaddingIsOutsideTheDeclaredPacketLength() throws {
        let ipv4 = try ipv4Header() + Data(repeating: 0xab, count: 12)
        XCTAssertEqual(try IPPacket.length(of: ipv4), 20)

        var ipv6 = ipv6Header() + Data([1, 2, 3])
        ipv6[5] = 3
        ipv6 += Data(repeating: 0xcd, count: 5)
        XCTAssertEqual(try IPPacket.length(of: ipv6), 43)
    }

    func testEmptyAndUnsupportedIPVersionsAreRejected() {
        assertInvalidPacket(Data())
        for version in [UInt8(0), 1, 5, 7, 15] {
            var packet = Data(repeating: 0, count: 40)
            packet[0] = version << 4
            assertInvalidPacket(packet)
        }
    }

    func testSlicedDataUsesIndicesRelativeToItsStart() throws {
        let ipv4 = try ipv4Header()
        var ipv6 = ipv6Header() + Data([1, 2, 3])
        ipv6[5] = 3
        for (packet, expectedLength) in [(ipv4, 20), (ipv6, 43)] {
            let sliced = (Data([0xaa, 0xbb, 0xcc]) + packet + Data([0xdd])).dropFirst(3)
            XCTAssertEqual(sliced.startIndex, 3)
            XCTAssertEqual(try IPPacket.length(of: sliced), expectedLength)
        }
    }

    private func ipv4Header() throws -> Data {
        // RFC 791 field positions; total length is 20 and IHL is five 32-bit words.
        try WireGuardTestData.hexBytes("450000140000000040110000c0000201c0000202")
    }

    private func ipv6Header() -> Data {
        var header = Data(repeating: 0, count: 40)
        header[0] = 0x60
        return header
    }

    private func assertInvalidPacket(_ packet: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try IPPacket.length(of: packet), file: file, line: line) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .invalidPacket, file: file, line: line)
        }
    }
}

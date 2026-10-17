//
//  STUNMessageTests.swift
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
@testable import VPN

final class STUNMessageTests: XCTestCase {

    func testBindingRequestHeader() {
        let request = STUNMessage.bindingRequest(transactionID: Data(repeating: 0xAB, count: 12))
        XCTAssertEqual(request.count, 20)
        XCTAssertEqual(request[0], 0x00)
        XCTAssertEqual(request[1], 0x01)
        XCTAssertEqual(request[2], 0x00)
        XCTAssertEqual(request[3], 0x00)
        XCTAssertEqual(request[4], 0x21)
        XCTAssertEqual(request[5], 0x12)
        XCTAssertEqual(request[6], 0xA4)
        XCTAssertEqual(request[7], 0x42)
        XCTAssertEqual(Array(request[8..<20]), Array(repeating: UInt8(0xAB), count: 12))
    }

    func testRandomTransactionIDsDiffer() {
        let a = STUNMessage.randomTransactionID()
        let b = STUNMessage.randomTransactionID()
        XCTAssertNotEqual(a, b)
    }

    func testDecodeBindingResponse_IPv4() throws {
        let transactionID = Data(repeating: 0x11, count: 12)
        var response = Data([0x01, 0x01, 0x00, 0x0C])
        response.append(contentsOf: STUNMessage.magicCookieBytes)
        response.append(transactionID)
        response.append(contentsOf: [0x00, 0x20, 0x00, 0x08])
        response.append(contentsOf: [0x00, 0x01])
        response.append(contentsOf: [0x33, 0x26])
        let xoredAddress: [UInt8] = [
            UInt8(0x08) ^ UInt8(0x21),
            UInt8(0x08) ^ UInt8(0x12),
            UInt8(0x08) ^ UInt8(0xA4),
            UInt8(0x08) ^ UInt8(0x42)
        ]
        response.append(contentsOf: xoredAddress)

        let ip = try STUNMessage.extractMappedAddress(from: response, transactionID: transactionID)
        XCTAssertEqual(ip, "8.8.8.8")
    }

    func testDecodeBindingResponse_IPv6() throws {
        let transactionID = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C])
        var response = Data([0x01, 0x01, 0x00, 0x18])
        response.append(contentsOf: STUNMessage.magicCookieBytes)
        response.append(transactionID)
        response.append(contentsOf: [0x00, 0x20, 0x00, 0x14])
        response.append(contentsOf: [0x00, 0x02])
        response.append(contentsOf: [0x00, 0x00])
        let plain: [UInt8] = [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01]
        let xorKey: [UInt8] = STUNMessage.magicCookieBytes + Array(transactionID)
        let xored = zip(plain, xorKey).map { $0 ^ $1 }
        response.append(contentsOf: xored)

        let ip = try STUNMessage.extractMappedAddress(from: response, transactionID: transactionID)
        XCTAssertEqual(ip, "2001:db8::1")
    }

    func testDecodeBindingResponse_Malformed_ShortHeader() {
        let short = Data(repeating: 0, count: 10)
        XCTAssertThrowsError(try STUNMessage.extractMappedAddress(from: short, transactionID: Data(count: 12)))
    }

    func testDecodeBindingResponse_MissingAttribute() {
        var response = Data([0x01, 0x01, 0x00, 0x00])
        response.append(contentsOf: STUNMessage.magicCookieBytes)
        response.append(Data(count: 12))
        XCTAssertThrowsError(try STUNMessage.extractMappedAddress(from: response, transactionID: Data(count: 12)))
    }
}

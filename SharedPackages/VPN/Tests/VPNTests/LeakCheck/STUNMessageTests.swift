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

    func testBindingRequestGeneratesRandomTransactionID() {
        let a = STUNMessage.bindingRequest()
        let b = STUNMessage.bindingRequest()
        XCTAssertNotEqual(Array(a[8..<20]), Array(b[8..<20]))
    }
}

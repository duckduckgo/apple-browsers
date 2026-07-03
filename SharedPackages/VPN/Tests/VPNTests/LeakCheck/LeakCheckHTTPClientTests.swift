//
//  LeakCheckHTTPClientTests.swift
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

final class LeakCheckHTTPClientTests: XCTestCase {

    func testParseIP_validResponse() throws {
        let raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 18\r\n\r\n{\"ip\":\"8.8.8.8\"}"
        let ip = try LeakCheckHTTPResponseParser.parse(raw)
        XCTAssertEqual(ip, "8.8.8.8")
    }

    func testParseIP_nonOKStatus() {
        let raw = "HTTP/1.1 500 Server Error\r\n\r\n"
        XCTAssertThrowsError(try LeakCheckHTTPResponseParser.parse(raw)) { error in
            guard case LeakCheckHTTPResponseParser.ParseError.nonSuccessStatus(let code) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(code, 500)
        }
    }

    func testParseIP_missingBody() {
        let raw = "HTTP/1.1 200 OK\r\n\r\n"
        XCTAssertThrowsError(try LeakCheckHTTPResponseParser.parse(raw))
    }

    func testParseIP_malformedJSON() {
        let raw = "HTTP/1.1 200 OK\r\n\r\n{not json}"
        XCTAssertThrowsError(try LeakCheckHTTPResponseParser.parse(raw))
    }

    func testParseIP_missingIPField() {
        let raw = "HTTP/1.1 200 OK\r\n\r\n{\"something\":\"else\"}"
        XCTAssertThrowsError(try LeakCheckHTTPResponseParser.parse(raw))
    }
}

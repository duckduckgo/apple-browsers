//
//  HTTPResponseTests.swift
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
@testable import DebugServer

final class HTTPResponseTests: XCTestCase {

    // MARK: - Convenience Constructors

    func testWhenJSONResponseCreatedThenContentTypeIsSet() {
        let data = "{\"key\":\"value\"}".data(using: .utf8)!
        let response = HTTPResponse.json(data)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "application/json; charset=utf-8")
        XCTAssertEqual(response.body, data)
    }

    func testWhenHTMLResponseCreatedThenContentTypeIsSet() {
        let response = HTTPResponse.html("<h1>Hi</h1>")

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "text/html; charset=utf-8")
        XCTAssertEqual(String(data: response.body!, encoding: .utf8), "<h1>Hi</h1>")
    }

    func testWhenTextResponseCreatedThenContentTypeIsSet() {
        let response = HTTPResponse.text("hello")

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers["Content-Type"], "text/plain; charset=utf-8")
        XCTAssertEqual(String(data: response.body!, encoding: .utf8), "hello")
    }

    func testWhenEmptyResponseCreatedThenStatusIsNoContent() {
        let response = HTTPResponse.empty()

        XCTAssertEqual(response.status, .noContent)
        XCTAssertNil(response.body)
    }

    func testWhenJSONResponseWithCustomStatusThenStatusIsUsed() {
        let response = HTTPResponse.json(Data(), status: .created)

        XCTAssertEqual(response.status, .created)
    }

    func testWhenHTMLResponseWithCustomStatusThenStatusIsUsed() {
        let response = HTTPResponse.html("<p>Error</p>", status: .badRequest)

        XCTAssertEqual(response.status, .badRequest)
    }
}

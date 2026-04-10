//
//  ResponseSerializerTests.swift
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

final class ResponseSerializerTests: XCTestCase {

    private let serializer = ResponseSerializer()

    // MARK: - Status Line

    func testWhenOKResponseThenStatusLineIsCorrect() {
        let response = HTTPResponse(status: .ok)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.hasPrefix("HTTP/1.1 200 OK\r\n"))
    }

    func testWhenNotFoundResponseThenStatusLineIsCorrect() {
        let response = HTTPResponse(status: .notFound)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
    }

    func testWhenInternalServerErrorThenStatusLineIsCorrect() {
        let response = HTTPResponse(status: .internalServerError)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.hasPrefix("HTTP/1.1 500 Internal Server Error\r\n"))
    }

    // MARK: - Headers

    func testWhenCustomHeadersThenTheyAreIncluded() {
        let response = HTTPResponse(
            status: .ok,
            headers: ["X-Custom": "value"]
        )
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("X-Custom: value\r\n"))
    }

    func testWhenNoContentLengthProvidedThenItIsAdded() {
        let body = "Hello".data(using: .utf8)!
        let response = HTTPResponse(status: .ok, body: body)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("Content-Length: 5\r\n"))
    }

    func testWhenContentLengthProvidedThenItIsNotOverridden() {
        let response = HTTPResponse(
            status: .ok,
            headers: ["Content-Length": "99"],
            body: "Hi".data(using: .utf8)
        )
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("Content-Length: 99\r\n"))
        XCTAssertFalse(output.contains("Content-Length: 2\r\n"))
    }

    func testWhenConnectionHeaderNotProvidedThenCloseIsAdded() {
        let response = HTTPResponse(status: .ok)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("Connection: close\r\n"))
    }

    // MARK: - Body

    func testWhenBodyPresentThenItAppearsAfterHeaders() {
        let body = "{\"ok\":true}"
        let response = HTTPResponse(status: .ok, body: body.data(using: .utf8))
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        let parts = output.components(separatedBy: "\r\n\r\n")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[1], body)
    }

    func testWhenNoBodyThenContentLengthIsZero() {
        let response = HTTPResponse(status: .noContent)
        let output = String(data: serializer.serialize(response), encoding: .utf8)!

        XCTAssertTrue(output.contains("Content-Length: 0\r\n"))
    }
}

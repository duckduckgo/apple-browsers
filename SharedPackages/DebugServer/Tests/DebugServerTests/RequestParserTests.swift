//
//  RequestParserTests.swift
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

final class RequestParserTests: XCTestCase {

    private let parser = RequestParser()

    // MARK: - Request Line Parsing

    func testWhenValidGETRequestThenMethodAndPathAreParsed() throws {
        let raw = "GET /api/chats HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertEqual(request.method, .GET)
        XCTAssertEqual(request.path, "/api/chats")
    }

    func testWhenPOSTRequestThenMethodIsParsed() throws {
        let raw = "POST /api/chats HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertEqual(request.method, .POST)
    }

    func testWhenDELETERequestThenMethodIsParsed() throws {
        let raw = "DELETE /api/chats/1 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertEqual(request.method, .DELETE)
        XCTAssertEqual(request.path, "/api/chats/1")
    }

    func testWhenEmptyDataThenThrowsEmptyDataError() {
        XCTAssertThrowsError(try parser.parse(Data())) { error in
            XCTAssertEqual(error as? RequestParserError, .emptyData)
        }
    }

    func testWhenInvalidRequestLineThenThrowsError() {
        let raw = "INVALID\r\n\r\n"
        XCTAssertThrowsError(try parser.parse(raw.data(using: .utf8)!)) { error in
            XCTAssertEqual(error as? RequestParserError, .invalidRequestLine)
        }
    }

    func testWhenUnsupportedMethodThenThrowsError() {
        let raw = "TRACE /path HTTP/1.1\r\n\r\n"
        XCTAssertThrowsError(try parser.parse(raw.data(using: .utf8)!)) { error in
            XCTAssertEqual(error as? RequestParserError, .unsupportedMethod("TRACE"))
        }
    }

    // MARK: - Query Parameters

    func testWhenQueryParametersPresentThenTheyAreParsed() throws {
        let raw = "GET /search?q=hello&page=2 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertEqual(request.path, "/search")
        XCTAssertEqual(request.queryParameters["q"], "hello")
        XCTAssertEqual(request.queryParameters["page"], "2")
    }

    func testWhenNoQueryParametersThenDictionaryIsEmpty() throws {
        let raw = "GET /path HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertTrue(request.queryParameters.isEmpty)
    }

    func testWhenQueryParameterHasNoValueThenValueIsEmptyString() throws {
        let raw = "GET /path?flag HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertEqual(request.queryParameters["flag"], "")
    }

    // MARK: - Headers

    func testWhenHeadersPresentThenTheyAreParsed() throws {
        let raw = "GET / HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nAccept: */*\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertEqual(request.headers["Host"], "localhost")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(request.headers["Accept"], "*/*")
    }

    func testWhenNoHeadersThenDictionaryIsEmpty() throws {
        let raw = "GET / HTTP/1.1\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertTrue(request.headers.isEmpty)
    }

    // MARK: - Body

    func testWhenBodyPresentThenItIsParsed() throws {
        let body = "{\"name\":\"test\"}"
        let raw = "POST /api HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n\(body)"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertNotNil(request.body)
        XCTAssertEqual(String(data: request.body!, encoding: .utf8), body)
    }

    func testWhenNoBodyThenBodyIsNil() throws {
        let raw = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertNil(request.body)
    }

    func testWhenBodyIsShorterThanContentLengthThenThrowsIncompleteBodyError() {
        let raw = "POST /api HTTP/1.1\r\nContent-Length: 10\r\n\r\n123"

        XCTAssertThrowsError(try parser.parse(raw.data(using: .utf8)!)) { error in
            XCTAssertEqual(error as? RequestParserError, .incompletebody)
        }
    }

    // MARK: - Case Insensitive Method

    func testWhenMethodIsLowercaseThenItIsParsed() throws {
        let raw = "get /path HTTP/1.1\r\n\r\n"
        let request = try parser.parse(raw.data(using: .utf8)!)

        XCTAssertEqual(request.method, .GET)
    }
}

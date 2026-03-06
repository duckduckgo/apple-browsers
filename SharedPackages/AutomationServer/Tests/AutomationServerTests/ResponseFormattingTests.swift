//
//  ResponseFormattingTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import AutomationServer

@MainActor
final class ResponseFormattingTests: XCTestCase {

    var mockProvider: MockBrowserAutomationProvider!
    var server: AutomationServerCore!

    override func setUp() async throws {
        mockProvider = MockBrowserAutomationProvider()
        // Use a random high port to avoid conflicts
        server = try AutomationServerCore(provider: mockProvider, port: 59999)
    }

    override func tearDown() async throws {
        server.listener.cancel()
        server = nil
        mockProvider = nil
    }

    // MARK: - HTTP Format Tests

    func testSuccessResponse_ContainsCRLFLineEndings() {
        let result: ConnectionResultWithPath = ("/test", .success("ok"))
        let response = server.responseToString(result)

        // HTTP requires CRLF (\r\n) line endings
        XCTAssertTrue(response.contains("\r\n"), "Response must use CRLF line endings")
    }

    func testSuccessResponse_ContainsHeaderTerminator() {
        let result: ConnectionResultWithPath = ("/test", .success("ok"))
        let response = server.responseToString(result)

        // Headers must be terminated with \r\n\r\n
        XCTAssertTrue(response.contains("\r\n\r\n"), "Response must have header terminator")
    }

    func testSuccessResponse_Has200StatusCode() {
        let result: ConnectionResultWithPath = ("/test", .success("ok"))
        let response = server.responseToString(result)

        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
    }

    func testErrorResponse_Has400StatusCode() {
        let result: ConnectionResultWithPath = ("/test", .failure(.unknownMethod))
        let response = server.responseToString(result)

        XCTAssertTrue(response.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
    }

    func testResponse_ContainsContentTypeHeader() {
        let result: ConnectionResultWithPath = ("/test", .success("ok"))
        let response = server.responseToString(result)

        XCTAssertTrue(response.contains("Content-Type: application/json\r\n"))
    }

    func testResponse_ContainsConnectionCloseHeader() {
        let result: ConnectionResultWithPath = ("/test", .success("ok"))
        let response = server.responseToString(result)

        XCTAssertTrue(response.contains("Connection: close\r\n"))
    }

    func testSuccessResponse_ContainsRequestPath() {
        let result: ConnectionResultWithPath = ("/myPath", .success("ok"))
        let response = server.responseToString(result)

        XCTAssertTrue(response.contains("\"requestPath\""))
        XCTAssertTrue(response.contains("myPath"))
    }

    func testSuccessResponse_ContainsMessage() {
        let result: ConnectionResultWithPath = ("/test", .success("testMessage"))
        let response = server.responseToString(result)

        XCTAssertTrue(response.contains("\"message\""))
        XCTAssertTrue(response.contains("testMessage"))
    }

    // MARK: - Query Parameter Tests

    func testGetQueryStringParameter_ReturnsValue() {
        let url = URLComponents(string: "/test?foo=bar")!
        let result = server.getQueryStringParameter(url: url, param: "foo")
        XCTAssertEqual(result, "bar")
    }

    func testGetQueryStringParameter_ReturnsNilForMissingParam() {
        let url = URLComponents(string: "/test?foo=bar")!
        let result = server.getQueryStringParameter(url: url, param: "missing")
        XCTAssertNil(result)
    }

    func testGetQueryStringParameter_HandlesURLEncodedValues() {
        let url = URLComponents(string: "/test?url=https%3A%2F%2Fexample.com")!
        let result = server.getQueryStringParameter(url: url, param: "url")
        XCTAssertEqual(result, "https://example.com")
    }

    func testGetQueryStringParameter_HandlesEmptyValue() {
        let url = URLComponents(string: "/test?empty=")!
        let result = server.getQueryStringParameter(url: url, param: "empty")
        XCTAssertEqual(result, "")
    }
}

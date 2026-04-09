//
//  DebugHTTPServerTests.swift
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

final class DebugHTTPServerTests: XCTestCase {

    private var server: DebugHTTPServer!

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    // MARK: - Lifecycle

    func testWhenCreatedThenStateIsStopped() {
        server = DebugHTTPServer(port: 8090)
        XCTAssertEqual(server.state, .stopped)
    }

    func testWhenStartedThenStateBecomesRunning() throws {
        server = DebugHTTPServer(port: 8091)

        let expectation = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state {
                expectation.fulfill()
            }
        }

        try server.start()
        wait(for: [expectation], timeout: 5)

        if case .running(let port) = server.state {
            XCTAssertEqual(port, 8091)
        } else {
            XCTFail("Expected running state, got \(server.state)")
        }
    }

    func testWhenStoppedThenStateIsStopped() throws {
        server = DebugHTTPServer(port: 8092)

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state {
                started.fulfill()
            }
        }

        try server.start()
        wait(for: [started], timeout: 5)

        let stopped = expectation(description: "Server stopped")
        server.stateDidChange = { state in
            if case .stopped = state {
                stopped.fulfill()
            }
        }

        server.stop()
        wait(for: [stopped], timeout: 5)

        XCTAssertEqual(server.state, .stopped)
    }

    func testWhenStateChangesThenCallbackIsCalled() throws {
        server = DebugHTTPServer(port: 8093)

        var observedStates: [ServerState] = []
        let running = expectation(description: "Running")

        server.stateDidChange = { state in
            observedStates.append(state)
            if case .running = state {
                running.fulfill()
            }
        }

        try server.start()
        wait(for: [running], timeout: 5)

        XCTAssertTrue(observedStates.contains(.starting))
        XCTAssertTrue(observedStates.contains(where: {
            if case .running = $0 { return true }
            return false
        }))
    }

    // MARK: - Integration (Full Request/Response Cycle)

    func testWhenGETRequestSentThenCorrectResponseIsReturned() throws {
        server = DebugHTTPServer(port: 8094)
        server.addRoute("/hello", method: .GET) { _ in
            .text("world")
        }

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        wait(for: [started], timeout: 5)

        let responseBody = try performRequest(port: 8094, path: "/hello")
        XCTAssertEqual(responseBody, "world")
    }

    func testWhenUnknownRouteThenReturns404() throws {
        server = DebugHTTPServer(port: 8095)

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        wait(for: [started], timeout: 5)

        let (statusCode, _) = try performRequestWithStatus(port: 8095, path: "/nonexistent")
        XCTAssertEqual(statusCode, 404)
    }

    func testWhenStaticRouteRegisteredThenHTMLIsReturned() throws {
        server = DebugHTTPServer(port: 8096)
        server.addStaticRoute("/page", htmlString: "<h1>Hello</h1>")

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        wait(for: [started], timeout: 5)

        let responseBody = try performRequest(port: 8096, path: "/page")
        XCTAssertEqual(responseBody, "<h1>Hello</h1>")
    }

    func testWhenPOSTWithBodyThenHandlerReceivesBody() throws {
        server = DebugHTTPServer(port: 8097)

        var receivedBody: String?
        server.addRoute("/echo", method: .POST) { request in
            if let body = request.body {
                receivedBody = String(data: body, encoding: .utf8)
            }
            return .text("ok")
        }

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        wait(for: [started], timeout: 5)

        let body = "test-body"
        _ = try performRequest(port: 8097, path: "/echo", method: "POST", body: body)
        XCTAssertEqual(receivedBody, body)
    }

    func testWhenMultiplePrefixRoutesMatchThenMostSpecificRouteIsUsed() throws {
        server = DebugHTTPServer(port: 8100)
        server.addPrefixRoute("/api/", method: .GET) { _ in
            .text("generic")
        }
        server.addPrefixRoute("/api/chats/", method: .GET) { _ in
            .text("specific")
        }

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        wait(for: [started], timeout: 5)

        let responseBody = try performRequest(port: 8100, path: "/api/chats/123")
        XCTAssertEqual(responseBody, "specific")
    }

    func testWhenHandlerThrowsThenReturns500() throws {
        server = DebugHTTPServer(port: 8098)
        server.addRoute("/fail", method: .GET) { _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "intentional"])
        }

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        wait(for: [started], timeout: 5)

        let (statusCode, _) = try performRequestWithStatus(port: 8098, path: "/fail")
        XCTAssertEqual(statusCode, 500)
    }

    // MARK: - Helpers

    private func performRequest(
        port: UInt16,
        path: String,
        method: String = "GET",
        body: String? = nil
    ) throws -> String {
        let (_, responseBody) = try performRequestWithStatus(port: port, path: path, method: method, body: body)
        return responseBody
    }

    private func performRequestWithStatus(
        port: UInt16,
        path: String,
        method: String = "GET",
        body: String? = nil
    ) throws -> (Int, String) {
        let url = URL(string: "http://localhost:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body.data(using: .utf8)
        }

        let responseExpectation = expectation(description: "Response received")
        var responseData: Data?
        var httpResponse: HTTPURLResponse?

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            responseData = data
            httpResponse = response as? HTTPURLResponse
            responseExpectation.fulfill()
        }
        task.resume()

        wait(for: [responseExpectation], timeout: 5)

        let statusCode = httpResponse?.statusCode ?? 0
        let responseBody = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return (statusCode, responseBody)
    }
}

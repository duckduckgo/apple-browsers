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
        server = DebugHTTPServer(port: 0)
        XCTAssertEqual(server.state, .stopped)
    }

    func testWhenStartedThenStateBecomesRunning() throws {
        server = DebugHTTPServer(port: 0)

        let expectation = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state {
                expectation.fulfill()
            }
        }

        try server.start()
        wait(for: [expectation], timeout: 5)

        if case .running(let port) = server.state {
            XCTAssertGreaterThan(port, 0)
        } else {
            XCTFail("Expected running state, got \(server.state)")
        }
    }

    func testWhenStoppedThenStateIsStopped() throws {
        server = DebugHTTPServer(port: 0)

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
        server = DebugHTTPServer(port: 0)

        let starting = expectation(description: "Starting")
        let running = expectation(description: "Running")
        server.stateDidChange = { state in
            if case .starting = state { starting.fulfill() }
            if case .running = state { running.fulfill() }
        }

        try server.start()
        wait(for: [starting, running], timeout: 5, enforceOrder: true)
    }

    // MARK: - Integration (Full Request/Response Cycle)

    func testWhenGETRequestSentThenCorrectResponseIsReturned() async throws {
        server = DebugHTTPServer(port: 0)
        server.addRoute("/hello", method: .GET) { _ in
            .text("world")
        }

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        await fulfillment(of: [started], timeout: 5)

        let responseBody = try await performRequest(path: "/hello")
        XCTAssertEqual(responseBody, "world")
    }

    func testWhenUnknownRouteThenReturns404() async throws {
        server = DebugHTTPServer(port: 0)

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        await fulfillment(of: [started], timeout: 5)

        let (statusCode, _) = try await performRequestWithStatus(path: "/nonexistent")
        XCTAssertEqual(statusCode, 404)
    }

    func testWhenStaticRouteRegisteredThenHTMLIsReturned() async throws {
        server = DebugHTTPServer(port: 0)
        server.addStaticRoute("/page", htmlString: "<h1>Hello</h1>")

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        await fulfillment(of: [started], timeout: 5)

        let responseBody = try await performRequest(path: "/page")
        XCTAssertEqual(responseBody, "<h1>Hello</h1>")
    }

    func testWhenPOSTWithBodyThenHandlerReceivesBody() async throws {
        server = DebugHTTPServer(port: 0)

        server.addRoute("/echo", method: .POST) { request in
            .text(request.body.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        }

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        await fulfillment(of: [started], timeout: 5)

        let body = "test-body"
        let receivedBody = try await performRequest(path: "/echo", method: "POST", body: body)
        XCTAssertEqual(receivedBody, body)
    }

    func testWhenMultiplePrefixRoutesMatchThenMostSpecificRouteIsUsed() async throws {
        server = DebugHTTPServer(port: 0)
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
        await fulfillment(of: [started], timeout: 5)

        let responseBody = try await performRequest(path: "/api/chats/123")
        XCTAssertEqual(responseBody, "specific")
    }

    func testWhenHandlerThrowsThenReturns500() async throws {
        server = DebugHTTPServer(port: 0)
        server.addRoute("/fail", method: .GET) { _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "intentional"])
        }

        let started = expectation(description: "Server started")
        server.stateDidChange = { state in
            if case .running = state { started.fulfill() }
        }

        try server.start()
        await fulfillment(of: [started], timeout: 5)

        let (statusCode, _) = try await performRequestWithStatus(path: "/fail")
        XCTAssertEqual(statusCode, 500)
    }

    // MARK: - Helpers

    private func performRequest(
        path: String,
        method: String = "GET",
        body: String? = nil
    ) async throws -> String {
        let (_, responseBody) = try await performRequestWithStatus(path: path, method: method, body: body)
        return responseBody
    }

    private func performRequestWithStatus(
        path: String,
        method: String = "GET",
        body: String? = nil
    ) async throws -> (Int, String) {
        guard case .running(let port) = server.state else {
            throw URLError(.cannotConnectToHost)
        }
        let url = URL(string: "http://localhost:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body.data(using: .utf8)
        }

        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let responseBody = String(data: data, encoding: .utf8) ?? ""
        return (statusCode, responseBody)
    }
}

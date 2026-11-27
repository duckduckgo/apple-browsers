//
//  ChromeWebStoreUpdateCheckerTests.swift
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
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class ChromeWebStoreUpdateCheckerTests: XCTestCase {
    private let fixture = ChromeWebStoreUpdateManifestFixture()

    private func checker(configuration: URLSessionConfiguration = .ephemeral) -> ChromeWebStoreUpdateChecker {
        configuration.protocolClasses = [UpdateURLProtocol.self]
        return ChromeWebStoreUpdateChecker(configuration: configuration)
    }

    private func respond(_ xml: String, status: Int = 200, headers: [String: String] = [:]) {
        respond(data: Data(xml.utf8), status: status, headers: headers)
    }

    private func respond(data: Data, status: Int = 200, headers: [String: String] = [:]) {
        UpdateURLProtocol.setHandler { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status,
                                                       httpVersion: "HTTP/1.1", headerFields: headers))
            return (response, data)
        }
    }

    func testAvailableManifestMapsToUpdateResult() async {
        respond(fixture.manifest(fixture.offer()))
        let result = await checker().check(extensionID: fixture.extensionID, installedVersion: "2026.1.0")
        guard case .update(let update) = result.outcome else { return XCTFail("Expected update, got \(result)") }
        XCTAssertEqual(update.version, "2026.10.1")
        XCTAssertNil(result.retryNotBefore)
    }

    func testNoUpdateManifestMapsToNoUpdateResult() async {
        respond(fixture.manifest(#"<updatecheck status="noupdate"/>"#))
        let result = await checker().check(extensionID: fixture.extensionID, installedVersion: "2026.10.1")
        XCTAssertEqual(result.outcome, .noUpdate)
    }

    func testRequestUsesOnlyRequiredParametersAndNoCookies() async {
        let data = Data(fixture.manifest(#"<updatecheck status="noupdate"/>"#).utf8)
        let expectedID = fixture.extensionID
        UpdateURLProtocol.setHandler { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.scheme, "https")
            XCTAssertEqual(components.host, "clients2.google.com")
            XCTAssertEqual(components.path, "/service/update2/crx")
            XCTAssertEqual(Set(components.queryItems ?? []), Set([
                URLQueryItem(name: "response", value: "updatecheck"),
                ChromeWebStoreURL.prodversionQueryItem,
                URLQueryItem(name: "acceptformat", value: "crx3"),
                URLQueryItem(name: "x", value: "id=\(expectedID)&v=2026.1.0&uc")
            ]))
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Mozilla/5.0")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), "en-US")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                headerFields: ["Set-Cookie": "update=tracking"])), data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "Browser/1.2.3", "Accept-Language": "es-AR", "Authorization": "private"]
        let checker = checker(configuration: configuration)
        _ = await checker.check(extensionID: fixture.extensionID, installedVersion: "2026.1.0")
        _ = await checker.check(extensionID: fixture.extensionID, installedVersion: "2026.1.0")
    }

    func testVersionValidation() {
        for version in ["1", "1.0", "0.0.0.1", "4.10.0", "65535.65535.65535.65535"] {
            XCTAssertTrue(ChromeWebStoreUpdateChecker.isValidVersion(version), version)
        }
        for version in ["", "1..0", "1.0-beta", "-1", "65536", "1.2.3.4.5", "01.2", "0.0", "１.0", "1.", ".1"] {
            XCTAssertFalse(ChromeWebStoreUpdateChecker.isValidVersion(version), version)
        }
    }

    func testInvalidInputNeverMakesARequest() async {
        UpdateURLProtocol.setHandler { _ in
            XCTFail("Invalid input must not reach the network")
            throw URLError(.badURL)
        }
        let result = await checker().check(extensionID: "invalid", installedVersion: "1.0")
        XCTAssertEqual(result.outcome, .failure(.invalidRequest))
        let invalidVersion = await checker().check(extensionID: fixture.extensionID, installedVersion: "1.0-beta")
        XCTAssertEqual(invalidVersion.outcome, .failure(.invalidRequest))
    }

    func testVersionsAreComparedNumericallyAndDoNotDowngrade() async {
        for (version, expected) in [("4.10.0", true), ("4.9.3", false), ("4.9.3.0", false), ("4.8.0", false)] {
            respond(fixture.manifest(fixture.offer(version: version)))
            let result = await checker().check(extensionID: fixture.extensionID, installedVersion: "4.9.3")
            if expected {
                guard case .update = result.outcome else { return XCTFail("Expected newer version") }
            } else {
                XCTAssertEqual(result.outcome, .noUpdate)
            }
        }
    }

    func testOversizedResponseWithAndWithoutContentLengthIsRejected() async {
        let data = Data(repeating: 32, count: ChromeWebStoreUpdateChecker.maximumResponseSize + 1)
        for headers in [[:], ["Content-Length": String(data.count)]] {
            respond(data: data, headers: headers)
            let result = await checker().check(extensionID: fixture.extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, .failure(.responseTooLarge))
        }
    }

    func testRetryDeadlineIsRetainedOnSuccessAndFailures() async throws {
        for (status, xml, expected) in [
            (200, fixture.manifest(#"<updatecheck status="noupdate"/>"#), ChromeWebStoreUpdateChecker.Outcome.noUpdate),
            (200, fixture.manifest(#"<updatecheck status="ok" _malware="true"/>"#), .skipped),
            (503, "unavailable", .failure(.httpStatus(503))),
            (200, "invalid XML", .failure(.invalidManifest))
        ] {
            respond(xml, status: status, headers: ["X-Retry-After": "600"])
            let before = Date()
            let result = await checker().check(extensionID: fixture.extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, expected)
            let deadline = try XCTUnwrap(result.retryNotBefore)
            XCTAssertGreaterThanOrEqual(deadline.timeIntervalSince(before), 600)
            XCTAssertLessThanOrEqual(deadline.timeIntervalSinceNow, 600)
        }
    }

    func testRetryDeadlineParsesPositiveSecondsAndCapsLargeValues() throws {
        let url = try XCTUnwrap(URL(string: "https://clients2.google.com/service/update2/crx"))
        for (value, expectedSeconds) in [("600", 600.0), (" 600 ", 600.0), ("86401", 86400.0), (String(repeating: "9", count: 400), 86400.0)] {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["X-Retry-After": value]))
            let before = Date()
            let deadline = try XCTUnwrap(ChromeWebStoreUpdateChecker.retryDeadline(response: response))
            XCTAssertGreaterThanOrEqual(deadline.timeIntervalSince(before), expectedSeconds)
            XCTAssertLessThanOrEqual(deadline.timeIntervalSinceNow, expectedSeconds)
        }
    }

    func testMissingOrMalformedRetryHeadersAreIgnored() throws {
        let url = try XCTUnwrap(URL(string: "https://clients2.google.com/service/update2/crx"))
        for value: String? in [nil, "", "0", "-1", "nan", "1.5", "tomorrow"] {
            let headers = value.map { ["X-Retry-After": $0] }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: headers))
            XCTAssertNil(ChromeWebStoreUpdateChecker.retryDeadline(response: response), value ?? "Missing header")
        }
    }

    func testNetworkFailureAndCancellation() async {
        for (code, expected) in [(URLError.Code.notConnectedToInternet, ChromeWebStoreUpdateChecker.Failure.networkFailure),
                                 (.cancelled, .cancelled)] {
            UpdateURLProtocol.setHandler { _ in throw URLError(code) }
            let result = await checker().check(extensionID: fixture.extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, .failure(expected))
        }
        let checker = checker()
        let extensionID = fixture.extensionID
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await checker.check(extensionID: extensionID, installedVersion: "1.0")
        }
        let result = await task.value
        XCTAssertEqual(result.outcome, .failure(.cancelled))
    }

    func testAllowedRedirectProceeds() async {
        let data = Data(fixture.manifest(#"<updatecheck status="noupdate"/>"#).utf8)
        let redirected = expectation(description: "Allowed destination is requested")
        UpdateURLProtocol.setHandler { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "clients2.google.com" {
                return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                                    headerFields: ["Location": "https://clients2.googleusercontent.com/update.xml"])), Data())
            }
            redirected.fulfill()
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)), data)
        }
        let result = await checker().check(extensionID: fixture.extensionID, installedVersion: "1.0")
        XCTAssertEqual(result.outcome, .noUpdate)
        await fulfillment(of: [redirected], timeout: 5)
    }

    func testRedirectDelegateRejectsDisallowedDestinationsBeforeFollowing() throws {
        // URLProtocol does not complete the original response after a refused redirect. Exercise
        // the actual delegate callback directly, without waiting for the stub request to time out.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = try XCTUnwrap(URL(string: "https://clients2.google.com/service/update2/crx"))
        let response = try XCTUnwrap(HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil))
        let task = session.dataTask(with: original)
        let policy = ChromeWebStoreUpdateChecker.RedirectPolicy()
        for destination in ["https://evil.example/x", "http://clients2.google.com/x",
                            "https://user@clients2.google.com/x", "https://clients2.google.com:444/x"] {
            let request = URLRequest(url: try XCTUnwrap(URL(string: destination)))
            var completed = false
            policy.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { followed in
                completed = true
                XCTAssertNil(followed, "Must refuse redirect before sending a request to \(destination)")
            }
            XCTAssertTrue(completed, "Redirect policy must complete its decision")
        }
    }

    func testCancellingAnActiveRequestCancelsTransport() async {
        let started = expectation(description: "Request started")
        let stopped = expectation(description: "Transport cancelled")
        UpdateURLProtocol.setPendingHandler(started: { started.fulfill() }, stopped: { stopped.fulfill() })
        let checker = checker()
        let extensionID = fixture.extensionID
        let task = Task { await checker.check(extensionID: extensionID, installedVersion: "1.0") }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.outcome, .failure(.cancelled))
        await fulfillment(of: [stopped], timeout: 5)
    }
}

private final class UpdateURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var pendingStarted: (() -> Void)?
    private static var pendingStopped: (() -> Void)?
    private var stopped: (() -> Void)?

    static func setHandler(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        pendingStarted = nil
        pendingStopped = nil
    }

    static func setPendingHandler(started: @escaping () -> Void, stopped: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        pendingStarted = started
        pendingStopped = stopped
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        let started = Self.pendingStarted
        stopped = Self.pendingStopped
        Self.lock.unlock()
        if let started {
            started()
            return
        }
        do {
            let (response, data) = try XCTUnwrap(handler)(request)
            if let destination = response.value(forHTTPHeaderField: "Location"), let url = URL(string: destination) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: url), redirectResponse: response)
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { stopped?() }
}

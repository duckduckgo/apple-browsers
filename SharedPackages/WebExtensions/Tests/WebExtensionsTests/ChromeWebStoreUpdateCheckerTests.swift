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
    private let extensionID = "nngceckbapebfimnlniiiahkandclblb"
    private let packageHash = "d92953eac40d64f5b38e254d2196babb0bf0c5e81c1d9afaae4cd88a55bab42c"

    private func checker() -> ChromeWebStoreUpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        return ChromeWebStoreUpdateChecker(configuration: configuration)
    }

    private func manifest(_ update: String, appID: String? = nil, appStatus: String = "ok") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <gupdate xmlns="http://www.google.com/update2/response" protocol="2.0" server="prod">
          <daystart elapsed_days="7242" elapsed_seconds="22482"/>
          <app appid="\(appID ?? extensionID)" status="\(appStatus)">\(update)</app>
        </gupdate>
        """
    }

    private func offer(version: String = "2026.10.1") -> String {
        """
        <updatecheck _esbAllowlist="true" codebase="https://clients2.googleusercontent.com/crx/extension.crx"
          fp="1.\(packageHash)" hash_sha256="\(packageHash)" protected="0" size="26045122" status="ok" version="\(version)"/>
        """
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

    func testAvailableUpdateFromRealResponseShape() async throws {
        respond(manifest(offer()))
        let result = await checker().check(extensionID: extensionID, installedVersion: "2026.1.0")
        guard case .update(let update) = result.outcome else { return XCTFail("Expected update, got \(result)") }
        XCTAssertEqual(update.extensionID, extensionID)
        XCTAssertEqual(update.version, "2026.10.1")
        XCTAssertEqual(update.size, 26045122)
        XCTAssertEqual(update.sha256, packageHash)
        XCTAssertEqual(update.downloadURL.absoluteString, "https://clients2.googleusercontent.com/crx/extension.crx")
        XCTAssertNil(result.retryNotBefore)
    }

    func testNoUpdateFromRealResponseShape() async {
        respond(manifest(#"<updatecheck status="noupdate"/>"#))
        let result = await checker().check(extensionID: extensionID, installedVersion: "2026.10.1")
        XCTAssertEqual(result.outcome, .noUpdate)
    }

    func testRequestUsesOnlyRequiredParametersAndNoCookies() async {
        let data = Data(manifest(#"<updatecheck status="noupdate"/>"#).utf8)
        let expectedID = extensionID
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
                URLQueryItem(name: "x", value: "id=\(expectedID)&v=2026.1.0&installsource=ondemand&uc")
            ]))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                headerFields: ["Set-Cookie": "update=tracking"])), data)
        }
        let checker = checker()
        _ = await checker.check(extensionID: extensionID, installedVersion: "2026.1.0")
        _ = await checker.check(extensionID: extensionID, installedVersion: "2026.1.0")
    }

    func testInvalidInputNeverMakesARequest() async {
        UpdateURLProtocol.setHandler { _ in
            XCTFail("Invalid input must not reach the network")
            throw URLError(.badURL)
        }
        let result = await checker().check(extensionID: "invalid", installedVersion: "1.0")
        XCTAssertEqual(result.outcome, .failure(.invalidRequest))
        for version in ["", "1..0", "1.0-beta", "-1", "65536", "1.2.3.4.5", "01.2", "0.0", "１.0"] {
            let result = await checker().check(extensionID: extensionID, installedVersion: version)
            XCTAssertEqual(result.outcome, .failure(.invalidRequest), version)
        }
    }

    func testVersionsAreComparedNumericallyAndDoNotDowngrade() async {
        for (version, expected) in [("4.10.0", true), ("4.9.3", false), ("4.9.3.0", false), ("4.8.0", false)] {
            respond(manifest(offer(version: version)))
            let result = await checker().check(extensionID: extensionID, installedVersion: "4.9.3")
            if expected {
                guard case .update = result.outcome else { return XCTFail("Expected newer version") }
            } else {
                XCTAssertEqual(result.outcome, .noUpdate)
            }
        }
    }

    func testInvalidOfferMetadataIsRejected() async {
        let valid = offer()
        let replacements = [
            ("version=\"2026.10.1\"", "version=\"1.0-beta\""),
            ("version=\"2026.10.1\"", "version=\"65536\""),
            ("version=\"2026.10.1\"", ""),
            ("size=\"26045122\"", "size=\"0\""),
            ("size=\"26045122\"", "size=\"-1\""),
            ("size=\"26045122\"", "size=\"99999999999999999999999\""),
            ("size=\"26045122\"", ""),
            ("hash_sha256=\"\(packageHash)\"", "hash_sha256=\"bad\""),
            ("hash_sha256=\"\(packageHash)\"", ""),
            ("status=\"ok\"", "status=\"error\""),
            ("status=\"ok\"", "")
        ]
        for (old, new) in replacements {
            respond(manifest(valid.replacingOccurrences(of: old, with: new)))
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, .failure(.invalidManifest), new)
        }
    }

    func testDisallowedPackageURLsAreRejected() async {
        for url in ["http://clients2.googleusercontent.com/x", "https://evil.example/x",
                    "https://clients2.googleusercontent.com.evil.example/x", "https://user@clients2.googleusercontent.com/x",
                    "https://clients2.googleusercontent.com:444/x", "https://clients2.googleusercontent.com/x#fragment"] {
            respond(manifest(offer().replacingOccurrences(of: "https://clients2.googleusercontent.com/crx/extension.crx", with: url)))
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, .failure(.invalidManifest), url)
        }
    }

    func testWrongOrAmbiguousApplicationAndStatusAreRejected() async {
        let app = "<app appid=\"\(extensionID)\" status=\"ok\">\(offer())</app>"
        let invalid = [
            manifest(offer(), appID: String(repeating: "a", count: 32)),
            manifest(offer(), appStatus: "error-unknownApplication"),
            manifest(offer() + offer()),
            manifest(offer()).replacingOccurrences(of: "</gupdate>", with: app + "</gupdate>"),
            manifest(offer()).replacingOccurrences(of: "protocol=\"2.0\"", with: "protocol=\"3.0\""),
            manifest(offer()).replacingOccurrences(of: "http://www.google.com/update2/response", with: "https://evil.example"),
            manifest(offer()).replacingOccurrences(of: "</gupdate>", with: ""),
            "<gupdate/>", "", "not XML"
        ]
        for xml in invalid {
            respond(xml)
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, .failure(.invalidManifest), xml)
        }
    }

    func testDTDsAndNonUTF8EncodingsAreRejected() async {
        let body = manifest(offer())
        let declaration = #"<?xml version="1.0" encoding="UTF-8"?>"#
        let dtds = [
            "<!DOCTYPE gupdate>",
            #"<!DOCTYPE gupdate SYSTEM "https://evil.example/external.dtd">"#,
            #"<!DOCTYPE gupdate [<!ENTITY example "expanded">]>"#,
            #"<!DOCTYPE gupdate [<!ENTITY example SYSTEM "file:///etc/passwd">]>"#
        ]
        for dtd in dtds {
            respond(body.replacingOccurrences(of: declaration, with: declaration + dtd))
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, .failure(.invalidManifest))
        }
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            respond(data: body.data(using: encoding) ?? Data())
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, .failure(.invalidManifest))
        }
        respond(body.replacingOccurrences(of: "UTF-8", with: "ISO-8859-1"))
        let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
        XCTAssertEqual(result.outcome, .failure(.invalidManifest))
    }

    func testUTF8BOMAndNamespacePrefixesAreAccepted() async {
        let xml = manifest(offer()).replacingOccurrences(of: "xmlns=", with: "xmlns:g=")
            .replacingOccurrences(of: "<gupdate", with: "<g:gupdate")
            .replacingOccurrences(of: "</gupdate", with: "</g:gupdate")
            .replacingOccurrences(of: "<daystart", with: "<g:daystart")
            .replacingOccurrences(of: "<app", with: "<g:app")
            .replacingOccurrences(of: "</app", with: "</g:app")
            .replacingOccurrences(of: "<updatecheck", with: "<g:updatecheck")
        respond("\u{FEFF}" + xml)
        let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
        guard case .update = result.outcome else { return XCTFail("Expected update, got \(result)") }
    }

    func testOversizedResponseWithAndWithoutContentLengthIsRejected() async {
        let data = Data(repeating: 32, count: ChromeWebStoreUpdateChecker.maximumResponseSize + 1)
        for headers in [[:], ["Content-Length": String(data.count)]] {
            respond(data: data, headers: headers)
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, .failure(.responseTooLarge))
        }
    }

    func testRetryDeadlineIsRetainedOnSuccessAndFailures() async throws {
        for (status, xml, expected) in [
            (200, manifest(#"<updatecheck status="noupdate"/>"#), ChromeWebStoreUpdateChecker.Outcome.noUpdate),
            (503, "unavailable", .failure(.httpStatus(503))),
            (200, "invalid XML", .failure(.invalidManifest))
        ] {
            respond(xml, status: status, headers: ["X-Retry-After": "600"])
            let before = Date()
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, expected)
            let deadline = try XCTUnwrap(result.retryNotBefore)
            XCTAssertGreaterThanOrEqual(deadline.timeIntervalSince(before), 600)
            XCTAssertLessThanOrEqual(deadline.timeIntervalSinceNow, 600)
        }
    }

    func testRetryDeadlineIsCappedAndMalformedValuesAreIgnored() async throws {
        for value in ["86401", String(repeating: "9", count: 400)] {
            respond("", status: 429, headers: ["X-Retry-After": value])
            let before = Date()
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            let deadline = try XCTUnwrap(result.retryNotBefore)
            XCTAssertGreaterThanOrEqual(deadline.timeIntervalSince(before), 86400)
            XCTAssertLessThanOrEqual(deadline.timeIntervalSinceNow, 86400)
        }
        for value in ["", "0", "-1", "nan", "1.5", "tomorrow"] {
            respond("", status: 503, headers: ["X-Retry-After": value])
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            XCTAssertNil(result.retryNotBefore, value)
        }
    }

    func testNetworkFailureAndCancellation() async {
        for (code, expected) in [(URLError.Code.notConnectedToInternet, ChromeWebStoreUpdateChecker.Failure.networkFailure),
                                 (.cancelled, .cancelled)] {
            UpdateURLProtocol.setHandler { _ in throw URLError(code) }
            let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
            XCTAssertEqual(result.outcome, .failure(expected))
        }
        let checker = checker()
        let extensionID = extensionID
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await checker.check(extensionID: extensionID, installedVersion: "1.0")
        }
        let result = await task.value
        XCTAssertEqual(result.outcome, .failure(.cancelled))
    }

    func testAllowedRedirectProceeds() async {
        let data = Data(manifest(#"<updatecheck status="noupdate"/>"#).utf8)
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
        let result = await checker().check(extensionID: extensionID, installedVersion: "1.0")
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
        let extensionID = extensionID
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

//
//  ChromeWebStoreUserScriptTests.swift
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

import WebExtensions
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class ChromeWebStoreUserScriptTests: XCTestCase {
    private let identifier = String(repeating: "a", count: 32)
    private var service: ChromeWebStoreServiceMock!

    override func setUp() async throws {
        try await super.setUp()
        service = ChromeWebStoreServiceMock()
    }

    override func tearDown() async throws {
        service = nil
        try await super.tearDown()
    }

    func testContractAndUnknownMethods() {
        let subfeature = ChromeWebStoreUserScript(serviceProvider: { self.service })
        XCTAssertEqual(subfeature.featureName, "chromeWebstorePatching")
        for method in ["getExtensionStatus", "installExtension", "removeExtension"] {
            XCTAssertNotNil(subfeature.handler(forMethodNamed: method))
        }
        XCTAssertNil(subfeature.handler(forMethodNamed: "unknown"))
    }

    func testStatusResponseAndUnavailableService() async throws {
        for status in [ChromeWebStoreStatus.installable, .installed, .unsupported, .unknown] {
            service.currentStatus = status
            let response = try await request("getExtensionStatus")
            XCTAssertEqual(response["status"] as? String, status.rawValue)
        }
        let subfeature = ChromeWebStoreUserScript(serviceProvider: { nil })
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: "getExtensionStatus"))
        let result = try await handler(["extensionId": identifier], message())
        let response = try dictionary(result)
        XCTAssertEqual(response["status"] as? String, "unknown")
    }

    func testInstallAndRemovalReturnFinalResult() async throws {
        for success in [true, false] {
            service.success = success
            let installed = try await request("installExtension", extra: ["crxUrl": ChromeWebStoreURL.downloadURL(for: identifier).absoluteString])
            XCTAssertEqual(installed["success"] as? Bool, success)
            XCTAssertEqual(service.installedIdentifier, identifier)
            let removed = try await request("removeExtension")
            XCTAssertEqual(removed["success"] as? Bool, success)
            XCTAssertEqual(service.removedIdentifier, identifier)
        }
    }

    func testUntrustedOriginsSubframesAndStalePagesCannotReachService() async throws {
        let messages = [
            message(origin: "http://chromewebstore.google.com/"),
            message(origin: "https://chromewebstore.google.com.evil.example/"),
            message(origin: "https://chromewebstore.google.com:8443/"),
            message(isMain: false),
            message(page: "https://evil.example/")
        ]
        for message in messages {
            do {
                _ = try await request("getExtensionStatus", message: message)
                XCTFail("Untrusted message accepted")
            } catch ChromeWebStoreError.invalidRequest {}
        }
        XCTAssertEqual(service.statusRequests, 0)
    }

    func testInvalidIDsAndDownloadURLsCannotReachService() async throws {
        for extra in [["extensionId": "invalid"], ["crxUrl": "https://evil.example/extension.crx"]] {
            do {
                _ = try await request("installExtension", extra: extra)
                XCTFail("Invalid request accepted")
            } catch ChromeWebStoreError.invalidRequest {}
        }
        XCTAssertNil(service.installedIdentifier)
    }

    private func request(_ method: String, extra: [String: String] = [:], message: WKScriptMessage? = nil) async throws -> [String: Any] {
        let subfeature = ChromeWebStoreUserScript(serviceProvider: { self.service })
        let handler = try XCTUnwrap(subfeature.handler(forMethodNamed: method))
        var params = ["extensionId": identifier]
        params.merge(extra) { _, new in new }
        return try dictionary(await handler(params, message ?? self.message()))
    }

    private func dictionary(_ response: Encodable?) throws -> [String: Any] {
        let response = try XCTUnwrap(response)
        let data = try JSONEncoder().encode(response)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func message(origin: String = "https://chromewebstore.google.com/",
                         page: String = "https://chromewebstore.google.com/",
                         isMain: Bool = true) -> WKScriptMessage {
        let webView = StoreURLWebView()
        webView.currentURL = URL(string: page)
        let origin = URL(string: origin)!
        return StoreScriptMessage(view: webView, frame: .mock(for: webView, isMain: isMain,
                                                           securityOrigin: WKSecurityOriginMock.new(url: origin),
                                                           request: URLRequest(url: origin)))
    }
}

@available(macOS 15.4, *)
@MainActor
private final class ChromeWebStoreServiceMock: ChromeWebStoreManaging {
    var currentStatus = ChromeWebStoreStatus.installable
    var success = true
    var statusRequests = 0
    var installedIdentifier: String?
    var removedIdentifier: String?
    func status(for identifier: String) -> ChromeWebStoreStatus {
        statusRequests += 1
        return currentStatus
    }
    func install(identifier: String, downloadURL: URL) async -> Bool {
        installedIdentifier = identifier
        return success
    }
    func remove(identifier: String) async -> Bool {
        removedIdentifier = identifier
        return success
    }
}

private final class StoreURLWebView: WKWebView {
    var currentURL: URL?
    override var url: URL? { currentURL }
}

private final class StoreScriptMessage: WKScriptMessage {
    private let view: WKWebView
    private let frame: WKFrameInfo
    override var webView: WKWebView? { view }
    override var frameInfo: WKFrameInfo { frame }

    init(view: WKWebView, frame: WKFrameInfo) {
        self.view = view
        self.frame = frame
        super.init()
    }
}

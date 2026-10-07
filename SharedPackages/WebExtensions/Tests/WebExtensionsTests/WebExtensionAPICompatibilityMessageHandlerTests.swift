//
//  WebExtensionAPICompatibilityMessageHandlerTests.swift
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
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionAPICompatibilityMessageHandlerTests: XCTestCase {

    private var lines: [String] = []
    private var handler: WebExtensionAPICompatibilityMessageHandler!
    private var resolvedURLs: [URL] = []

    override func setUp() {
        super.setUp()
        lines = []
        resolvedURLs = []
        handler = WebExtensionAPICompatibilityMessageHandler(reporter: WebExtensionAPICompatibilityReporter { [unowned self] in
            lines.append($0)
        })
        handler.resolveExtension = { [unowned self] url in
            resolvedURLs.append(url)
            return url.host == "loaded" ? ("Bitwarden", "2025.1.0") : nil
        }
    }

    override func tearDown() {
        handler = nil
        super.tearDown()
    }

    // MARK: - Origin Gate

    func testWhenTheFrameIsAWebsite_ThenTheReportIsDropped() {
        handler.handle(body: stubbedReport, originProtocol: "https", originHost: "loaded")

        XCTAssertEqual(lines, [])
        XCTAssertEqual(resolvedURLs, [])
    }

    func testWhenTheFrameIsAnExtensionThatIsNotLoaded_ThenTheReportIsDropped() {
        handler.handle(body: stubbedReport, originProtocol: "webkit-extension", originHost: "other")

        XCTAssertEqual(lines, [])
    }

    func testWhenTheFrameHasNoHost_ThenTheReportIsDropped() {
        handler.handle(body: stubbedReport, originProtocol: "webkit-extension", originHost: "")

        XCTAssertEqual(lines, [])
    }

    func testWhenTheFrameIsALoadedExtension_ThenTheReportIsLogged() {
        handler.handle(body: stubbedReport, originProtocol: "webkit-extension", originHost: "loaded")

        XCTAssertEqual(lines, ["stubbed chrome.notifications.create ext=Bitwarden v=2025.1.0"])
        XCTAssertEqual(resolvedURLs, [URL(string: "webkit-extension://loaded/")])
    }

    func testWhenTheHostDiffersOnlyInCase_ThenTheExtensionIsStillFound() throws {
        let baseURL = try XCTUnwrap(URL(string: "webkit-extension://ABC-123/"))

        XCTAssertTrue(WebExtensionManager.url(try XCTUnwrap(URL(string: "webkit-extension://abc-123/")), isWithin: baseURL))
        XCTAssertTrue(WebExtensionManager.url(try XCTUnwrap(URL(string: "webkit-extension://ABC-123/page.html")), isWithin: baseURL))
        XCTAssertFalse(WebExtensionManager.url(try XCTUnwrap(URL(string: "webkit-extension://other/")), isWithin: baseURL))
    }

    // MARK: - Reports

    func testWhenAnErrorIsReported_ThenOnlyItsClassificationIsLogged() {
        let body: [String: Any] = ["kind": "error",
                                   "message": "undefined is not an object (evaluating 'chrome.tts.speak') https://example.com/?token=1"]

        handler.handle(body: body, originProtocol: "webkit-extension", originHost: "loaded")

        XCTAssertEqual(lines, ["missing chrome.tts ext=Bitwarden v=2025.1.0"])
    }

    func testWhenAnErrorIsUnrelatedToAnAPI_ThenNothingIsLogged() {
        handler.handle(body: ["kind": "error", "message": "Failed to fetch https://example.com/secret"],
                       originProtocol: "webkit-extension", originHost: "loaded")

        XCTAssertEqual(lines, [])
    }

    func testWhenAPageClaimsInvalidArgsDirectly_ThenItIsDropped() {
        handler.handle(body: ["kind": "invalidArgs", "api": "tabs.query"],
                       originProtocol: "webkit-extension", originHost: "loaded")

        XCTAssertEqual(lines, [])
    }

    func testWhenTheBodyIsNotAReport_ThenItIsDropped() {
        for body: Any in ["text", 1, ["kind": 1], ["kind": "stubbed"], ["kind": "unknown", "api": "a.b"], ["kind": "stubbed", "api": "https://x.y"]] {
            handler.handle(body: body, originProtocol: "webkit-extension", originHost: "loaded")
        }

        XCTAssertEqual(lines, [])
    }

    func testWhenTheSameIssueIsReportedAgain_ThenItIsLoggedOnce() {
        handler.handle(body: stubbedReport, originProtocol: "webkit-extension", originHost: "loaded")
        handler.handle(body: stubbedReport, originProtocol: "webkit-extension", originHost: "loaded")
        handler.handle(body: ["kind": "stubbed", "api": "notifications.clear"], originProtocol: "webkit-extension", originHost: "loaded")

        XCTAssertEqual(lines, ["stubbed chrome.notifications.create ext=Bitwarden v=2025.1.0",
                               "stubbed chrome.notifications.clear ext=Bitwarden v=2025.1.0"])
    }

    private var stubbedReport: [String: Any] {
        ["kind": "stubbed", "api": "notifications.create"]
    }
}

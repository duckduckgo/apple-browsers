//
//  UserScriptMessageDuckAITests.swift
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

import BrowserServicesKitTestsUtils
import UserScript
import WebKit
import XCTest
@testable import AIChat

@MainActor
final class UserScriptMessageDuckAITests: XCTestCase {

    func testHTTPSDuckAIMainFrameIsAccepted() {
        XCTAssertTrue(message(origin: "https://duck.ai").isFromDuckAIMainFrame())
    }

    func testHostIsComparedCaseInsensitively() {
        XCTAssertTrue(message(origin: "https://DUCK.AI").isFromDuckAIMainFrame())
    }

    func testDuckDuckGoOriginIsRejected() {
        XCTAssertFalse(message(origin: "https://duckduckgo.com").isFromDuckAIMainFrame())
    }

    func testDuckAISubdomainIsRejected() {
        XCTAssertFalse(message(origin: "https://chat.duck.ai").isFromDuckAIMainFrame())
    }

    func testHTTPDuckAIIsRejected() {
        XCTAssertFalse(message(origin: "http://duck.ai").isFromDuckAIMainFrame())
    }

    func testSubframeIsRejected() {
        XCTAssertFalse(message(origin: "https://duck.ai", isMainFrame: false).isFromDuckAIMainFrame())
    }

    func testDebugHostnameIsAcceptedOverHTTP() {
        XCTAssertTrue(message(origin: "http://localhost:3000").isFromDuckAIMainFrame(customHostname: "localhost"))
    }

    func testDebugHostnameDoesNotRelaxProductionHosts() {
        XCTAssertFalse(message(origin: "http://duck.ai").isFromDuckAIMainFrame(customHostname: "localhost"))
        XCTAssertFalse(message(origin: "https://duckduckgo.com").isFromDuckAIMainFrame(customHostname: "localhost"))
    }

    func testDebugHostnameSubframeIsRejected() {
        XCTAssertFalse(message(origin: "http://localhost:3000", isMainFrame: false).isFromDuckAIMainFrame(customHostname: "localhost"))
    }

    func testMessageWithoutFrameInfoIsRejected() {
        XCTAssertFalse(FramelessMessage().isFromDuckAIMainFrame())
    }

    private func message(origin: String, isMainFrame: Bool = true) -> WKScriptMessage {
        let securityOrigin = MockWKSecurityOrigin.new(url: URL(string: origin)!)
        let frameInfo = WKFrameInfo.mock(isMainFrame: isMainFrame, securityOrigin: securityOrigin)
        return WKScriptMessage.mock(webView: nil, frameInfo: frameInfo)
    }
}

/// A message that isn't a `WKScriptMessage`, so it carries no frame security origin.
private struct FramelessMessage: UserScriptMessage {
    var messageName = ""
    var messageBody: Any = [:]
    var messageHost = "duck.ai"
    var isMainFrame = true
    var messageWebView: WKWebView?
}

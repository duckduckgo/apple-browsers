//
//  UserScriptBlankSubframeTests.swift
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

import WebKit
import XCTest
import UserScript

@MainActor
final class UserScriptBlankSubframeTests: XCTestCase {

    private static let pageHTML = """
    <html><body>
    <iframe></iframe>
    <iframe srcdoc="<p>content</p>"></iframe>
    </body></html>
    """

    private final class FrameProbeScript: NSObject, UserScript {
        let source = "window.webkit.messageHandlers.frameProbe.postMessage(window.location.href);"
        let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
        let forMainFrameOnly = false
        let messageNames: [String] = []

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
    }

    private final class FrameRecorder: NSObject, WKScriptMessageHandler {
        var hrefs: [String] = []

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let href = message.body as? String else { return }
            hrefs.append(href)
        }
    }

    private var webView: WKWebView?

    override func tearDown() {
        webView = nil
        super.tearDown()
    }

    func testWhenSkippingBlankSubframesThenScriptDoesNotRunInAboutBlankSubframe() async throws {
        let hrefs = try await loadPage(skippingBlankSubframes: true, expectedFrameCount: 2)

        XCTAssertEqual(Set(hrefs), ["https://example.com/", "about:srcdoc"])
    }

    func testWhenNotSkippingBlankSubframesThenScriptRunsInEveryFrame() async throws {
        let hrefs = try await loadPage(skippingBlankSubframes: false, expectedFrameCount: 3)

        XCTAssertEqual(Set(hrefs), ["https://example.com/", "about:blank", "about:srcdoc"])
    }

    private func loadPage(skippingBlankSubframes: Bool, expectedFrameCount: Int) async throws -> [String] {
        let recorder = FrameRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, contentWorld: .defaultClient, name: "frameProbe")
        let userScript = await FrameProbeScript().makeWKUserScript(skippingBlankSubframes: skippingBlankSubframes)
        configuration.userContentController.addUserScript(userScript.wkUserScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.loadHTMLString(Self.pageHTML, baseURL: URL(string: "https://example.com/"))

        let deadline = Date().addingTimeInterval(5)
        while recorder.hrefs.count < expectedFrameCount && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        // Give any unexpected extra frame a chance to report before asserting.
        try await Task.sleep(nanoseconds: 300_000_000)
        return recorder.hrefs
    }
}

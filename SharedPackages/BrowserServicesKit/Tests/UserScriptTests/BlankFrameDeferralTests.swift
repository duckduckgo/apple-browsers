//
//  BlankFrameDeferralTests.swift
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
import WebKit
import XCTest
import UserScript

final class BlankFrameDeferralTests: XCTestCase {

    /// Counts its runs in `window.__runs` and protects `navigator.hardwareConcurrency` (37), like Content Scope Scripts
    final class CountingUserScript: NSObject, UserScript {
        let source = """
        window.__runs = (window.__runs || 0) + 1;
        Object.defineProperty(Navigator.prototype, 'hardwareConcurrency', { get: () => 37, configurable: true });
        """
        let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
        let forMainFrameOnly = false
        let requiresRunInPageContentWorld = true
        let messageNames: [String] = []
        let blankFrameStart: BlankFrameStart

        init(blankFrameStart: BlankFrameStart) {
            self.blankFrameStart = blankFrameStart
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
    }

    @MainActor
    func testWhenStartingImmediatelyThenTheWrapperIsUnchanged() async {
        let script = await CountingUserScript(blankFrameStart: .immediately).makeWKUserScript().wkUserScript

        XCTAssertFalse(script.source.contains("isBlankSubframe"))
        XCTAssertTrue(script.source.contains("window.__runs = (window.__runs || 0) + 1;"))
    }

    @MainActor
    func testWhenDeferringThenTheWrapperHoldsTheSourceOnce() async {
        for start in [BlankFrameStart.onProtectedAPIAccess, .onContent, .onFormField] {
            let script = await CountingUserScript(blankFrameStart: start).makeWKUserScript().wkUserScript

            XCTAssertTrue(script.source.contains("isBlankSubframe"), "\(start)")
            XCTAssertEqual(script.source.components(separatedBy: "window.__runs = (window.__runs || 0) + 1;").count, 2, "\(start)")
        }
    }

#if os(macOS)

    @MainActor
    func testWhenStartingOnProtectedAPIAccessThenABlankFrameRunsTheScriptOnTheFirstReadAndGetsTheProtectedValue() async throws {
        let webView = try await loadPage(with: .onProtectedAPIAccess)

        let result = try await evaluate(in: webView, """
            const frame = document.createElement('iframe');
            document.body.appendChild(frame);
            const runsBefore = frame.contentWindow.__runs ?? 0;
            const value = frame.contentWindow.navigator.hardwareConcurrency;
            return { main: window.__runs, runsBefore, value, runsAfter: frame.contentWindow.__runs ?? 0 };
            """)

        XCTAssertEqual(result["main"] as? Int, 1)
        XCTAssertEqual(result["runsBefore"] as? Int, 0)
        XCTAssertEqual(result["value"] as? Int, 37)
        XCTAssertEqual(result["runsAfter"] as? Int, 1)
    }

    @MainActor
    func testWhenStartingOnProtectedAPIAccessThenWrittenContentRunsAfterTheScript() async throws {
        let webView = try await loadPage(with: .onProtectedAPIAccess)

        let result = try await evaluate(in: webView, """
            const frame = document.createElement('iframe');
            document.body.appendChild(frame);
            frame.contentDocument.open();
            frame.contentDocument.write('<script>parent.__writtenValue = navigator.hardwareConcurrency<\\/script>');
            frame.contentDocument.close();
            return { value: window.__writtenValue };
            """)

        XCTAssertEqual(result["value"] as? Int, 37)
    }

    @MainActor
    func testWhenStartingOnProtectedAPIAccessThenAnUntouchedBlankFrameNeverRunsTheScript() async throws {
        let webView = try await loadPage(with: .onProtectedAPIAccess)

        let result = try await evaluate(in: webView, """
            const frame = document.createElement('iframe');
            document.body.appendChild(frame);
            frame.contentDocument.body.appendChild(frame.contentDocument.createElement('div'));
            await new Promise((resolve) => setTimeout(resolve, 50));
            return { runs: frame.contentWindow.__runs ?? 0 };
            """)

        XCTAssertEqual(result["runs"] as? Int, 0)
    }

    @MainActor
    func testWhenStartingOnContentThenABlankFrameRunsTheScriptOnceItHasContent() async throws {
        let webView = try await loadPage(with: .onContent)

        let result = try await evaluate(in: webView, """
            const frame = document.createElement('iframe');
            document.body.appendChild(frame);
            const runsBefore = frame.contentWindow.__runs ?? 0;
            frame.contentDocument.body.appendChild(frame.contentDocument.createElement('div'));
            await new Promise((resolve) => setTimeout(resolve, 0));
            return { runsBefore, runsAfter: frame.contentWindow.__runs ?? 0 };
            """)

        XCTAssertEqual(result["runsBefore"] as? Int, 0)
        XCTAssertEqual(result["runsAfter"] as? Int, 1)
    }

    @MainActor
    func testWhenStartingOnFormFieldThenABlankFrameRunsTheScriptOnlyOnceItHasAField() async throws {
        let webView = try await loadPage(with: .onFormField)

        let result = try await evaluate(in: webView, """
            const frame = document.createElement('iframe');
            document.body.appendChild(frame);
            const doc = frame.contentDocument;
            doc.body.appendChild(doc.createElement('div'));
            await new Promise((resolve) => setTimeout(resolve, 0));
            const runsWithContent = frame.contentWindow.__runs ?? 0;
            doc.body.appendChild(doc.createElement('input'));
            await new Promise((resolve) => setTimeout(resolve, 0));
            return { runsWithContent, runsWithField: frame.contentWindow.__runs ?? 0 };
            """)

        XCTAssertEqual(result["runsWithContent"] as? Int, 0)
        XCTAssertEqual(result["runsWithField"] as? Int, 1)
    }

    @MainActor
    func testWhenDeferringThenAFrameWithSrcdocRunsTheScriptImmediately() async throws {
        let webView = try await loadPage(with: .onProtectedAPIAccess)

        let result = try await evaluate(in: webView, """
            const frame = document.createElement('iframe');
            frame.srcdoc = '<p>content</p>';
            await new Promise((resolve) => { frame.onload = resolve; document.body.appendChild(frame); });
            return { runs: frame.contentWindow.__runs ?? 0 };
            """)

        XCTAssertEqual(result["runs"] as? Int, 1)
    }

    @MainActor
    func testWhenStartingImmediatelyThenABlankFrameRunsTheScriptWhenCreated() async throws {
        let webView = try await loadPage(with: .immediately)

        let result = try await evaluate(in: webView, """
            const frame = document.createElement('iframe');
            document.body.appendChild(frame);
            return { runs: frame.contentWindow.__runs ?? 0 };
            """)

        XCTAssertEqual(result["runs"] as? Int, 1)
    }

    // MARK: - Helpers

    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        var onFinish: ((Error?) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish?(nil)
            onFinish = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFinish?(error)
            onFinish = nil
        }
    }

    private var navigationDelegate: NavigationDelegate?

    @MainActor
    private func loadPage(with start: BlankFrameStart) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(CountingUserScript(blankFrameStart: start).makeWKUserScriptSync())
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let delegate = NavigationDelegate()
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.onFinish = { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            webView.loadHTMLString("<!DOCTYPE html><body></body>", baseURL: URL(string: "https://example.com/"))
        }
        return webView
    }

    @MainActor
    private func evaluate(in webView: WKWebView, _ body: String) async throws -> [String: Any] {
        let result = try await webView.callAsyncJavaScript(body, arguments: [:], contentWorld: .page)
        return try XCTUnwrap(result as? [String: Any])
    }

#endif
}

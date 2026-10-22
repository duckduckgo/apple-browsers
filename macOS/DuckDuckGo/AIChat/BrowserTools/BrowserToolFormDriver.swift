//
//  BrowserToolFormDriver.swift
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

import AIChat
import Foundation
import WebKit

/// Reads and changes a page's forms, behind a seam so the form tools are testable without a web view.
@MainActor
protocol BrowserToolFormDriving: AnyObject {
    func page(in webView: WKWebView) async -> BrowserToolRawPage?
    func apply(_ actions: [BrowserToolFillAction], in webView: WKWebView) async -> [BrowserToolFillReadback]?
    func click(_ ref: String, in webView: WKWebView) async -> Bool
    /// Scrolls the element into view and gives it focus. False when it is gone or cannot take focus.
    func focus(_ ref: String, in webView: WKWebView) async -> Bool
    func submit(formRef: String, submitterRef: String?, in webView: WKWebView) async -> Bool
    func millisecondsSinceLastChange(in webView: WKWebView) async -> Int?
}

/// Runs `BrowserToolForms.js` in Duck.ai's own content world. The page's scripts never see it, so
/// they cannot read or rewrite the refs, while the DOM and its events are shared as usual.
@MainActor
final class WebViewFormDriver: BrowserToolFormDriving {

    static let contentWorld = WKContentWorld.world(name: "DuckAIBrowserTools")

    /// Run before every call; it sets itself up once per document and is a no-op after that.
    private static let library: String = {
        guard let url = Bundle.main.url(forResource: "BrowserToolForms", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("BrowserToolForms.js is missing from the app bundle")
            return ""
        }
        return source
    }()

    func page(in webView: WKWebView) async -> BrowserToolRawPage? {
        await call("__duckAIForms.page()", in: webView).flatMap(BrowserToolRawPage.init)
    }

    func apply(_ actions: [BrowserToolFillAction], in webView: WKWebView) async -> [BrowserToolFillReadback]? {
        guard let result = await call("__duckAIForms.apply(actions)", arguments: ["actions": actions.map(\.bridgeValue)], in: webView),
              let data = try? JSONEncoder().encode(result) else { return nil }
        return try? JSONDecoder().decode([BrowserToolFillReadback].self, from: data)
    }

    func click(_ ref: String, in webView: WKWebView) async -> Bool {
        await call("__duckAIForms.click(ref)", arguments: ["ref": ref], in: webView)?.boolValue ?? false
    }

    func focus(_ ref: String, in webView: WKWebView) async -> Bool {
        await call("__duckAIForms.focus(ref)", arguments: ["ref": ref], in: webView)?.boolValue ?? false
    }

    func submit(formRef: String, submitterRef: String?, in webView: WKWebView) async -> Bool {
        let arguments: [String: Any] = ["formRef": formRef, "submitterRef": submitterRef ?? NSNull()]
        return await call("__duckAIForms.submit(formRef, submitterRef)", arguments: arguments, in: webView)?.boolValue ?? false
    }

    func millisecondsSinceLastChange(in webView: WKWebView) async -> Int? {
        await call("__duckAIForms.millisecondsSinceLastChange()", in: webView)?.intValue
    }

    /// Nil when the script cannot run, for example while a navigation replaces the document.
    private func call(_ expression: String, arguments: [String: Any] = [:], in webView: WKWebView) async -> JSONValue? {
        guard !Self.library.isEmpty,
              let result = try? await webView.callAsyncJavaScript(Self.library + "\nreturn " + expression + ";",
                                                                  arguments: arguments,
                                                                  in: nil,
                                                                  contentWorld: Self.contentWorld) else {
            return nil
        }
        return JSONValue(bridgeValue: result)
    }
}

/// Waits for a page to react to a click or a submit, behind a seam so the tools are testable.
@MainActor
protocol BrowserToolPageSettling: AnyObject {

    /// Returns whether the page navigated away from `startURL`. Throws `CancellationError` when
    /// the calling task is cancelled.
    func settle(_ tab: Tab, from startURL: URL?, quietPeriod: TimeInterval, timeout: TimeInterval) async throws -> Bool
}

/// Settled means a navigation finished, or the DOM has been quiet for the quiet period. Polled, so
/// the load state and the DOM are read against one deadline and `Task.sleep` handles cancellation.
@MainActor
final class FormPageSettleWaiter: BrowserToolPageSettling {

    private let driver: BrowserToolFormDriving
    private let pollInterval: TimeInterval

    init(driver: BrowserToolFormDriving, pollInterval: TimeInterval = 0.1) {
        self.driver = driver
        self.pollInterval = pollInterval
    }

    func settle(_ tab: Tab, from startURL: URL?, quietPeriod: TimeInterval, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var sawNavigation = false
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if tab.isLoading {
                sawNavigation = true
                continue
            }
            if let quiet = await driver.millisecondsSinceLastChange(in: tab.webView), Double(quiet) >= quietPeriod * 1000 {
                break
            }
        }
        return sawNavigation || tab.webView.url != startURL
    }
}

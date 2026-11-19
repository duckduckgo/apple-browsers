//
//  WebExtensionPermissionUserGestureScriptTests.swift
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

#if os(macOS)
import JavaScriptCore
import WebKit
import XCTest
@testable import WebExtensions

final class WebExtensionPermissionUserGestureScriptTests: XCTestCase {
    @available(macOS 15.4, *)
    @MainActor
    func testWebKitHidesTheIsolatedHandlerAndRejectsSyntheticDOMInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Gesture test", "version": "1.0"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        try "<button id='request'>Request</button>".write(to: directory.appendingPathComponent("test.html"), atomically: true, encoding: .utf8)
        let extensionContext = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        try controller.loadCopyingErrors(extensionContext)
        defer { try? controller.unloadCopyingErrors(extensionContext) }
        let configuration = try XCTUnwrap(extensionContext.webViewConfiguration)
        let recorder = GestureRecorder()
        configuration.userContentController.add(recorder, contentWorld: .defaultClient,
                                                name: WebExtensionPermissionUserGestureScript.messageHandlerName)
        configuration.userContentController.addUserScript(
            WKUserScript(source: WebExtensionPermissionUserGestureScript.source,
                         injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Extension document loaded")
        let navigation = GestureNavigationDelegate(loaded: loaded)
        webView.navigationDelegate = navigation
        webView.load(URLRequest(url: extensionContext.baseURL.appendingPathComponent("test.html")))
        await fulfillment(of: [loaded], timeout: 5)
        let visibleToPage = try await webView.callAsyncJavaScript("""
            return typeof window.webkit?.messageHandlers?.\(WebExtensionPermissionUserGestureScript.messageHandlerName);
            """, arguments: [:], contentWorld: .page)
        XCTAssertEqual(visibleToPage as? String, "undefined")

        _ = try await webView.callAsyncJavaScript("""
            document.getElementById('request').click();
            window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
            """, arguments: [:], contentWorld: .page)
        let protocolName = try await webView.callAsyncJavaScript("return location.protocol;", arguments: [:], contentWorld: .defaultClient)

        XCTAssertEqual(protocolName as? String, "webkit-extension:")
        XCTAssertEqual(recorder.count, 0)
    }

    func testSyntheticEventsDoNotAuthorizePermissionRequests() throws {
        let context = try makeContext()
        context.evaluateScript("listeners.click({ isTrusted: false, detail: 0 }); listeners.pointerdown({ isTrusted: false }); listeners.keydown({ isTrusted: false });")
        XCTAssertEqual(context.objectForKeyedSubscript("recordedGestures")?.toInt32(), 0)
        XCTAssertNil(context.exception)
    }

    func testTrustedClicksAndKeyPressesAreRecorded() throws {
        let context = try makeContext()
        context.evaluateScript("listeners.click({ isTrusted: true, detail: 0 }); listeners.pointerdown({ isTrusted: true }); listeners.keydown({ isTrusted: true });")
        XCTAssertEqual(context.objectForKeyedSubscript("recordedGestures")?.toInt32(), 3)
        XCTAssertNil(context.exception)
    }

    func testScreenshotShortcutsModifierKeysAndEscapeDoNotAuthorizeRequests() throws {
        let context = try makeContext()
        context.evaluateScript("""
        [
            { key: 'Shift', shiftKey: true },
            { key: 'Meta', metaKey: true, shiftKey: true },
            { key: '4', metaKey: true, shiftKey: true },
            { key: 'Control', ctrlKey: true },
            { key: 'c', ctrlKey: true },
            { key: 'Alt', altKey: true },
            { key: 'CapsLock' },
            { key: 'Escape' }
        ].forEach(function(event) {
            event.isTrusted = true;
            listeners.keydown(event);
        });
        """)

        XCTAssertEqual(context.objectForKeyedSubscript("recordedGestures")?.toInt32(), 0)
        XCTAssertNil(context.exception)
    }

    func testOrdinaryTypingAndKeyboardActivationStillAuthorizeRequests() throws {
        let context = try makeContext()
        context.evaluateScript("""
        [
            { key: 'Enter' },
            { key: ' ' },
            { key: 'a' },
            { key: 'A', shiftKey: true },
            { key: 'é', altKey: true }
        ].forEach(function(event) {
            event.isTrusted = true;
            listeners.keydown(event);
        });
        """)

        XCTAssertEqual(context.objectForKeyedSubscript("recordedGestures")?.toInt32(), 5)
        XCTAssertNil(context.exception)
    }

    func testWebsitesDoNotInstallGestureListeners() throws {
        let context = try makeContext(originProtocol: "https:")
        XCTAssertEqual(context.evaluateScript("Object.keys(listeners).length")?.toInt32(), 0)
        XCTAssertNil(context.exception)
    }

    func testPointerClickAndKeyboardClickDoNotReplaceTheirEarlierAuthorization() throws {
        let context = try makeContext()
        context.evaluateScript("""
        listeners.pointerdown({ isTrusted: true });
        listeners.click({ isTrusted: true, detail: 1 });
        listeners.keydown({ isTrusted: true });
        listeners.click({ isTrusted: true, detail: 0 });
        listeners.keydown({ isTrusted: true, repeat: true });
        """)

        XCTAssertEqual(context.objectForKeyedSubscript("recordedGestures")?.toInt32(), 2)
        XCTAssertNil(context.exception)
    }

    func testKeyUpDefersResetUntilAfterTheKeyboardClickAndAllowsTheNextAccessibilityClick() throws {
        let context = try makeContext()
        context.evaluateScript("""
        listeners.keydown({ isTrusted: true });
        listeners.keyup({ isTrusted: true });
        listeners.click({ isTrusted: true, detail: 0 });
        """)

        XCTAssertEqual(context.objectForKeyedSubscript("recordedGestures")?.toInt32(), 1)
        XCTAssertNil(context.exception)

        context.evaluateScript("""
        scheduledTimers.splice(0).forEach(function(callback) { callback(); });
        listeners.click({ isTrusted: true, detail: 0 });
        """)

        XCTAssertEqual(context.objectForKeyedSubscript("recordedGestures")?.toInt32(), 2)
        XCTAssertNil(context.exception)
    }

    private func makeContext(originProtocol: String = "webkit-extension:") throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var location = { protocol: "\(originProtocol)" };
        var listeners = {};
        var recordedGestures = 0;
        var scheduledTimers = [];
        function setTimeout(callback) { scheduledTimers.push(callback); }
        function addEventListener(name, callback, capture) {
            if (capture !== true) { throw new Error("Input must be captured before extension listeners"); }
            listeners[name] = callback;
        }
        var webkit = { messageHandlers: {
            "\(WebExtensionPermissionUserGestureScript.messageHandlerName)": {
                postMessage: function() { recordedGestures += 1; }
            }
        } };
        """)
        context.evaluateScript(WebExtensionPermissionUserGestureScript.source)
        XCTAssertNil(context.exception)
        return context
    }
}

private final class GestureRecorder: NSObject, WKScriptMessageHandler {
    var count = 0

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        count += 1
    }
}

private final class GestureNavigationDelegate: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation

    init(loaded: XCTestExpectation) {
        self.loaded = loaded
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded.fulfill()
    }
}
#endif

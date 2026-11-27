//
//  WebExtensionClipboardReadTests.swift
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

import AppKit
import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, *)
@MainActor
final class WebExtensionClipboardReadTests: XCTestCase {
    private let handler = WebExtensionClipboardReadMessageHandler()
    private let pasteboard = NSPasteboard.withUniqueName()
    private var readCount = 0
    private var webKit: WKWebExtensionController!
    private var context: WKWebExtensionContext!
    private var background: WKWebView!

    override func setUp() async throws {
        try await super.setUp()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Clipboard test", "version": "1",
                                       "background": ["page": "page.html"], "optional_permissions": ["clipboardRead"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        try Data("<p>Clipboard</p>".utf8).write(to: directory.appendingPathComponent("page.html"))
        try Data("<script src='read.js'></script>".utf8).write(to: directory.appendingPathComponent("offscreen.html"))
        try Data("globalThis.readClipboard = () => navigator.clipboard.readText();".utf8).write(to: directory.appendingPathComponent("read.js"))

        let configuration = WKWebExtensionController.Configuration.nonPersistent()
        let scripts = configuration.webViewConfiguration.userContentController
        scripts.addScriptMessageHandler(handler, contentWorld: .page, name: WebExtensionAPIStubScript.clipboardReadMessageHandlerName)
        // Keep even WebKit's ordinary user-initiated paste path away from the system clipboard in this test.
        scripts.addUserScript(WKUserScript(source: "navigator.clipboard.readText = async () => 'native fallback';",
                                           injectionTime: .atDocumentStart, forMainFrameOnly: false))
        scripts.addUserScript(WKUserScript(source: WebExtensionAPIStubScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webKit = WKWebExtensionController(configuration: configuration)
        context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        try webKit.loadCopyingErrors(context)
        handler.extensionContext = { [unowned self] in self.webKit.extensionContext(for: $0) }
        handler.pasteboard = { [unowned self] in
            self.readCount += 1
            return self.pasteboard
        }
        try await context.loadBackgroundContentCopyingErrors()
        background = try XCTUnwrap(context.value(forKey: "_backgroundWebView") as? WKWebView)
    }

    override func tearDown() async throws {
        if let context { try? webKit.unloadCopyingErrors(context) }
        pasteboard.releaseGlobally()
        try await super.tearDown()
    }

    func testGrantedOffscreenDocumentReadsCurrentTextAndStopsAfterRevocation() async throws {
        _ = try await background.callAsyncJavaScript("""
            await chrome.offscreen.createDocument({url: "offscreen.html", reasons: ["CLIPBOARD"], justification: "Read text"});
            """, contentWorld: .page)
        let read = "return await document.querySelector('iframe').contentWindow.readClipboard();"
        let denied = try await background.callAsyncJavaScript(read, contentWorld: .page)
        XCTAssertEqual(denied as? String, "native fallback")
        XCTAssertEqual(readCount, 0)

        handler.hasPermission = { [unowned self] in $0 === self.context }
        let privateAccessDenied = try await background.callAsyncJavaScript(read, contentWorld: .page)
        XCTAssertEqual(privateAccessDenied as? String, "native fallback")
        XCTAssertEqual(readCount, 0)
        // The controller uses an ephemeral data store, so it also needs private browsing access.
        context.hasAccessToPrivateData = true
        for text in ["copied by the extension", "copied by another application"] {
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(text, forType: .string))
            let value = try await background.callAsyncJavaScript(read, contentWorld: .page)
            XCTAssertEqual(value as? String, text)
        }
        pasteboard.clearContents()
        let empty = try await background.callAsyncJavaScript(read, contentWorld: .page)
        XCTAssertEqual(empty as? String, "")
        handler.hasPermission = { _ in false }
        let revoked = try await background.callAsyncJavaScript(read, contentWorld: .page)
        XCTAssertEqual(revoked as? String, "native fallback")
        XCTAssertEqual(readCount, 3)
    }

    func testWebsiteCannotReadThroughTheNativeHandler() async throws {
        handler.hasPermission = { _ in true }
        let configuration = WKWebViewConfiguration()
        configuration.webExtensionController = webKit
        configuration.userContentController.addScriptMessageHandler(handler, contentWorld: .page, name: WebExtensionAPIStubScript.clipboardReadMessageHandlerName)
        let website = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Website loaded")
        let observer = website.observe(\.isLoading, options: [.new]) { _, change in
            if change.newValue == false { loaded.fulfill() }
        }
        defer { observer.invalidate() }
        website.loadHTMLString("<p>Website</p>", baseURL: URL(string: "https://example.com/"))
        await fulfillment(of: [loaded], timeout: 5)
        let value = try await website.callAsyncJavaScript(
            "return (await webkit.messageHandlers.\(WebExtensionAPIStubScript.clipboardReadMessageHandlerName).postMessage(null)) == null;",
            contentWorld: .page)
        XCTAssertEqual(value as? Bool, true)
        XCTAssertEqual(readCount, 0)
    }
}
#endif

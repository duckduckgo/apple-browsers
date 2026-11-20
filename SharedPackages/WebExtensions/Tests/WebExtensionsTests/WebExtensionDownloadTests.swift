//
//  WebExtensionDownloadTests.swift
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

import CoreServices
@_spi(Testing) import Persistence
import WebKit
import XCTest
@testable import WebExtensions

final class WebExtensionDownloadTests: XCTestCase {

    func testOnlyBase64DataAndSafeSingleComponentNamesAreAccepted() throws {
        let url = "data:attachment/file;base64,AAEC"
        let request = try XCTUnwrap(WebExtensionDownload(options: ["url": url, "filename": "Résumé.pdf"]))
        XCTAssertEqual(try request.decode(), Data([0, 1, 2]))
        for name in ["", ".hidden", "../escape", "/destination", "a\\b", "a:b", "a\nb", "a\u{202E}fdp", "file."] {
            XCTAssertNil(WebExtensionDownload(options: ["url": url, "filename": name]))
        }
        for url in ["https://example.com", "file:///tmp/test", "blob:null/test", "data:text/plain,abc"] {
            XCTAssertNil(WebExtensionDownload(options: ["url": url, "filename": "file"]))
        }
        XCTAssertNil(WebExtensionDownload(options: ["url": url, "filename": "file", "conflictAction": "overwrite"]))
        let invalid = try XCTUnwrap(WebExtensionDownload(options: ["url": "data:attachment/file;base64,%20!", "filename": "file"]))
        XCTAssertThrowsError(try invalid.decode())
        let oversized = String(repeating: "A", count: WebExtensionDownload.maximumURLLength)
        XCTAssertNil(WebExtensionDownload(options: ["url": "data:;base64," + oversized, "filename": "file"]))
    }

    func testDataURLMediaTypeIsOptionalAndCannotContainParametersOrNonVisibleASCII() throws {
        let options = ["url": "data:;base64,AAEC", "filename": "file"]
        let download = try XCTUnwrap(WebExtensionDownload(options: options))
        XCTAssertEqual(try download.decode(), Data([0, 1, 2]))

        for mediaType in ["text/plain;charset=utf-8", "text/ plain", "text/\nplain", "text/café"] {
            let url = "data:\(mediaType);base64,AAEC"
            XCTAssertNil(WebExtensionDownload(options: ["url": url, "filename": "file"]), mediaType)
        }
    }

    func testPublishingPreservesAnExistingFileOrSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("selected.txt")
        let target = directory.appendingPathComponent("existing.txt")
        try Data([5]).write(to: target)
        let stage = try WebExtensionDownload.StagedFile(data: Data([7]), destination: destination)
        defer { stage.cleanUp() }
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
        XCTAssertThrowsError(try stage.publish(to: destination))
        XCTAssertThrowsError(try stage.publish(to: target))
        XCTAssertEqual(try Data(contentsOf: target), Data([5]))
    }
}

@available(macOS 15.4, *)
@MainActor
final class WebExtensionDownloadIntegrationTests: XCTestCase, WKNavigationDelegate {

    private let handler = WebExtensionDownloadMessageHandler()
    private var webKit: WKWebExtensionController!
    private var permissionController: WebExtensionPermissionController!
    private var context: WKWebExtensionContext!
    private var directory: URL!
    private var view: WKWebView!
    private var loaded: XCTestExpectation!
    private let window = NSWindow()
    private let options = ["url": "data:attachment/file;base64,AAEC", "filename": "sample.bin"]

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Download test", "version": "1",
                                       "optional_permissions": ["downloads"], "background": ["page": "page.html"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        try Data("<p>Download</p>".utf8).write(to: directory.appendingPathComponent("page.html"))
        context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        context.uniqueIdentifier = UUID().uuidString
        permissionController = WebExtensionPermissionController(store: WebExtensionPermissionStore(keyValueStore: InMemoryThrowingKeyValueStore()),
                                                               installationStore: InstalledWebExtensionStoringMock(), prompter: DownloadTestPrompter())
        try await permissionController.prepare(context)
        let controllerConfig = WKWebExtensionController.Configuration.nonPersistent()
        let scripts = controllerConfig.webViewConfiguration.userContentController
        scripts.addScriptMessageHandler(handler, contentWorld: .page, name: WebExtensionAPIStubScript.downloadMessageHandlerName)
        scripts.addUserScript(WKUserScript(source: WebExtensionAPIStubScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webKit = WKWebExtensionController(configuration: controllerConfig)
        try webKit.loadCopyingErrors(context)
        handler.contextForOrigin = { [unowned self] url in self.webKit.extensionContext(for: url) }
        handler.presentationWindow = { [unowned self] _, _ in self.window }
        handler.permissionController = { [unowned self] in self.permissionController }
        let config = try XCTUnwrap(context.webViewConfiguration)
        view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        loaded = expectation(description: "Extension page loaded")
        view.load(URLRequest(url: context.baseURL.appendingPathComponent("page.html")))
        await fulfillment(of: [loaded], timeout: 5)
    }

    override func tearDown() async throws {
        if let context { try webKit.unloadCopyingErrors(context) }
        if let directory { try FileManager.default.removeItem(at: directory) }
        try await super.tearDown()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded.fulfill()
    }

    private func grant() async {
        permissionController.recordUserGesture(for: context)
        let granted = await permissionController.requestAppPermissions([.downloads], for: context)
        XCTAssertTrue(granted)
    }

    private func download() async throws -> String? {
        try await view.callAsyncJavaScript("""
            try { await chrome.downloads.download(options); return "saved"; } catch (e) { return "rejected"; }
            """, arguments: ["options": options], contentWorld: .page) as? String
    }

    func testAttachmentIsQuarantinedAndBothPromiseAndEventIdentifyTheDownload() async throws {
        await grant()
        let target = directory.appendingPathComponent("chosen.bin")
        handler.chooseDestination = { name, _, _ in
            XCTAssertEqual(name, "sample.bin")
            return target
        }
        // 1Password calls this from its background page after reading the decrypted vault attachment.
        try await context.loadBackgroundContent()
        let background = try XCTUnwrap(context.value(forKey: "_backgroundWebView") as? WKWebView)
        let result = try await background.callAsyncJavaScript("""
            const id = await browser.downloads.download(options);
            return await new Promise(resolve => {
                const timer = setTimeout(() => resolve("missing event"), 1000);
                browser.downloads.onChanged.addListener(delta => {
                    clearTimeout(timer);
                    resolve(Number.isInteger(id) && id > 0 && id <= \(Int32.max) && delta.id === id && delta.filename.current);
                });
            });
            """, arguments: ["options": options], contentWorld: .page)
        XCTAssertEqual(result as? String, "chosen.bin")
        XCTAssertEqual(try Data(contentsOf: target), Data([0, 1, 2]))
        let properties = try XCTUnwrap(target.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        XCTAssertNil(properties[kLSQuarantineDataURLKey as String])
    }

    func testCallbackReceivesTheDownloadIDAndReportsCancellation() async throws {
        await grant()
        let target = directory.appendingPathComponent("callback.bin")
        handler.chooseDestination = { _, _, _ in target }
        let call = """
            let complete;
            const callback = new Promise(resolve => { complete = resolve; });
            const result = chrome.downloads.download(options, id => complete(id));
            try {
                const id = await result;
                return Number.isSafeInteger(id) && (await callback) === id ? "saved" : "wrong ID";
            } catch (error) {
                return (await callback) === undefined ? error.message : "unexpected ID";
            }
            """
        let saved = try await view.callAsyncJavaScript(call, arguments: ["options": options], contentWorld: .page)
        XCTAssertEqual(saved as? String, "saved")
        handler.chooseDestination = { _, _, _ in nil }
        let canceled = try await view.callAsyncJavaScript(call, arguments: ["options": options], contentWorld: .page)
        XCTAssertEqual(canceled as? String, "Download canceled")
    }

    func testDeniedPermissionAndRevocationWhileChoosingDestinationPreventSaving() async throws {
        let target = directory.appendingPathComponent("denied.bin")
        handler.chooseDestination = { _, _, _ in XCTFail("Unexpected dialog"); return target }
        let denied = try await download()
        XCTAssertEqual(denied, "rejected")
        await grant()
        handler.chooseDestination = { [unowned self] _, _, _ in
            XCTAssertTrue(self.permissionController.revoke(.downloads, from: self.context))
            return target
        }
        let revoked = try await download()
        XCTAssertEqual(revoked, "rejected")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testChangingThePresentationWindowDuringConsentCancelsTheDownload() async throws {
        await grant()
        let target = directory.appendingPathComponent("canceled.bin")
        let otherWindow = NSWindow()
        handler.chooseDestination = { [unowned self] _, _, window in
            XCTAssertTrue(window === self.window)
            self.handler.presentationWindow = { _, _ in otherWindow }
            return target
        }
        let result = try await download()
        XCTAssertEqual(result, "rejected")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testWebsiteCannotInvokeTheNativeHandlerDirectly() async throws {
        await grant()
        handler.chooseDestination = { _, _, _ in XCTFail("Unexpected dialog"); return nil }
        // A normal browser tab has its own configuration. WebKit pins the extension-owned
        // configuration in setUp to extension pages and rejects ordinary website navigation.
        let configuration = WKWebViewConfiguration()
        configuration.webExtensionController = webKit
        configuration.userContentController.addScriptMessageHandler(handler, contentWorld: .page, name: WebExtensionAPIStubScript.downloadMessageHandlerName)
        view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        loaded = expectation(description: "Website loaded")
        view.loadHTMLString("<p>Website</p>", baseURL: URL(string: "https://example.org/"))
        await fulfillment(of: [loaded], timeout: 5)
        let result = try await view.callAsyncJavaScript("""
            if (location.origin !== "https://example.org") { return "wrong origin"; }
            try {
                await webkit.messageHandlers.\(WebExtensionAPIStubScript.downloadMessageHandlerName).postMessage(options);
                return "saved";
            } catch (e) { return "rejected"; }
            """, arguments: ["options": options], contentWorld: .page)
        XCTAssertEqual(result as? String, "rejected")
    }

    func testCancelAndConcurrentCallRejectAndAllowRetry() async throws {
        await grant()
        var panels = 0
        handler.chooseDestination = { [unowned self] _, _, _ in
            panels += 1
            if panels == 1 {
                let concurrent = try? await self.download()
                XCTAssertEqual(concurrent, "rejected")
            }
            return nil
        }
        let canceled = try await download()
        let retry = try await download()
        XCTAssertEqual(canceled, "rejected")
        XCTAssertEqual(retry, "rejected")
        XCTAssertEqual(panels, 2)
    }
}

@available(macOS 15.4, *)
private struct DownloadTestPrompter: WebExtensionPermissionPrompting {
    func confirmInstallation(of webExtension: WKWebExtension, permissions: WebExtensionPermissionRequest) async -> WebExtensionPermissionInstallationPromptResult {
        .granted(privateDataAccess: true)
    }
    func confirmPermissions(_ permissions: WebExtensionPermissionRequest, for context: WKWebExtensionContext) async -> WebExtensionPermissionPromptResult {
        .granted
    }
}

#endif

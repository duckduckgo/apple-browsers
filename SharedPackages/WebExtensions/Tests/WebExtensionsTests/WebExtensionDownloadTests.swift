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

    private let origin = URL(string: "webkit-extension://owner/")!

    private func request(_ url: String, filename: String = "file") -> WebExtensionDownload? {
        WebExtensionDownload(options: ["url": url, "filename": filename], extensionBaseURL: origin)
    }

    func testRequiresSafeSingleComponentFilenameAndKnownOptions() {
        let url = "data:attachment/file;base64,AAEC"
        XCTAssertNotNil(request(url, filename: "Résumé.pdf"))
        for name in ["", ".hidden", "../escape", "/destination", "a\\b", "a:b", "a\nb", "a\u{202E}fdp", "file."] {
            XCTAssertNil(request(url, filename: name))
        }
        let extraOptions = ["url": url, "filename": "file", "conflictAction": "overwrite"]
        XCTAssertNil(WebExtensionDownload(options: extraOptions, extensionBaseURL: origin))
    }

    func testPreservesJoinControlsInFilenames() {
        for name in ["می\u{200C}روم.txt", "👩\u{200D}💻.png"] {
            XCTAssertEqual(request("data:,", filename: name)?.filename, name)
        }
    }

    func testJoinControlsCannotMaskUnsafeFilenames() {
        let tooLong = String(repeating: "a", count: 253) + "\u{200C}"
        for name in ["\u{200D}", "\u{200C}.hidden", ".\u{200D}hidden", "file.\u{200C}", "\u{200D} file", "a\u{200D}/b",
                     "a\u{200C}\u{2066}b", "a\u{200D}\u{200B}b", tooLong] {
            XCTAssertNil(request("data:,", filename: name), name.debugDescription)
        }
    }

    func testAcceptsDataURLsAndOnlyObjectURLsFromTheCallingExtension() {
        let id = UUID().uuidString
        XCTAssertNotNil(request("data:;base64,"))
        XCTAssertNotNil(request("data:text/plain;charset=utf-8,hello%20world"))
        XCTAssertNotNil(request("blob:webkit-extension://owner/\(id)"))
        for url in ["https://example.com", "file:///tmp/test", "data:attachment/file", "blob:null/\(id)",
                    "blob:https://owner/\(id)", "blob:webkit-extension://other/\(id)", "blob:webkit-extension://owner.evil/\(id)",
                    "blob:webkit-extension://owner@other/\(id)", "blob:webkit-extension://owner:42/\(id)"] {
            XCTAssertNil(request(url), url)
        }
    }

    func testNormalizesDataURLsForDownload() throws {
        let cases = [("data:,hello%23world#ignored", "data:,hello%23world"),
                     ("data:; base64,QQ==", "data:;base64,QQ=="),
                     ("data:text/plain;base64;x=y,QQ==", "data:,QQ=="),
                     ("data:;base64,AAE#ignored", "data:;base64,AAE="),
                     ("data:text/plain;base64,YQ", "data:;base64,YQ=="),
                     ("data:;base64,%41%20AE", "data:;base64,AAE=")]
        for (input, expected) in cases {
            let download = try XCTUnwrap(request(input))
            XCTAssertEqual(download.makeDownloadURL()?.absoluteString, expected, input)
        }
    }

    func testPlainDataURLPreservesEscapesWhenLiteralBytesNeedEncoding() throws {
        let cases = [("caf%C3%A9☕", "caf%C3%A9%E2%98%95"),
                     ("50%25%20off now", "50%25%20off%20now"),
                     ("50%25%20off%", "50%25%20off%25"),
                     ("%FF%00 %2523%23#fragment", "%FF%00%20%2523%23")]
        for (input, expected) in cases {
            let download = try XCTUnwrap(request("data:," + input))
            XCTAssertEqual(download.makeDownloadURL()?.absoluteString, "data:," + expected, input)
        }
    }

    func testRejectsMalformedBase64() throws {
        for payload in ["%20!", "QQ=0", "YQ=", "A", "%252F"] {
            let download = try XCTUnwrap(request("data:attachment/file;base64," + payload))
            XCTAssertNil(download.makeDownloadURL(), payload)
        }
    }

    func testPublishingPreservesAnExistingFileOrSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("selected.txt")
        let target = directory.appendingPathComponent("existing.txt")
        try Data([5]).write(to: target)
        let stage = try WebExtensionDownload.StagedFile(destination: destination)
        defer { stage.cleanUp() }
        try Data([7]).write(to: stage.file)
        try stage.prepareForPublication()
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
    private var context: DownloadTestContext!
    private var directory: URL!
    private var view: DownloadTestWebView!
    private var loaded: XCTestExpectation!
    private let window = DownloadTestWindow()
    private let options = ["url": "data:attachment/file;base64,AAEC", "filename": "sample.bin"]

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Download test", "version": "1",
                                       "optional_permissions": ["downloads"], "background": ["page": "page.html"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        try Data("<p>Download</p>".utf8).write(to: directory.appendingPathComponent("page.html"))
        context = DownloadTestContext(for: try await WKWebExtension(resourceBaseURL: directory))
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
        handler.backgroundWebView = { $0.value(forKey: "_backgroundWebView") as? WKWebView }
        handler.presentationWindow = { [unowned self] _, _, _ in self.window }
        handler.chooseDestination = { _, _, _ in nil }
        handler.permissionController = { [unowned self] in self.permissionController }
        let config = try XCTUnwrap(context.webViewConfiguration)
        view = DownloadTestWebView(frame: .zero, configuration: config)
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

    private func download(url: String? = nil) async throws -> String? {
        var request = options
        if let url { request["url"] = url }
        return try await view.callAsyncJavaScript("""
            try { await chrome.downloads.download(options); return "saved"; } catch (e) { return "rejected"; }
            """, arguments: ["options": request], contentWorld: .page) as? String
    }

    private func downloadAndObserveCompletion(in webView: WKWebView) async throws -> String? {
        try await webView.callAsyncJavaScript("""
            const id = await browser.downloads.download(options);
            return await new Promise(resolve => {
                const timer = setTimeout(() => resolve("missing event"), 1000);
                browser.downloads.onChanged.addListener(delta => {
                    clearTimeout(timer);
                    resolve(Number.isInteger(id) && id > 0 && id <= \(Int32.max) && delta.id === id && delta.filename.current);
                });
            });
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
        let result = try await downloadAndObserveCompletion(in: background)
        XCTAssertEqual(result, "chosen.bin")
        XCTAssertEqual(try Data(contentsOf: target), Data([0, 1, 2]))
        let properties = try XCTUnwrap(target.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        XCTAssertNil(properties[kLSQuarantineDataURLKey as String])
        XCTAssertNil(properties[kLSQuarantineOriginURLKey as String])
        XCTAssertEqual(getxattr(target.path, "com.apple.metadata:kMDItemWhereFroms", nil, 0, 0, XATTR_NOFOLLOW), -1)
        XCTAssertEqual(errno, ENOATTR)
    }

    func testAutomaticDownloadPreservesExistingFileAndReportsTheSavedFilename() async throws {
        await grant()
        let existing = directory.appendingPathComponent("sample.bin")
        try Data([9]).write(to: existing)
        handler.automaticDownloadDirectory = { [unowned self] in self.directory }
        let result = try await downloadAndObserveCompletion(in: view)
        XCTAssertEqual(result, "sample 1.bin")
        XCTAssertEqual(try Data(contentsOf: existing), Data([9]))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("sample 1.bin")), Data([0, 1, 2]))
    }

    func testAutomaticDownloadContinuesAfterFocusChanges() async throws {
        await grant()
        handler.automaticDownloadDirectory = { [unowned self] in self.directory }
        view.didStartDownload = { [unowned self] in
            self.handler.presentationWindow = { _, _, boundWindow in boundWindow }
        }

        let result = try await download()
        XCTAssertEqual(result, "saved")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("sample.bin")), Data([0, 1, 2]))
    }

    func testPopOutUsesItsOwnWindowAndRespectsPrivateAccess() {
        let manager = WebExtensionManager(configuration: WebExtensionConfigurationProvidingMock(),
                                          windowTabProvider: WebExtensionWindowTabProvidingMock(),
                                          storageProvider: WebExtensionStorageProvidingMock())
        let popup = DownloadTestWindow()
        let controller = DownloadTestWindowController(window: popup)
        popup.contentView = view
        defer { withExtendedLifetime(controller) {} }

        XCTAssertIdentical(manager.downloadPresentationWindow(for: view, context: context), popup)
        controller.privateWindow = true
        context.hasAccessToPrivateData = false
        XCTAssertNil(manager.downloadPresentationWindow(for: view, context: context))
        context.hasAccessToPrivateData = true
        XCTAssertIdentical(manager.downloadPresentationWindow(for: view, context: context), popup)

        popup.isFocused = false
        XCTAssertIdentical(manager.downloadPresentationWindow(for: view, context: context, boundTo: popup), popup)
        context.hasAccessToPrivateData = false
        XCTAssertNil(manager.downloadPresentationWindow(for: view, context: context, boundTo: popup))
    }

    func testBackgroundRefreshesWhileChoosingADestinationAndStopsAfterCancellation() async throws {
        await grant()
        try await context.loadBackgroundContentCopyingErrors()
        let background = try XCTUnwrap(handler.backgroundWebView(context))
        handler.backgroundRefreshInterval = .milliseconds(10)
        let refreshes = expectation(description: "Background refreshed twice during the panel")
        refreshes.expectedFulfillmentCount = 2
        refreshes.assertForOverFulfill = false
        handler.chooseDestination = { [unowned self] _, _, _ in
            self.context.onBackgroundLoad = { refreshes.fulfill() }
            await self.fulfillment(of: [refreshes], timeout: 2)
            self.context.onBackgroundLoad = nil
            return nil
        }
        let result = try await background.callAsyncJavaScript("""
            try { await browser.downloads.download(options); return "saved"; } catch { return "rejected"; }
            """, arguments: ["options": options], contentWorld: .page)
        XCTAssertEqual(result as? String, "rejected")

        let unexpectedLoad = expectation(description: "No refresh after cancellation or while a tab saves")
        unexpectedLoad.isInverted = true
        context.onBackgroundLoad = { unexpectedLoad.fulfill() }
        handler.chooseDestination = { [unowned self] _, _, _ in
            await self.fulfillment(of: [unexpectedLoad], timeout: 0.1)
            return nil
        }
        let tabResult = try await download()
        XCTAssertEqual(tabResult, "rejected")
    }

    func testLargeBlobAndDataURLsSaveAllBytesFromTheExtensionBackground() async throws {
        await grant()
        try await context.loadBackgroundContent()
        let background = try XCTUnwrap(context.value(forKey: "_backgroundWebView") as? WKWebView)
        let target = directory.appendingPathComponent("large.bin")
        handler.chooseDestination = { _, _, _ in target }
        let block = Data(repeating: 120, count: 1024 * 1024)
        let blockCount = 20
        for useBlobURL in [true, false] {
            let id = try await background.callAsyncJavaScript("""
                const part = new Blob([new Uint8Array(1024 * 1024).fill(120)]);
                const file = new Blob(Array(blockCount).fill(part), {type: "attachment/file"});
                const url = useBlobURL ? URL.createObjectURL(file) : await new Promise((resolve, reject) => {
                    const reader = new FileReader();
                    reader.onload = () => resolve(reader.result);
                    reader.onerror = () => reject(reader.error);
                    reader.readAsDataURL(file);
                });
                try { return await browser.downloads.download({url, filename: "large.bin"}); }
                finally { if (useBlobURL) URL.revokeObjectURL(url); }
                """, arguments: ["useBlobURL": useBlobURL, "blockCount": blockCount], contentWorld: .page)
            XCTAssertNotNil(id as? NSNumber)
            let handle = try FileHandle(forReadingFrom: target)
            defer { try? handle.close() }
            for _ in 0..<blockCount {
                guard try handle.read(upToCount: block.count) == block else { return XCTFail("Incorrect attachment bytes") }
            }
            XCTAssertTrue(try handle.read(upToCount: 1)?.isEmpty ?? true)
            try FileManager.default.removeItem(at: target)
        }
    }

    func testUnavailableObjectURLFailsAndNextDownloadSucceeds() async throws {
        await grant()
        let target = directory.appendingPathComponent("retry.bin")
        handler.chooseDestination = { _, _, _ in target }
        let failed = try await view.callAsyncJavaScript("""
            const url = URL.createObjectURL(new Blob(["test"]));
            URL.revokeObjectURL(url);
            try { await chrome.downloads.download({url, filename: "file"}); return false; }
            catch { return true; }
            """, contentWorld: .page)
        XCTAssertEqual(failed as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        let result = try await download()
        XCTAssertEqual(result, "saved")
    }

    func testInvalidBase64IsRejectedBeforeChoosingADestination() async throws {
        await grant()
        handler.chooseDestination = { _, _, _ in XCTFail("Unexpected Save panel"); return nil }
        let result = try await download(url: "data:;base64,QQ=0")
        XCTAssertEqual(result, "rejected")
    }

    func testWebKitSavesPlainAndBase64DataURLBytes() async throws {
        await grant()
        let target = directory.appendingPathComponent("data.bin")
        handler.chooseDestination = { _, _, _ in target }
        let cases = [("data:text/plain;base64;x=y,QQ==%23#ignored", Data("QQ==#".utf8)),
                     ("data:,caf%C3%A9☕%00%FF", Data("café☕".utf8) + Data([0, 255])),
                     ("data:; base64,%41%20AE#ignored", Data([0, 1]))]
        for (url, expected) in cases {
            let result = try await download(url: url)
            XCTAssertEqual(result, "saved", url)
            XCTAssertEqual(try Data(contentsOf: target), expected, url)
            try FileManager.default.removeItem(at: target)
        }
    }

    func testBlobCreatedByAnotherLoadedExtensionIsRejectedBeforeConsent() async throws {
        await grant()
        let otherContext = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        try webKit.loadCopyingErrors(otherContext)
        defer { try? webKit.unloadCopyingErrors(otherContext) }
        try await otherContext.loadBackgroundContent()
        let otherView = try XCTUnwrap(otherContext.value(forKey: "_backgroundWebView") as? WKWebView)
        let blob = try await otherView.callAsyncJavaScript("return URL.createObjectURL(new Blob(['private']));", contentWorld: .page)
        let foreignURL = try XCTUnwrap(blob as? String)
        handler.chooseDestination = { _, _, _ in XCTFail("Unexpected Save panel"); return nil }
        let result = try await view.callAsyncJavaScript("""
            try { await chrome.downloads.download({url, filename: "other.bin"}); return "saved"; }
            catch { return "rejected"; }
            """, arguments: ["url": foreignURL], contentWorld: .page)
        XCTAssertEqual(result as? String, "rejected")
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

    func testManualDownloadKeepsTheOriginalWindowAfterChoosingDestination() async throws {
        await grant()
        let target = directory.appendingPathComponent("saved.bin")
        let otherWindow = NSWindow()
        window.isFocused = false
        handler.chooseDestination = { [unowned self] _, _, window in
            XCTAssertTrue(window === self.window)
            self.handler.presentationWindow = { _, _, boundWindow in boundWindow ?? otherWindow }
            return target
        }
        let result = try await download()
        XCTAssertEqual(result, "saved")
        XCTAssertEqual(try Data(contentsOf: target), Data([0, 1, 2]))
    }

    func testRevocationWhenWebKitStartsPreventsPublication() async throws {
        await grant()
        let target = directory.appendingPathComponent("revoked.bin")
        handler.chooseDestination = { _, _, _ in target }
        view.didStartDownload = { [unowned self] in
            XCTAssertTrue(self.permissionController.revoke(.downloads, from: self.context))
        }
        let result = try await download()
        XCTAssertEqual(result, "rejected")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testDiscardedWebKitStartCallbackReleasesDownloadForRetry() async throws {
        await grant()
        let target = directory.appendingPathComponent("retry.bin")
        handler.chooseDestination = { _, _, _ in target }
        view.discardNextStart = true
        handler.downloadStartTimeout = .milliseconds(50)
        let interrupted = try await download()
        XCTAssertEqual(interrupted, "rejected")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        handler.downloadStartTimeout = .seconds(60)
        let retry = try await download()
        XCTAssertEqual(retry, "saved")
    }

    func testWebsiteCannotInvokeTheNativeHandlerDirectly() async throws {
        await grant()
        handler.chooseDestination = { _, _, _ in XCTFail("Unexpected dialog"); return nil }
        // A normal browser tab has its own configuration. WebKit pins the extension-owned
        // configuration in setUp to extension pages and rejects ordinary website navigation.
        let configuration = WKWebViewConfiguration()
        configuration.webExtensionController = webKit
        configuration.userContentController.addScriptMessageHandler(handler, contentWorld: .page, name: WebExtensionAPIStubScript.downloadMessageHandlerName)
        view = DownloadTestWebView(frame: .zero, configuration: configuration)
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

private final class DownloadTestWindow: NSWindow {
    var isFocused = true
    override var isKeyWindow: Bool { isFocused }
    override var isVisible: Bool { true }
}

@available(macOS 15.4, *)
private final class DownloadTestWindowController: NSWindowController, WKWebExtensionWindow {
    var privateWindow = false

    func isPrivate(for context: WKWebExtensionContext) -> Bool { privateWindow }
}

@available(macOS 15.4, *)
private final class DownloadTestContext: WKWebExtensionContext {
    var onBackgroundLoad: (() -> Void)?

    override func loadBackgroundContent(completionHandler: @escaping (Swift.Error?) -> Void) {
        onBackgroundLoad?()
        super.loadBackgroundContent(completionHandler: completionHandler)
    }
}

@available(macOS 15.4, *)
private final class DownloadTestWebView: WKWebView {
    var didStartDownload: (() -> Void)?
    var discardNextStart = false

    override func startDownload(using request: URLRequest, completionHandler: @escaping @MainActor @Sendable (WKDownload) -> Void) {
        if discardNextStart {
            discardNextStart = false
            return
        }
        super.startDownload(using: request) { download in
            completionHandler(download)
            self.didStartDownload?()
        }
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

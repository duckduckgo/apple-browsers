//
//  WebExtensionDownloadMessageHandler.swift
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

@available(macOS 15.4, *)
@MainActor
final class WebExtensionDownloadMessageHandler: NSObject, WKScriptMessageHandlerWithReply {

    var contextForOrigin: (URL) -> WKWebExtensionContext? = { _ in nil }
    var backgroundWebView: (WKWebExtensionContext) -> WKWebView? = { _ in nil }
    var permissionController: () -> WebExtensionPermissionController? = { nil }

    var presentationWindow: (WKWebView, WKWebExtensionContext) -> NSWindow? = { _, _ in nil }
    var automaticDownloadDirectory: () -> URL? = { nil }
    var canChooseDestination: (NSWindow) -> Bool = { NSApp.isActive && $0.isVisible && $0.attachedSheet == nil }
    var chooseDestination: @MainActor (String, String?, NSWindow) async -> URL? = WebExtensionDownloadMessageHandler.showSavePanel
    var downloadStartTimeout: Duration = .seconds(60)
    var backgroundRefreshInterval: Duration = .seconds(15)
    private var saving = false

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        reply(to: message, replyHandler: replyHandler)
    }

    func reply(to message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        guard message.name == WebExtensionAPIStubScript.downloadMessageHandlerName, message.world == .page,
              message.frameInfo.isMainFrame, origin.protocol == "webkit-extension", !origin.host.isEmpty,
              let url = message.frameInfo.request.url, url.scheme == origin.protocol,
              url.host?.caseInsensitiveCompare(origin.host) == .orderedSame,
              let webView = message.webView, let context = contextForOrigin(url),
              isCurrent(context, in: webView), context.webExtension.declaresPermission("downloads"),
              let controller = permissionController(), let window = presentationWindow(webView, context) else {
            replyHandler(nil, "Extension downloads are unavailable")
            return
        }
        guard !saving else {
            replyHandler(nil, "Another extension download is in progress")
            return
        }
        guard let download = WebExtensionDownload(options: message.body, extensionBaseURL: context.baseURL) else {
            replyHandler(nil, "Unsupported attachment URL or filename")
            return
        }
        saving = true
        Task {
            let keepAlive = keepBackgroundLoaded(context, for: webView)
            defer {
                keepAlive?.cancel()
                saving = false
            }
            let identifier = context.uniqueIdentifier
            // Older installs can have required downloads in their manifest without a saved grant.
            // Only a recent user interaction can start the normal permission prompt.
            if !controller.isGranted(.downloads, to: identifier), context.webExtension.requiresPermission("downloads") {
                _ = await controller.requestAppPermissions([.downloads], for: context)
            }
            @MainActor func authorized() -> Bool {
                isCurrent(context, in: webView) && permissionController() === controller &&
                    presentationWindow(webView, context) === window && controller.isGranted(.downloads, to: identifier)
            }
            @MainActor func checkAuthorization() throws {
                guard authorized() else { throw WebExtensionDownload.DownloadError.canceled }
            }
            guard authorized() else {
                replyHandler(nil, "The downloads permission is required")
                return
            }
            do {
                guard let source = await Task.detached(operation: { download.makeDownloadURL() }).value else {
                    throw WebExtensionDownload.DownloadError.invalid
                }
                try checkAuthorization()
                let (destination, isAutomatic) = try await downloadDestination(for: download.filename, context: context, window: window)
                // The panel grants access to its URL. Preferences own access to the configured directory.
                defer { if !isAutomatic { destination.stopAccessingSecurityScopedResource() } }
                try checkAuthorization()
                let staged = try await Task.detached { try WebExtensionDownload.StagedFile(destination: destination) }.value
                defer { staged.cleanUp() }
                try checkAuthorization()
                let writer = AttachmentDownloadDelegate(destination: staged.file, authorized: authorized)
                try await writer.write(source, from: webView, startTimeout: downloadStartTimeout)
                try await Task.detached { try staged.prepareForPublication() }.value
                try checkAuthorization()
                let saved = try staged.publish(to: destination, uniquify: isAutomatic)
                // Only return the basename. The directory selected by the user stays private.
                replyHandler(["id": Int32.random(in: 1...Int32.max), "filename": saved.lastPathComponent], nil)
            } catch WebExtensionDownload.DownloadError.canceled {
                replyHandler(nil, "Download canceled")
            } catch WebExtensionDownload.DownloadError.fileExists {
                replyHandler(nil, "A file with this name already exists. Choose another name.")
            } catch {
                replyHandler(nil, "Could not save the download")
            }
        }
    }

    private func downloadDestination(for filename: String, context: WKWebExtensionContext, window: NSWindow) async throws -> (url: URL, isAutomatic: Bool) {
        guard canChooseDestination(window) else { throw WebExtensionDownload.DownloadError.canceled }
        if let directory = automaticDownloadDirectory() {
            return (directory.appendingPathComponent(filename, isDirectory: false), true)
        }
        guard let chosen = await chooseDestination(filename, context.webExtension.displayName, window) else {
            throw WebExtensionDownload.DownloadError.canceled
        }
        return (chosen, false)
    }

    private func keepBackgroundLoaded(_ context: WKWebExtensionContext, for webView: WKWebView) -> Task<Void, Never>? {
        guard !context.webExtension.hasPersistentBackgroundContent, backgroundWebView(context) === webView else { return nil }
        return Task {
            // Loading the existing page resets WebKit's 30-second idle timer while the user chooses a file.
            // Check identity before every refresh so a closed page is never reopened.
            while !Task.isCancelled, context.isLoaded, backgroundWebView(context) === webView {
                do {
                    try await context.loadBackgroundContentCopyingErrors()
                    try await Task.sleep(for: backgroundRefreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func isCurrent(_ context: WKWebExtensionContext, in webView: WKWebView) -> Bool {
        guard context.isLoaded, let pageURL = webView.url, contextForOrigin(pageURL) === context,
              let controller = context.webExtensionController, webView.configuration.webExtensionController === controller else { return false }
        return webView.configuration.websiteDataStore.isPersistent || context.hasAccessToPrivateData
    }

    private static func showSavePanel(_ filename: String, extensionName: String?, window: NSWindow) async -> URL? {
        let panel = NSSavePanel()
        let validator = DestinationValidator()
        panel.delegate = validator
        defer { withExtendedLifetime(validator) {} }
        panel.nameFieldStringValue = filename
        panel.isExtensionHidden = false
        panel.canSelectHiddenExtension = false
        if let extensionName {
            panel.message = String(extensionName.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(100))
        }
        guard await panel.beginSheetModal(for: window) == .OK else { return nil }
        return panel.url
    }
}

/// Only the staging path reaches WebKit. The caller owns consent, quarantine and final publication.
@available(macOS 15.4, *)
@MainActor
private final class AttachmentDownloadDelegate: NSObject, WKDownloadDelegate {
    private let destination: URL
    private let authorized: @MainActor () -> Bool
    private var completion: CheckedContinuation<Void, Error>?

    init(destination: URL, authorized: @escaping @MainActor () -> Bool) {
        self.destination = destination
        self.authorized = authorized
    }

    func write(_ source: URL, from webView: WKWebView, startTimeout: Duration) async throws {
        // WKDownload holds a weak delegate. Keep it alive until WebKit finishes or fails.
        defer { withExtendedLifetime(self) {} }
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            // A lost network process may never acknowledge the start. A transfer already in progress has no timeout.
            let timeout = Task { [weak self] in
                try await Task.sleep(for: startTimeout)
                try Task.checkCancellation()
                self?.finish(.failure(WebExtensionDownload.DownloadError.saveFailed))
            }
            webView.startDownload(using: URLRequest(url: source)) { [weak self] download in
                timeout.cancel()
                guard let self, self.completion != nil else {
                    download.cancel { _ in }
                    return
                }
                download.delegate = self
            }
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard authorized() else {
            finish(.failure(WebExtensionDownload.DownloadError.canceled))
            return nil
        }
        return destination
    }

    func download(_ download: WKDownload, decidedPolicyForHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest) async -> WKDownload.RedirectPolicy {
        finish(.failure(WebExtensionDownload.DownloadError.invalid))
        return .cancel
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(.success(()))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(.failure(WebExtensionDownload.DownloadError.saveFailed))
    }

    private func finish(_ result: Result<Void, Error>) {
        completion?.resume(with: result)
        completion = nil
    }
}

/// Give the user another chance to choose a name in the panel. The exclusive rename also
/// checks for files created between panel validation and publication.
private final class DestinationValidator: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, validate url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            throw CocoaError(.fileWriteFileExists)
        }
    }
}

#endif

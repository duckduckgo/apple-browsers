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
    var permissionController: () -> WebExtensionPermissionController? = { nil }

    var presentationWindow: (WKWebView, WKWebExtensionContext) -> NSWindow? = { _, _ in nil }
    var chooseDestination: @MainActor (String, String?, NSWindow) async -> URL? = WebExtensionDownloadMessageHandler.showSavePanel
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
        guard let download = WebExtensionDownload(options: message.body) else {
            replyHandler(nil, "Unsupported download options or file size")
            return
        }
        saving = true
        Task {
            defer { saving = false }
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
            guard authorized() else {
                replyHandler(nil, "The downloads permission is required")
                return
            }
            do {
                let data = try await Task.detached { try download.decode() }.value
                guard authorized(), let destination = await chooseDestination(download.filename, context.webExtension.displayName, window) else {
                    replyHandler(nil, "Download canceled")
                    return
                }
                // The Save panel starts security-scoped access to the selected URL.
                defer { destination.stopAccessingSecurityScopedResource() }
                guard authorized() else {
                    replyHandler(nil, "Download canceled")
                    return
                }
                let staged = try await Task.detached { try WebExtensionDownload.StagedFile(data: data, destination: destination) }.value
                defer { staged.cleanUp() }
                guard authorized() else {
                    replyHandler(nil, "Download canceled")
                    return
                }
                try staged.publish(to: destination)
                // Only return the basename. The directory selected by the user stays private.
                replyHandler(["id": Int32.random(in: 1...Int32.max), "filename": destination.lastPathComponent], nil)
            } catch WebExtensionDownload.DownloadError.fileExists {
                replyHandler(nil, "A file with this name already exists. Choose another name.")
            } catch {
                replyHandler(nil, "Could not save the download")
            }
        }
    }

    private func isCurrent(_ context: WKWebExtensionContext, in webView: WKWebView) -> Bool {
        guard context.isLoaded, let pageURL = webView.url, contextForOrigin(pageURL) === context,
              let controller = context.webExtensionController, webView.configuration.webExtensionController === controller else { return false }
        return webView.configuration.websiteDataStore.isPersistent || context.hasAccessToPrivateData
    }

    private static func showSavePanel(_ filename: String, extensionName: String?, window: NSWindow) async -> URL? {
        guard NSApp.isActive, window.isVisible, window.attachedSheet == nil else { return nil }
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

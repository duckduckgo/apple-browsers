//
//  WebExtensionClipboardReadMessageHandler.swift
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
import Common
import WebKit

@available(macOS 15.4, *)
@MainActor
final class WebExtensionClipboardReadMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    var extensionContext: (URL) -> WKWebExtensionContext? = { _ in nil }
    var hasPermission: (WKWebExtensionContext) -> Bool = { _ in false }
    var pasteboard: () -> NSPasteboard = { .general }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        replyHandler(readText(for: message), nil)
    }

    /// A nil reply leaves the caller subject to WebKit's normal paste rules.
    func readText(for message: WKScriptMessage) -> String? {
        guard message.name == WebExtensionAPIStubScript.clipboardReadMessageHandlerName,
              message.world == .page else { return nil }

        guard let context = contextForFrame(message.frameInfo),
              let webView = message.webView,
              isExtensionPage(webView, in: context) else { return nil }

        guard webView.configuration.websiteDataStore.isPersistent || context.hasAccessToPrivateData else { return nil }
        guard context.webExtension.declaresPermission(WebExtensionManifestPermission.clipboardRead.rawValue),
              hasPermission(context) else { return nil }

        return pasteboard().string(forType: .string) ?? ""
    }

    private func contextForFrame(_ frame: WKFrameInfo) -> WKWebExtensionContext? {
        let origin = frame.securityOrigin
        guard origin.protocol == URL.NavigationalScheme.webkitExtension.rawValue,
              !origin.host.isEmpty else { return nil }

        guard let url = frame.request.url,
              url.scheme == origin.protocol,
              url.host?.caseInsensitiveCompare(origin.host) == .orderedSame else { return nil }

        guard let context = extensionContext(url), context.isLoaded else { return nil }
        return context
    }

    private func isExtensionPage(_ webView: WKWebView, in context: WKWebExtensionContext) -> Bool {
        guard let pageURL = webView.url, extensionContext(pageURL) === context else { return false }
        guard let controller = context.webExtensionController else { return false }
        return webView.configuration.webExtensionController === controller
    }
}

#endif

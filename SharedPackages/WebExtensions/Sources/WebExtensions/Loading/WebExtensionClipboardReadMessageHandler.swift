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
        let origin = message.frameInfo.securityOrigin
        guard message.name == WebExtensionAPIStubScript.clipboardReadMessageHandlerName, message.world == .page,
              origin.protocol == "webkit-extension", !origin.host.isEmpty,
              let frameURL = message.frameInfo.request.url, frameURL.scheme == origin.protocol,
              frameURL.host?.caseInsensitiveCompare(origin.host) == .orderedSame,
              let context = extensionContext(frameURL), context.isLoaded,
              let webView = message.webView, let pageURL = webView.url, extensionContext(pageURL) === context,
              let controller = context.webExtensionController, webView.configuration.webExtensionController === controller,
              webView.configuration.websiteDataStore.isPersistent || context.hasAccessToPrivateData,
              context.webExtension.declaresPermission("clipboardRead"), hasPermission(context) else { return nil }

        return pasteboard().string(forType: .string) ?? ""
    }
}

#endif

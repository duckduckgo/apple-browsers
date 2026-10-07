//
//  WebExtensionWindowCloseScript.swift
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

/// JavaScript that reports an extension page's `window.close()` call to the browser, so a popup
/// hosted in a panel of our own can close the panel; WebKit only unloads the page. It does nothing
/// without a `WebExtensionWindowCloseMessageHandler`.
enum WebExtensionWindowCloseScript {

    /// Name of the script message handler the page posts to.
    static let messageHandlerName = "ddgWebExtensionWindowClose"

    static let source = """
    (function() {
        var handlers = globalThis.webkit && globalThis.webkit.messageHandlers;
        var handler = handlers && handlers["\(messageHandlerName)"];
        if (!handler || typeof globalThis.close !== "function") {
            return;
        }

        // Our own extensions declare `browser_specific_settings.duckduckgo` and are left alone.
        try {
            var api = globalThis.chrome || globalThis.browser;
            var settings = api && api.runtime && typeof api.runtime.getManifest === "function"
                ? api.runtime.getManifest().browser_specific_settings : undefined;
            if (settings && settings.duckduckgo) {
                return;
            }
        } catch (error) {
            // A page that cannot read its manifest is treated like any other extension page.
        }

        var originalClose = globalThis.close;
        globalThis.close = function() {
            try {
                handler.postMessage(String(globalThis.location && globalThis.location.href));
            } catch (error) {
                // A missing handler must not keep the page from closing.
            }
            return originalClose.apply(this, arguments);
        };
    })();
    """
}

/// Receives the message `WebExtensionWindowCloseScript` posts and hands the closing web view on.
@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionWindowCloseMessageHandler: NSObject, WKScriptMessageHandler {

    /// Called on the main actor with the web view whose page called `window.close()`.
    var onWindowClose: (@MainActor (WKWebView) -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == WebExtensionWindowCloseScript.messageHandlerName,
              let webView = message.webView else {
            return
        }
        MainActor.assumeIsolated {
            onWindowClose?(webView)
        }
    }
}

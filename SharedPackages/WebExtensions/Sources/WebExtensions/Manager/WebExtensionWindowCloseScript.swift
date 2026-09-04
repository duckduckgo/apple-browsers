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

/// JavaScript injected at document start into every page an extension owns, which reports a
/// `window.close()` call to the browser before WebKit acts on it.
///
/// An action popup closes itself with `window.close()` once it has done its job — 1Password does
/// so after "Open & Fill" and after "Lock". Chrome then dismisses the popup. WebKit reacts too, but
/// only on its own terms: `WKWebExtension.Action` closes the popover *it* would have shown and
/// unloads the popup web view. A browser that hosts that web view in a panel of its own, as the
/// macOS app does, is not told, and is left with an empty panel. The public API offers no
/// notification for the dismissal, so the page reports the call itself through a script message.
///
/// The script does nothing on a page with no `webkit.messageHandlers` entry of the expected name,
/// so a platform that never registers `WebExtensionWindowCloseMessageHandler` is unaffected.
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

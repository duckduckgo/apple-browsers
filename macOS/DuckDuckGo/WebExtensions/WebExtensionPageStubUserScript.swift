//
//  WebExtensionPageStubUserScript.swift
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
import UserScript
import WebExtensions
import WebKit

/// Installs the third-party extension scripts (`WebExtensionAPICompatibilityScript` and
/// `WebExtensionAPIStubScript`) in tab web views, so they reach extension pages that the tab's own
/// web view configuration hosts.
///
/// `WebExtensionLoader` installs these scripts on the extension controller's web view
/// configuration, which covers the pages WebKit creates for an extension: its background page,
/// action popup, options page and the iframes inside them. A tab built from that configuration
/// (a popup that pops out into a window, for instance) goes through the app's standard
/// configuration, which replaces the user content controller, so the controller's scripts never
/// run there. Without the stubs, Bitwarden's pop-out hangs on the first API WebKit lacks.
///
/// The scripts run in every frame of every tab, but return right away unless the frame is an
/// extension page (`webkit-extension:`), so ordinary web content is untouched.
@available(macOS 15.4, *)
final class WebExtensionPageStubUserScript: NSObject, UserScript, WKScriptMessageHandlerWithReply {

    /// Finds the tab a frame that asks to open the action popup belongs to.
    private weak var windowControllersManager: WindowControllersManagerProtocol?

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    /// Third-party extensions can only be installed by internal users, so nobody else needs the
    /// script.
    static func make(isInternalUser: Bool, windowControllersManager: WindowControllersManagerProtocol) -> WebExtensionPageStubUserScript? {
        isInternalUser ? WebExtensionPageStubUserScript(windowControllersManager: windowControllersManager) : nil
    }

    /// The same scripts, in the same order, as `WebExtensionLoader` installs on the controller.
    var source: String {
        WebExtensionLoader.thirdPartyScriptSources.joined(separator: "\n")
    }

    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly: Bool = false

    /// The extension's own scripts run in the page world of an extension frame, and that is where
    /// `chrome` exists, so the stubs must be installed in that world. The isolated world
    /// DuckDuckGo uses for its own scripts would not be seen by the extension.
    let requiresRunInPageContentWorld: Bool = true

    /// The scripts report the unsupported APIs an extension touches through the first handler, ask
    /// for the `chrome.idle` state through the second, keep `chrome.privacy` settings through the
    /// third, ask about app permissions through the fourth and open the action popup from a frame
    /// embedded in a website through the fifth; the last four answer.
    let messageNames: [String] = [WebExtensionAPICompatibilityScript.messageHandlerName,
                                  WebExtensionAPIStubScript.idleMessageHandlerName,
                                  WebExtensionAPIStubScript.privacyMessageHandlerName,
                                  WebExtensionAPIStubScript.permissionsMessageHandlerName,
                                  WebExtensionAPIStubScript.actionOpenPopupMessageHandlerName]

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        (NSApp.delegateTyped.webExtensionManager as? WebExtensionManager)?.handleAPICompatibilityMessage(message)
    }

    /// A script registered with a reply handler receives all its messages here, so the compatibility
    /// reports, which expect no answer, are acknowledged with an empty one.
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let manager = NSApp.delegateTyped.webExtensionManager as? WebExtensionManager else {
            replyHandler(nil, "Web extensions are unavailable")
            return
        }
        if message.name == WebExtensionAPIStubScript.idleMessageHandlerName {
            manager.handleIdleMessage(message, replyHandler: replyHandler)
        } else if message.name == WebExtensionAPIStubScript.privacyMessageHandlerName {
            manager.handlePrivacyMessage(message, replyHandler: replyHandler)
        } else if message.name == WebExtensionAPIStubScript.permissionsMessageHandlerName {
            manager.handlePermissionsMessage(message, replyHandler: replyHandler)
        } else if message.name == WebExtensionAPIStubScript.actionOpenPopupMessageHandlerName {
            let tab = windowControllersManager?.tab(for: message.webView)
            manager.handleActionOpenPopupMessage(message, tab: tab, replyHandler: replyHandler)
        } else {
            manager.handleAPICompatibilityMessage(message)
            replyHandler(nil, nil)
        }
    }
}

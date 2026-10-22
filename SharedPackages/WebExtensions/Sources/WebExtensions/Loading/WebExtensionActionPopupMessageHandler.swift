//
//  WebExtensionActionPopupMessageHandler.swift
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

import Foundation
import WebKit

/// Opens the action popup for `chrome.action.openPopup()` calls the API stub script forwards from an
/// extension page embedded in a website, such as iCloud Passwords' completion list.
///
/// That frame runs in the website's web process, where WebKit treats a native `openPopup` call as an
/// invalid message and terminates the process. The app performs the extension's action for the tab
/// instead, as a click on its toolbar button does. Only pages of a loaded extension are answered.
@available(macOS 15.4, *)
final class WebExtensionActionPopupMessageHandler {

    enum Failure: String, Error {
        case notAnExtensionPage = "The caller is not a page of a loaded extension"
        case noTab = "The caller is not in a tab"
    }

    private static let extensionScheme = "webkit-extension"

    /// The loaded extension context the page URL belongs to.
    @MainActor var extensionContext: (URL) -> WKWebExtensionContext? = { _ in nil }

    /// Opens the popup the way the toolbar button does.
    @MainActor var performAction: (WKWebExtensionContext, any WKWebExtensionTab) -> Void = { context, tab in
        context.performAction(for: tab)
    }

    @MainActor
    func reply(to message: WKScriptMessage, tab: (any WKWebExtensionTab)?, replyHandler: @escaping (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        do {
            try openPopup(originProtocol: origin.protocol, originHost: origin.host, tab: tab)
            replyHandler(NSNull(), nil)
        } catch {
            replyHandler(nil, error.rawValue)
        }
    }

    @MainActor
    func openPopup(originProtocol: String, originHost: String, tab: (any WKWebExtensionTab)?) throws(Failure) {
        guard originProtocol == Self.extensionScheme,
              !originHost.isEmpty,
              let url = URL(string: "\(Self.extensionScheme)://\(originHost)/"),
              let context = extensionContext(url) else {
            throw .notAnExtensionPage
        }
        guard let tab else { throw .noTab }
        performAction(context, tab)
    }
}

#endif

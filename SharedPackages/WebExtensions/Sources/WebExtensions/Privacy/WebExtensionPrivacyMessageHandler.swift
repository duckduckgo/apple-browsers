//
//  WebExtensionPrivacyMessageHandler.swift
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

/// Answers the `chrome.privacy.services` calls the API stub script makes for an extension page.
///
/// The script sends `{action: "get" | "set" | "clear", setting, value}`. `get` answers
/// `{value, levelOfControl}`; `set` and `clear` answer `null`, and a `set` the extension may not make
/// is rejected. Only pages of a loaded extension are answered, so a website can't reach the settings.
@available(macOS 15.4, *)
final class WebExtensionPrivacyMessageHandler: NSObject, WKScriptMessageHandlerWithReply {

    private static let extensionScheme = "webkit-extension"
    private static let rejectedReason = "Not a loaded extension page"
    private static let invalidReason = "Invalid privacy setting request"
    private static let notControllableReason = "The extension can't control this setting"

    /// The installation identifier of the loaded extension that the page URL belongs to.
    @MainActor var extensionIdentifier: (URL) -> String? = { _ in nil }

    /// The store the settings go to. Without one every request is rejected.
    @MainActor var store: WebExtensionPrivacySettingsStore?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        // WebKit delivers script messages on the main thread.
        MainActor.assumeIsolated {
            reply(to: message, replyHandler: replyHandler)
        }
    }

    @MainActor
    func reply(to message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.name == WebExtensionAPIStubScript.privacyMessageHandlerName else {
            replyHandler(nil, Self.rejectedReason)
            return
        }
        let origin = message.frameInfo.securityOrigin
        let result = answer(body: message.body, originProtocol: origin.protocol, originHost: origin.host)
        replyHandler(result.reply, result.error)
    }

    @MainActor
    func answer(body: Any, originProtocol: String, originHost: String) -> (reply: Any?, error: String?) {
        guard originProtocol == Self.extensionScheme,
              !originHost.isEmpty,
              let url = URL(string: "\(Self.extensionScheme)://\(originHost)/"),
              let identifier = extensionIdentifier(url),
              let store else {
            return (nil, Self.rejectedReason)
        }
        guard let request = body as? [String: Any],
              let action = request["action"] as? String,
              let settingName = request["setting"] as? String,
              let setting = WebExtensionPrivacySetting(rawValue: settingName) else {
            return (nil, Self.invalidReason)
        }

        switch action {
        case "get":
            let details = store.details(of: setting, for: identifier)
            return (["value": details.value, "levelOfControl": details.levelOfControl.rawValue], nil)
        case "set":
            guard let value = request["value"] as? Bool else { return (nil, Self.invalidReason) }
            return store.set(value, for: setting, by: identifier) ? (NSNull(), nil) : (nil, Self.notControllableReason)
        case "clear":
            store.clear(setting, for: identifier)
            return (NSNull(), nil)
        default:
            return (nil, Self.invalidReason)
        }
    }
}

#endif

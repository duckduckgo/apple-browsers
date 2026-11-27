//
//  WebExtensionBadgeColorMessageHandler.swift
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

/// Hears the badge colors the API stub script relays on behalf of `action.setBadgeBackgroundColor` and
/// `action.setBadgeTextColor`: WebKit accepts the first without passing the color on, and lacks the second.
///
/// The script sends `{kind: "background" | "text", color: "#rrggbb"}` and expects no answer. An empty color
/// restores the default. Only pages of a loaded extension are heard. Without a store the colors are dropped.
@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionBadgeColorMessageHandler: NSObject, WKScriptMessageHandler {

    private static let extensionScheme = "webkit-extension"
    private static let kindKey = "kind"
    private static let colorKey = "color"

    private enum Kind: String {
        case background
        case text
    }

    @MainActor var extensionContext: (URL) -> WKWebExtensionContext? = { _ in nil }
    @MainActor var store: WebExtensionBadgeColorStore?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // WebKit delivers script messages on the main thread.
        MainActor.assumeIsolated {
            receive(message)
        }
    }

    @MainActor
    func receive(_ message: WKScriptMessage) {
        guard message.name == WebExtensionAPIStubScript.badgeColorMessageHandlerName else { return }
        let origin = message.frameInfo.securityOrigin
        update(body: message.body, originProtocol: origin.protocol, originHost: origin.host)
    }

    @MainActor
    func update(body: Any, originProtocol: String, originHost: String) {
        guard originProtocol == Self.extensionScheme,
              !originHost.isEmpty,
              let url = URL(string: "\(Self.extensionScheme)://\(originHost)/"),
              let context = extensionContext(url),
              let store,
              let request = body as? [String: Any],
              let kindName = request[Self.kindKey] as? String,
              let kind = Kind(rawValue: kindName),
              let hex = request[Self.colorKey] as? String else {
            return
        }
        let color = hex.isEmpty ? nil : hex

        let didChange = switch kind {
        case .background:
            store.setBackgroundColor(color, for: context)
        case .text:
            store.setTextColor(color, for: context)
        }

        if didChange {
            NotificationCenter.default.post(name: .webExtensionActionDidChange, object: context)
        }
    }
}

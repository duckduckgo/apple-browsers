//
//  WebExtensionPermissionsMessageHandler.swift
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

/// Answers the `chrome.permissions` calls the API stub script makes for app permissions, the ones WebKit
/// doesn't know (see `WebExtensionAppPermission`).
///
/// The script sends `{action: "contains" | "request" | "remove", permissions: [name]}` and hears `true`
/// or `false`, or `{action: "getAll"}` and hears the names held. It never hears an error, so a caller
/// waiting on a callback always gets one. Only pages of a loaded extension are answered, and without a
/// permission controller nothing is held or granted.
@available(macOS 15.4, *)
final class WebExtensionPermissionsMessageHandler: NSObject, WKScriptMessageHandlerWithReply {

    private static let extensionScheme = "webkit-extension"

    /// The loaded extension context the page URL belongs to.
    @MainActor var extensionContext: (URL) -> WKWebExtensionContext? = { _ in nil }

    /// Where the permissions are asked for and kept.
    @MainActor var controller: WebExtensionPermissionController?

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
        guard message.name == WebExtensionAPIStubScript.permissionsMessageHandlerName else {
            replyHandler(false, nil)
            return
        }
        let origin = message.frameInfo.securityOrigin
        Task { @MainActor in
            replyHandler(await answer(body: message.body, originProtocol: origin.protocol, originHost: origin.host), nil)
        }
    }

    @MainActor
    func answer(body: Any, originProtocol: String, originHost: String) async -> Any {
        let request = body as? [String: Any]
        let action = request?["action"] as? String
        let refusal: Any = action == "getAll" ? [String]() : false
        guard originProtocol == Self.extensionScheme,
              !originHost.isEmpty,
              let url = URL(string: "\(Self.extensionScheme)://\(originHost)/"),
              let context = extensionContext(url),
              let controller else {
            return refusal
        }

        if action == "getAll" {
            return WebExtensionAppPermission.allCases
                .filter { controller.isGranted($0, to: context.uniqueIdentifier) }
                .map(\.rawValue)
        }
        let names = request?["permissions"] as? [String] ?? []
        let permissions = names.compactMap(WebExtensionAppPermission.init(rawValue:))
        guard !permissions.isEmpty, permissions.count == names.count else { return false }

        switch action {
        case "contains":
            return permissions.allSatisfy { controller.isGranted($0, to: context.uniqueIdentifier) }
        case "request":
            return await controller.request(WebExtensionPermissionRequest(appPermissions: Set(permissions)), for: context)
        case "remove":
            return permissions.allSatisfy { controller.revoke($0, from: context) }
        default:
            return false
        }
    }
}

#endif

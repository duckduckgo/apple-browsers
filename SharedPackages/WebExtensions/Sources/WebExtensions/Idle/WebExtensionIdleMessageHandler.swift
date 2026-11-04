//
//  WebExtensionIdleMessageHandler.swift
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

/// Answers the idle state the API stub script asks for on behalf of `chrome.idle.queryState`.
///
/// The script sends `{detectionInterval}` in seconds and expects `"active"`, `"idle"` or `"locked"`
/// back. Only extension pages that belong to a loaded extension are answered; the page treats a
/// rejected request as `active`.
@available(macOS 15.4, *)
final class WebExtensionIdleMessageHandler: NSObject, WKScriptMessageHandlerWithReply {

    private static let extensionScheme = "webkit-extension"
    private static let rejectedReason = "Not a loaded extension page"

    /// Whether the given extension page URL belongs to a loaded extension.
    var isLoadedExtension: (URL) -> Bool = { _ in false }

    private let stateProvider: WebExtensionIdleStateProvider

    init(stateProvider: WebExtensionIdleStateProvider = WebExtensionIdleStateProvider()) {
        self.stateProvider = stateProvider
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        reply(to: message, replyHandler: replyHandler)
    }

    func reply(to message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.name == WebExtensionAPIStubScript.idleMessageHandlerName else {
            replyHandler(nil, Self.rejectedReason)
            return
        }
        let origin = message.frameInfo.securityOrigin
        guard let state = state(body: message.body, originProtocol: origin.protocol, originHost: origin.host) else {
            replyHandler(nil, Self.rejectedReason)
            return
        }
        replyHandler(state.rawValue, nil)
    }

    func state(body: Any, originProtocol: String, originHost: String) -> WebExtensionIdleState? {
        guard originProtocol == Self.extensionScheme,
              !originHost.isEmpty,
              let url = URL(string: "\(Self.extensionScheme)://\(originHost)/"),
              isLoadedExtension(url) else {
            return nil
        }
        let seconds = (body as? [String: Any])?["detectionInterval"] as? Double
        return stateProvider.state(detectionInterval: seconds ?? WebExtensionIdleStateProvider.defaultDetectionInterval)
    }
}

#endif

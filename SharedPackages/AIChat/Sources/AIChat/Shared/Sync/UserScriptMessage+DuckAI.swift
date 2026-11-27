//
//  UserScriptMessage+DuckAI.swift
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
import WebKit

extension UserScriptMessage {

    /// Returns `true` if the message was sent by the main frame of an https duck.ai page.
    ///
    /// The aiChat script accepts messages from any duckduckgo.com page, so handlers exposing
    /// sync secrets use this to narrow the sender to Duck.ai itself. The check reads the sending
    /// frame's security origin, not the web view's URL: a page can change its own URL with
    /// `history.replaceState`, and the web view's URL can belong to a page that hasn't loaded yet.
    ///
    /// - Parameter customHostname: Debug-only hostname that is also treated as Duck.ai, over any
    ///   scheme so a local http server works.
    @MainActor
    public func isFromDuckAIMainFrame(customHostname: String? = nil) -> Bool {
        guard let frame = (self as? WKScriptMessage)?.frameInfo, frame.isMainFrame else {
            return false
        }
        let origin = frame.securityOrigin
        let host = origin.host.lowercased()
        if let customHostname, !customHostname.isEmpty, host == customHostname.lowercased() {
            return true
        }
        return origin.protocol.lowercased() == "https" && host == URL.duckAIHost
    }
}

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

extension UserScriptMessage {

    /// Returns `true` if the message was sent by the main frame of an https Duck.ai page.
    ///
    /// The aiChat script accepts messages from any duckduckgo.com page, so handlers exposing
    /// sync secrets use this to narrow the sender to Duck.ai itself.
    ///
    /// - Parameter customHostname: Debug-only hostname that is also treated as Duck.ai.
    @MainActor
    public func isFromDuckAIMainFrame(customHostname: String? = nil) -> Bool {
        guard isMainFrame,
              let url = messageWebView?.url,
              url.scheme?.lowercased() == "https" else {
            return false
        }
        if url.isDuckAIURL {
            return true
        }
        guard let customHostname, !customHostname.isEmpty, let host = url.host else {
            return false
        }
        return host.lowercased() == customHostname.lowercased()
    }
}

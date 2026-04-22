//
//  DuckAiNativeStorageBootstrapScriptRefresher.swift
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
import os.log
import UserScript
import WebKit

/// Rebuilds `DuckAiNativeStorageBootstrapUserScript` with a current snapshot of native storage
/// and reinstalls it on a `WKUserContentController` alongside the caller-provided static scripts.
///
/// Needed because `WKUserScript.source` is frozen at creation time: a bootstrap installed once at
/// tab setup goes stale as soon as the FE writes new entry values, causing a flash on reload.
/// Callers should invoke `refresh(on:staticScripts:)` before each navigation to Duck.ai.
public final class DuckAiNativeStorageBootstrapScriptRefresher {

    private let handler: DuckAiNativeStorageHandling
    private let originRules: [HostnameMatchingRule]

    public init(handler: DuckAiNativeStorageHandling, originRules: [HostnameMatchingRule]) {
        self.handler = handler
        self.originRules = originRules
    }

    /// Returns `true` when `url`'s host matches any of the configured origin rules — use this to
    /// decide whether a navigation needs a bootstrap refresh. Mirrors the guard embedded in the
    /// script's JS so the Swift-side scope check and the runtime scope check stay in sync.
    public func isInScope(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return originRules.contains { rule in
            switch rule {
            case .exact(let ruleHost):
                return host == ruleHost.lowercased()
            case .exactOrSubdomain(let ruleHost), .etldPlus1(let ruleHost):
                let lowered = ruleHost.lowercased()
                return host == lowered || host.hasSuffix("." + lowered)
            }
        }
    }

    /// Wipes all user scripts from `userContentController`, reinstalls the provided static scripts,
    /// then appends a freshly built bootstrap script with the current native storage snapshot.
    @MainActor
    public func refresh(on userContentController: WKUserContentController, staticScripts: [WKUserScript]) {
        let bootstrap = DuckAiNativeStorageBootstrapUserScript(handler: handler, allowedOrigins: originRules)
        let wkBootstrap = bootstrap.makeWKUserScriptSync()

        userContentController.removeAllUserScripts()
        for script in staticScripts {
            userContentController.addUserScript(script)
        }
        userContentController.addUserScript(wkBootstrap)
        Logger.aiChat.debug("[NativeStorage] Bootstrap script refreshed (\(staticScripts.count) static scripts preserved)")
    }
}

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
/// and swaps it in for the previously installed bootstrap on a `WKUserContentController`.
///
/// Needed because `WKUserScript.source` is frozen at creation time: a bootstrap installed once at
/// tab setup goes stale as soon as the FE writes new entry values, causing a flash on reload.
/// Callers should invoke `refresh(on:staticScripts:)` before each navigation to Duck.ai.
public final class DuckAiNativeStorageBootstrapScriptRefresher {

    private static let unavailableFireModeHandler: DuckAiNativeStorageHandling = NullDuckAiNativeStorageHandler()

    private let diskHandler: DuckAiNativeStorageHandling
    private let originRules: [HostnameMatchingRule]
    private var didLogUnavailableFireModeHandler = false
    /// The bootstrap installed by the last `refresh`, removed (and only it) on the next one.
    private weak var installedBootstrap: WKUserScript?

    /// Returns the fire-mode storage state for the surrounding webview.
    /// `.notFireMode` uses the normal on-disk store, `.available` uses the isolated
    /// fire-mode handler, and `.unavailable` resolves to empty storage rather than
    /// falling back to disk.
    public var fireModeStorageProvider: (() -> DuckAiFireModeStorage)?

    private var handler: DuckAiNativeStorageHandling {
        switch fireModeStorageProvider?() ?? .notFireMode {
        case .notFireMode:
            return diskHandler
        case .unavailable:
            if !didLogUnavailableFireModeHandler {
                didLogUnavailableFireModeHandler = true
                Logger.aiChat.error("[NativeStorage] Fire-mode handler unavailable; using null storage to preserve mode isolation")
            }
            return Self.unavailableFireModeHandler
        case .available(let fireModeHandler):
            return fireModeHandler
        }
    }

    public init(handler: DuckAiNativeStorageHandling,
                originRules: [HostnameMatchingRule]) {
        self.diskHandler = handler
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

    /// Returns `true` when a navigation should refresh the bootstrap: only main-frame navigations to
    /// an https URL in scope. Subframe navigations must not trigger a refresh, since any page can
    /// embed a Duck.ai frame.
    public func shouldRefresh(navigatingTo url: URL, isForMainFrame: Bool) -> Bool {
        guard isForMainFrame, url.scheme?.lowercased() == "https" else { return false }
        return isInScope(url: url)
    }

    /// Replaces the previously installed bootstrap script with a freshly built one carrying the current
    /// native storage snapshot, re-adding any of the provided static scripts that are missing.
    ///
    /// Other user scripts (e.g. web extension content scripts, which WebKit installs only once per
    /// controller) are left in place. Only if the targeted-removal API is unavailable does this fall
    /// back to wiping all user scripts and reinstalling the static scripts.
    @MainActor
    public func refresh(on userContentController: WKUserContentController, staticScripts: [WKUserScript]) {
        let bootstrap = DuckAiNativeStorageBootstrapUserScript(handler: handler, allowedOrigins: originRules)
        let wkBootstrap = bootstrap.makeWKUserScriptSync()

        if Self.removeUserScriptSupported(by: userContentController) {
            if let installedBootstrap {
                userContentController.perform(NSSelectorFromString(Self.removeUserScriptSelector), with: installedBootstrap)
            }
            let installedScripts = userContentController.userScripts
            for script in staticScripts where !installedScripts.contains(where: { $0 === script }) {
                userContentController.addUserScript(script)
            }
        } else {
            userContentController.removeAllUserScripts()
            for script in staticScripts {
                userContentController.addUserScript(script)
            }
        }
        userContentController.addUserScript(wkBootstrap)
        installedBootstrap = wkBootstrap
        Logger.aiChat.debug("[NativeStorage] Bootstrap script refreshed (\(staticScripts.count) static scripts preserved)")
    }

    /// Private `WKUserContentController` API also used by BSK's `UserContentController` to remove a
    /// single user script without wiping web extension scripts.
    static let removeUserScriptSelector = "_removeUserScript:"

    static func removeUserScriptSupported(by userContentController: WKUserContentController) -> Bool {
#if os(macOS)
        userContentController.responds(to: NSSelectorFromString(removeUserScriptSelector))
#else
        false
#endif
    }
}

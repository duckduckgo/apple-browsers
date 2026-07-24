//
//  WebExtensionUnloadGuard.swift
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
import WebKit

/// Workaround for a WebKit crash when unloading a web extension that uses declarativeNetRequest
/// (https://bugs.webkit.org/show_bug.cgi?id=305585).
///
/// Loading an extension context starts a fire-and-forget read of its declarativeNetRequest rules
/// on a background queue. Unloading the context destroys the SQLite store that read uses, and a
/// store torn down while the read is still queued invokes the completion callback with a null
/// rules array, which WebKit dereferences — crashing the app. The bug is fixed upstream
/// (https://commits.webkit.org/305661@main) but the fix has not shipped in any macOS 26.x WebKit.
///
/// The guard closes the race with a "settle window": callers record every successful extension
/// load (`recordLoad(of:)`) and, before unloading or reloading an extension that requests
/// declarativeNetRequest, wait until at least `settleWindow` has passed since that extension's
/// load (`awaitSettled(_:)`). Extensions without the permission never trigger the vulnerable
/// rules read, so the guard lets them pass immediately — as it does any extension loaded longer
/// than the window.
///
/// Remove this type (and its call sites in `WebExtensionManager`) once the minimum supported
/// macOS ships the WebKit fix.
///
/// Tracked in https://app.asana.com/1/137249556945/project/1201037661562251/task/1216821343663926
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionUnloadGuard {

    /// How long an extension that requests declarativeNetRequest must stay loaded before it may
    /// be unloaded. The largest load-to-crash gap observed in crash reports was ~1.5s (perf-CI,
    /// Jul 2026); doubled as a safety factor.
    nonisolated static let defaultSettleWindow: TimeInterval = 3

    private static let dnrPermissions: Set<WKWebExtension.Permission> = [
        WKWebExtension.Permission("declarativeNetRequest"),
        WKWebExtension.Permission("declarativeNetRequestWithHostAccess"),
    ]

    private let settleWindow: TimeInterval
    private let now: () -> Date
    private let sleeper: (TimeInterval) async -> Void

    /// Most recent successful load time per extension identifier.
    private var lastLoadDates: [String: Date] = [:]

    init(settleWindow: TimeInterval = WebExtensionUnloadGuard.defaultSettleWindow,
         now: @escaping () -> Date = Date.init,
         sleeper: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.settleWindow = settleWindow
        self.now = now
        self.sleeper = sleeper
    }

    /// Records a successful load of the extension so `awaitSettled(_:)` can measure how long it
    /// has been loaded.
    func recordLoad(of identifier: String) {
        lastLoadDates[identifier] = now()
    }

    /// Suspends until the extension behind `context` has been loaded for at least `settleWindow`.
    /// Returns immediately when the extension doesn't request declarativeNetRequest, isn't loaded
    /// (`context` is nil), or has no recorded load.
    ///
    /// Deliberately not applied to the synchronous unload paths (`unloadAllExtensions`,
    /// user-initiated `uninstallExtension`): those cannot await, and in practice they run long
    /// after the extension was loaded.
    func awaitSettled(_ context: WKWebExtensionContext?) async {
        guard let context,
              !Self.dnrPermissions.isDisjoint(with: context.webExtension.requestedPermissions),
              let loadDate = lastLoadDates[context.uniqueIdentifier] else { return }

        let remaining = settleWindow - now().timeIntervalSince(loadDate)
        guard remaining > 0 else { return }

        Logger.webExtensions.debug("⏸️ Delaying unload of '\(context.uniqueIdentifier)' by \(remaining)s for WebKit's in-flight declarativeNetRequest load")
        await sleeper(remaining)
    }
}

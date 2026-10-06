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

/// Delays unloading a declarativeNetRequest extension until shortly after it loads, to avoid a
/// WebKit crash: unloading one while WebKit is still reading its rules dereferences a null and
/// crashes the app. Fixed upstream but not yet in any shipping macOS 26.x.
///
/// Callers record each load with `recordLoad(of:)`, then call `awaitSettled(_:)` before unloading.
///
/// Remove once the minimum supported macOS ships the fix.
/// - WebKit bug: https://bugs.webkit.org/show_bug.cgi?id=305585 (fix: https://commits.webkit.org/305661@main)
/// - Tracked in: https://app.asana.com/1/137249556945/project/1201037661562251/task/1216821343663926
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionUnloadGuard {

    /// Minimum time a declarativeNetRequest extension must stay loaded before it may be unloaded.
    /// The largest load-to-crash gap seen in crash reports was ~1.5s; doubled for safety.
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

    /// Deliberately not `Task.sleep`: cancellation would skip the wait and unload inside the danger
    /// window, and teardown — the very thing that cancels — is when unloads happen.
    private static func sleep(for seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                continuation.resume()
            }
        }
    }

    init(settleWindow: TimeInterval = WebExtensionUnloadGuard.defaultSettleWindow,
         now: @escaping () -> Date = Date.init,
         sleeper: @escaping (TimeInterval) async -> Void = { await WebExtensionUnloadGuard.sleep(for: $0) }) {
        self.settleWindow = settleWindow
        self.now = now
        self.sleeper = sleeper
    }

    /// Records when the extension finished loading, so `awaitSettled(_:)` can tell how long ago.
    func recordLoad(of identifier: String) {
        lastLoadDates[identifier] = now()
    }

    /// Waits until the extension has been loaded for at least `settleWindow`. Returns immediately
    /// when it doesn't use declarativeNetRequest, isn't loaded, or loaded long enough ago.
    ///
    /// Not applied to the synchronous unload paths (`unloadAllExtensions`, `uninstallExtension`):
    /// they can't await, and in practice run long after the load.
    func awaitSettled(_ context: WKWebExtensionContext?) async {
        guard let context, usesDeclarativeNetRequest(context),
              let loadDate = lastLoadDates[context.uniqueIdentifier] else { return }

        let elapsed = now().timeIntervalSince(loadDate)
        let remaining = settleWindow - elapsed
        guard remaining > 0 else { return }

        Logger.webExtensions.debug("⏸️ Delaying unload of '\(context.uniqueIdentifier)' by \(remaining)s for WebKit's in-flight declarativeNetRequest load")
        await sleeper(remaining)
    }

    private func usesDeclarativeNetRequest(_ context: WKWebExtensionContext) -> Bool {
        let requested = context.webExtension.requestedPermissions
        return Self.dnrPermissions.contains { requested.contains($0) }
    }
}

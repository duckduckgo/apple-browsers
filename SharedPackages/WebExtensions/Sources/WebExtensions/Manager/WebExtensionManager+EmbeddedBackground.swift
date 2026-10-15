//
//  WebExtensionManager+EmbeddedBackground.swift
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

// MARK: - Embedded background readiness

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager {

    /// Prepares the embedded background for a main-frame navigation that is about to start.
    ///
    /// Returns a waiter while a newly installed embedded extension is still loading its background
    /// for the first time. WebKit loads that background eagerly and drops content-script messages
    /// that arrive before its script has run, so the navigation must not start until the load
    /// completes.
    @MainActor
    public func prepareEmbeddedBackgroundForNavigation() -> WebExtensionInitialLoadWaiter? {
        guard let startup = embeddedBackgroundStartup else { return nil }
        return { await startup.value }
    }

    /// Records the first background load of an embedded extension installed under a new identifier
    /// (first install or upgrade), at any time during the session. During an upgrade the previous
    /// version is still loaded, so this waits for the new context specifically.
    @MainActor
    func trackEmbeddedBackgroundStartup(identifier: String) {
        guard let context = context(for: identifier), context.webExtension.hasBackgroundContent else { return }
        let startup = Task<Void, Never> { @MainActor in
            do {
                try await context.loadBackgroundContent()
            } catch {
                Logger.webExtensions.error("❌ Failed to load background content of embedded extension '\(identifier)': \(error.localizedDescription)")
            }
        }
        embeddedBackgroundStartup = startup
        Task { @MainActor [weak self] in
            await startup.value
            guard self?.embeddedBackgroundStartup == startup else { return }
            self?.embeddedBackgroundStartup = nil
        }
    }
}

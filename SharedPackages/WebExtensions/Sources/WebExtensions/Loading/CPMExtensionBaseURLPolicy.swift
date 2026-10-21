//
//  CPMExtensionBaseURLPolicy.swift
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

/// Keeps the CPM origin stable across context reloads without making it predictable across installations.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMExtensionBaseURLPolicy {
    private let installationStore: InstalledWebExtensionStoring
    private let isEnabled: @MainActor () -> Bool
    private let failedBackgroundContexts = NSHashTable<WKWebExtensionContext>.weakObjects()
    // A first install has not reached the persistent registry when the loader creates its context.
    var pendingInstallations: [String: DuckDuckGoWebExtensionType] = [:]

    init(installationStore: InstalledWebExtensionStoring, isEnabled: @escaping @MainActor () -> Bool) {
        self.installationStore = installationStore
        self.isEnabled = isEnabled
    }

    func baseURL(for identifier: String, webExtension: WKWebExtension) -> URL? {
        guard let uuid = originIdentifier(for: identifier, webExtension: webExtension) else { return nil }
        guard isEnabled() else {
            // WebKit removes the old origin's service-worker data when migrating to its random origin.
            // Re-enabling must use a fresh origin, never that abandoned worker registration.
            if let installed = installationStore.installedExtension(withUniqueIdentifier: identifier) {
                rotateOrigin(of: installed)
            }
            return nil
        }
        return URL(string: "webkit-extension://\(uuid.uuidString.lowercased())/")
    }

    /// WebKit can retain a stale service-worker registration after website data is cleared.
    /// Rotate only for the data-clearing lifecycle, and persist the new origin for subsequent launches/reloads.
    func prepareForDataClearingReload(of context: WKWebExtensionContext) {
        rotateOrigin(of: context)
    }

    /// Save a fresh origin before retry/reload can be skipped or the app can terminate.
    /// The live context keeps its origin. Repeated errors from it must preserve the saved replacement.
    func recordBackgroundLoadFailure(in context: WKWebExtensionContext, errors: [Error]) {
        guard isEnabled(), !failedBackgroundContexts.contains(context), errors.contains(where: {
            let error = $0 as NSError
            return error.domain == WKWebExtensionContext.errorDomain &&
                error.code == WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue
        }) else { return }
        if rotateOrigin(of: context) {
            failedBackgroundContexts.add(context)
        }
    }

    @discardableResult
    private func rotateOrigin(of context: WKWebExtensionContext) -> Bool {
        let identifier = context.uniqueIdentifier
        guard originIdentifier(for: identifier, webExtension: context.webExtension) != nil,
              let installed = installationStore.installedExtension(withUniqueIdentifier: identifier) else { return false }
        rotateOrigin(of: installed)
        return true
    }

    private func rotateOrigin(of installed: InstalledWebExtension) {
        installationStore.update(InstalledWebExtension(
            uniqueIdentifier: installed.uniqueIdentifier, filename: installed.filename, name: installed.name, version: installed.version,
            embeddedType: installed.embeddedType, storeIdentity: installed.storeIdentity, cpmOriginIdentifier: UUID()
        ))
    }

    private func originIdentifier(for identifier: String, webExtension: WKWebExtension) -> UUID? {
        let installed = installationStore.installedExtension(withUniqueIdentifier: identifier)
        guard (pendingInstallations[identifier] ?? installed?.embeddedType) == .embedded,
              webExtension.duckDuckGoWebExtensionType == .embedded,
              let uuid = UUID(uuidString: identifier) else { return nil }

        // Never stabilize a web-observable resource origin, even if a future bundled version adds resources.
        if let resources = webExtension.manifest["web_accessible_resources"] {
            guard let resources = resources as? [Any], resources.isEmpty else { return nil }
        }

        return installed?.cpmOriginIdentifier ?? uuid
    }
}

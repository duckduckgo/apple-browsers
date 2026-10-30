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
    private let isSupportedOS: @MainActor () -> Bool
    private let failedBackgroundContexts = NSHashTable<WKWebExtensionContext>.weakObjects()
    // A first install has not reached the persistent registry when the loader creates its context.
    var pendingInstallations: [String: DuckDuckGoWebExtensionType] = [:]
    // Carries an upgrade's origin while its replacement loads, before the new registry record exists.
    var pendingOriginIdentifiers: [String: UUID] = [:]

    /// The caller must ensure the previous installation has no live context before carrying its origin.
    func originForUpgrade(of installed: InstalledWebExtension) -> UUID? {
        guard isEnabled(), installed.embeddedType == .embedded else { return nil }
        return installed.cpmOriginIdentifier ?? UUID(uuidString: installed.uniqueIdentifier)
    }

    init(installationStore: InstalledWebExtensionStoring,
         isEnabled: @escaping @MainActor () -> Bool,
         isSupportedOS: @escaping @MainActor () -> Bool = {
             if #available(macOS 26.6, iOS 26.6, *) { return true }
             return false
         }) {
        self.installationStore = installationStore
        self.isEnabled = isEnabled
        self.isSupportedOS = isSupportedOS
    }

    /// The stable origin is only used on macOS and iOS 26.6 and later. Older releases use WebKit's random origin.
    func baseURL(for identifier: String, webExtension: WKWebExtension) -> URL? {
        guard let uuid = originIdentifier(for: identifier, webExtension: webExtension) else {
            // If this manifest no longer permits a stable origin, do not save the inherited one.
            // A later private version must not revive the abandoned service-worker registration.
            pendingOriginIdentifiers[identifier] = nil
            return nil
        }
        guard isSupportedOS(), isEnabled() else {
            // Moving to WebKit's random origin leaves this origin's service-worker registration behind.
            // Re-enabling or updating the OS must use a fresh origin, never that abandoned registration.
            if let installed = installationStore.installedExtension(withUniqueIdentifier: identifier) {
                rotateOrigin(of: installed)
            } else if pendingOriginIdentifiers[identifier] != nil {
                // An upgrade may not be in the registry yet. Do not persist its abandoned origin.
                pendingOriginIdentifiers[identifier] = UUID()
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
        guard isSupportedOS(), isEnabled(), !failedBackgroundContexts.contains(context),
              errors.contains(where: { NSError.webKitSafe($0).isBackgroundContentLoadFailure }) else { return }
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
        var updated = installed
        updated.cpmOriginIdentifier = UUID()
        installationStore.update(updated)
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

        // Recovery may already have saved a replacement origin while installation was pending.
        // Its persistent value must take precedence over the inherited pending origin.
        return installed?.cpmOriginIdentifier ?? pendingOriginIdentifiers[identifier] ?? uuid
    }
}

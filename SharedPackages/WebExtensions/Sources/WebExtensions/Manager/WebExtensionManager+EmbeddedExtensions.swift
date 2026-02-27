//
//  WebExtensionManager+EmbeddedExtensions.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

// MARK: - Embedded Extensions

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager {

    /// Syncs embedded extensions from the registry based on the enabled types.
    /// Installs/upgrades enabled extensions and uninstalls disabled ones.
    /// Call this after `loadInstalledExtensions()`.
    /// - Parameter enabledTypes: The set of extension types that should be installed.
    ///   Extensions not in this set will be uninstalled if previously installed.
    @MainActor
    public func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {
        Logger.webExtensions.debug("🔄 Syncing embedded extensions...")

        for descriptor in EmbeddedWebExtensionRegistry.all {
            if enabledTypes.contains(descriptor.type) {
                await syncEmbeddedExtension(descriptor)
            } else {
                uninstallEmbeddedExtension(type: descriptor.type)
            }
        }

        Logger.webExtensions.debug("✅ Embedded extensions sync completed")
    }

    /// Uninstalls an embedded extension of the given type if it's currently installed.
    /// - Parameter type: The type of embedded extension to uninstall.
    public func uninstallEmbeddedExtension(type: DuckDuckGoWebExtensionType) {
        guard let installed = installedEmbeddedExtension(for: type) else {
            return
        }

        Logger.webExtensions.info("🗑️ Uninstalling embedded extension: \(type.rawValue)")
        do {
            try uninstallExtension(identifier: installed.uniqueIdentifier)
        } catch {
            Logger.webExtensions.error("❌ Failed to uninstall embedded extension \(type.rawValue): \(error.localizedDescription)")
        }
    }

    @MainActor
    private func syncEmbeddedExtension(_ descriptor: EmbeddedWebExtensionDescriptor) async {
        guard let bundledURL = descriptor.bundledURL else {
            Logger.webExtensions.error("❌ Embedded extension not found in bundle: \(descriptor.resourceFilename)")
            return
        }

        do {
            let bundledMetadata = try await WKWebExtension.metadata(from: bundledURL)

            guard bundledMetadata.type == descriptor.type else {
                Logger.webExtensions.error("❌ Bundled extension type mismatch: expected \(descriptor.type.rawValue), got \(bundledMetadata.type?.rawValue ?? "nil")")
                return
            }

            if let installed = installedEmbeddedExtension(for: descriptor.type) {
                if shouldUpgrade(installed: installed, bundledVersion: bundledMetadata.version) {
                    Logger.webExtensions.info("⬆️ Upgrading embedded extension \(descriptor.type.rawValue): \(installed.version ?? "?") → \(bundledMetadata.version ?? "?")")
                    let oldVersion = installed.version
                    try uninstallExtension(identifier: installed.uniqueIdentifier)
                    try await installEmbeddedExtension(from: bundledURL, type: descriptor.type)
                    pixelFiring.fire(.embeddedUpgraded(fromVersion: oldVersion, toVersion: bundledMetadata.version))
                } else {
                    Logger.webExtensions.debug("👌 Embedded extension \(descriptor.type.rawValue) is up to date (v\(installed.version ?? "?"))")
                }
            } else {
                Logger.webExtensions.info("📦 Installing embedded extension \(descriptor.type.rawValue) v\(bundledMetadata.version ?? "?")")
                try await installEmbeddedExtension(from: bundledURL, type: descriptor.type)
                pixelFiring.fire(.embeddedInstalled)
            }
        } catch {
            Logger.webExtensions.error("❌ Failed to sync embedded extension \(descriptor.type.rawValue): \(error.localizedDescription)")
            pixelFiring.fire(.embeddedInstallError(error: error))
        }
    }

    /// Finds an installed extension by its embedded type.
    public func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension? {
        installationStore.installedExtensions.first { $0.embeddedType == type }
    }

    /// Installs an embedded extension from the given URL.
    @MainActor
    private func installEmbeddedExtension(from sourceURL: URL, type: DuckDuckGoWebExtensionType) async throws {
        Logger.webExtensions.debug("🔄 Installing embedded extension: \(type.rawValue)")

        let identifier = UUID().uuidString
        _ = try storageProvider.copyExtension(from: sourceURL, identifier: identifier)

        do {
            let loadResult = try await loader.loadWebExtension(identifier: identifier, into: controller)

            let installedExtension = InstalledWebExtension(
                uniqueIdentifier: identifier,
                filename: loadResult.filename,
                name: loadResult.displayName,
                version: loadResult.version,
                embeddedType: type
            )

            installationStore.add(installedExtension)
            Logger.webExtensions.info("✅ Installed embedded extension \(type.rawValue) v\(loadResult.version ?? "?")")
            notifyUpdate()
        } catch {
            Logger.webExtensions.error("❌ Failed to load embedded extension '\(identifier)': \(error.localizedDescription)")
            unregisterHandlers(for: identifier)
            try? storageProvider.removeExtension(identifier: identifier)
            throw WebExtensionError.failedToLoadWebExtension(error)
        }
    }

    /// Updates the permission status for an embedded extension, denying access to the specified domains.
    ///
    /// Previously denied domains that are no longer in the exclusion list will have their denial removed
    /// by resetting their permission status to `.unknown`.
    ///
    /// - Parameters:
    ///   - excludedDomains: The list of domains to deny access to.
    ///   - type: The type of embedded extension to update.
    public func updateExcludedDomains(_ excludedDomains: [String], forExtensionType type: DuckDuckGoWebExtensionType) {
        guard let installed = installedEmbeddedExtension(for: type),
              let context = context(for: installed.uniqueIdentifier) else {
            return
        }

        let currentDenied = Set(context.deniedPermissionMatchPatterns.keys)
        let newDeniedPatterns: Set<WKWebExtension.MatchPattern> = Set(excludedDomains.flatMap { domain -> [WKWebExtension.MatchPattern] in
            [
                try? WKWebExtension.MatchPattern(scheme: "*", host: domain, path: "/*"),
                try? WKWebExtension.MatchPattern(scheme: "*", host: "*.\(domain)", path: "/*")
            ].compactMap { $0 }
        })

        let toRevoke = currentDenied.subtracting(newDeniedPatterns)
        let toDeny = newDeniedPatterns.subtracting(currentDenied)

        for pattern in toRevoke {
            context.setPermissionStatus(.unknown, for: pattern, expirationDate: nil)
            Logger.webExtensions.debug("🔓 Revoked denial for pattern: \(pattern.description)")
        }

        for pattern in toDeny {
            context.setPermissionStatus(.deniedExplicitly, for: pattern, expirationDate: nil)
            Logger.webExtensions.debug("🚫 Denied pattern for \(type.rawValue): \(pattern.description)")
        }

        if !toRevoke.isEmpty || !toDeny.isEmpty {
            Logger.webExtensions.info("Updated domain exclusions for \(type.rawValue): \(excludedDomains.count) domain(s) excluded")
        }
    }

    /// Determines if the installed extension should be upgraded to the bundled version.
    private func shouldUpgrade(installed: InstalledWebExtension, bundledVersion: String?) -> Bool {
        SemanticVersionComparator().shouldUpgrade(installedVersion: installed.version, bundledVersion: bundledVersion)
    }
}

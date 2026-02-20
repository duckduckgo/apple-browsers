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

    /// Syncs all embedded extensions from the registry.
    /// Installs new embedded extensions and upgrades outdated ones.
    /// Call this after `loadInstalledExtensions()`.
    @MainActor
    public func syncEmbeddedExtensions() async {
        Logger.webExtensions.debug("🔄 Syncing embedded extensions...")

        for descriptor in EmbeddedWebExtensionRegistry.all {
            await syncEmbeddedExtension(descriptor)
        }

        Logger.webExtensions.debug("✅ Embedded extensions sync completed")
    }

    @MainActor
    private func syncEmbeddedExtension(_ descriptor: EmbeddedWebExtensionDescriptor) async {
        guard let bundledURL = descriptor.bundledURL else {
            Logger.webExtensions.error("❌ Embedded extension not found in bundle: \(descriptor.resourceName).\(descriptor.resourceExtension)")
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
                    Logger.webExtensions.debug("✓ Embedded extension \(descriptor.type.rawValue) is up to date (v\(installed.version ?? "?"))")
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

    /// Determines if the installed extension should be upgraded to the bundled version.
    private func shouldUpgrade(installed: InstalledWebExtension, bundledVersion: String?) -> Bool {
        guard let bundledVersion, let installedVersion = installed.version else {
            return bundledVersion != nil
        }
        return isVersion(bundledVersion, newerThan: installedVersion)
    }

    /// Semantic version comparison: returns true if `new` > `old`.
    private func isVersion(_ new: String, newerThan old: String) -> Bool {
        let newComponents = new.split(separator: ".").compactMap { Int($0) }
        let oldComponents = old.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(newComponents.count, oldComponents.count)
        for i in 0..<maxLength {
            let newPart = i < newComponents.count ? newComponents[i] : 0
            let oldPart = i < oldComponents.count ? oldComponents[i] : 0
            if newPart > oldPart { return true }
            if newPart < oldPart { return false }
        }
        return false
    }
}

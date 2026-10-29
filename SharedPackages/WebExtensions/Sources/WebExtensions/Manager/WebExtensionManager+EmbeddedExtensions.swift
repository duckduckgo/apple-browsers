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

    /// Prepares only CPM at launch. The full load starts scriptlet handling after all contexts load.
    @MainActor
    public func syncCPMExtensionBeforeLoad(isEnabled: Bool) async {
        guard !isLoadingInstalledExtensions else { return }
        connectEventsListener()
        if isEnabled {
            guard let descriptor = EmbeddedWebExtensionRegistry.descriptor(for: .embedded) else { return }
            await syncEmbeddedExtension(descriptor, startScriptlets: false)
        } else {
            if let installed = installedEmbeddedExtension(for: .embedded) {
                await unloadGuard.awaitSettled(context(for: installed.uniqueIdentifier))
            }
            uninstallEmbeddedExtension(type: .embedded)
        }
    }

    /// Syncs embedded extensions from the registry based on the enabled types.
    /// Installs/upgrades enabled extensions and uninstalls disabled ones.
    /// At launch, use the lifecycle coordinator so only CPM can be prepared before the full load.
    /// - Parameter enabledTypes: The set of extension types that should be installed.
    ///   Extensions not in this set will be uninstalled if previously installed.
    @MainActor
    public func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {
        guard !isLoadingInstalledExtensions else {
            Logger.webExtensions.debug("⏳ Skipping sync — load in progress, sync will run after load completes")
            return
        }

        // Sync can create the first context at launch, so its events must already reach the controller.
        connectEventsListener()
        Logger.webExtensions.debug("🔄 Syncing embedded extensions...")

        for descriptor in EmbeddedWebExtensionRegistry.all {
            if enabledTypes.contains(descriptor.type) {
                await syncEmbeddedExtension(descriptor)
            } else {
                // A runtime disable may unload a context whose DNR load is still settling.
                if let installed = installedEmbeddedExtension(for: descriptor.type) {
                    await unloadGuard.awaitSettled(context(for: installed.uniqueIdentifier))
                }
                uninstallEmbeddedExtension(type: descriptor.type)
            }
        }

        Logger.webExtensions.debug("✅ Embedded extensions sync completed")
    }

    /// Uninstalls an embedded extension of the given type if it's currently installed.
    /// - Parameter type: The type of embedded extension to uninstall.
    @MainActor
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
    private func syncEmbeddedExtension(_ descriptor: EmbeddedWebExtensionDescriptor, startScriptlets: Bool = true) async {
        guard let bundledURL = bundledExtensionURL(descriptor) else {
            Logger.webExtensions.error("❌ Embedded extension not found in bundle: \(descriptor.resourceFilename)")
            return
        }

        do {
            let bundledMetadata = try await WebExtensionMetadata.fromZip(at: bundledURL)

            guard bundledMetadata.type == descriptor.type else {
                Logger.webExtensions.error("❌ Bundled extension type mismatch: expected \(descriptor.type.rawValue), got \(bundledMetadata.type?.rawValue ?? "nil")")
                return
            }

            if let installed = installedEmbeddedExtension(for: descriptor.type) {
                if shouldUpgrade(installed: installed, bundledVersion: bundledMetadata.version) {
                    Logger.webExtensions.info("⬆️ Upgrading embedded extension \(descriptor.type.rawValue): \(installed.version ?? "?") → \(bundledMetadata.version ?? "?")")
                    let oldVersion = installed.version
                    let oldIdentifier = installed.uniqueIdentifier

                    // With upgrade-before-load enabled, launch sync replaces CPM before its old
                    // context loads, so the replacement can keep its webkit-extension://<UUID>/ origin.
                    // The old context may already be loaded with the flag off, or if a failed
                    // pre-load upgrade falls back to loading it before the post-load sync retries.
                    // Installation then loads the new context before unloading the old one; use
                    // separate origins so their service-worker registrations do not overlap.
                    let origin = isCPMUpgradeBeforeLoadEnabled && context(for: oldIdentifier) == nil
                        ? cpmBaseURLPolicy.originForUpgrade(of: installed) : nil

                    // Install before uninstalling: the versions have distinct identifiers and can
                    // coexist, so a failed upgrade leaves the old version installed and working.
                    try await installEmbeddedExtension(from: bundledURL,
                                                       type: descriptor.type,
                                                       requiresExtraction: bundledMetadata.requiresExtraction,
                                                       cpmOriginIdentifier: origin,
                                                       startScriptlets: startScriptlets)
                    cpmDiagnosticsRecorder?.extensionDidUpdate(type: descriptor.type)

                    // Only unload the old version once its own load has settled.
                    await unloadGuard.awaitSettled(context(for: oldIdentifier))

                    // Removal failure isn't fatal — the new version is already installed.
                    do {
                        try uninstallExtension(identifier: oldIdentifier)
                    } catch {
                        Logger.webExtensions.error("⚠️ Upgraded \(descriptor.type.rawValue) but failed to remove old version '\(oldIdentifier)': \(error.localizedDescription)")
                    }

                    // Uninstalling the old version disabled scriptlet handling for the type (it's
                    // keyed by type, not identifier), so re-enable it for the now-current version.
                    if startScriptlets {
                        await scriptletCoordinator?.onExtensionEnabled(for: descriptor.type)
                    }

                    pixelFiring.fire(.embeddedUpgraded(type: descriptor.type, fromVersion: oldVersion, toVersion: bundledMetadata.version))
                } else {
                    Logger.webExtensions.debug("👌 Embedded extension \(descriptor.type.rawValue) is up to date (v\(installed.version ?? "?"))")
                    if startScriptlets {
                        await scriptletCoordinator?.onExtensionEnabled(for: descriptor.type)
                    }
                }
            } else {
                Logger.webExtensions.info("📦 Installing embedded extension \(descriptor.type.rawValue) v\(bundledMetadata.version ?? "?")")
                try await installEmbeddedExtension(from: bundledURL,
                                                   type: descriptor.type,
                                                   requiresExtraction: bundledMetadata.requiresExtraction,
                                                   startScriptlets: startScriptlets)
                pixelFiring.fire(.embeddedInstalled(type: descriptor.type))
            }
        } catch {
            Logger.webExtensions.error("❌ Failed to sync embedded extension \(descriptor.type.rawValue): \(error.localizedDescription)")
            pixelFiring.fire(.embeddedInstallError(type: descriptor.type, error: error))
        }
    }

    /// Finds an installed extension by its embedded type.
    public func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension? {
        installationStore.installedExtensions.first { $0.embeddedType == type }
    }

    /// Returns the installed path for an embedded extension type.
    public func installedExtensionPath(for type: DuckDuckGoWebExtensionType) -> URL? {
        guard let installed = installedEmbeddedExtension(for: type) else {
            return nil
        }
        return storageProvider.resolveInstalledExtension(identifier: installed.uniqueIdentifier)
    }

    @MainActor
    public func reloadExtension(for type: DuckDuckGoWebExtensionType) async throws {
        guard let installed = installedEmbeddedExtension(for: type) else {
            Logger.webExtensions.warning("⚠️ Cannot reload extension for type '\(type.rawValue)': not installed")
            return
        }
        try await reloadExtension(identifier: installed.uniqueIdentifier, trigger: .scriptletUpdate)
    }

    /// Installs an embedded extension from the given URL.
    @MainActor
    private func installEmbeddedExtension(from sourceURL: URL, type: DuckDuckGoWebExtensionType,
                                          requiresExtraction: Bool, cpmOriginIdentifier: UUID? = nil,
                                          startScriptlets: Bool = true) async throws {
        Logger.webExtensions.debug("🔄 Installing embedded extension: \(type.rawValue)")

        let identifier = UUID().uuidString
        cpmBaseURLPolicy.pendingInstallations[identifier] = type
        cpmBaseURLPolicy.pendingOriginIdentifiers[identifier] = cpmOriginIdentifier
        defer {
            cpmBaseURLPolicy.pendingInstallations[identifier] = nil
            cpmBaseURLPolicy.pendingOriginIdentifiers[identifier] = nil
        }
        permissionController?.trustedInstallations.insert(identifier)
        defer { permissionController?.trustedInstallations.remove(identifier) }
        if requiresExtraction {
            // Unzipping on the main thread risks the watchdog (Dark Reader has ~140 files).
            let storageProvider = storageProvider
            _ = try await Task.detached {
                try storageProvider.extractExtension(from: sourceURL, identifier: identifier)
            }.value
        } else {
            _ = try storageProvider.copyExtension(from: sourceURL, identifier: identifier)
        }

        do {
            let loadResult = try await loader.loadWebExtension(identifier: identifier, into: controller)
            unloadGuard.recordLoad(of: identifier)

            // The policy may have rotated the pending origin while loading; persist its current value.
            let installedExtension = InstalledWebExtension(
                uniqueIdentifier: identifier,
                filename: loadResult.filename,
                name: loadResult.displayName,
                version: loadResult.version,
                embeddedType: type,
                cpmOriginIdentifier: cpmBaseURLPolicy.pendingOriginIdentifiers[identifier]
            )

            installationStore.add(installedExtension)
            if type == .embedded {
                // An error notification can arrive while the initial installation is still pending.
                if let context = context(for: identifier) {
                    cpmBaseURLPolicy.recordBackgroundLoadFailure(in: context, errors: context.errors)
                }
                trackEmbeddedBackgroundStartup(identifier: identifier)
            }
            reportLifecycleEvent(.loaded(identifier: identifier, type: type))
            Logger.webExtensions.info("✅ Installed embedded extension \(type.rawValue) v\(loadResult.version ?? "?")")
            notifyUpdate()

            if startScriptlets {
                await scriptletCoordinator?.onExtensionEnabled(for: type)
            }
        } catch {
            Logger.webExtensions.error("❌ Failed to load embedded extension '\(identifier)': \(error.localizedDescription)")
            unregisterHandlers(for: identifier)
            try? storageProvider.removeExtension(identifier: identifier)
            throw WebExtensionError.failedToLoadWebExtension(error)
        }
    }

    /// Determines if the installed extension should be upgraded to the bundled version.
    private func shouldUpgrade(installed: InstalledWebExtension, bundledVersion: String?) -> Bool {
        SemanticVersionComparator().shouldUpgrade(installedVersion: installed.version, bundledVersion: bundledVersion)
    }

}

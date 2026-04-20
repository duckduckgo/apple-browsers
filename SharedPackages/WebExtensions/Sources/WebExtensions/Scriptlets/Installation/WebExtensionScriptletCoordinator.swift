//
//  WebExtensionScriptletCoordinator.swift
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

import Combine
import Foundation
import os.log

/// Coordinates scriptlet installation into web extension directories.
///
/// This is the bridge between the scriptlet provider layer (``ScriptletManager``)
/// and the on-disk extension directories managed by ``WebExtensionManager``.
/// When a web extension type is enabled, the coordinator:
///
/// 1. Starts the ``ScriptletProviding`` provider to fetch/cache scriptlets.
/// 2. Installs any already-cached scriptlets into the extension directory immediately.
/// 3. Subscribes to the provider's availability publisher so future updates
///    are installed automatically and the extension is reloaded.
///
/// ## Installation serialization
///
/// Installations are serialized per extension type: if an install is already in progress
/// for a given type, a new install waits for it to complete before starting. This prevents
/// partial overwrites of the extension's scriptlet directory.
///
/// ## Path resolution
///
/// The ``installationPathResolver`` is held weakly to avoid a retain cycle with
/// ``WebExtensionManager``, which owns both this coordinator and provides the
/// installed extension paths. It must be set before calling ``onExtensionEnabled(for:)``.
@MainActor
@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionScriptletCoordinator {

    private let scriptletProvider: ScriptletProviding
    private let installationTracker: ScriptletInstallationTracking
    private let installer: ScriptletInstalling
    private let pixelFiring: WebExtensionPixelFiring
    private let cacheRootDirectory: URL

    public weak var installationPathResolver: (any WebExtensionInstallationPathResolving)?

    private var cancellables: [DuckDuckGoWebExtensionType: AnyCancellable] = [:]
    private var enabledTypes: Set<DuckDuckGoWebExtensionType> = []
    private var installationTasks: [DuckDuckGoWebExtensionType: Task<Void, Never>] = [:]

    public init(
        scriptletProvider: ScriptletProviding,
        installationTracker: ScriptletInstallationTracking,
        installer: ScriptletInstalling,
        pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring(),
        cacheRootDirectory: URL,
        installationPathResolver: any WebExtensionInstallationPathResolving
    ) {
        self.scriptletProvider = scriptletProvider
        self.installationTracker = installationTracker
        self.installer = installer
        self.pixelFiring = pixelFiring
        self.cacheRootDirectory = cacheRootDirectory
        self.installationPathResolver = installationPathResolver
    }

    public func onExtensionEnabled(for type: DuckDuckGoWebExtensionType) async {
        guard !enabledTypes.contains(type) else { return }
        enabledTypes.insert(type)

        Logger.webExtensions.info("[Scriptlets] Enabled scriptlet handling for '\(type.rawValue)'")
        await scriptletProvider.start(for: type)
        subscribeToUpdates(for: type)
        await installCurrentScriptlets(for: type)
    }

    public func onExtensionDisabled(for type: DuckDuckGoWebExtensionType) {
        Logger.webExtensions.info("[Scriptlets] Disabled scriptlet handling for '\(type.rawValue)'")
        enabledTypes.remove(type)
        installationTasks[type]?.cancel()
        installationTasks.removeValue(forKey: type)
        cancellables.removeValue(forKey: type)
        installationTracker.clearInstalledVersion(for: type)
        scriptletProvider.stop(for: type)
    }

    // MARK: - Private

    private func subscribeToUpdates(for type: DuckDuckGoWebExtensionType) {
        guard cancellables[type] == nil else { return }

        cancellables[type] = scriptletProvider.availabilityPublisher(for: type)
            .dropFirst()
            .sink { [weak self] availability in
                switch availability {
                case .notAvailable, .updating:
                    break

                case .available(let scriptlets):
                    Task { @MainActor [weak self] in
                        guard let self,
                              let version = self.scriptletProvider.scriptletVersion(for: type) else { return }
                        await self.installScriptlets(scriptlets, version: version, for: type)
                    }
                }
            }
    }

    private func resolveInstallationDirectory(for type: DuckDuckGoWebExtensionType) -> URL? {
        guard let directory = installationPathResolver?.installedExtensionPath(for: type) else {
            Logger.webExtensions.warning("[Scriptlets] No installation directory available for '\(type.rawValue)'")
            return nil
        }
        return directory
    }

    private func installCurrentScriptlets(for type: DuckDuckGoWebExtensionType) async {
        guard let scriptlets = scriptletProvider.scriptlets(for: type),
              let version = scriptletProvider.scriptletVersion(for: type) else { return }
        await installScriptlets(scriptlets, version: version, for: type)
    }

    private func installScriptlets(_ scriptlets: [Scriptlet], version: String, for type: DuckDuckGoWebExtensionType) async {
        if let existingTask = installationTasks[type] {
            await existingTask.value
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performInstallation(scriptlets, version: version, for: type)
        }
        installationTasks[type] = task
        await task.value
        installationTasks.removeValue(forKey: type)
    }

    private func performInstallation(_ scriptlets: [Scriptlet], version: String, for type: DuckDuckGoWebExtensionType) async {
        guard enabledTypes.contains(type) else { return }

        let installedVersion = installationTracker.installedVersion(for: type)
        guard version != installedVersion else { return }

        guard let installationDirectory = resolveInstallationDirectory(for: type) else {
            return
        }

        do {
            try await installer.installScriptlets(scriptlets, cacheRootDirectory: cacheRootDirectory, to: installationDirectory)

            guard !Task.isCancelled, enabledTypes.contains(type) else { return }

            installationTracker.setInstalledVersion(version, for: type)
            pixelFiring.fire(.scriptletInstalled(type: type, version: version))
            Logger.webExtensions.info("[Scriptlets] Installed v\(version) for '\(type.rawValue)'")
            try await installationPathResolver?.reloadExtension(for: type)
        } catch {
            Logger.webExtensions.error("[Scriptlets] Failed to install scriptlets for '\(type.rawValue)': \(error)")
            pixelFiring.fire(.scriptletInstallError(type: type, error: error))
        }
    }
}

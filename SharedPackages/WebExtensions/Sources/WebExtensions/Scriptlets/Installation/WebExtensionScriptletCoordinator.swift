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

@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionScriptletCoordinator {

    private let scriptletProvider: ScriptletProviding
    private let installer: ScriptletInstalling

    public weak var installationPathResolver: (any WebExtensionInstallationPathResolving)?

    private var cancellables: [DuckDuckGoWebExtensionType: AnyCancellable] = [:]
    private var enabledTypes: Set<DuckDuckGoWebExtensionType> = []
    private var installationTasks: [DuckDuckGoWebExtensionType: Task<Void, Never>] = [:]

    public init(
        scriptletProvider: ScriptletProviding,
        installer: ScriptletInstalling,
        installationPathResolver: any WebExtensionInstallationPathResolving
    ) {
        self.scriptletProvider = scriptletProvider
        self.installer = installer
        self.installationPathResolver = installationPathResolver
    }

    public func onExtensionEnabled(for type: DuckDuckGoWebExtensionType) async {
        guard !enabledTypes.contains(type) else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ Extension '\(type.rawValue)' already enabled, skipping")
            return
        }
        enabledTypes.insert(type)

        Logger.webExtensions.debug("[Scriptlets] ▶️ Extension '\(type.rawValue)' enabled, installing scriptlets")
        await scriptletProvider.start(for: type)
        subscribeToUpdates(for: type)
        await installCurrentScriptlets(for: type)
    }

    public func onExtensionDisabled(for type: DuckDuckGoWebExtensionType) {
        Logger.webExtensions.debug("[Scriptlets] ⏸️ Extension '\(type.rawValue)' disabled")
        enabledTypes.remove(type)
        installationTasks[type]?.cancel()
        installationTasks.removeValue(forKey: type)
        cancellables.removeValue(forKey: type)
    }

    // MARK: - Private

    private func subscribeToUpdates(for type: DuckDuckGoWebExtensionType) {
        guard cancellables[type] == nil else { return }

        cancellables[type] = scriptletProvider.availabilityPublisher(for: type)
            .dropFirst()
            .sink { [weak self] availability in
                guard let self = self else { return }

                switch availability {
                case .notAvailable, .updating:
                    break

                case .available(let scriptlets):
                    Logger.webExtensions.debug("[Scriptlets] 🔄 Scriptlets updated for '\(type.rawValue)' (\(scriptlets.count) scriptlet(s))")
                    Task {
                        await self.installScriptlets(scriptlets, for: type)
                    }
                }
            }
    }

    private func resolveInstallationDirectory(for type: DuckDuckGoWebExtensionType) -> URL? {
        guard let directory = installationPathResolver?.installedExtensionPath(for: type) else {
            Logger.webExtensions.warning("[Scriptlets] ⚠️ No installation directory available for '\(type.rawValue)'")
            return nil
        }
        return directory
    }

    private func installCurrentScriptlets(for type: DuckDuckGoWebExtensionType) async {
        guard let scriptlets = scriptletProvider.scriptlets(for: type) else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No scriptlets available for installation to '\(type.rawValue)'")
            return
        }

        await installScriptlets(scriptlets, for: type)
    }

    private func installScriptlets(_ scriptlets: [Scriptlet], for type: DuckDuckGoWebExtensionType) async {
        if let existingTask = installationTasks[type] {
            Logger.webExtensions.debug("[Scriptlets] ⏳ Waiting for existing installation to complete for '\(type.rawValue)'")
            await existingTask.value
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performInstallation(scriptlets, for: type)
        }
        installationTasks[type] = task
        await task.value
        installationTasks.removeValue(forKey: type)
    }

    private func performInstallation(_ scriptlets: [Scriptlet], for type: DuckDuckGoWebExtensionType) async {
        guard let currentVersion = scriptletProvider.scriptletVersion(for: type) else {
            return
        }

        let installedVersion = scriptletProvider.installedVersion(for: type)
        guard currentVersion != installedVersion else {
            Logger.webExtensions.debug("[Scriptlets] ✓ Scriptlets v\(currentVersion) already installed for '\(type.rawValue)', skipping")
            return
        }

        guard let installationDirectory = resolveInstallationDirectory(for: type) else {
            return
        }

        do {
            try await installer.installScriptlets(scriptlets, cacheRootDirectory: scriptletProvider.cacheRootDirectory, to: installationDirectory)
            scriptletProvider.setInstalledVersion(currentVersion, for: type)
            Logger.webExtensions.info("[Scriptlets] ✅ Installed scriptlets v\(currentVersion) for '\(type.rawValue)'")
            try await installationPathResolver?.reloadExtension(for: type)
        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to install scriptlets to '\(type.rawValue)': \(error.localizedDescription)")
        }
    }
}

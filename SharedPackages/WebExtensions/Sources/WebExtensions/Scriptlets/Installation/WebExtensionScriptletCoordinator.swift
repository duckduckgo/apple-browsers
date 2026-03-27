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
    public let extensionType: DuckDuckGoWebExtensionType

    /// Resolves the installation path for the extension type.
    /// Set after creation when the web extension manager is available.
    public weak var installationPathResolver: (any WebExtensionInstallationPathResolving)?

    private var cancellable: AnyCancellable?

    public init(
        scriptletProvider: ScriptletProviding,
        installer: ScriptletInstalling,
        extensionType: DuckDuckGoWebExtensionType,
        installationPathResolver: (any WebExtensionInstallationPathResolving)? = nil
    ) {
        self.scriptletProvider = scriptletProvider
        self.installer = installer
        self.extensionType = extensionType
        self.installationPathResolver = installationPathResolver
    }

    public func start() {
        Logger.webExtensions.debug("[Scriptlets] 🚀 Starting coordinator for extension type '\(self.extensionType.rawValue)'")
        subscribeToScriptletUpdates()
    }

    public func onExtensionEnabled() async {
        Logger.webExtensions.debug("[Scriptlets] ▶️ Extension '\(self.extensionType.rawValue)' enabled, installing scriptlets")
        await installCurrentScriptlets()
    }

    public func onExtensionDisabled() {
        Logger.webExtensions.debug("[Scriptlets] ⏸️ Extension '\(self.extensionType.rawValue)' disabled")
    }

    private func resolveInstallationDirectory() -> URL? {
        guard let directory = installationPathResolver?.installedExtensionPath(for: extensionType) else {
            Logger.webExtensions.warning("[Scriptlets] ⚠️ No installation directory available for '\(self.extensionType.rawValue)'")
            return nil
        }
        return directory
    }

    private func subscribeToScriptletUpdates() {
        cancellable = scriptletProvider.availabilityPublisher(for: extensionType)
            .dropFirst()
            .sink { [weak self] availability in
                guard let self = self else { return }

                switch availability {
                case .notAvailable, .updating:
                    break

                case .available(let scriptlets):
                    Logger.webExtensions.debug("[Scriptlets] 🔄 Scriptlets updated for '\(self.extensionType.rawValue)' (\(scriptlets.count) scriptlet(s))")
                    Task {
                        await self.installScriptlets(scriptlets)
                    }
                }
            }
    }

    private func installCurrentScriptlets() async {
        guard let scriptlets = scriptletProvider.scriptlets(for: extensionType) else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No scriptlets available for installation to '\(self.extensionType.rawValue)'")
            return
        }

        await installScriptlets(scriptlets)
    }

    private func installScriptlets(_ scriptlets: [Scriptlet]) async {
        guard let currentVersion = scriptletProvider.scriptletVersion(for: extensionType) else {
            return
        }

        let installedVersion = scriptletProvider.installedVersion(for: extensionType)
        guard currentVersion != installedVersion else {
            Logger.webExtensions.debug("[Scriptlets] ✓ Scriptlets v\(currentVersion) already installed for '\(self.extensionType.rawValue)', skipping")
            return
        }

        guard let installationDirectory = resolveInstallationDirectory() else {
            return
        }

        do {
            try await installer.installScriptlets(scriptlets, cacheRootDirectory: scriptletProvider.cacheRootDirectory, to: installationDirectory)
            scriptletProvider.setInstalledVersion(currentVersion, for: extensionType)
            Logger.webExtensions.info("[Scriptlets] ✅ Installed scriptlets v\(currentVersion) for '\(self.extensionType.rawValue)'")
            try await installationPathResolver?.reloadExtension(for: extensionType)
        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to install scriptlets to '\(self.extensionType.rawValue)': \(error.localizedDescription)")
        }
    }
}

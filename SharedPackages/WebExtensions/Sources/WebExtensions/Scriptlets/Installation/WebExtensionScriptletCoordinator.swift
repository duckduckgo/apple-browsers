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
    private var installationDirectory: URL?

    private var cancellable: AnyCancellable?

    public init(
        scriptletProvider: ScriptletProviding,
        installer: ScriptletInstalling,
        extensionType: DuckDuckGoWebExtensionType
    ) {
        self.scriptletProvider = scriptletProvider
        self.installer = installer
        self.extensionType = extensionType
    }

    public func start() {
        Logger.webExtensions.debug("[Scriptlets] 🚀 Starting coordinator for extension type '\(self.extensionType.rawValue)'")
        subscribeToScriptletUpdates()

        Task {
            await installCurrentScriptlets()
        }
    }

    public func setInstallationDirectory(_ directory: URL) async {
        Logger.webExtensions.debug("[Scriptlets] 📍 Setting installation directory for '\(self.extensionType.rawValue)': \(directory.path)")
        self.installationDirectory = directory
        await installCurrentScriptlets()
    }

    public func onExtensionEnabled() async {
        Logger.webExtensions.debug("[Scriptlets] ▶️ Extension '\(self.extensionType.rawValue)' enabled, installing scriptlets")
        await installCurrentScriptlets()
    }

    public func onExtensionDisabled() {
        Logger.webExtensions.debug("[Scriptlets] ⏸️ Extension '\(self.extensionType.rawValue)' disabled, removing scriptlets")
        guard let installationDirectory = installationDirectory else {
            Logger.webExtensions.warning("[Scriptlets] ⚠️ No installation directory set for '\(self.extensionType.rawValue)', cannot remove scriptlets")
            return
        }
        try? installer.removeScriptlets(from: installationDirectory)
    }

    private func subscribeToScriptletUpdates() {
        cancellable = scriptletProvider.availabilityPublisher
            .sink { [weak self] availability in
                guard let self = self else { return }

                switch availability {
                case .notAvailable:
                    Logger.webExtensions.debug("[Scriptlets] ⏭️ Scriptlets not available for '\(self.extensionType.rawValue)'")
                    break

                case .available(let scriptlets), .updating(let scriptlets):
                    Logger.webExtensions.debug("[Scriptlets] 🔄 Scriptlets availability updated for '\(self.extensionType.rawValue)' (\(scriptlets.count) scriptlet(s))")
                    Task {
                        await self.installScriptlets(scriptlets)
                    }
                }
            }
    }

    private func installCurrentScriptlets() async {
        guard let scriptlets = scriptletProvider.scriptlets else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No scriptlets available for installation to '\(self.extensionType.rawValue)'")
            return
        }

        await installScriptlets(scriptlets)
    }

    private func installScriptlets(_ scriptlets: [Scriptlet]) async {
        guard let installationDirectory = installationDirectory else {
            Logger.webExtensions.warning("[Scriptlets] ⚠️ No installation directory set for '\(self.extensionType.rawValue)', cannot install scriptlets")
            return
        }

        do {
            try await installer.installScriptlets(scriptlets, to: installationDirectory)
        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to install scriptlets to '\(self.extensionType.rawValue)': \(error.localizedDescription)")
        }
    }
}

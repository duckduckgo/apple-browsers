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

public final class WebExtensionScriptletCoordinator {

    private let scriptletProvider: ScriptletProviding
    private let installer: ScriptletInstalling
    private let extensionID: String

    private var cancellable: AnyCancellable?

    public init(
        scriptletProvider: ScriptletProviding,
        installer: ScriptletInstalling,
        extensionID: String
    ) {
        self.scriptletProvider = scriptletProvider
        self.installer = installer
        self.extensionID = extensionID
    }

    public func start() {
        Logger.webExtensions.debug("[Scriptlets] 🚀 Starting coordinator for extension '\(self.extensionID)'")
        subscribeToScriptletUpdates()

        Task {
            await installCurrentScriptlets()
        }
    }

    public func onExtensionEnabled() async {
        Logger.webExtensions.debug("[Scriptlets] ▶️ Extension '\(self.extensionID)' enabled, installing scriptlets")
        await installCurrentScriptlets()
    }

    public func onExtensionDisabled() {
        Logger.webExtensions.debug("[Scriptlets] ⏸️ Extension '\(self.extensionID)' disabled, removing scriptlets")
        try? installer.removeScriptlets(from: extensionID)
    }

    private func subscribeToScriptletUpdates() {
        cancellable = scriptletProvider.availabilityPublisher
            .sink { [weak self] availability in
                guard let self = self else { return }

                switch availability {
                case .notAvailable:
                    Logger.webExtensions.debug("[Scriptlets] ⏭️ Scriptlets not available for '\(self.extensionID)'")
                    break

                case .available(let scriptlets), .updating(let scriptlets):
                    Logger.webExtensions.debug("[Scriptlets] 🔄 Scriptlets availability updated for '\(self.extensionID)' (\(scriptlets.count) scriptlet(s))")
                    Task {
                        await self.installScriptlets(scriptlets)
                    }
                }
            }
    }

    private func installCurrentScriptlets() async {
        guard let scriptlets = scriptletProvider.scriptlets else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No scriptlets available for installation to '\(self.extensionID)'")
            return
        }

        await installScriptlets(scriptlets)
    }

    private func installScriptlets(_ scriptlets: [Scriptlet]) async {
        do {
            try await installer.installScriptlets(scriptlets, to: extensionID)
        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to install scriptlets to '\(self.extensionID)': \(error.localizedDescription)")
        }
    }
}

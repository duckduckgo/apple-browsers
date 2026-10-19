//
//  WebExtensionRemoteDisableEnforcer.swift
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
import PrivacyConfig

/// Disables installed Chrome Web Store extensions whose IDs are listed in `disabledExtensionIds`
/// of the `extensionManagement` Privacy Configuration feature.
///
/// While `extensionManagement.isLaunchedExtensions` is enabled, a pass runs when the enforcer starts,
/// on every Privacy Configuration update, and whenever the loaded extensions change. The last one
/// covers new installations and the user enabling a listed extension, which is disabled again.
///
/// Disabling is one-way, matching the Windows browser: the enforcer never enables an extension.
/// An extension stays disabled after its ID leaves the list, until the user enables it.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class WebExtensionRemoteDisableEnforcer {

    private weak var manager: WebExtensionManaging?
    private let configurationManager: PrivacyConfigurationManaging
    private var cancellables = Set<AnyCancellable>()

    /// The most recent pass. Each pass waits for the previous one, so passes never overlap.
    private(set) var enforcementTask: Task<Void, Never>?

    public init(manager: WebExtensionManaging, configurationManager: PrivacyConfigurationManaging) {
        self.manager = manager
        self.configurationManager = configurationManager
    }

    /// The lowercased Chrome Web Store IDs to disable. Empty while extension management isn't launched.
    public var remotelyDisabledExtensionIDs: Set<String> {
        let config = configurationManager.privacyConfig
        guard config.isSubfeatureEnabled(ExtensionManagementSubfeature.isLaunchedExtensions) else { return [] }

        let identifiers = config.settings(for: .extensionManagement)["disabledExtensionIds"] as? [String] ?? []
        return Set(identifiers.map { $0.lowercased() })
    }

    /// Whether remote configuration currently disables the extension, so the user can't enable it.
    public func isRemotelyDisabled(_ installedExtension: InstalledWebExtension) -> Bool {
        guard let storeIdentity = installedExtension.storeIdentity, storeIdentity.store == .chromeWebStore else { return false }
        return remotelyDisabledExtensionIDs.contains(storeIdentity.id.lowercased())
    }

    /// Runs a pass now and then on every trigger. Call it after the installed extensions load.
    public func start() {
        guard cancellables.isEmpty, let manager else { return }

        configurationManager.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor in
                    self?.scheduleEnforcement()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .webExtensionsDidChangeLoadedExtensions, object: manager)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleEnforcement()
                }
            }
            .store(in: &cancellables)

        scheduleEnforcement()
    }

    @discardableResult
    func scheduleEnforcement() -> Task<Void, Never> {
        let previousTask = enforcementTask
        let task = Task { @MainActor [weak self] in
            await previousTask?.value
            await self?.enforce()
        }
        enforcementTask = task
        return task
    }

    private func enforce() async {
        guard let manager else { return }

        // A disabled extension can still be loaded when it was disabled while installed extensions were loading.
        let extensionsToDisable = manager.webExtensionIdentifiers
            .compactMap { manager.installedExtension(identifier: $0) }
            .filter { isRemotelyDisabled($0) && (!$0.isDisabled || manager.context(for: $0.uniqueIdentifier) != nil) }

        for installedExtension in extensionsToDisable {
            let identifier = installedExtension.uniqueIdentifier
            do {
                try await manager.unloadExtension(identifier: identifier)
                Logger.webExtensions.info("Disabled extension '\(identifier)' because remote configuration lists it")
            } catch {
                Logger.webExtensions.error("Failed to disable remotely disabled extension '\(identifier)': \(error.localizedDescription)")
            }
        }
    }
}

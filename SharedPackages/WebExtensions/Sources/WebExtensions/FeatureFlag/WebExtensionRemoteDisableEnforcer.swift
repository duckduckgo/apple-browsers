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
/// of the `extensionManagement` Privacy Configuration feature, or that the app disables itself
/// (`disabledExtensionIDs`), such as an extension whose feature flag is off.
///
/// The configuration's list counts only while `isExtensionsEnabled` returns true or
/// `extensionManagement.isLaunchedExtensions` is enabled.
/// A pass runs when the enforcer starts, on every Privacy Configuration update or
/// `disabledExtensionIDsDidChange`, and whenever the loaded extensions change. The last one
/// covers new installations and the user enabling a listed extension, which is disabled again.
///
/// While extensions are not enabled, a pass disables every Chrome Web Store extension,
/// matching the Windows browser's sweep.
///
/// Disabling is one-way, matching the Windows browser: the enforcer never enables an extension.
/// An extension stays disabled after its ID leaves the list or extensions are enabled again,
/// until the user enables it.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class WebExtensionRemoteDisableEnforcer {

    private weak var manager: WebExtensionManaging?
    private let configurationManager: PrivacyConfigurationManaging
    private let disabledExtensionIDs: @MainActor () -> Set<String>
    private let disabledExtensionIDsDidChange: AnyPublisher<Void, Never>
    private let isExtensionsEnabled: @MainActor () -> Bool
    private let pixelFiring: WebExtensionPixelFiring
    private var cancellables = Set<AnyCancellable>()

    /// The most recent pass. Each pass waits for the previous one, so passes never overlap.
    private(set) var enforcementTask: Task<Void, Never>?

    /// - Parameters:
    ///   - disabledExtensionIDs: Chrome Web Store IDs the app disables, whether or not extension management is launched.
    ///   - disabledExtensionIDsDidChange: Fires when `disabledExtensionIDs` or `isExtensionsEnabled` may have changed.
    ///   - isExtensionsEnabled: When it returns false, every Chrome Web Store extension is disabled.
    public init(manager: WebExtensionManaging,
                configurationManager: PrivacyConfigurationManaging,
                disabledExtensionIDs: @escaping @MainActor () -> Set<String> = { [] },
                disabledExtensionIDsDidChange: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher(),
                isExtensionsEnabled: @escaping @MainActor () -> Bool = { true },
                pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring()) {
        self.manager = manager
        self.configurationManager = configurationManager
        self.disabledExtensionIDs = disabledExtensionIDs
        self.disabledExtensionIDsDidChange = disabledExtensionIDsDidChange
        self.isExtensionsEnabled = isExtensionsEnabled
        self.pixelFiring = pixelFiring
    }

    /// The lowercased Chrome Web Store IDs to disable. The configuration's list counts only while extensions
    /// are enabled or extension management is launched.
    public var remotelyDisabledExtensionIDs: Set<String> {
        let config = configurationManager.privacyConfig
        var identifiers = disabledExtensionIDs()
        if isExtensionsEnabled() || config.isSubfeatureEnabled(ExtensionManagementSubfeature.isLaunchedExtensions) {
            identifiers.formUnion(config.settings(for: .extensionManagement)["disabledExtensionIds"] as? [String] ?? [])
        }
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
            .merge(with: disabledExtensionIDsDidChange)
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

        let isSweeping = !isExtensionsEnabled()
        // A disabled extension can still be loaded when it was disabled while installed extensions were loading.
        let extensionsToDisable = manager.webExtensionIdentifiers
            .compactMap { manager.installedExtension(identifier: $0) }
            .filter { (isSweeping && isFromChromeWebStore($0)) || isRemotelyDisabled($0) }
            .filter { !$0.isDisabled || manager.context(for: $0.uniqueIdentifier) != nil }

        var sweptCount = 0
        for installedExtension in extensionsToDisable {
            let identifier = installedExtension.uniqueIdentifier
            let isListed = isRemotelyDisabled(installedExtension)
            do {
                try await manager.disableExtension(identifier: identifier)
                // Unloading an extension that was disabled while loading doesn't turn it off.
                if !installedExtension.isDisabled {
                    if isListed {
                        pixelFiring.fire(.remotelyDisabled(extension: pixelExtension(for: installedExtension)))
                    } else {
                        sweptCount += 1
                    }
                }
                Logger.webExtensions.info("Disabled extension '\(identifier)' because \(isListed ? "remote configuration lists it" : "extensions are not enabled")")
            } catch {
                Logger.webExtensions.error("Failed to disable remotely disabled extension '\(identifier)': \(error.localizedDescription)")
            }
        }
        if sweptCount > 0 {
            pixelFiring.fire(.killSwitchDisabled(count: sweptCount))
        }
    }

    private func isFromChromeWebStore(_ installedExtension: InstalledWebExtension) -> Bool {
        installedExtension.storeIdentity?.store == .chromeWebStore
    }

    private func pixelExtension(for installedExtension: InstalledWebExtension) -> WebExtensionPixelExtension {
        guard let storeIdentity = installedExtension.storeIdentity,
              let entry = manager?.chromeWebStore?.catalogEntry(of: storeIdentity.id) else {
            return .other
        }
        return .catalog(entry)
    }
}

//
//  ExtensionsManagementPreferences.swift
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
import PrivacyConfig
import WebExtensions

@available(macOS 15.4, *)
@MainActor
final class ExtensionsManagementPreferences: ObservableObject {

    @Published private(set) var installedExtensions: [ChromeWebStoreListing] = []
    @Published private(set) var uninstalledPasswordManagers: [ChromeWebStoreListing] = []
    @Published private var locallyDisabledIDs: Set<String> = []
    @Published private var remotelyDisabledIDs: Set<String> = []

    private let webExtensionManager: WebExtensionManaging?
    private let windowControllersManager: WindowControllersManagerProtocol
    private var cancellables = Set<AnyCancellable>()

    init(configurationManager: PrivacyConfigurationManaging, webExtensionManager: WebExtensionManaging? = nil, windowControllersManager: WindowControllersManagerProtocol) {
        self.webExtensionManager = webExtensionManager
        self.windowControllersManager = windowControllersManager

        reloadExtensions()
        startObservingChanges(configurationManager: configurationManager)
    }

    func openStorePage(for item: ChromeWebStoreListing) {
        windowControllersManager.show(url: item.storeURL, source: .ui, newTab: true, selected: true)
    }

    func isEnabled(_ item: ChromeWebStoreListing) -> Bool {
        !locallyDisabledIDs.contains(item.id) && !remotelyDisabledIDs.contains(item.id)
    }

    func isRemotelyDisabled(_ item: ChromeWebStoreListing) -> Bool {
        remotelyDisabledIDs.contains(item.id)
    }

    func setEnabled(_ isEnabled: Bool, for item: ChromeWebStoreListing) {
        guard let identifier = installedIdentifier(for: item) else {
            return
        }

        applyOptimisticEnabledState(isEnabled, for: item)
        Task { [weak self] in
            await self?.applyEnabledState(isEnabled, identifier: identifier)
        }
    }
}

@available(macOS 15.4, *)
private extension ExtensionsManagementPreferences {

    func startObservingChanges(configurationManager: PrivacyConfigurationManaging) {
        let extensionsPublisher = NotificationCenter.default
            .publisher(for: .chromeWebStoreExtensionChanged)
            .merge(with: NotificationCenter.default.publisher(for: .webExtensionsDidChangeLoadedExtensions))
            .asVoid()

        configurationManager.updatesPublisher
            .merge(with: extensionsPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.reloadExtensions()
            }
            .store(in: &cancellables)
    }

    func reloadExtensions() {
        guard let manager = webExtensionManager, let store = manager.chromeWebStore else {
            resetExtensions()
            return
        }

        (installedExtensions, locallyDisabledIDs, remotelyDisabledIDs) = classifyExtensions(manager: manager, store: store)
        uninstalledPasswordManagers = availablePasswordManagers(in: store)
    }

    func resetExtensions() {
        installedExtensions = []
        uninstalledPasswordManagers = []
        locallyDisabledIDs = []
        remotelyDisabledIDs = []
    }

    func classifyExtensions(manager: WebExtensionManaging, store: ChromeWebStoreManaging) -> (installed: [ChromeWebStoreListing], locallyDisabledIDs: Set<String>, remotelyDisabledIDs: Set<String>) {
        var installed: [ChromeWebStoreListing] = []
        var locallyDisabledIDs = Set<String>()
        var remotelyDisabledIDs = Set<String>()

        for identifier in manager.webExtensionIdentifiers {
            guard
                let record = manager.installedExtension(identifier: identifier),
                let listing = listing(for: record, in: store),
                !installed.contains(where: { $0.id == listing.id })
            else {
                // Old and new versions coexist during an update.
                continue
            }

            installed.append(listing)
            if record.isDisabled {
                locallyDisabledIDs.insert(listing.id)
            }
            if manager.isRemotelyDisabled(identifier: identifier) {
                remotelyDisabledIDs.insert(listing.id)
            }
        }

        return (installed, locallyDisabledIDs, remotelyDisabledIDs)
    }

    func availablePasswordManagers(in store: ChromeWebStoreManaging) -> [ChromeWebStoreListing] {
        store.catalogExtensionIDs
            .filter { store.status(for: $0) != .installed }
            .compactMap(store.catalogEntry(of:))
            .compactMap(store.listing(of:))
            .filter(\.isPasswordManager)
    }

    func installedIdentifier(for item: ChromeWebStoreListing) -> String? {
        guard let manager = webExtensionManager, let store = manager.chromeWebStore else {
            return nil
        }

        return manager.webExtensionIdentifiers.first { identifier in
            manager.installedExtension(identifier: identifier).flatMap { listing(for: $0, in: store) }?.id == item.id
        }
    }

    func listing(for record: InstalledWebExtension, in store: ChromeWebStoreManaging) -> ChromeWebStoreListing? {
        guard let storeIdentity = record.storeIdentity, storeIdentity.store == .chromeWebStore else {
            return nil
        }

        return store.catalogEntry(of: storeIdentity.id).flatMap(store.listing(of:))
    }

    /// Updated ahead of the async load, so the switch doesn't snap back.
    func applyOptimisticEnabledState(_ isEnabled: Bool, for item: ChromeWebStoreListing) {
        guard isEnabled else {
            locallyDisabledIDs.insert(item.id)
            return
        }

        locallyDisabledIDs.remove(item.id)
    }

    func applyEnabledState(_ isEnabled: Bool, identifier: String) async {
        guard let webExtensionManager else {
            return
        }

        do {
            guard isEnabled else {
                try await webExtensionManager.disableExtension(identifier: identifier)
                return
            }

            try await webExtensionManager.enableExtension(identifier: identifier)
        } catch {
            reloadExtensions()
        }
    }
}

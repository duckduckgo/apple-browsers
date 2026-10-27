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

    @Published private(set) var installedExtensions: [InstalledExtensionEntry] = []
    @Published private(set) var uninstalledPasswordManagers: [ChromeWebStoreListing] = []

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

    func setEnabled(_ isEnabled: Bool, for entry: InstalledExtensionEntry) {
        applyOptimisticEnabledState(isEnabled, for: entry)
        Task { [weak self] in
            await self?.applyEnabledState(isEnabled, identifier: entry.id)
        }
    }

    func remove(_ entry: InstalledExtensionEntry) {
        guard
            let store = webExtensionManager?.chromeWebStore,
            let storeID = entry.record.storeIdentity?.id
        else {
            return
        }

        Task {
            _ = await store.remove(identifier: storeID)
        }
    }
}

@available(macOS 15.4, *)
extension ExtensionsManagementPreferences {

    struct InstalledExtensionEntry: Identifiable {
        var record: InstalledWebExtension
        let listing: ChromeWebStoreListing
        let isRemotelyDisabled: Bool

        var id: String { record.uniqueIdentifier }
        var isEnabled: Bool { !record.isDisabled && !isRemotelyDisabled }
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

        installedExtensions = installedEntries(manager: manager, store: store)
        uninstalledPasswordManagers = availablePasswordManagers(in: store)
    }

    func resetExtensions() {
        installedExtensions = []
        uninstalledPasswordManagers = []
    }

    /// Built from the installation records, so extensions the catalog no longer offers stay listed.
    func installedEntries(manager: WebExtensionManaging, store: ChromeWebStoreManaging) -> [InstalledExtensionEntry] {
        var entries: [InstalledExtensionEntry] = []
        var seenListingIDs = Set<String>()

        for identifier in manager.webExtensionIdentifiers {
            guard
                let record = manager.installedExtension(identifier: identifier),
                let listing = listing(for: record, in: store),
                seenListingIDs.contains(listing.id) == false
            else {
                // Old and new versions coexist during an update.
                continue
            }

            let entry = InstalledExtensionEntry(record: record, listing: listing, isRemotelyDisabled: manager.isRemotelyDisabled(identifier: identifier))
            entries.append(entry)
            seenListingIDs.insert(listing.id)
        }

        return entries
    }

    func availablePasswordManagers(in store: ChromeWebStoreManaging) -> [ChromeWebStoreListing] {
        store.catalogExtensionIDs
            .filter { store.status(for: $0) != .installed }
            .compactMap(store.catalogEntry(of:))
            .compactMap(store.listing(of:))
            .filter(\.isPasswordManager)
    }

    func listing(for record: InstalledWebExtension, in store: ChromeWebStoreManaging) -> ChromeWebStoreListing? {
        guard let storeIdentity = record.storeIdentity, storeIdentity.store == .chromeWebStore else {
            return nil
        }

        return store.catalogEntry(of: storeIdentity.id).flatMap(store.listing(of:))
    }

    /// Updated ahead of the async load, so the switch doesn't snap back.
    func applyOptimisticEnabledState(_ isEnabled: Bool, for entry: InstalledExtensionEntry) {
        guard let index = installedExtensions.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        installedExtensions[index].record.isDisabled = !isEnabled
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

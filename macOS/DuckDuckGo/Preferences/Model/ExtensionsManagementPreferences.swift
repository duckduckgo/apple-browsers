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
    @Published private(set) var detailsListingID: String?

    /// Looked up by store ID, so an update keeps the details open.
    var detailsEntry: InstalledExtensionEntry? {
        detailsListingID.flatMap { id in
            installedExtensions.first { $0.listing.id == id }
        }
    }

    private let webExtensionManager: WebExtensionManaging?
    private let windowControllersManager: WindowControllersManagerProtocol
    private var cancellables = Set<AnyCancellable>()
    private var enabledStateTasks: [String: Task<Void, Never>] = [:]

    init(configurationManager: PrivacyConfigurationManaging, webExtensionManager: WebExtensionManaging? = nil, windowControllersManager: WindowControllersManagerProtocol) {
        self.webExtensionManager = webExtensionManager
        self.windowControllersManager = windowControllersManager

        reloadExtensions()
        startObservingChanges(configurationManager: configurationManager)
    }

    func openStorePage(for item: ChromeWebStoreListing) {
        windowControllersManager.show(url: item.storeURL, source: .ui, newTab: true, selected: true)
    }

    func showDetails(for entry: InstalledExtensionEntry) {
        detailsListingID = entry.listing.id
    }

    func hideDetails() {
        detailsListingID = nil
    }

    func setEnabled(_ isEnabled: Bool, for entry: InstalledExtensionEntry) {
        applyOptimisticEnabledState(isEnabled, for: entry)
        scheduleEnabledState(isEnabled, identifier: entry.id)
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

    func openLearnMore() {
        guard let url = webExtensionManager?.chromeWebStore?.learnMoreURL else {
            return
        }

        windowControllersManager.show(url: url, source: .ui, newTab: true, selected: true)
    }
}

@available(macOS 15.4, *)
extension ExtensionsManagementPreferences {

    struct InstalledExtensionEntry: Identifiable {
        var record: InstalledWebExtension
        let listing: ChromeWebStoreListing
        let isRemotelyDisabled: Bool
        /// Saved at installation, so they're known while the extension is disabled.
        let permissions: [String]

        var id: String { record.uniqueIdentifier }
        var isEnabled: Bool { !record.isDisabled && !isRemotelyDisabled }

        var permissionsSummary: String? {
            let names = permissions
                .compactMap(WebExtensionManifestPermission.init(rawValue:))
                .map(\.displayName)

            if names.isEmpty {
                return nil
            }

            let summary = ListFormatter.localizedString(byJoining: names)
            return summary.prefix(1).uppercased() + summary.dropFirst()
        }
    }
}

extension WebExtensionManifestPermission {

    var displayName: String {
        switch self {
        case .accessibilityFeaturesModify: UserText.extensionsSettingsPermissionAccessibilityFeaturesModify
        case .accessibilityFeaturesRead: UserText.extensionsSettingsPermissionAccessibilityFeaturesRead
        case .bookmarks: UserText.extensionsSettingsPermissionBookmarks
        case .clipboardRead: UserText.extensionsSettingsPermissionClipboardRead
        case .clipboardWrite: UserText.extensionsSettingsPermissionClipboardWrite
        case .contentSettings: UserText.extensionsSettingsPermissionContentSettings
        case .debugger: UserText.extensionsSettingsPermissionDebugger
        case .declarativeNetRequest: UserText.extensionsSettingsPermissionDeclarativeNetRequest
        case .declarativeNetRequestFeedback: UserText.extensionsSettingsPermissionDeclarativeNetRequestFeedback
        case .desktopCapture: UserText.extensionsSettingsPermissionDesktopCapture
        case .downloads: UserText.extensionsSettingsPermissionDownloads
        case .downloadsOpen: UserText.extensionsSettingsPermissionDownloadsOpen
        case .downloadsUI: UserText.extensionsSettingsPermissionDownloadsUI
        case .favicon: UserText.extensionsSettingsPermissionFavicon
        case .geolocation: UserText.extensionsSettingsPermissionGeolocation
        case .history: UserText.extensionsSettingsPermissionHistory
        case .identityEmail: UserText.extensionsSettingsPermissionIdentityEmail
        case .management: UserText.extensionsSettingsPermissionManagement
        case .nativeMessaging: UserText.extensionsSettingsPermissionNativeMessaging
        case .notifications: UserText.extensionsSettingsPermissionNotifications
        case .pageCapture: UserText.extensionsSettingsPermissionPageCapture
        case .privacy: UserText.extensionsSettingsPermissionPrivacy
        case .proxy: UserText.extensionsSettingsPermissionProxy
        case .readingList: UserText.extensionsSettingsPermissionReadingList
        case .sessions: UserText.extensionsSettingsPermissionSessions
        case .systemStorage: UserText.extensionsSettingsPermissionSystemStorage
        case .tabCapture: UserText.extensionsSettingsPermissionTabCapture
        case .tabGroups: UserText.extensionsSettingsPermissionTabGroups
        case .tabs: UserText.extensionsSettingsPermissionTabs
        case .topSites: UserText.extensionsSettingsPermissionTopSites
        case .ttsEngine: UserText.extensionsSettingsPermissionTtsEngine
        case .webAuthenticationProxy: UserText.extensionsSettingsPermissionWebAuthenticationProxy
        case .webNavigation: UserText.extensionsSettingsPermissionWebNavigation
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

        installedExtensions = installedEntries(manager: manager, store: store)
        uninstalledPasswordManagers = availablePasswordManagers(in: store)

        // Whoever removed it, a reinstall shouldn't reopen its details.
        if detailsEntry == nil {
            detailsListingID = nil
        }
    }

    func resetExtensions() {
        installedExtensions = []
        uninstalledPasswordManagers = []
        detailsListingID = nil
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

            let entry = InstalledExtensionEntry(record: record,
                                                listing: listing,
                                                isRemotelyDisabled: manager.isRemotelyDisabled(identifier: identifier),
                                                permissions: manager.extensionPermissions(for: identifier))
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

    func scheduleEnabledState(_ isEnabled: Bool, identifier: String) {
        let previousTask = enabledStateTasks[identifier]
        previousTask?.cancel()

        enabledStateTasks[identifier] = Task { [weak self] in
            await previousTask?.value
            if Task.isCancelled {
                return
            }

            await self?.applyEnabledState(isEnabled, identifier: identifier)
        }
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

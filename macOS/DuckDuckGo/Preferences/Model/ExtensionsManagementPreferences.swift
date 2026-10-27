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
import RemoteMessaging
import WebExtensions

struct ExtensionPasswordManager: Identifiable {
    let id: String
    let name: String
    let publisher: String
    let iconURL: URL?
    let storeURL: URL?
}

@MainActor
final class ExtensionsManagementPreferences: ObservableObject, @MainActor PreferencesTabOpening {

    @Published private(set) var uninstalledPasswordManagers: [ExtensionPasswordManager] = []

    private let catalog: ChromeWebStoreCatalog
    private let webExtensionManager: WebExtensionManaging?
    private var cancellables = Set<AnyCancellable>()

    let windowControllersManager: WindowControllersManagerProtocol
    let imageLoader: RemoteMessagingImageLoading

    init(configurationManager: PrivacyConfigurationManaging, imageLoader: RemoteMessagingImageLoading? = nil, webExtensionManager: WebExtensionManaging? = nil, windowControllersManager: WindowControllersManagerProtocol) {
        self.catalog = ChromeWebStoreCatalog(configurationManager: configurationManager)
        self.imageLoader = imageLoader ?? RemoteMessagingImageLoader(dataProvider: RemoteMessagingImageLoader.defaultDataProvider, cache: RemoteMessagingImageLoader.defaultCache)
        self.webExtensionManager = webExtensionManager
        self.windowControllersManager = windowControllersManager

        reloadPasswordManagers()
        startObservingChanges(configurationManager: configurationManager)
    }

    func openStorePage(for passwordManager: ExtensionPasswordManager) {
        guard let storeURL = passwordManager.storeURL else {
            return
        }

        openNewTab(with: storeURL)
    }
}

private extension ExtensionsManagementPreferences {

    func startObservingChanges(configurationManager: PrivacyConfigurationManaging) {
        let extensionsPublisher = NotificationCenter.default
            .publisher(for: .chromeWebStoreExtensionChanged)
            .asVoid()

        configurationManager.updatesPublisher
            .merge(with: extensionsPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.reloadPasswordManagers()
            }
            .store(in: &cancellables)
    }

    func reloadPasswordManagers() {
        uninstalledPasswordManagers = catalog.extensionIDs
            .filter(isUninstalled)
            .compactMap(catalog.catalogEntry(of:))
            .filter(\.isPasswordManager)
            .compactMap(passwordManager(for:))
    }

    func isUninstalled(_ storeID: String) -> Bool {
        guard #available(macOS 15.4, *) else {
            return true
        }

        return webExtensionManager?.chromeWebStore?.status(for: storeID) != .installed
    }

    func passwordManager(for entry: ExtensionsCatalogSubfeature) -> ExtensionPasswordManager? {
        guard let name = catalog.name(of: entry) else {
            return nil
        }

        return ExtensionPasswordManager(id: entry.rawValue,
                                        name: name,
                                        publisher: catalog.publisher(of: entry) ?? "",
                                        iconURL: catalog.iconURL(of: entry),
                                        storeURL: catalog.storeURL(of: entry))
    }
}

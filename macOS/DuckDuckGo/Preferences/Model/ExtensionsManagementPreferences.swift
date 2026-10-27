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

/// Lists the extensions catalog's password managers for the Extensions settings pane, refreshed on every Privacy Config update.
@MainActor
final class ExtensionsManagementPreferences: ObservableObject, PreferencesTabOpening {

    struct PasswordManager: Identifiable {
        let catalogEntry: ExtensionsCatalogSubfeature
        let name: String
        let publisher: String
        let iconURL: URL?
        let storeURL: URL?

        var id: String {
            catalogEntry.rawValue
        }
    }

    /// Enabled password managers, in catalog order. Entries without a name are skipped.
    @Published private(set) var passwordManagers: [PasswordManager] = []

    let windowControllersManager: WindowControllersManagerProtocol
    private let catalog: ChromeWebStoreCatalog
    private var cancellables = Set<AnyCancellable>()

    init(configurationManager: PrivacyConfigurationManaging, windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
        catalog = ChromeWebStoreCatalog(configurationManager: configurationManager)
        reloadPasswordManagers()

        configurationManager.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.reloadPasswordManagers()
            }
            .store(in: &cancellables)
    }

    /// Opens the password manager's Chrome Web Store page in a new tab.
    func openStorePage(for passwordManager: PasswordManager) {
        guard let storeURL = passwordManager.storeURL else { return }
        openNewTab(with: storeURL)
    }

    private func reloadPasswordManagers() {
        passwordManagers = catalog.enabledEntries.filter(\.isPasswordManager).compactMap { entry in
            guard let name = catalog.name(of: entry) else { return nil }
            return PasswordManager(catalogEntry: entry,
                                   name: name,
                                   publisher: catalog.publisher(of: entry) ?? "",
                                   iconURL: catalog.iconURL(of: entry),
                                   storeURL: catalog.storeURL(of: entry))
        }
    }
}

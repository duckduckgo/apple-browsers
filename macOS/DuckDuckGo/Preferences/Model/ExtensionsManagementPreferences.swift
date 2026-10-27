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

@MainActor
final class ExtensionsManagementPreferences: ObservableObject, @MainActor PreferencesTabOpening {

    @Published private(set) var uninstalledPasswordManagers: [ChromeWebStoreListing] = []

    private let webExtensionManager: WebExtensionManaging?
    private var cancellables = Set<AnyCancellable>()

    let windowControllersManager: WindowControllersManagerProtocol
    let imageLoader: RemoteMessagingImageLoading

    init(configurationManager: PrivacyConfigurationManaging, imageLoader: RemoteMessagingImageLoading? = nil, webExtensionManager: WebExtensionManaging? = nil, windowControllersManager: WindowControllersManagerProtocol) {
        self.imageLoader = imageLoader ?? RemoteMessagingImageLoader(dataProvider: RemoteMessagingImageLoader.defaultDataProvider, cache: RemoteMessagingImageLoader.defaultCache)
        self.webExtensionManager = webExtensionManager
        self.windowControllersManager = windowControllersManager

        reloadPasswordManagers()
        startObservingChanges(configurationManager: configurationManager)
    }

    func openStorePage(for passwordManager: ChromeWebStoreListing) {
        openNewTab(with: passwordManager.storeURL)
    }

    func openLearnMore() {
        guard #available(macOS 15.4, *), let url = webExtensionManager?.chromeWebStore?.learnMoreURL else {
            return
        }

        openNewTab(with: url)
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
        guard #available(macOS 15.4, *), let store = webExtensionManager?.chromeWebStore else {
            uninstalledPasswordManagers = []
            return
        }

        uninstalledPasswordManagers = store.catalogExtensionIDs
            .filter { store.status(for: $0) != .installed }
            .compactMap(store.catalogEntry(of:))
            .compactMap(store.listing(of:))
            .filter(\.isPasswordManager)
    }
}

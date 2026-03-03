//
//  WebExtensionManager+macOS.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import AppKit
import WebExtensions
import PrivacyConfig

// MARK: - macOS-specific WebExtensionManager Extensions

@available(macOS 15.4, *)
extension WebExtensionManager {

    /// Whether web extensions are enabled in the app.
    static var areExtensionsEnabled: Bool {
        NSApp.delegateTyped.webExtensionManager != nil
    }
}

// MARK: - AutoconsentPreferencesProviding

extension CookiePopupProtectionPreferences: AutoconsentPreferencesProviding {}

// MARK: - Factory

@available(macOS 15.4, *)
enum WebExtensionManagerFactory {

    /// Creates a fully configured WebExtensionManager with all macOS-specific providers.
    @MainActor
    static func makeManager(
        privacyConfigurationManager: PrivacyConfigurationManaging,
        autoconsentPreferences: AutoconsentPreferencesProviding,
        darkReaderExcludedDomainsProvider: DarkReaderExcludedDomainsProviding? = nil
    ) -> WebExtensionManager {
        let internalSiteHandler = WebExtensionInternalSiteHandler()

        let manager = WebExtensionManager(
            configuration: WebExtensionConfigurationProvider(),
            windowTabProvider: WebExtensionWindowTabProvider(),
            storageProvider: WebExtensionStorageProvider(),
            internalSiteHandler: internalSiteHandler,
            pixelFiring: MacOSWebExtensionPixelFiring(),
            handlerProvider: WebExtensionHandlerProvider(
                privacyConfigurationManager: privacyConfigurationManager,
                autoconsentPreferences: autoconsentPreferences,
                darkReaderExcludedDomainsProvider: darkReaderExcludedDomainsProvider
            )
        )

        internalSiteHandler.dataSource = manager

        return manager
    }
}

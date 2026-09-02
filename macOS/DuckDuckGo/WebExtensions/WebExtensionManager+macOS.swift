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
import AppKitExtensions
import Combine
import FeatureFlags_macOS
import PrivacyConfig
import WebExtensions

@available(macOS 15.4, *)
@MainActor
private final class MacOSCPMDiagnosticsFeatureFlags: CPMDiagnosticsFeatureFlagsProviding {
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var isBackgroundDelegateProxyEnabled: Bool {
        featureFlagger.isFeatureOn(.cpmBackgroundDelegateProxy)
    }

    var updatesPublisher: AnyPublisher<Void, Never> {
        featureFlagger.updatesPublisher
    }
}

// MARK: - macOS-specific WebExtensionManager Extensions

@available(macOS 15.4, *)
extension WebExtensionManager {

    /// Whether web extensions are enabled in the app.
    static var areExtensionsEnabled: Bool {
        NSApp.delegateTyped.webExtensionManager != nil
    }
}

// MARK: - Factory

@available(macOS 15.4, *)
enum WebExtensionManagerFactory {

    private static var extensionsDirectory: URL {
        URL.sandboxApplicationSupportURL.appendingPathComponent("WebExtensions", isDirectory: true)
    }

    /// Creates a fully configured WebExtensionManager with all macOS-specific providers.
    @MainActor
    static func makeManager(
        privacyConfigurationManager: PrivacyConfigurationManaging,
        autoconsentPreferences: AutoconsentPreferencesProviding,
        darkReaderExcludedDomainsProvider: DarkReaderExcludedDomainsProviding? = nil,
        scriptletConfiguration: ScriptletConfiguration? = nil
    ) -> WebExtensionManager {
        let internalSiteHandler = WebExtensionInternalSiteHandler()
        let pixelFiring = MacOSWebExtensionPixelFiring()
        let cpmMessagingHealthMonitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring)
        let cpmDiagnosticsRecorder = Application.appDelegate.featureFlagger.isFeatureOn(.cpmDiagnosticsRecorder) ? CPMMessagingDiagnosticsRecorder(
            tabResolver: { tabIdentifier in
                for windowController in Application.appDelegate.windowControllersManager.mainWindowControllers {
                    let viewModel = windowController.mainViewController.tabCollectionViewModel
                    if let tab = (viewModel.loadedPinnedTabs + viewModel.loadedTabs).first(where: { $0.uuid == tabIdentifier }) {
                        return (webView: tab.webView, extensionTab: tab)
                    }
                }
                return nil
            },
            featureFlags: MacOSCPMDiagnosticsFeatureFlags(featureFlagger: Application.appDelegate.featureFlagger),
            appSession: Application.appDelegate.cpmAppSessionDiagnostics
        ) : nil

        let manager = WebExtensionManager(
            configuration: WebExtensionConfigurationProvider(),
            windowTabProvider: WebExtensionWindowTabProvider(),
            storageProvider: WebExtensionStorageProvider(extensionsDirectory: extensionsDirectory),
            internalSiteHandler: internalSiteHandler,
            pixelFiring: pixelFiring,
            cpmMessagingHealthMonitor: cpmMessagingHealthMonitor,
            cpmDiagnosticsRecorder: cpmDiagnosticsRecorder,
            handlerProvider: WebExtensionHandlerProvider(
                privacyConfigurationManager: privacyConfigurationManager,
                autoconsentPreferences: autoconsentPreferences,
                cpmMessagingHealthMonitor: cpmMessagingHealthMonitor,
                darkReaderExcludedDomainsProvider: darkReaderExcludedDomainsProvider
            ),
            nativeMessagingHandler: NativeMessagingHandler(),
            scriptletConfiguration: scriptletConfiguration
        )

        internalSiteHandler.dataSource = manager

        return manager
    }
}

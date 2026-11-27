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
import DuckPlayer
import EventHub
import FeatureFlags_macOS
import Persistence
import PrivacyConfig
import WebExtensions

// MARK: - macOS-specific WebExtensionManager Extensions

@available(macOS 15.4, *)
extension WebExtensionManager {

    /// Whether web extensions are enabled in the app.
    static var areExtensionsEnabled: Bool {
        NSApp.delegateTyped.webExtensionManager != nil
    }

    /// Whether extension management is on for this user: launched for everyone, or for internal users only.
    static func isExtensionsEnabled(featureFlagger: FeatureFlagger) -> Bool {
        featureFlagger.isFeatureOn(.webExtensions) || featureFlagger.isFeatureOn(.webExtensionsInternal)
    }

    /// Installed with the manager, so `isRemotelyDisabled` is correct before the initial load finishes.
    @MainActor
    func installRemoteDisableEnforcer(configurationManager: PrivacyConfigurationManaging, featureFlagger: FeatureFlagger) {
        guard remoteDisableEnforcer == nil else { return }
        remoteDisableEnforcer = WebExtensionRemoteDisableEnforcer(
            manager: self,
            configurationManager: configurationManager,
            disabledExtensionIDs: { [featureFlagger] in
                Self.flagDisabledExtensionIDs(featureFlagger: featureFlagger)
            },
            disabledExtensionIDsDidChange: featureFlagger.updatesPublisher,
            isExtensionsEnabled: { [featureFlagger] in
                Self.isExtensionsEnabled(featureFlagger: featureFlagger)
            },
            pixelFiring: MacOSWebExtensionPixelFiring()
        )
    }

    /// Start after installed extensions load, so enforcement can't race the initial load.
    @MainActor
    func startRemoteDisableEnforcer() {
        remoteDisableEnforcer?.start()
    }

    /// Catalog extensions that a feature flag turns on or off.
    static let flaggedCatalogExtensions: [(flag: FeatureFlag, id: ChromeWebStoreID)] = [
        (.webExtensionBitwarden, .bitwarden),
        (.webExtensionOnePassword, .onePassword),
        (.webExtensionICloudPasswords, .iCloudPasswords),
    ]

    /// The catalog extensions whose feature flag is off.
    static func flagDisabledExtensionIDs(featureFlagger: FeatureFlagger) -> Set<String> {
        Set(flaggedCatalogExtensions.filter { !featureFlagger.isFeatureOn($0.flag) }.map(\.id.rawValue))
    }
}

// MARK: - Factory

@available(macOS 15.4, *)
enum WebExtensionManagerFactory {

    /// Catalog extensions this macOS version can't run.
    private static var unsupportedExtensionIDs: Set<String> {
        if #available(macOS 26, *) { return [] }
        return [ChromeWebStoreID.iCloudPasswords.rawValue]
    }

    private static var extensionsDirectory: URL {
        URL.sandboxApplicationSupportURL.appendingPathComponent("WebExtensions", isDirectory: true)
    }

    /// Creates a fully configured WebExtensionManager with all macOS-specific providers.
    @MainActor
    static func makeManager(
        keyValueStore: any ThrowingKeyValueStoring,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        autoconsentPreferences: AutoconsentPreferencesProviding,
        themeManager: ThemeManager,
        buildType: ApplicationBuildType = StandardApplicationBuildType(),
        featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger,
        darkReaderExcludedDomainsProvider: DarkReaderExcludedDomainsProviding? = nil,
        scriptletConfiguration: ScriptletConfiguration? = nil,
        eventHub: EventHubManaging,
        isAppleSurrogateRedirectionEnabled: @escaping @MainActor () -> Bool = { false }
    ) -> WebExtensionManager {
        let internalSiteHandler = WebExtensionInternalSiteHandler()
        let windowTabProvider = WebExtensionWindowTabProvider()
        func updateApplicationPolicy(for manager: WebExtensionManager) -> (@MainActor (String) -> Bool) {
            { [weak manager, weak windowTabProvider] identifier in
                guard !NSApp.isActive, let manager, let windowTabProvider else { return false }
                guard let context = manager.context(for: identifier) else { return true }
                return !windowTabProvider.hasOpenUpdateUI(for: context)
            }
        }
        let updateActivity = Publishers.MergeMany(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification).map { _ in () }.eraseToAnyPublisher(),
            windowTabProvider.updateActivityPublisher
        ).eraseToAnyPublisher()
        // Prompts attach to the browser window the user works in, including an extension's popup window. A prompt on
        // another window makes that window key, and extensions that later close `windows.getCurrent()` close it instead.
        let promptWindowProvider: () -> NSWindow? = {
            if let keyWindow = NSApp.keyWindow, keyWindow.windowController is MainWindowController {
                return keyWindow
            }
            return Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.window
        }
        let permissionPrompt = WebExtensionPermissionPrompt(
            windowProvider: promptWindowProvider,
            themeManager: themeManager,
            nativeMessagingAlertPresenter: NativeMessagingAlertPresenter(
                limitationProvider: { Application.appDelegate.webExtensionManager },
                alertPresenter: WebExtensionAlertPresenter(windowProvider: promptWindowProvider, themeManager: themeManager),
                windowControllersManager: Application.appDelegate.windowControllersManager
            )
        )
#if DEBUG && WEB_EXTENSION_UPDATE_TESTING
        if buildType.isDebugBuild, buildType.isSparkleBuild, ChromeWebStoreManualUpdateTesting.isEnabled {
            let manager = ChromeWebStoreManualUpdateTesting().makeManager(
                configuration: WebExtensionConfigurationProvider(), windowTabProvider: windowTabProvider,
                permissionPrompter: permissionPrompt,
                presenter: ChromeWebStorePresenter(windowProvider: { NSApp.keyWindow ?? NSApp.mainWindow }, themeManager: themeManager),
                internalSiteHandler: internalSiteHandler,
                isUpdateDiscoveryEnabled: { featureFlagger.isFeatureOn(.webExtensionUpdateDiscovery) },
                updateApplicationPolicy: updateApplicationPolicy,
                updateApplicationActivityUpdates: updateActivity)
            internalSiteHandler.dataSource = manager
            return manager
        }
#endif
        let pixelFiring = MacOSWebExtensionPixelFiring()
        let isInitProgressEnabled = { privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(AutoconsentSubfeature.cpmInitProgress) }
        let cpmMessagingHealthMonitor = CPMMessagingHealthMonitor(pixelFiring: pixelFiring,
                                                                  isUnmeasuredPage: { $0.isDuckPlayer },
                                                                  isInitProgressEnabled: isInitProgressEnabled)
        let installationStore = InstalledWebExtensionStore()
        let permissionController = WebExtensionPermissionController(
            store: WebExtensionPermissionStore(keyValueStore: keyValueStore),
            installationStore: installationStore,
            prompter: permissionPrompt
        )
        // The App Store sandbox cannot launch another app's host, so only Sparkle builds offer native messaging.
        let nativeMessagingHandler = buildType.isSparkleBuild
            ? NativeMessagingHandler(installationStore: installationStore)
            : nil
        let manager = WebExtensionManager(
            configuration: WebExtensionConfigurationProvider(),
            windowTabProvider: windowTabProvider,
            storageProvider: WebExtensionStorageProvider(extensionsDirectory: extensionsDirectory),
            installationStore: installationStore,
            permissionController: permissionController,
            internalSiteHandler: internalSiteHandler,
            pixelFiring: pixelFiring,
            cpmMessagingHealthMonitor: cpmMessagingHealthMonitor,
            isCPMNetworkProcessRecoveryEnabled: {
                featureFlagger.isFeatureOn(.cpmNetworkProcessRecovery)
            },
            cpmNetworkProcessRecoveryFeatureFlagUpdates: featureFlagger.updatesPublisher,
            isCPMBackgroundLoadRestartEnabled: {
                featureFlagger.isFeatureOn(.cpmBackgroundLoadRestart)
            },
            isCPMStableBaseURLEnabled: {
                featureFlagger.isFeatureOn(.cpmStableBaseURL)
            },
            isCPMUpgradeBeforeLoadEnabled: featureFlagger.isFeatureOn(.cpmUpgradeBeforeLoad),
            handlerProvider: WebExtensionHandlerProvider(
                privacyConfigurationManager: privacyConfigurationManager,
                autoconsentPreferences: autoconsentPreferences,
                cpmMessagingHealthMonitor: cpmMessagingHealthMonitor,
                darkReaderExcludedDomainsProvider: darkReaderExcludedDomainsProvider,
                eventHub: eventHub,
                isAppleSurrogateRedirectionEnabled: isAppleSurrogateRedirectionEnabled
            ),
            nativeMessagingHandler: nativeMessagingHandler,
            unavailablePermissions: buildType.isAppStoreBuild ? [.nativeMessaging] : [],
            nativeMessagingLimitationStore: buildType.isAppStoreBuild ? NativeMessagingLimitationStore(keyValueStore: keyValueStore) : nil,
            keyValueStore: keyValueStore,
            retentionStore: WebExtensionRetentionStore(storage: keyValueStore.throwingKeyedStoring()),
            scriptletConfiguration: scriptletConfiguration
        )

        internalSiteHandler.dataSource = manager
        manager.chromeWebStore = ChromeWebStoreService(
            manager: manager,
            catalog: ChromeWebStoreCatalog(configurationManager: privacyConfigurationManager,
                                           isExtensionsEnabled: {
                                               WebExtensionManager.isExtensionsEnabled(featureFlagger: featureFlagger)
                                           },
                                           isAppStoreBuild: buildType.isAppStoreBuild,
                                           unsupportedExtensionIDs: unsupportedExtensionIDs),
            presenter: ChromeWebStorePresenter(windowProvider: { NSApp.keyWindow ?? NSApp.mainWindow }, themeManager: themeManager),
            isUpdateDiscoveryEnabled: {
                WebExtensionManager.isExtensionsEnabled(featureFlagger: featureFlagger)
                    && featureFlagger.isFeatureOn(.webExtensionUpdateDiscovery)
            },
            updateDiscoveryFeatureFlagUpdates: featureFlagger.updatesPublisher,
            canApplyUpdatesWhileInactive: updateApplicationPolicy(for: manager),
            updateApplicationActivityUpdates: updateActivity,
            keyValueStore: keyValueStore,
            pixelFiring: pixelFiring
        )

        return manager
    }
}

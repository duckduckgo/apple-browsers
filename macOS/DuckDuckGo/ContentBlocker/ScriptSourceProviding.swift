//
//  ScriptSourceProviding.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Foundation
import Combine
import Common
import FoundationExtensions
import BrowserServicesKit
import Configuration
import History
import HistoryView
import NewTabPage
import TrackerRadarKit
import Persistence
import PixelKit
import PrivacyConfig
import enum UserScript.UserScriptError
import DDGSync
import WebExtensions

protocol ScriptSourceProviding {

    var featureFlagger: FeatureFlagger { get }
    var privacyConfigurationManager: PrivacyConfigurationManaging { get }
    var autofillSourceProvider: AutofillUserScriptSourceProvider? { get }
    var autoconsentManagement: AutoconsentManagement { get }
    var sessionKey: String? { get }
    var messageSecret: String? { get }
    var onboardingActionsManager: OnboardingActionsManaging? { get }
    var historyViewActionsManager: HistoryViewActionsManager? { get }
    var windowControllersManager: WindowControllersManagerProtocol { get }
    var currentCohorts: [ContentScopeExperimentData]? { get }
    var webTrackingProtectionPreferences: WebTrackingProtectionPreferences { get }
    var cookiePopupProtectionPreferences: CookiePopupProtectionPreferences { get }
    var duckPlayer: DuckPlayer { get }
    var syncServiceProvider: () -> DDGSyncing? { get }
    var syncErrorHandler: SyncErrorHandling { get }
    var webExtensionAvailability: WebExtensionAvailabilityProviding? { get }
    var trackerProtectionDataSource: TrackerProtectionDataSource? { get }
    /// The page-world Content Scope Scripts source every tab of this update shares.
    var contentScopeSource: ContentScopeScriptSource { get }
    /// The isolated Content Scope Scripts source every tab of this update shares.
    var contentScopeIsolatedSource: ContentScopeScriptSource { get }
    func buildAutofillSource() -> AutofillUserScriptSourceProvider

}

// refactor: ScriptSourceProvider to be passed to init methods as `some ScriptSourceProviding`, DefaultScriptSourceProvider to be killed
// swiftlint:disable:next identifier_name
@MainActor func DefaultScriptSourceProvider() -> ScriptSourceProviding {
    ScriptSourceProvider(
        configStorage: Application.appDelegate.configurationStore,
        privacyConfigurationManager: Application.appDelegate.privacyFeatures.contentBlocking.privacyConfigurationManager,
        webTrackingProtectionPreferences: Application.appDelegate.webTrackingProtectionPreferences,
        cookiePopupProtectionPreferences: Application.appDelegate.cookiePopupProtectionPreferences,
        duckPlayer: Application.appDelegate.duckPlayer,
        contentBlockingManager: Application.appDelegate.privacyFeatures.contentBlocking.contentBlockingManager,
        trackerDataManager: Application.appDelegate.privacyFeatures.contentBlocking.trackerDataManager,
        experimentManager: Application.appDelegate.contentScopeExperimentsManager,
        tld: Application.appDelegate.tld,
        featureFlagger: Application.appDelegate.featureFlagger,
        onboardingNavigationDelegate: Application.appDelegate.windowControllersManager,
        appearancePreferences: Application.appDelegate.appearancePreferences,
        themeManager: Application.appDelegate.themeManager,
        startupPreferences: Application.appDelegate.startupPreferences,
        windowControllersManager: Application.appDelegate.windowControllersManager,
        bookmarkManager: Application.appDelegate.bookmarkManager,
        pinningManager: Application.appDelegate.pinningManager,
        historyCoordinator: Application.appDelegate.historyCoordinator,
        fireproofDomains: Application.appDelegate.fireproofDomains,
        fireCoordinator: Application.appDelegate.fireCoordinator,
        autoconsentManagement: Application.appDelegate.autoconsentManagement,
        contentScopePreferences: Application.appDelegate.contentScopePreferences,
        syncServiceProvider: { [weak appDelegate = Application.appDelegate] in
            return appDelegate?.syncService
        },
        syncErrorHandler: Application.appDelegate.syncErrorHandler,
        webExtensionAvailability: Application.appDelegate.webExtensionAvailability,
        dockCustomization: Application.appDelegate.dockCustomization,
        reinstallUserDetection: DefaultReinstallUserDetection(keyValueStore: Application.appDelegate.keyValueStore),
        installDateProvider: { AppDelegate.firstLaunchDate }
    )
}

struct ScriptSourceProvider: ScriptSourceProviding {
    private(set) var onboardingActionsManager: OnboardingActionsManaging?
    private(set) var historyViewActionsManager: HistoryViewActionsManager?
    private(set) var autofillSourceProvider: AutofillUserScriptSourceProvider?
    private(set) var sessionKey: String?
    private(set) var messageSecret: String?
    private(set) var currentCohorts: [ContentScopeExperimentData]?

    let featureFlagger: FeatureFlagger
    let configStorage: ConfigurationStoring
    let privacyConfigurationManager: PrivacyConfigurationManaging
    let contentBlockingManager: ContentBlockerRulesManagerProtocol
    let trackerDataManager: TrackerDataManager
    let webTrackingProtectionPreferences: WebTrackingProtectionPreferences
    let cookiePopupProtectionPreferences: CookiePopupProtectionPreferences
    let duckPlayer: DuckPlayer
    let tld: TLD
    let experimentManager: ContentScopeExperimentsManaging
    let bookmarkManager: BookmarkManager & HistoryViewBookmarksHandling
    let pinningManager: PinningManager
    let historyCoordinator: HistoryDataSource
    let windowControllersManager: WindowControllersManagerProtocol
    let autoconsentManagement: AutoconsentManagement
    let syncServiceProvider: () -> DDGSyncing?
    let syncErrorHandler: SyncErrorHandling
    let webExtensionAvailability: WebExtensionAvailabilityProviding?
    let trackerProtectionDataSource: TrackerProtectionDataSource?
    let appearancePreferences: AppearancePreferences
    let dockCustomization: DockCustomization
    private let contentScopeSources: ContentScopeScriptSources

    var contentScopeSource: ContentScopeScriptSource { contentScopeSources.contentScope }
    var contentScopeIsolatedSource: ContentScopeScriptSource { contentScopeSources.contentScopeIsolated }

    init(configStorage: ConfigurationStoring,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         webTrackingProtectionPreferences: WebTrackingProtectionPreferences,
         cookiePopupProtectionPreferences: CookiePopupProtectionPreferences,
         duckPlayer: DuckPlayer,
         contentBlockingManager: ContentBlockerRulesManagerProtocol,
         trackerDataManager: TrackerDataManager,
         experimentManager: ContentScopeExperimentsManaging,
         tld: TLD,
         featureFlagger: FeatureFlagger,
         onboardingNavigationDelegate: OnboardingNavigating,
         appearancePreferences: AppearancePreferences,
         themeManager: ThemeManaging,
         startupPreferences: StartupPreferences,
         windowControllersManager: WindowControllersManagerProtocol,
         bookmarkManager: BookmarkManager & HistoryViewBookmarksHandling,
         pinningManager: PinningManager,
         historyCoordinator: HistoryDataSource,
         fireproofDomains: DomainFireproofStatusProviding,
         fireCoordinator: FireCoordinator,
         autoconsentManagement: AutoconsentManagement,
         contentScopePreferences: ContentScopePreferences,
         syncServiceProvider: @escaping () -> DDGSyncing?,
         syncErrorHandler: SyncErrorHandling,
         webExtensionAvailability: WebExtensionAvailabilityProviding?,
         dockCustomization: DockCustomization,
         reinstallUserDetection: ReinstallingUserDetecting,
         installDateProvider: @escaping () -> Date
    ) {

        self.configStorage = configStorage
        self.privacyConfigurationManager = privacyConfigurationManager
        self.webTrackingProtectionPreferences = webTrackingProtectionPreferences
        self.cookiePopupProtectionPreferences = cookiePopupProtectionPreferences
        self.duckPlayer = duckPlayer
        self.contentBlockingManager = contentBlockingManager
        self.trackerDataManager = trackerDataManager
        self.experimentManager = experimentManager
        self.tld = tld
        self.featureFlagger = featureFlagger
        self.bookmarkManager = bookmarkManager
        self.pinningManager = pinningManager
        self.historyCoordinator = historyCoordinator
        self.windowControllersManager = windowControllersManager
        self.autoconsentManagement = autoconsentManagement
        self.syncServiceProvider = syncServiceProvider
        self.syncErrorHandler = syncErrorHandler
        self.webExtensionAvailability = webExtensionAvailability
        self.trackerProtectionDataSource = DefaultTrackerProtectionDataSource(
            contentBlockingManager: contentBlockingManager
        )

        self.appearancePreferences = appearancePreferences
        self.dockCustomization = dockCustomization

        let sessionKey = Self.generateSessionKey()
        let messageSecret = Self.generateSessionKey()
        let currentCohorts = Self.generateCurrentCohorts(experimentManager: experimentManager)
        self.sessionKey = sessionKey
        self.messageSecret = messageSecret
        self.currentCohorts = currentCohorts
        self.contentScopeSources = Self.makeContentScopeSources(
            privacyConfigurationManager: privacyConfigurationManager,
            properties: ContentScopeProperties(gpcEnabled: webTrackingProtectionPreferences.isGPCEnabled,
                                               sessionKey: sessionKey,
                                               messageSecret: messageSecret,
                                               isInternalUser: featureFlagger.internalUserDecider.isInternalUser,
                                               debug: contentScopePreferences.isDebugStateEnabled,
                                               featureToggles: ContentScopeFeatureToggles.supportedFeaturesOnMacOS(privacyConfigurationManager.privacyConfig),
                                               currentCohorts: currentCohorts,
                                               themeVariant: appearancePreferences.themeName.rawValue),
            surrogateTrackerData: trackerProtectionDataSource?.surrogateFilteredTrackerData
        )
        self.autofillSourceProvider = buildAutofillSource()
        self.onboardingActionsManager = buildOnboardingActionsManager(
            onboardingNavigationDelegate,
            appearancePreferences,
            startupPreferences,
            reinstallUserDetection,
            installDateProvider
        )
        self.historyViewActionsManager = HistoryViewActionsManager(
            historyCoordinator: historyCoordinator,
            bookmarksHandler: bookmarkManager,
            featureFlagger: featureFlagger,
            themeManager: themeManager,
            fireproofStatusProvider: fireproofDomains,
            tld: tld,
            fire: { @MainActor in fireCoordinator.fireViewModel.fire }
        )
    }

    /// Builds the Content Scope Scripts sources now, on the calling thread, rather than when the first tab asks for them.
    func buildContentScopeSources() {
        contentScopeSources.build()
    }

    private static func makeContentScopeSources(privacyConfigurationManager: PrivacyConfigurationManaging,
                                                properties: ContentScopeProperties,
                                                surrogateTrackerData: TrackerData?) -> ContentScopeScriptSources {
        // Native-only — Duck.ai gates on `supportsBrowserTools` and never reads this key.
        // Windows found injecting it broke the aiChat message bridge, which is shared code.
        let nativeOnlyFeatures = [PrivacyFeature.aiChatBrowserTools.rawValue]
        return ContentScopeScriptSources(
            privacyConfigurationManager: privacyConfigurationManager,
            properties: properties,
            surrogateTrackerData: surrogateTrackerData,
            contentScopeExcludedFeatures: [PrivacyFeature.autoconsent.rawValue, PrivacyFeature.eventHub.rawValue] + nativeOnlyFeatures,
            contentScopeIsolatedExcludedFeatures: ContentScopePrivacyConfigurationJSONGenerator.defaultExcludedFeatures + nativeOnlyFeatures,
            onFailure: { error in
                if let error = error as? UserScriptError {
                    error.fireLoadJSFailedPixelIfNeeded()
                }
                fatalError("Failed to build the Content Scope Scripts source: \(error.localizedDescription)")
            }
        )
    }

    private static func generateSessionKey() -> String {
        return UUID().uuidString
    }

    public func buildAutofillSource() -> AutofillUserScriptSourceProvider {
        let privacyConfig = privacyConfigurationManager.privacyConfig
        let themeVariant = appearancePreferences.themeName.rawValue
        do {
            return try DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfigurationManager,
                                                             properties: ContentScopeProperties(gpcEnabled: webTrackingProtectionPreferences.isGPCEnabled,
                                                                                                sessionKey: self.sessionKey ?? "",
                                                                                                messageSecret: self.messageSecret ?? "",
                                                                                                featureToggles: ContentScopeFeatureToggles.supportedFeaturesOnMacOS(privacyConfig),
                                                                                                themeVariant: themeVariant),
                                                             isDebug: AutofillPreferences().debugScriptEnabled)
            .withJSLoading()
            .build()
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to build DefaultAutofillSourceProvider: \(error.localizedDescription)")
        }
    }

    private func buildOnboardingActionsManager(
        _ navigationDelegate: OnboardingNavigating,
        _ appearancePreferences: AppearancePreferences,
        _ startupPreferences: StartupPreferences,
        _ reinstallUserDetection: ReinstallingUserDetecting,
        _ installDateProvider: @escaping () -> Date
    ) -> OnboardingActionsManaging {
        return OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: SystemDefaultBrowserProvider(),
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            bookmarkManager: bookmarkManager,
            pinningManager: pinningManager,
            featureFlagger: featureFlagger,
            reinstallUserDetection: reinstallUserDetection,
            installDateProvider: installDateProvider,
            contextualOnboardingStateUpdater: Application.appDelegate.onboardingContextualDialogsManager
        )
    }

    private func loadTextFile(_ fileName: String, _ fileExt: String) -> String? {
        let url = Bundle.main.url(
            forResource: fileName,
            withExtension: fileExt
        )
        guard let data = try? String(contentsOf: url!) else {
            assertionFailure("Failed to load text file")
            return nil
        }

        return data
    }

    private static func generateCurrentCohorts(experimentManager: ContentScopeExperimentsManaging) -> [ContentScopeExperimentData] {
        let experiments = experimentManager.resolveContentScopeScriptActiveExperiments()
        return experiments.map {
            ContentScopeExperimentData(feature: $0.value.parentID, subfeature: $0.key, cohort: $0.value.cohortID)
        }
    }
}

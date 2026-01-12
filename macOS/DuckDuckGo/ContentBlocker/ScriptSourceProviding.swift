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
import BrowserServicesKit
import Configuration
import History
import HistoryView
import NewTabPage
import TrackerRadarKit
import PixelKit
import PrivacyConfig
import enum UserScript.UserScriptError

protocol ScriptSourceProviding {

    var featureFlagger: FeatureFlagger { get }
    var configStorage: ConfigurationStoring { get }
    var contentBlockingManager: ContentBlockerRulesManagerProtocol { get }
    var privacyConfigurationManager: PrivacyConfigurationManaging { get }
    var autofillSourceProvider: AutofillUserScriptSourceProvider? { get }
    var autoconsentManagement: AutoconsentManagement { get }
    var sessionKey: String? { get }
    var messageSecret: String? { get }
    var onboardingActionsManager: OnboardingActionsManaging? { get }
    var newTabPageActionsManager: NewTabPageActionsManager? { get }
    var historyViewActionsManager: HistoryViewActionsManager? { get }
    var windowControllersManager: WindowControllersManagerProtocol { get }
    var currentCohorts: [ContentScopeExperimentData]? { get }
    var webTrackingProtectionPreferences: WebTrackingProtectionPreferences { get }
    var cookiePopupProtectionPreferences: CookiePopupProtectionPreferences { get }
    var duckPlayer: DuckPlayer { get }
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
        historyCoordinator: Application.appDelegate.historyCoordinator,
        fireproofDomains: Application.appDelegate.fireproofDomains,
        fireCoordinator: Application.appDelegate.fireCoordinator,
        autoconsentManagement: Application.appDelegate.autoconsentManagement,
        newTabPageActionsManager: nil
    )
}

struct ScriptSourceProvider: ScriptSourceProviding {
    private(set) var onboardingActionsManager: OnboardingActionsManaging?
    private(set) var newTabPageActionsManager: NewTabPageActionsManager?
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
    let historyCoordinator: HistoryDataSource
    let windowControllersManager: WindowControllersManagerProtocol
    let autoconsentManagement: AutoconsentManagement

    @MainActor
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
         historyCoordinator: HistoryDataSource,
         fireproofDomains: DomainFireproofStatusProviding,
         fireCoordinator: FireCoordinator,
         autoconsentManagement: AutoconsentManagement,
         newTabPageActionsManager: NewTabPageActionsManager?
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
        self.historyCoordinator = historyCoordinator
        self.windowControllersManager = windowControllersManager
        self.autoconsentManagement = autoconsentManagement

        self.newTabPageActionsManager = newTabPageActionsManager
        self.sessionKey = generateSessionKey()
        self.messageSecret = generateSessionKey()
        self.autofillSourceProvider = buildAutofillSource()
        self.onboardingActionsManager = buildOnboardingActionsManager(onboardingNavigationDelegate, appearancePreferences, startupPreferences)
        self.historyViewActionsManager = HistoryViewActionsManager(
            historyCoordinator: historyCoordinator,
            bookmarksHandler: bookmarkManager,
            featureFlagger: featureFlagger,
            themeManager: themeManager,
            fireproofStatusProvider: fireproofDomains,
            tld: tld,
            fire: { @MainActor in fireCoordinator.fireViewModel.fire }
        )
        self.currentCohorts = generateCurrentCohorts()
    }

    private func generateSessionKey() -> String {
        return UUID().uuidString
    }

    public func buildAutofillSource() -> AutofillUserScriptSourceProvider {
        let privacyConfig = self.privacyConfigurationManager.privacyConfig
        do {
            return try DefaultAutofillSourceProvider.Builder(privacyConfigurationManager: privacyConfigurationManager,
                                                             properties: ContentScopeProperties(gpcEnabled: webTrackingProtectionPreferences.isGPCEnabled,
                                                                                                sessionKey: self.sessionKey ?? "",
                                                                                                messageSecret: self.messageSecret ?? "",
                                                                                                featureToggles: ContentScopeFeatureToggles.supportedFeaturesOnMacOS(privacyConfig)),
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

    @MainActor
    private func buildOnboardingActionsManager(_ navigationDelegate: OnboardingNavigating, _ appearancePreferences: AppearancePreferences, _ startupPreferences: StartupPreferences) -> OnboardingActionsManaging {
        return OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: DockCustomizer(),
            defaultBrowserProvider: SystemDefaultBrowserProvider(),
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            bookmarkManager: bookmarkManager
        )
    }

    private func generateCurrentCohorts() -> [ContentScopeExperimentData] {
        let experiments = experimentManager.resolveContentScopeScriptActiveExperiments()
        return experiments.map {
            ContentScopeExperimentData(feature: $0.value.parentID, subfeature: $0.key, cohort: $0.value.cohortID)
        }
    }
}

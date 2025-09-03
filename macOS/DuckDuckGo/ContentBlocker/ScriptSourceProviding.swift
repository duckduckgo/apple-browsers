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
import enum UserScript.UserScriptError

protocol ScriptSourceProviding {

    var featureFlagger: FeatureFlagger { get }
    var contentBlockerRulesConfig: ContentBlockerUserScriptConfig? { get }
    var surrogatesConfig: SurrogatesUserScriptConfig? { get }
    var privacyConfigurationManager: PrivacyConfigurationManaging { get }
    var autofillSourceProvider: AutofillUserScriptSourceProvider? { get }
    var sessionKey: String? { get }
    var messageSecret: String? { get }
    var onboardingActionsManager: OnboardingActionsManaging? { get }
    var newTabPageActionsManager: NewTabPageActionsManager? { get }
    var historyViewActionsManager: HistoryViewActionsManager? { get }
    var windowControllersManager: WindowControllersManagerProtocol { get }
    var currentCohorts: [ContentScopeExperimentData]? { get }
    func buildAutofillSource() -> AutofillUserScriptSourceProvider

}

// refactor: ScriptSourceProvider to be passed to init methods as `some ScriptSourceProviding`, DefaultScriptSourceProvider to be killed
// swiftlint:disable:next identifier_name
@MainActor func DefaultScriptSourceProvider() -> ScriptSourceProviding {
    ScriptSourceProvider(
        configStorage: Application.appDelegate.configurationStore,
        privacyConfigurationManager: Application.appDelegate.privacyFeatures.contentBlocking.privacyConfigurationManager,
        webTrackingProtectionPreferences: WebTrackingProtectionPreferences.shared,
        contentBlockingManager: Application.appDelegate.privacyFeatures.contentBlocking.contentBlockingManager,
        trackerDataManager: Application.appDelegate.privacyFeatures.contentBlocking.trackerDataManager,
        experimentManager: Application.appDelegate.contentScopeExperimentsManager,
        tld: Application.appDelegate.tld,
        featureFlagger: Application.appDelegate.featureFlagger,
        onboardingNavigationDelegate: Application.appDelegate.windowControllersManager,
        appearancePreferences: Application.appDelegate.appearancePreferences,
        startupPreferences: Application.appDelegate.startupPreferences,
        windowControllersManager: Application.appDelegate.windowControllersManager,
        bookmarkManager: Application.appDelegate.bookmarkManager,
        historyCoordinator: Application.appDelegate.historyCoordinator,
        fireproofDomains: Application.appDelegate.fireproofDomains,
        fireCoordinator: Application.appDelegate.fireCoordinator,
        newTabPageActionsManager: nil
    )
}

struct ScriptSourceProvider: ScriptSourceProviding {
    private(set) var contentBlockerRulesConfig: ContentBlockerUserScriptConfig?
    private(set) var surrogatesConfig: SurrogatesUserScriptConfig?
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
    let webTrakcingProtectionPreferences: WebTrackingProtectionPreferences
    let tld: TLD
    let experimentManager: ContentScopeExperimentsManaging
    let bookmarkManager: BookmarkManager & HistoryViewBookmarksHandling
    let historyCoordinator: HistoryDataSource
    let windowControllersManager: WindowControllersManagerProtocol

    @MainActor
    init(configStorage: ConfigurationStoring,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         webTrackingProtectionPreferences: WebTrackingProtectionPreferences,
         contentBlockingManager: ContentBlockerRulesManagerProtocol,
         trackerDataManager: TrackerDataManager,
         experimentManager: ContentScopeExperimentsManaging,
         tld: TLD,
         featureFlagger: FeatureFlagger,
         onboardingNavigationDelegate: OnboardingNavigating,
         appearancePreferences: AppearancePreferences,
         startupPreferences: StartupPreferences,
         windowControllersManager: WindowControllersManagerProtocol,
         bookmarkManager: BookmarkManager & HistoryViewBookmarksHandling,
         historyCoordinator: HistoryDataSource,
         fireproofDomains: DomainFireproofStatusProviding,
         fireCoordinator: FireCoordinator,
         newTabPageActionsManager: NewTabPageActionsManager?
    ) {

        self.configStorage = configStorage
        self.privacyConfigurationManager = privacyConfigurationManager
        self.webTrakcingProtectionPreferences = webTrackingProtectionPreferences
        self.contentBlockingManager = contentBlockingManager
        self.trackerDataManager = trackerDataManager
        self.experimentManager = experimentManager
        self.tld = tld
        self.featureFlagger = featureFlagger
        self.bookmarkManager = bookmarkManager
        self.historyCoordinator = historyCoordinator
        self.windowControllersManager = windowControllersManager

        self.newTabPageActionsManager = newTabPageActionsManager
        self.contentBlockerRulesConfig = buildContentBlockerRulesConfig()
        self.surrogatesConfig = buildSurrogatesConfig()
        self.sessionKey = generateSessionKey()
        self.messageSecret = generateSessionKey()
        self.autofillSourceProvider = buildAutofillSource()
        self.onboardingActionsManager = buildOnboardingActionsManager(onboardingNavigationDelegate, appearancePreferences, startupPreferences)
        self.historyViewActionsManager = HistoryViewActionsManager(
            historyCoordinator: historyCoordinator,
            bookmarksHandler: bookmarkManager,
            fireproofStatusProvider: fireproofDomains,
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
                                                             properties: ContentScopeProperties(gpcEnabled: webTrakcingProtectionPreferences.isGPCEnabled,
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

    private func buildContentBlockerRulesConfig() -> ContentBlockerUserScriptConfig {

        let tdsName = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName
        let trackerData = contentBlockingManager.currentRules.first(where: { $0.name == tdsName })?.trackerData

        let ctlTrackerData = (contentBlockingManager.currentRules.first(where: {
            $0.name == DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName
        })?.trackerData)

        do {
            return try DefaultContentBlockerUserScriptConfig(privacyConfiguration: privacyConfigurationManager.privacyConfig,
                                                             trackerData: trackerData,
                                                             ctlTrackerData: ctlTrackerData,
                                                             tld: tld,
                                                             trackerDataManager: trackerDataManager)
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to initialize DefaultContentBlockerUserScriptConfig: \(error.localizedDescription)")
        }
    }

    private func buildSurrogatesConfig() -> SurrogatesUserScriptConfig {

        let isDebugBuild: Bool
#if DEBUG
        isDebugBuild = true
#else
        isDebugBuild = false
#endif

        let surrogates = configStorage.loadData(for: .surrogates)?.utf8String() ?? ""
        let allTrackers = mergeTrackerDataSets(rules: contentBlockingManager.currentRules)
        do {
            return try DefaultSurrogatesUserScriptConfig(privacyConfig: privacyConfigurationManager.privacyConfig,
                                                         surrogates: surrogates,
                                                         trackerData: allTrackers.trackerData,
                                                         encodedSurrogateTrackerData: allTrackers.encodedTrackerData,
                                                         trackerDataManager: trackerDataManager,
                                                         tld: tld,
                                                         isDebugBuild: isDebugBuild)
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to initialize DefaultSurrogatesUserScriptConfig: \(error.localizedDescription)")
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

    private func mergeTrackerDataSets(rules: [ContentBlockerRulesManager.Rules]) -> (trackerData: TrackerData, encodedTrackerData: String) {
        var combinedTrackers: [String: KnownTracker] = [:]
        var combinedEntities: [String: Entity] = [:]
        var combinedDomains: [String: String] = [:]
        var cnames: [TrackerData.CnameDomain: TrackerData.TrackerDomain]? = [:]

        let setsToCombine = [ DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName, DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName ]

        for setName in setsToCombine {
            if let ruleSetIndex = contentBlockingManager.currentRules.firstIndex(where: { $0.name == setName }) {
                let ruleSet = rules[ruleSetIndex]

                combinedTrackers = combinedTrackers.merging(ruleSet.trackerData.trackers) { (_, new) in new }
                combinedEntities = combinedEntities.merging(ruleSet.trackerData.entities) { (_, new) in new }
                combinedDomains = combinedDomains.merging(ruleSet.trackerData.domains) { (_, new) in new }
                if setName == DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName {
                    cnames = ruleSet.trackerData.cnames
                }
            }
        }

        let combinedTrackerData = TrackerData(trackers: combinedTrackers,
                            entities: combinedEntities,
                            domains: combinedDomains,
                            cnames: cnames)

        let surrogateTDS = ContentBlockerRulesManager.extractSurrogates(from: combinedTrackerData)
        let encodedTrackerData = encodeTrackerData(surrogateTDS)

        return (trackerData: combinedTrackerData, encodedTrackerData: encodedTrackerData)
    }

    private func encodeTrackerData(_ trackerData: TrackerData) -> String {
        let encodedData = try? JSONEncoder().encode(trackerData)
        return String(data: encodedData!, encoding: .utf8)!
    }

    private func generateCurrentCohorts() -> [ContentScopeExperimentData] {
        let experiments = experimentManager.resolveContentScopeScriptActiveExperiments()
        return experiments.map {
            ContentScopeExperimentData(feature: $0.value.parentID, subfeature: $0.key, cohort: $0.value.cohortID)
        }
    }
}

//
//  ContentBlocking.swift
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
import WebKit
import Combine
import ContentBlocking
import BrowserServicesKit
import Common
import os.log
import Persistence
import PixelKit
import PixelExperimentKit
import PrivacyConfig
import WebExtensions

protocol ContentBlockingProtocol {

    var privacyConfigurationManager: PrivacyConfigurationManaging { get }
    var contentBlockingManager: ContentBlockerRulesManagerProtocol { get }
    var trackerDataManager: TrackerDataManager { get }
    var tld: TLD { get }

    var contentBlockingAssetsPublisher: AnyPublisher<UserContentUpdating.NewContent, Never> { get }

}

// refactor: AnyContentBlocking to be removed, ContentBlockingProtocol to be renamed to ContentBlocking
// ContentBlocking to be passed to init methods as `some ContentBlocking`
typealias AnyContentBlocking = any ContentBlockingProtocol & AdClickAttributionDependencies

final class AppContentBlocking {
    let privacyConfigurationManager: PrivacyConfigurationManaging
    let trackerDataManager: TrackerDataManager
    let contentBlockingManager: ContentBlockerRulesManagerProtocol
    let userContentUpdating: UserContentUpdating

    let tld: TLD

    let adClickAttribution: AdClickAttributing
    let adClickAttributionRulesProvider: AdClickAttributionRulesProviding

    private let contentBlockerRulesSource: ContentBlockerRulesLists
    private let exceptionsSource: DefaultContentBlockerRulesExceptionsSource

    enum Constants {
        enum ParameterName {
            static let experimentName = "experimentName"
            static let etag = "etag"
        }
    }

    // keeping whole ContentBlocking state initialization in one place to avoid races between updates publishing and rules storing
    @MainActor
    convenience init(
        database: CoreDataDatabase,
        internalUserDecider: InternalUserDecider,
        featureFlagger: FeatureFlagger,
        configurationStore: ConfigurationStore,
        contentScopeExperimentsManager: @autoclosure @escaping () -> ContentScopeExperimentsManaging,
        onboardingNavigationDelegate: OnboardingNavigating,
        appearancePreferences: AppearancePreferences,
        themeManager: ThemeManaging,
        startupPreferences: StartupPreferences,
        webTrackingProtectionPreferences: WebTrackingProtectionPreferences,
        cookiePopupProtectionPreferences: CookiePopupProtectionPreferences,
        duckPlayer: DuckPlayer,
        windowControllersManager: WindowControllersManagerProtocol,
        bookmarkManager: BookmarkManager & HistoryViewBookmarksHandling,
        pinningManager: PinningManager,
        historyCoordinator: HistoryDataSource,
        fireproofDomains: DomainFireproofStatusProviding,
        fireCoordinator: FireCoordinator,
        tld: TLD,
        autoconsentManagement: AutoconsentManagement,
        contentScopePreferences: ContentScopePreferences,
        syncErrorHandler: SyncErrorHandling,
        webExtensionAvailability: WebExtensionAvailabilityProviding?
    ) {
#if DEBUG || REVIEW
        // When TEST_PRIVACY_CONFIG_PATH is set, skip cached config to use embedded (test) config
        let useTestConfig = ProcessInfo.processInfo.environment[AppPrivacyConfigurationDataProvider.EnvironmentKeys.testPrivacyConfigPath] != nil
        let fetchedEtag: String? = useTestConfig ? nil : configurationStore.loadEtag(for: .privacyConfiguration)
        let fetchedData: Data? = useTestConfig ? nil : configurationStore.loadData(for: .privacyConfiguration)

        if useTestConfig {
            Logger.general.log("[DDG-TEST-CONFIG] Skipping cached privacy config to use TEST_PRIVACY_CONFIG_PATH")
        }
#else
        let fetchedEtag: String? = configurationStore.loadEtag(for: .privacyConfiguration)
        let fetchedData: Data? = configurationStore.loadData(for: .privacyConfiguration)
#endif

        let privacyConfigurationManager = PrivacyConfigurationManager(fetchedETag: fetchedEtag,
                                                                      fetchedData: fetchedData,
                                                                      embeddedDataProvider: AppPrivacyConfigurationDataProvider(),
                                                                      localProtection: LocalUnprotectedDomains(database: database),
                                                                      errorReporting: Self.debugEvents,
                                                                      internalUserDecider: internalUserDecider)
        self.init(
            privacyConfigurationManager: privacyConfigurationManager,
            internalUserDecider: internalUserDecider,
            featureFlagger: featureFlagger,
            configurationStore: configurationStore,
            contentScopeExperimentsManager: contentScopeExperimentsManager(),
            onboardingNavigationDelegate: onboardingNavigationDelegate,
            appearancePreferences: appearancePreferences,
            themeManager: themeManager,
            startupPreferences: startupPreferences,
            webTrackingProtectionPreferences: webTrackingProtectionPreferences,
            cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
            duckPlayer: duckPlayer,
            windowControllersManager: windowControllersManager,
            bookmarkManager: bookmarkManager,
            pinningManager: pinningManager,
            historyCoordinator: historyCoordinator,
            fireproofDomains: fireproofDomains,
            fireCoordinator: fireCoordinator,
            tld: tld,
            autoconsentManagement: autoconsentManagement,
            contentScopePreferences: contentScopePreferences,
            syncErrorHandler: syncErrorHandler,
            webExtensionAvailability: webExtensionAvailability
        )
    }

    @MainActor
    init(
        privacyConfigurationManager: PrivacyConfigurationManager,
        internalUserDecider: InternalUserDecider,
        featureFlagger: FeatureFlagger,
        configurationStore: ConfigurationStore,
        contentScopeExperimentsManager: @autoclosure @escaping () -> ContentScopeExperimentsManaging,
        onboardingNavigationDelegate: OnboardingNavigating,
        appearancePreferences: AppearancePreferences,
        themeManager: ThemeManaging,
        startupPreferences: StartupPreferences,
        webTrackingProtectionPreferences: WebTrackingProtectionPreferences,
        cookiePopupProtectionPreferences: CookiePopupProtectionPreferences,
        duckPlayer: DuckPlayer,
        windowControllersManager: WindowControllersManagerProtocol,
        bookmarkManager: BookmarkManager & HistoryViewBookmarksHandling,
        pinningManager: PinningManager,
        historyCoordinator: HistoryDataSource,
        fireproofDomains: DomainFireproofStatusProviding,
        fireCoordinator: FireCoordinator,
        tld: TLD,
        autoconsentManagement: AutoconsentManagement,
        contentScopePreferences: ContentScopePreferences,
        syncErrorHandler: SyncErrorHandling,
        webExtensionAvailability: WebExtensionAvailabilityProviding?
    ) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.tld = tld

#if DEBUG || REVIEW
        // When using test config, also skip cached tracker data to ensure consistent state
        let useTestConfig = ProcessInfo.processInfo.environment[AppPrivacyConfigurationDataProvider.EnvironmentKeys.testPrivacyConfigPath] != nil
        let trackerEtag: String? = useTestConfig ? nil : configurationStore.loadEtag(for: .trackerDataSet)
        let trackerData: Data? = useTestConfig ? nil : configurationStore.loadData(for: .trackerDataSet)
#else
        let trackerEtag: String? = configurationStore.loadEtag(for: .trackerDataSet)
        let trackerData: Data? = configurationStore.loadData(for: .trackerDataSet)
#endif

        trackerDataManager = TrackerDataManager(etag: trackerEtag,
                                                data: trackerData,
                                                embeddedDataProvider: AppTrackerDataSetProvider(),
                                                errorReporting: Self.debugEvents)

        adClickAttribution = AdClickAttributionFeature(with: privacyConfigurationManager)

        contentBlockerRulesSource = ContentBlockerRulesLists(trackerDataManager: trackerDataManager, adClickAttribution: adClickAttribution)
        exceptionsSource = DefaultContentBlockerRulesExceptionsSource(privacyConfigManager: privacyConfigurationManager)

        contentBlockingManager = ContentBlockerRulesManager(rulesSource: contentBlockerRulesSource,
                                                            exceptionsSource: exceptionsSource,
                                                            cache: ContentBlockingRulesCache(),
                                                            errorReporting: Self.debugEvents)
        userContentUpdating = UserContentUpdating(contentBlockerRulesManager: contentBlockingManager,
                                                  privacyConfigurationManager: privacyConfigurationManager,
                                                  trackerDataManager: trackerDataManager,
                                                  configStorage: configurationStore,
                                                  webTrackingProtectionPreferences: webTrackingProtectionPreferences,
                                                  cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
                                                  duckPlayer: duckPlayer,
                                                  experimentManager: contentScopeExperimentsManager(),
                                                  tld: tld,
                                                  featureFlagger: featureFlagger,
                                                  onboardingNavigationDelegate: onboardingNavigationDelegate,
                                                  appearancePreferences: appearancePreferences,
                                                  themeManager: themeManager,
                                                  startupPreferences: startupPreferences,
                                                  windowControllersManager: windowControllersManager,
                                                  bookmarkManager: bookmarkManager,
                                                  pinningManager: pinningManager,
                                                  historyCoordinator: historyCoordinator,
                                                  fireproofDomains: fireproofDomains,
                                                  fireCoordinator: fireCoordinator,
                                                  autoconsentManagement: autoconsentManagement,
                                                  contentScopePreferences: contentScopePreferences,
                                                  syncErrorHandler: syncErrorHandler,
                                                  webExtensionAvailability: webExtensionAvailability)

        adClickAttributionRulesProvider = AdClickAttributionRulesProvider(config: adClickAttribution,
                                                                          compiledRulesSource: contentBlockingManager,
                                                                          exceptionsSource: exceptionsSource,
                                                                          errorReporting: attributionDebugEvents,
                                                                          compilationErrorReporting: Self.debugEvents)
    }

    static let debugEvents = EventMapping<ContentBlockerDebugEvents> { event, error, parameters, onComplete in
        guard AppVersion.runType.requiresEnvironment else { return }

        let domainEvent: GeneralPixel
        var finalParameters = parameters ?? [:]
        switch event {
        case .trackerDataParseFailed:
            domainEvent = .couldNotParseConfiguration(configuration: .trackerDataSet)
            if let experimentName = SiteBreakageExperimentMetrics.activeTDSExperimentNameWithCohort {
                finalParameters[Constants.ParameterName.experimentName] = experimentName
                finalParameters[Constants.ParameterName.etag] = Application.appDelegate.privacyFeatures.contentBlocking.trackerDataManager.fetchedData?.etag ?? ""
            }

        case .trackerDataReloadFailed:
            domainEvent = .trackerDataReloadFailed

        case .trackerDataCouldNotBeLoaded:
            domainEvent = .couldNotLoadConfiguration(configuration: .trackerDataSet)

        case .privacyConfigurationReloadFailed:
            domainEvent = .privacyConfigurationReloadFailed

        case .privacyConfigurationParseFailed:
            domainEvent = .couldNotParseConfiguration(configuration: .privacyConfiguration)

        case .contentBlockingCompilationFailed(let listName, let component):
            let defaultTDSListName = DefaultContentBlockerRulesListsSource.Constants.trackerDataSetRulesListName

            let listType: GeneralPixel.CompileRulesListType
            switch listName {
            case defaultTDSListName:
                listType = .tds
            case DefaultContentBlockerRulesListsSource.Constants.clickToLoadRulesListName:
                listType = .clickToLoad
            case AdClickAttributionRulesSplitter.blockingAttributionRuleListName(forListNamed: defaultTDSListName):
                listType = .blockingAttribution
            case AdClickAttributionRulesProvider.Constants.attributedTempRuleListName:
                listType = .attributed
            default:
                listType = .unknown
            }

            domainEvent = .contentBlockingCompilationFailed(listType: listType, component: component)

        case .contentBlockingLookupRulesSucceeded:
                    domainEvent = .contentBlockingLookupRulesSucceeded

        case .contentBlockingFetchLRCSucceeded:
                    domainEvent = .contentBlockingFetchLRCSucceeded

        case .contentBlockingNoMatchInLRC:
                    domainEvent = .contentBlockingNoMatchInLRC

        case .contentBlockingLRCMissing:
                    domainEvent = .contentBlockingLRCMissing

        case .contentBlockingCompilationTaskPerformance(let iterationCount, let timeBucketAggregation):
            let timeBucket = GeneralPixel.CompileTimeBucketAggregation(number: timeBucketAggregation)
            domainEvent = .contentBlockingCompilationTaskPerformance(iterationCount: iterationCount,
                                                                     timeBucketAggregation: timeBucket)
            if let experimentName = SiteBreakageExperimentMetrics.activeTDSExperimentNameWithCohort {
                finalParameters[Constants.ParameterName.experimentName] = experimentName
                finalParameters[Constants.ParameterName.etag] = Application.appDelegate.privacyFeatures.contentBlocking.trackerDataManager.fetchedData?.etag ?? ""
            }
        }

        PixelKit.fire(DebugEvent(domainEvent, error: error), withAdditionalParameters: finalParameters) { _, error in
            onComplete(error)
        }
    }

    // MARK: - Ad Click Attribution

    let attributionEvents: EventMapping<AdClickAttributionEvents>? = .init { event, _, parameters, _ in
        let domainEvent: GeneralPixel
        switch event {
        case .adAttributionDetected:
            domainEvent = .adClickAttributionDetected
        case .adAttributionActive:
            domainEvent = .adClickAttributionActive
        case .adAttributionPageLoads:
            domainEvent = .adClickAttributionPageLoads
        }

        PixelKit.fire(domainEvent, withAdditionalParameters: parameters ?? [:])
    }

    let attributionDebugEvents: EventMapping<AdClickAttributionDebugEvents>? = .init { event, _, _, _ in
        let domainEvent: GeneralPixel
        switch event {
        case .adAttributionCompilationFailedForAttributedRulesList:
            domainEvent = .adAttributionCompilationFailedForAttributedRulesList
        case .adAttributionGlobalAttributedRulesDoNotExist:
            domainEvent = .adAttributionGlobalAttributedRulesDoNotExist
        case .adAttributionDetectionHeuristicsDidNotMatchDomain:
            domainEvent = .adAttributionDetectionHeuristicsDidNotMatchDomain
        case .adAttributionLogicUnexpectedStateOnRulesCompiled:
            domainEvent = .adAttributionLogicUnexpectedStateOnRulesCompiled
        case .adAttributionLogicUnexpectedStateOnInheritedAttribution:
            domainEvent = .adAttributionLogicUnexpectedStateOnInheritedAttribution
        case .adAttributionLogicUnexpectedStateOnRulesCompilationFailed:
            domainEvent = .adAttributionLogicUnexpectedStateOnRulesCompilationFailed
        case .adAttributionDetectionInvalidDomainInParameter:
            domainEvent = .adAttributionDetectionInvalidDomainInParameter
        case .adAttributionLogicRequestingAttributionTimedOut:
            domainEvent = .adAttributionLogicRequestingAttributionTimedOut
        case .adAttributionLogicWrongVendorOnSuccessfulCompilation:
            domainEvent = .adAttributionLogicWrongVendorOnSuccessfulCompilation
        case .adAttributionLogicWrongVendorOnFailedCompilation:
            domainEvent = .adAttributionLogicWrongVendorOnFailedCompilation
        }

        PixelKit.fire(DebugEvent(domainEvent), includeAppVersionParameter: false)
    }
}

protocol ContentBlockerRulesManagerProtocol: CompiledRuleListsSource, EntityProviding {
    var updatesPublisher: AnyPublisher<ContentBlockerRulesManager.UpdateEvent, Never> { get }
    var currentRules: [ContentBlockerRulesManager.Rules] { get }
    @discardableResult func scheduleCompilation() -> ContentBlockerRulesManager.CompletionToken
}

extension ContentBlockerRulesManager: ContentBlockerRulesManagerProtocol {}

final class ContentBlockingRulesCache: ContentBlockerRulesCaching {

    @UserDefaultsWrapper(key: .contentBlockingRulesCache, defaultValue: [:])
    public var contentRulesCache: [String: Date]

    var contentRulesCacheInterval: TimeInterval {
        7 * 24 * 3600
    }

}

extension AppContentBlocking: ContentBlockingProtocol {

    var contentBlockingAssetsPublisher: AnyPublisher<UserContentUpdating.NewContent, Never> {
        self.userContentUpdating.userContentBlockingAssets
    }

}

//
//  MockScriptSourceProviderDependencies.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Common
import Configuration
import History
import HistoryView
import PersistenceTestingUtils
@testable import DuckDuckGo_Privacy_Browser

extension ScriptSourceProvider.Dependencies {

    @MainActor
    static func makeMock(
        configStorage: ConfigurationStoring? = nil,
        privacyConfigurationManager: PrivacyConfigurationManaging? = nil,
        webTrackingProtectionPreferences: WebTrackingProtectionPreferences? = nil,
        cookiePopupProtectionPreferences: CookiePopupProtectionPreferences? = nil,
        duckPlayer: DuckPlayer? = nil,
        contentBlockingManager: ContentBlockerRulesManagerProtocol? = nil,
        trackerDataManager: TrackerDataManager? = nil,
        experimentManager: ContentScopeExperimentsManaging? = nil,
        tld: TLD? = nil,
        featureFlagger: FeatureFlagger? = nil,
        onboardingNavigationDelegate: OnboardingNavigating? = nil,
        appearancePreferences: AppearancePreferences? = nil,
        startupPreferences: StartupPreferences? = nil,
        windowControllersManager: WindowControllersManagerProtocol? = nil,
        bookmarkManager: (BookmarkManager & HistoryViewBookmarksHandling)? = nil,
        historyCoordinator: HistoryDataSource? = nil,
        fireproofDomains: DomainFireproofStatusProviding? = nil,
        fireCoordinator: FireCoordinator? = nil,
        autoconsentManagement: AutoconsentManagement? = nil
    ) -> Self {

        let resolvedFeatureFlagger = featureFlagger ?? MockFeatureFlagger()
        let resolvedWindowControllersManager = windowControllersManager ?? WindowControllersManagerMock()
        let resolvedPrivacyConfigurationManager = privacyConfigurationManager ?? MockPrivacyConfigurationManaging()
        let resolvedTld = tld ?? TLD()
        let resolvedConfigStorage = configStorage ?? MockConfigurationStore()

        // swiftlint:disable:next force_try
        let resolvedAppearancePreferences = appearancePreferences ?? AppearancePreferences(
            keyValueStore: try! MockKeyValueFileStore(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: resolvedFeatureFlagger
        )

        let resolvedStartupPreferences = startupPreferences ?? StartupPreferences(
            persistor: StartupPreferencesPersistorMock(launchToCustomHomePage: false, customHomePageURL: ""),
            windowControllersManager: resolvedWindowControllersManager,
            appearancePreferences: resolvedAppearancePreferences
        )

        let resolvedFireCoordinator = fireCoordinator ?? FireCoordinator(
            tld: resolvedTld,
            featureFlagger: resolvedFeatureFlagger,
            historyCoordinating: HistoryCoordinatingMock(),
            visualizeFireAnimationDecider: nil,
            onboardingContextualDialogsManager: nil,
            fireproofDomains: MockFireproofDomains(),
            faviconManagement: FaviconManagerMock(),
            windowControllersManager: resolvedWindowControllersManager,
            pixelFiring: nil,
            historyProvider: MockHistoryViewDataProvider()
        )

        return Self(
            configStorage: resolvedConfigStorage,
            privacyConfigurationManager: resolvedPrivacyConfigurationManager,
            webTrackingProtectionPreferences: webTrackingProtectionPreferences ?? WebTrackingProtectionPreferences(
                persistor: MockWebTrackingProtectionPreferencesPersistor(),
                windowControllersManager: resolvedWindowControllersManager
            ),
            cookiePopupProtectionPreferences: cookiePopupProtectionPreferences ?? CookiePopupProtectionPreferences(
                persistor: MockCookiePopupProtectionPreferencesPersistor(),
                windowControllersManager: resolvedWindowControllersManager
            ),
            duckPlayer: duckPlayer ?? DuckPlayer(
                preferencesPersistor: DuckPlayerPreferencesPersistorMock(),
                privacyConfigurationManager: resolvedPrivacyConfigurationManager,
                internalUserDecider: resolvedFeatureFlagger.internalUserDecider
            ),
            contentBlockingManager: contentBlockingManager ?? ContentBlockerRulesManagerMock(),
            trackerDataManager: trackerDataManager ?? TrackerDataManager(
                etag: resolvedConfigStorage.loadEtag(for: .trackerDataSet),
                data: resolvedConfigStorage.loadData(for: .trackerDataSet),
                embeddedDataProvider: AppTrackerDataSetProvider(),
                errorReporting: nil
            ),
            experimentManager: experimentManager ?? MockContentScopeExperimentManager(),
            tld: resolvedTld,
            featureFlagger: resolvedFeatureFlagger,
            onboardingNavigationDelegate: onboardingNavigationDelegate ?? CapturingOnboardingNavigation(),
            appearancePreferences: resolvedAppearancePreferences,
            startupPreferences: resolvedStartupPreferences,
            windowControllersManager: resolvedWindowControllersManager,
            bookmarkManager: bookmarkManager ?? MockBookmarkManager(),
            historyCoordinator: historyCoordinator ?? CapturingHistoryDataSource(),
            fireproofDomains: fireproofDomains ?? MockFireproofDomains(domains: []),
            fireCoordinator: resolvedFireCoordinator,
            autoconsentManagement: autoconsentManagement ?? AutoconsentManagement()
        )
    }
}


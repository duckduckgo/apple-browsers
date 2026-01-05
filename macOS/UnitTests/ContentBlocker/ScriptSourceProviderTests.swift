//
//  ScriptSourceProviderTests.swift
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
import History
import HistoryView
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class ScriptSourceProviderTests: XCTestCase {

    var experimentManager: MockContentScopeExperimentManager!
    let testExperimentData = ExperimentData(
        parentID: "parent",
        cohortID: "aCohort",
        enrollmentDate: Date()
    )

    override func setUpWithError() throws {
        experimentManager = MockContentScopeExperimentManager()
    }

    override func tearDownWithError() throws {
        experimentManager = nil
    }

    @MainActor
    func testCohortDataInitialisedCorrectly() throws {
        let expectedCohortData = ContentScopeExperimentData(feature: testExperimentData.parentID, subfeature: "test", cohort: testExperimentData.cohortID)
        let experimentManager = MockContentScopeExperimentManager()

        experimentManager.allActiveContentScopeExperiments = ["test": testExperimentData]

        let featureFlagger = MockFeatureFlagger()
        let privacyConfigurationManager = MockPrivacyConfigurationManager()
        let appearancePreferences = AppearancePreferences(
            keyValueStore: try MockKeyValueFileStore(),
            privacyConfigurationManager: privacyConfigurationManager,
            featureFlagger: featureFlagger
        )
        let windowControllersManager = WindowControllersManagerMock()
        let startupPreferences = StartupPreferences(
            persistor: StartupPreferencesPersistorMock(launchToCustomHomePage: false, customHomePageURL: ""),
            windowControllersManager: windowControllersManager,
            appearancePreferences: appearancePreferences
        )
        let fireCoordinator = FireCoordinator(tld: TLD(),
                                              featureFlagger: Application.appDelegate.featureFlagger,
                                              historyCoordinating: HistoryCoordinatingMock(),
                                              visualizeFireAnimationDecider: nil,
                                              onboardingContextualDialogsManager: nil,
                                              fireproofDomains: MockFireproofDomains(),
                                              faviconManagement: FaviconManagerMock(),
                                              windowControllersManager: windowControllersManager,
                                              pixelFiring: nil,
                                              historyProvider: MockHistoryViewDataProvider())
        let sourceProvider = ScriptSourceProvider(
            configStorage: MockConfigurationStore(),
            privacyConfigurationManager: privacyConfigurationManager,
            webTrackingProtectionPreferences: WebTrackingProtectionPreferences(persistor: MockWebTrackingProtectionPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock()),
            cookiePopupProtectionPreferences: CookiePopupProtectionPreferences(persistor: MockCookiePopupProtectionPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock()),
            duckPlayer: DuckPlayer(preferencesPersistor: DuckPlayerPreferencesPersistorMock(), privacyConfigurationManager: privacyConfigurationManager, internalUserDecider: featureFlagger.internalUserDecider),
            contentBlockingManager: MockContentBlockerRulesManagerProtocol(),
            trackerDataManager: TrackerDataManager(etag: nil, data: Data(), embeddedDataProvider: MockEmbeddedDataProvider()),
            experimentManager: experimentManager,
            tld: Application.appDelegate.tld,
            featureFlagger: featureFlagger,
            onboardingNavigationDelegate: CapturingOnboardingNavigation(),
            appearancePreferences: appearancePreferences,
            themeManager: MockThemeManager(),
            startupPreferences: startupPreferences,
            windowControllersManager: windowControllersManager,
            bookmarkManager: MockBookmarkManager(),
            historyCoordinator: HistoryCoordinatingMock(),
            fireproofDomains: MockFireproofDomains(domains: []),
            fireCoordinator: fireCoordinator,
            autoconsentManagement: AutoconsentManagement(),
            newTabPageActionsManager: nil
        )

        let cohorts = try XCTUnwrap(sourceProvider.currentCohorts)
        XCTAssertFalse(cohorts.isEmpty)
        XCTAssertEqual(cohorts[0], expectedCohortData)
        XCTAssertTrue(experimentManager.resolveContentScopeScriptActiveExperimentsWasCalled)
    }

}

class MockContentScopeExperimentManager: ContentScopeExperimentsManaging {
    var allActiveContentScopeExperiments: Experiments = [:]
    private(set) var resolveContentScopeScriptActiveExperimentsWasCalled = false

    func resolveContentScopeScriptActiveExperiments() -> Experiments {
        resolveContentScopeScriptActiveExperimentsWasCalled = true
        return allActiveContentScopeExperiments
    }
}

//
//  AutoClearHandlerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PrivacyConfigTestsUtils
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
class AutoClearHandlerTests: XCTestCase {

    var handler: AutoClearHandler!
    var dataClearingPreferences: DataClearingPreferences!
    var startupPreferences: StartupPreferences!
    var fireViewModel: FireViewModel!

    override func setUp() {
        super.setUp()
        let persistor = MockFireButtonPreferencesPersistor()
        dataClearingPreferences = DataClearingPreferences(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: MockFeatureFlagger(),
            aiChatHistoryCleaner: MockAIChatHistoryCleaner()
        )
        let persistor2 = StartupPreferencesPersistorMock(launchToCustomHomePage: false, customHomePageURL: "duckduckgo.com")
        let appearancePreferences = AppearancePreferences(
            persistor: MockAppearancePreferencesPersistor(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )
        startupPreferences = StartupPreferences(
            persistor: persistor2,
            windowControllersManager: WindowControllersManagerMock(),
            appearancePreferences: appearancePreferences
        )

        fireViewModel = FireViewModel(tld: Application.appDelegate.tld,
                                      visualizeFireAnimationDecider: MockVisualizeFireAnimationDecider())
        let fileName = "AutoClearHandlerTests"
        let fileStore = FileStoreMock()
        let service = StatePersistenceService(fileStore: fileStore, fileName: fileName)
        let appStateRestorationManager = AppStateRestorationManager(fileStore: fileStore,
                                                                    service: service,
                                                                    startupPreferences: NSApp.delegateTyped.startupPreferences,
                                                                    tabsPreferences: NSApp.delegateTyped.tabsPreferences,
                                                                    keyValueStore: NSApp.delegateTyped.keyValueStore,
                                                                    sessionRestorePromptCoordinator: NSApp.delegateTyped.sessionRestorePromptCoordinator,
                                                                    pixelFiring: nil)
        handler = AutoClearHandler(dataClearingPreferences: dataClearingPreferences,
                                   startupPreferences: startupPreferences,
                                   fireViewModel: fireViewModel,
                                   stateRestorationManager: appStateRestorationManager,
                                   syncAIChatsCleaner: nil)
    }

    override func tearDown() {
        handler = nil
        dataClearingPreferences = nil
        startupPreferences = nil
        fireViewModel = nil
        super.tearDown()
    }

    func testWhenBurningEnabledAndNoWarningRequiredThenAsyncTaskIsReturned() {
        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isWarnBeforeClearingEnabled = false

        let query = handler.shouldTerminate(isAsync: false)

        switch query {
        case .async:
            // Expected: async task for burning
            break
        case .sync:
            XCTFail("Expected async query for auto-clear, got sync")
        }
    }

    func testWhenBurningDisabledThenSyncNextIsReturned() {
        dataClearingPreferences.isAutoClearEnabled = false

        let query = handler.shouldTerminate(isAsync: false)

        switch query {
        case .sync(.next):
            // Expected: continue to next decider
            break
        case .sync(.cancel):
            XCTFail("Expected .sync(.next), got .sync(.cancel)")
        case .async:
            XCTFail("Expected .sync(.next), got .async")
        }
    }

    func testWhenBurningEnabledWithWarningThenTerminationQueryDependsOnUserChoice() {
        // This test verifies the structure - actual alert behavior would need to be mocked
        // to test the three branches: clear and quit, quit without clearing, cancel
        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isWarnBeforeClearingEnabled = true

        // Note: In real usage, this would show an alert and wait for user response
        // The alert mock would need to be set up to test different user choices
        let query = handler.shouldTerminate(isAsync: false)

        // At minimum, verify it returns a valid query
        switch query {
        case .sync(.next), .sync(.cancel), .async:
            // All are valid depending on user's choice in the alert
            break
        }
    }

    func testWhenBurningEnabledAndFlagFalseThenBurnOnStartTriggered() {
        dataClearingPreferences.isAutoClearEnabled = true
        handler.resetTheCorrectTerminationFlag()

        XCTAssertTrue(handler.burnOnStartIfNeeded())
    }

    func testWhenBurningDisabledThenBurnOnStartNotTriggered() {
        dataClearingPreferences.isAutoClearEnabled = false
        handler.resetTheCorrectTerminationFlag()

        XCTAssertFalse(handler.burnOnStartIfNeeded())
    }

}

final class MockVisualizeFireAnimationDecider: VisualizeFireSettingsDecider {
    var isOpenFireWindowByDefaultEnabled: Bool = false

    var shouldShowOpenFireWindowByDefaultPublisher: AnyPublisher<Bool, Never> = Just(false)
        .eraseToAnyPublisher()

    var shouldShowFireAnimationPublisher: AnyPublisher<Bool, Never> = Just(true)
        .eraseToAnyPublisher()

    var shouldShowFireAnimation: Bool {
        return true
    }
}

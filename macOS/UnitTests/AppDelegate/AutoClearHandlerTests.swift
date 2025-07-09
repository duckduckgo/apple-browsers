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

import Foundation
import XCTest

@testable import DuckDuckGo_Privacy_Browser
import Combine

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
            featureFlagger: MockFeatureFlagger()
        )
        let persistor2 = StartupPreferencesPersistorMock(launchToCustomHomePage: false, customHomePageURL: "duckduckgo.com")
        let appearancePreferences = AppearancePreferences(
            persistor: MockAppearancePreferencesPersistor(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )
        startupPreferences = StartupPreferences(persistor: persistor2,
                                                appearancePreferences: appearancePreferences)

        fireViewModel = FireViewModel(tld: Application.appDelegate.tld,
                                      visualizeFireAnimationDecider: MockVisualizeFireAnimationDecider())
        let fileName = "AutoClearHandlerTests"
        let fileStore = FileStoreMock()
        let service = StatePersistenceService(fileStore: fileStore, fileName: fileName)
        let appStateRestorationManager = AppStateRestorationManager(fileStore: fileStore,
                                                                    service: service,
                                                                    startupPreferences: NSApp.delegateTyped.startupPreferences)
        handler = AutoClearHandler(dataClearingPreferences: dataClearingPreferences,
                                   startupPreferences: startupPreferences,
                                   fireViewModel: fireViewModel,
                                   stateRestorationManager: appStateRestorationManager)
    }

    override func tearDown() {
        handler = nil
        dataClearingPreferences = nil
        startupPreferences = nil
        fireViewModel = nil
        super.tearDown()
    }

    func testWhenBurningEnabledAndNoWarningRequiredThenTerminateLaterIsReturned() {
        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isWarnBeforeClearingEnabled = false

        let response = handler.handleAppTermination()

        XCTAssertEqual(response, .terminateLater)
    }

    func testWhenBurningDisabledThenNoTerminationResponse() {
        dataClearingPreferences.isAutoClearEnabled = false

        let response = handler.handleAppTermination()

        XCTAssertNil(response)
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

final class MockVisualizeFireAnimationDecider: VisualizeFireAnimationDecider {
    var shouldShowFireAnimationPublisher: AnyPublisher<Bool, Never> = Just(true)
        .eraseToAnyPublisher()

    var shouldShowFireAnimation: Bool {
        return true
    }
}

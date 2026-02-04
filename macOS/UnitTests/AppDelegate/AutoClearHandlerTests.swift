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

import AppKit
import Combine
import Foundation
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class MockAutoClearAlertPresenter: AutoClearAlertPresenting {
    var responseToReturn: NSApplication.ModalResponse = .alertFirstButtonReturn
    var confirmAutoClearCalled = false
    var clearChatsParameter: Bool?

    func confirmAutoClear(clearChats: Bool) -> NSApplication.ModalResponse {
        confirmAutoClearCalled = true
        clearChatsParameter = clearChats
        return responseToReturn
    }
}

@MainActor
class AutoClearHandlerTests: XCTestCase {

    var handler: AutoClearHandler!
    var dataClearingPreferences: DataClearingPreferences!
    var startupPreferences: StartupPreferences!
    var fireViewModel: FireViewModel!
    var mockAlertPresenter: MockAutoClearAlertPresenter!

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
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )
        startupPreferences = StartupPreferences(
            pinningManager: MockPinningManager(),
            persistor: persistor2,
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
        mockAlertPresenter = MockAutoClearAlertPresenter()
        handler = AutoClearHandler(dataClearingPreferences: dataClearingPreferences,
                                   startupPreferences: startupPreferences,
                                   fireViewModel: fireViewModel,
                                   stateRestorationManager: appStateRestorationManager,
                                   aiChatSyncCleaner: nil,
                                   alertPresenter: mockAlertPresenter)
    }

    override func tearDown() {
        handler = nil
        dataClearingPreferences = nil
        startupPreferences = nil
        fireViewModel = nil
        mockAlertPresenter = nil
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

    func testWhenBurningEnabledWithWarningAndUserChoosesClearAndQuitThenAsyncTaskIsReturned() {
        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isWarnBeforeClearingEnabled = true
        mockAlertPresenter.responseToReturn = .alertFirstButtonReturn // Clear and Quit

        let query = handler.shouldTerminate(isAsync: false)

        XCTAssertTrue(mockAlertPresenter.confirmAutoClearCalled)
        switch query {
        case .async:
            // Expected: async task for burning
            break
        case .sync:
            XCTFail("Expected async query for clear and quit, got sync")
        }
    }

    func testWhenBurningEnabledWithWarningAndUserChoosesQuitWithoutClearingThenSyncNextIsReturned() {
        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isWarnBeforeClearingEnabled = true
        mockAlertPresenter.responseToReturn = .alertSecondButtonReturn // Quit without Clearing

        let query = handler.shouldTerminate(isAsync: false)

        XCTAssertTrue(mockAlertPresenter.confirmAutoClearCalled)
        switch query {
        case .sync(.next):
            // Expected: skip clearing and proceed to next decider
            break
        case .sync(.cancel):
            XCTFail("Expected .sync(.next), got .sync(.cancel)")
        case .async:
            XCTFail("Expected .sync(.next), got .async")
        }
    }

    func testWhenBurningEnabledWithWarningAndUserCancelsThenSyncCancelIsReturned() {
        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isWarnBeforeClearingEnabled = true
        mockAlertPresenter.responseToReturn = .alertThirdButtonReturn // Cancel

        let query = handler.shouldTerminate(isAsync: false)

        XCTAssertTrue(mockAlertPresenter.confirmAutoClearCalled)
        switch query {
        case .sync(.cancel):
            // Expected: cancel termination
            break
        case .sync(.next):
            XCTFail("Expected .sync(.cancel), got .sync(.next)")
        case .async:
            XCTFail("Expected .sync(.cancel), got .async")
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

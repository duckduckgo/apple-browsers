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
import Common
import Foundation
import History
@_spi(Testing) import PixelKit
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

final class MockAppStateRestorationManager: AppStateRestorationManaging {
    var isRelaunchingAutomatically: Bool = false
    var resetRelaunchFlagCalled = false

    func resetRelaunchFlag() {
        resetRelaunchFlagCalled = true
        isRelaunchingAutomatically = false
    }
}

@MainActor
class AutoClearHandlerTests: XCTestCase {

    private var quitCleanupEvents: [String] = []
    var handler: AutoClearHandler!
    var dataClearingPreferences: DataClearingPreferences!
    var startupPreferences: StartupPreferences!
    var fireViewModel: FireViewModel!
    var mockAlertPresenter: MockAutoClearAlertPresenter!
    var mockStateRestoration: MockAppStateRestorationManager!

    override func setUp() {
        super.setUp()
        quitCleanupEvents = []
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

        let fire = AutoClearFireMock()
        fire.onBurnAll = { [weak self] in self?.quitCleanupEvents.append("burn") }
        fireViewModel = FireViewModel(fire: fire)
        mockStateRestoration = MockAppStateRestorationManager()
        mockAlertPresenter = MockAutoClearAlertPresenter()
        handler = AutoClearHandler(dataClearingPreferences: dataClearingPreferences,
                                   startupPreferences: startupPreferences,
                                   fireViewModel: fireViewModel,
                                   stateRestorationManager: mockStateRestoration,
                                   aiChatSyncCleaner: nil,
                                   wideEvent: WideEventMock(),
                                   pixelFiring: nil,
                                   alertPresenter: mockAlertPresenter,
                                   willPerformAutoClear: { [weak self] in self?.quitCleanupEvents.append("detach") })
    }

    override func tearDown() {
        handler = nil
        dataClearingPreferences = nil
        startupPreferences = nil
        fireViewModel = nil
        mockAlertPresenter = nil
        mockStateRestoration = nil
        super.tearDown()
    }

    func testWhenBurningEnabledAndNoWarningRequiredThenAsyncTaskIsReturned() async {
        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isWarnBeforeClearingEnabled = false

        let query = handler.shouldTerminate(isAsync: false)

        switch query {
        case .async(let task):
            _ = await task.value
            XCTAssertEqual(quitCleanupEvents, ["detach", "burn"])
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

    func testWhenBurningEnabledWithWarningAndUserChoosesClearAndQuitThenAsyncTaskIsReturned() async {
        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isWarnBeforeClearingEnabled = true
        mockAlertPresenter.responseToReturn = .alertFirstButtonReturn // Clear and Quit

        let query = handler.shouldTerminate(isAsync: false)

        XCTAssertTrue(mockAlertPresenter.confirmAutoClearCalled)
        switch query {
        case .async(let task):
            _ = await task.value
            XCTAssertEqual(quitCleanupEvents, ["detach", "burn"])
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
            XCTAssertTrue(quitCleanupEvents.isEmpty)
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
            XCTAssertTrue(quitCleanupEvents.isEmpty)
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
        XCTAssertEqual(quitCleanupEvents, ["burn"])
    }

    func testWhenBurningDisabledThenBurnOnStartNotTriggered() {
        dataClearingPreferences.isAutoClearEnabled = false
        handler.resetTheCorrectTerminationFlag()

        XCTAssertFalse(handler.burnOnStartIfNeeded())
    }

    func testShouldTerminate_whenRelaunchingAutomatically_skipsClearPrompt() {
        mockStateRestoration.isRelaunchingAutomatically = true
        dataClearingPreferences.isAutoClearEnabled = true
        dataClearingPreferences.isWarnBeforeClearingEnabled = true
        handler.resetTheCorrectTerminationFlag() // Ensure flag is false initially

        let result = handler.shouldTerminate(isAsync: false)

        // Verify bypass returns .sync(.next)
        switch result {
        case .sync(.next):
            break
        case .sync(.cancel):
            XCTFail("Expected .sync(.next), got .sync(.cancel)")
        case .async:
            XCTFail("Expected .sync(.next), got .async")
        }

        // Verify prompt was not shown
        XCTAssertFalse(mockAlertPresenter.confirmAutoClearCalled)

        // Verify burn-on-start will NOT trigger on next launch
        XCTAssertFalse(handler.burnOnStartIfNeeded(),
                       "Burn-on-start should not trigger after automatic relaunch termination")
    }

    func testDeciderSequenceCompleted_whenTerminationCancelledAndRelaunchFlagTrue_resetsFlag() {
        mockStateRestoration.isRelaunchingAutomatically = true
        dataClearingPreferences.isAutoClearEnabled = true

        handler.deciderSequenceCompleted(shouldProceed: false)

        XCTAssertTrue(mockStateRestoration.resetRelaunchFlagCalled)
        XCTAssertFalse(mockStateRestoration.isRelaunchingAutomatically)
    }

    func testDeciderSequenceCompleted_whenTerminationSucceedsAndRelaunchFlagTrue_doesNotResetFlag() {
        mockStateRestoration.isRelaunchingAutomatically = true
        dataClearingPreferences.isAutoClearEnabled = true

        handler.deciderSequenceCompleted(shouldProceed: true)

        XCTAssertFalse(mockStateRestoration.resetRelaunchFlagCalled)
        XCTAssertTrue(mockStateRestoration.isRelaunchingAutomatically)
    }

    func testDeciderSequenceCompleted_whenTerminationCancelledAndRelaunchFlagFalse_doesNothing() {
        mockStateRestoration.isRelaunchingAutomatically = false

        handler.deciderSequenceCompleted(shouldProceed: false)

        XCTAssertFalse(mockStateRestoration.resetRelaunchFlagCalled)
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

private final class AutoClearFireMock: FireProtocol {
    var burningData: Fire.BurningData? { nil }
    let fireproofDomains = FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD())
    let visualizeFireAnimationDecider: VisualizeFireSettingsDecider = MockVisualizeFireAnimationDecider()
    var burningDataPublisher: AnyPublisher<Fire.BurningData?, Never> { Just(nil).eraseToAnyPublisher() }
    var onBurnAll: (() -> Void)?

    func fireAnimationDidStart() {}
    func fireAnimationDidFinish() {}

    @MainActor
    func burnAll(isBurnOnExit: Bool, opening url: URL, includeCookiesAndSiteData: Bool,
                 includeChatHistory: Bool, isAutoClear: Bool, dataClearingWideEventService: DataClearingWideEventService?,
                 completion: (@MainActor () -> Void)?) {
        onBurnAll?()
        completion?()
    }

    @MainActor
    func burnEntity(_ entity: Fire.BurningEntity, includingHistory: Bool, includeCookiesAndSiteData: Bool,
                    includeChatHistory: Bool, dataClearingWideEventService: DataClearingWideEventService?,
                    completion: (@MainActor () -> Void)?) {
        XCTFail("Unexpected entity burn")
        completion?()
    }

    @MainActor
    func burnVisits(_ visits: [Visit], except fireproofDomains: DomainFireproofStatusProviding,
                    isToday: Bool, closeWindows: Bool, clearSiteData: Bool, clearChatHistory: Bool,
                    urlToOpenIfWindowsAreClosed url: URL?, dataClearingWideEventService: DataClearingWideEventService?,
                    completion: (@MainActor () -> Void)?) {
        XCTFail("Unexpected visits burn")
        completion?()
    }

    @MainActor
    func burnChatHistory() async -> Result<Void, Error> {
        XCTFail("Unexpected chat burn")
        return .success(())
    }
}

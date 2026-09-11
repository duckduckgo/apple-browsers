//
//  DuckPlayerOverlayObserverTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DuckPlayerOverlayObserverTests: XCTestCase {

    private var windowControllersManager: WindowControllersManagerMock!
    private var featureFlagger: MockFeatureFlagger!
    private var persistor: DuckPlayerPreferencesPersistorMock!
    private var privacyConfigManager: MockPrivacyConfigurationManager!
    private var stateChangedSubject: PassthroughSubject<Void, Never>!
    private var duckPlayer: DuckPlayer!
    private var cancellables: Set<AnyCancellable>!

    private static let watchURL = URL(string: "https://www.youtube.com/watch?v=abc123")!
    private static let nonWatchURL = URL(string: "https://duckduckgo.com/")!

    override func setUp() {
        super.setUp()
        cancellables = []
        stateChangedSubject = PassthroughSubject<Void, Never>()
        windowControllersManager = WindowControllersManagerMock()
        windowControllersManager.stateChanged = stateChangedSubject.eraseToAnyPublisher()

        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueDuckPlayerOverlayPromo]

        let privacyConfig = MockPrivacyConfiguration()
        privacyConfig.isFeatureEnabledCheck = { feature, _ in feature == .duckPlayer }
        privacyConfigManager = MockPrivacyConfigurationManager(privacyConfig: privacyConfig)

        persistor = DuckPlayerPreferencesPersistorMock()
        persistor.duckPlayerModeBool = nil // .alwaysAsk
        persistor.youtubeOverlayInteracted = false
        duckPlayer = DuckPlayer(
            preferences: DuckPlayerPreferences(
                persistor: persistor,
                privacyConfigurationManager: privacyConfigManager,
                internalUserDecider: MockInternalUserDecider()
            ),
            privacyConfigurationManager: privacyConfigManager
        )

        setSelectedTabContent(.url(Self.watchURL, source: .link))
    }

    override func tearDown() {
        cancellables = nil
        duckPlayer = nil
        windowControllersManager = nil
        featureFlagger = nil
        persistor = nil
        privacyConfigManager = nil
        stateChangedSubject = nil
        super.tearDown()
    }

    private func makeSUT() -> DuckPlayerOverlayObserver {
        DuckPlayerOverlayObserver(
            duckPlayer: duckPlayer,
            windowControllersManager: windowControllersManager,
            featureFlagger: featureFlagger
        )
    }

    private func setSelectedTabContent(_ content: TabContent) {
        let tabCollectionViewModel = TabCollectionViewModel(
            tabCollection: TabCollection(),
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock())
        )
        tabCollectionViewModel.append(tab: Tab(uuid: "tab1", content: content))
        windowControllersManager.customAllTabCollectionViewModels = [tabCollectionViewModel]
    }

    /// Drains the main queue so the delegate's `receive(on: DispatchQueue.main)` pipeline runs.
    private func waitForVisibilityUpdate() {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - The protocol contract

    func testWhenSubscribingThenCurrentValueIsEmittedImmediately() {
        let sut = makeSUT()
        var received: [Bool] = []

        sut.isVisiblePublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        XCTAssertEqual(received, [true], "isVisiblePublisher must replay a current value on subscribe")
    }

    func testWhenNothingChangesThenVisibilityIsNotRepublished() {
        let sut = makeSUT()
        var received: [Bool] = []

        sut.isVisiblePublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        waitForVisibilityUpdate()

        XCTAssertEqual(received, [true], "Visibility should only be emitted when it actually changes")
    }

    func testResultWhenHiddenIsRecordedDismissalWithNoCooldown() {
        XCTAssertEqual(makeSUT().resultWhenHidden, .ignored(cooldown: 0))
    }

    // MARK: - Each term of the visibility inference

    func testWhenAlwaysAskAndNotInteractedAndOnWatchPageThenVisible() {
        XCTAssertTrue(makeSUT().isVisible)
    }

    func testWhenModeIsEnabledThenNotVisible() {
        duckPlayer.preferences.duckPlayerMode = .enabled
        XCTAssertFalse(makeSUT().isVisible)
    }

    func testWhenModeIsDisabledThenNotVisible() {
        duckPlayer.preferences.duckPlayerMode = .disabled
        XCTAssertFalse(makeSUT().isVisible)
    }

    func testWhenOverlayAlreadyInteractedThenNotVisible() {
        duckPlayer.preferences.youtubeOverlayInteracted = true
        XCTAssertFalse(makeSUT().isVisible)
    }

    func testWhenSelectedTabIsNotAWatchPageThenNotVisible() {
        setSelectedTabContent(.url(Self.nonWatchURL, source: .link))
        XCTAssertFalse(makeSUT().isVisible)
    }

    func testWhenNoWindowIsOpenThenNotVisible() {
        windowControllersManager.customAllTabCollectionViewModels = []
        XCTAssertFalse(makeSUT().isVisible)
    }

    func testWhenDuckPlayerFeatureIsDisabledInConfigThenNotVisible() {
        let privacyConfig = MockPrivacyConfiguration()
        privacyConfig.isFeatureEnabledCheck = { _, _ in false }
        let manager = MockPrivacyConfigurationManager(privacyConfig: privacyConfig)
        duckPlayer = DuckPlayer(
            preferences: DuckPlayerPreferences(
                persistor: persistor,
                privacyConfigurationManager: manager,
                internalUserDecider: MockInternalUserDecider()
            ),
            privacyConfigurationManager: manager
        )

        XCTAssertFalse(makeSUT().isVisible)
    }

    // MARK: - The kill switch

    func testWhenPromoFeatureFlagIsOffThenNotVisibleRegardlessOfState() {
        featureFlagger.enabledFeatureFlags = []
        XCTAssertFalse(makeSUT().isVisible, "The promo's own kill switch must stop the queue observing the overlay")
    }

    // MARK: - Reacting to changes

    func testWhenOverlayInteractedFlipsWhileVisibleThenBecomesHidden() {
        let sut = makeSUT()
        XCTAssertTrue(sut.isVisible)

        duckPlayer.preferences.youtubeOverlayInteracted = true
        waitForVisibilityUpdate()

        XCTAssertFalse(sut.isVisible)
    }

    func testWhenModeChangesWhileVisibleThenBecomesHidden() {
        let sut = makeSUT()
        XCTAssertTrue(sut.isVisible)

        duckPlayer.preferences.duckPlayerMode = .enabled
        waitForVisibilityUpdate()

        XCTAssertFalse(sut.isVisible)
    }

    func testWhenSelectedTabChangesToNonYouTubeThenBecomesHidden() {
        let sut = makeSUT()
        XCTAssertTrue(sut.isVisible)

        setSelectedTabContent(.url(Self.nonWatchURL, source: .link))
        stateChangedSubject.send(())
        waitForVisibilityUpdate()

        XCTAssertFalse(sut.isVisible)
    }

    func testWhenSelectedTabNavigatesAwayThenBecomesHidden() {
        let sut = makeSUT()
        XCTAssertTrue(sut.isVisible)

        windowControllersManager.selectedTab?.setContent(.url(Self.nonWatchURL, source: .link))
        waitForVisibilityUpdate()

        XCTAssertFalse(sut.isVisible)
    }

    func testWhenSelectedTabNavigatesToAWatchPageThenBecomesVisible() {
        setSelectedTabContent(.url(Self.nonWatchURL, source: .link))
        let sut = makeSUT()
        XCTAssertFalse(sut.isVisible)

        windowControllersManager.selectedTab?.setContent(.url(Self.watchURL, source: .link))
        waitForVisibilityUpdate()

        XCTAssertTrue(sut.isVisible)
    }

    // MARK: - Selected-tab-only scope

    func testWhenWatchPageIsInABackgroundWindowThenNotVisible() {
        let backgroundModel = TabCollectionViewModel(
            tabCollection: TabCollection(),
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock())
        )
        backgroundModel.append(tab: Tab(uuid: "background", content: .url(Self.watchURL, source: .link)))

        let selectedModel = TabCollectionViewModel(
            tabCollection: TabCollection(),
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock())
        )
        selectedModel.append(tab: Tab(uuid: "selected", content: .url(Self.nonWatchURL, source: .link)))

        // selectedWindowIndex defaults to 0, so the second model is the background one.
        windowControllersManager.customAllTabCollectionViewModels = [selectedModel, backgroundModel]

        XCTAssertFalse(makeSUT().isVisible, "Only the selected tab counts — a background overlay must not suppress other promos")
    }
}

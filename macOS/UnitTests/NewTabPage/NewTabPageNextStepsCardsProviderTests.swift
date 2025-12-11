//
//  NewTabPageNextStepsCardsProviderTests.swift
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

import BrowserServicesKit
import Combine
import NewTabPage
import PixelKit
import XCTest
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageNextStepsCardsProviderTests: XCTestCase {
    private var provider: NewTabPageNextStepsCardsProvider!
    private var firedPixels: [(name: String, parameters: [String: String])]!
    private var testUserDefaults: UserDefaults!
    private var pixelKit: PixelKit!

    @MainActor
    override func setUp() async throws {
        let privacyConfigManager = MockPrivacyConfigurationManager()
        let config = MockPrivacyConfiguration()
        privacyConfigManager.mockPrivacyConfig = config

        let continueSetUpModel = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: CapturingDefaultBrowserProvider(),
            dockCustomizer: DockCustomizerMock(),
            dataImportProvider: CapturingDataImportProvider(),
            tabOpener: TabCollectionViewModelTabOpener(tabCollectionViewModel: TabCollectionViewModel(isPopup: false)),
            emailManager: EmailManager(storage: MockEmailStorage()),
            duckPlayerPreferences: DuckPlayerPreferencesPersistorMock(),
            privacyConfigurationManager: privacyConfigManager,
            subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging(),
            persistor: MockHomePageContinueSetUpModelPersisting()
        )

        firedPixels = []
        let testSuiteName = "NewTabPageNextStepsCardsProviderTests_\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
        testUserDefaults.removePersistentDomain(forName: testSuiteName)

        pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            source: "TESTS",
            defaultHeaders: [:],
            dailyPixelCalendar: nil,
            defaults: testUserDefaults
        ) { [weak self] pixelName, _, parameters, _, _, _ in
            self?.firedPixels.append((name: pixelName, parameters: parameters))
        }

        provider = NewTabPageNextStepsCardsProvider(
            continueSetUpModel: continueSetUpModel,
            appearancePreferences: AppearancePreferences(
                persistor: MockAppearancePreferencesPersistor(),
                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                featureFlagger: MockFeatureFlagger()
            ),
            pixelKit: pixelKit
        )
    }

    override func tearDown() {
        provider = nil
        firedPixels = nil
        testUserDefaults = nil
        pixelKit = nil
    }

    func testWhenCardsViewIsNotOutdatedThenCardsAreReportedByModel() {
        provider.appearancePreferences.isContinueSetUpCardsViewOutdated = false
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser, .dock, .emailProtection]]

        XCTAssertEqual(provider.cards, [.defaultApp, .addAppToDockMac, .emailProtection])
    }

    func testWhenCardsViewIsOutdatedThenCardsAreEmpty() {
        provider.appearancePreferences.isContinueSetUpCardsViewOutdated = true
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser, .dock, .emailProtection]]

        XCTAssertEqual(provider.cards, [])
    }

    func testWhenCardsViewIsNotOutdatedThenCardsAreEmitted() {
        provider.appearancePreferences.isContinueSetUpCardsViewOutdated = false
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser]]

        var cardsEvents = [[NewTabPageDataModel.CardID]]()

        let cancellable = provider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        provider.continueSetUpModel.featuresMatrix = [[.dock]]
        provider.continueSetUpModel.featuresMatrix = [[.dock, .duckplayer]]
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser]]

        cancellable.cancel()
        XCTAssertEqual(cardsEvents, [[.addAppToDockMac], [.addAppToDockMac, .duckplayer], [.defaultApp]])
    }

    func testWhenCardsViewIsOutdatedThenEmptyCardsAreEmitted() {
        provider.appearancePreferences.isContinueSetUpCardsViewOutdated = true
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser]]

        var cardsEvents = [[NewTabPageDataModel.CardID]]()

        let cancellable = provider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        provider.continueSetUpModel.featuresMatrix = [[.dock]]
        provider.continueSetUpModel.featuresMatrix = [[.duckplayer]]
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser]]

        cancellable.cancel()
        XCTAssertEqual(cardsEvents, [[], [], []])
    }

    func testWhenCardsViewBecomesOutdatedThenCardsStopBeingEmitted() {
        provider.appearancePreferences.isContinueSetUpCardsViewOutdated = false
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser]]

        var cardsEvents = [[NewTabPageDataModel.CardID]]()

        let cancellable = provider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        provider.continueSetUpModel.featuresMatrix = [[.dock]]
        provider.continueSetUpModel.featuresMatrix = [[.dock, .duckplayer]]
        provider.appearancePreferences.isContinueSetUpCardsViewOutdated = true
        provider.continueSetUpModel.featuresMatrix = [[.defaultBrowser]]

        cancellable.cancel()
        XCTAssertEqual(cardsEvents, [[.addAppToDockMac], [.addAppToDockMac, .duckplayer], [], []])
    }

    // MARK: - Pixel Tests (Card Shown)

    @MainActor
    func testWhenWillDisplayCardsWithAddToDockThenCardPresentedPixelIsFired() {
        provider.willDisplayCards([.addAppToDockMac])

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, "m_mac_add_to_dock_new_tab_page_card_presented_u")
        XCTAssertNil(firedPixels.first?.parameters["appVersion"], "Expected appVersion parameter to NOT be included")
    }

    @MainActor
    func testWhenWillDisplayCardsWithDuckplayerThenShownPixelIsFired() {
        provider.willDisplayCards([.duckplayer])

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, "m_mac_new-tab-page_next-steps_shown")
        XCTAssertEqual(firedPixels.first?.parameters["key"], "duckplayer")
        XCTAssertNil(firedPixels.first?.parameters["appVersion"], "Expected appVersion parameter to NOT be included")
    }

    @MainActor
    func testWhenWillDisplayCardsWithMultipleCardsThenShownPixelIsFiredForEach() {
        provider.willDisplayCards([.duckplayer, .emailProtection, .addAppToDockMac])

        XCTAssertEqual(firedPixels.count, 3)

        // duckplayer fires nextStepsCardShown
        XCTAssertEqual(firedPixels[0].name, "m_mac_new-tab-page_next-steps_shown")
        XCTAssertEqual(firedPixels[0].parameters["key"], "duckplayer")

        // emailProtection fires nextStepsCardShown
        XCTAssertEqual(firedPixels[1].name, "m_mac_new-tab-page_next-steps_shown")
        XCTAssertEqual(firedPixels[1].parameters["key"], "emailProtection")

        // addAppToDockMac fires its own unique pixel
        XCTAssertEqual(firedPixels[2].name, "m_mac_add_to_dock_new_tab_page_card_presented_u")
    }

    @MainActor
    func testWhenWillDisplayCardsWithSubscriptionThenShownPixelIsFired() {
        provider.willDisplayCards([.subscription])

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, "m_mac_new-tab-page_next-steps_shown")
        XCTAssertEqual(firedPixels.first?.parameters["key"], "subscription")
    }

    @MainActor
    func testWhenWillDisplayCardsWithDefaultAppThenShownPixelIsFired() {
        provider.willDisplayCards([.defaultApp])

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, "m_mac_new-tab-page_next-steps_shown")
        XCTAssertEqual(firedPixels.first?.parameters["key"], "defaultApp")
    }

    @MainActor
    func testWhenWillDisplayCardsWithBringStuffThenShownPixelIsFired() {
        provider.willDisplayCards([.bringStuff])

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.name, "m_mac_new-tab-page_next-steps_shown")
        XCTAssertEqual(firedPixels.first?.parameters["key"], "bringStuff")
    }
}

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
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageNextStepsCardsProviderTests: XCTestCase {
    private var provider: NewTabPageNextStepsCardsProvider!
    private var pixelHandler: MockNewTabPageNextStepsCardsPixelHandler!

    @MainActor
    override func setUp() async throws {
        pixelHandler = MockNewTabPageNextStepsCardsPixelHandler()

        let continueSetUpModel = HomePage.Models.ContinueSetUpModel(
            defaultBrowserProvider: CapturingDefaultBrowserProvider(),
            dockCustomizer: DockCustomizerMock(),
            dataImportProvider: CapturingDataImportProvider(),
            emailManager: EmailManager(storage: MockEmailStorage()),
            duckPlayerPreferences: DuckPlayerPreferencesPersistorMock(),
            subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging(),
            persistor: MockHomePageContinueSetUpModelPersisting(),
            pixelHandler: pixelHandler,
            cardActionsHandler: MockNewTabPageNextStepsCardsActionHandler()
        )
        provider = NewTabPageNextStepsCardsProvider(
            continueSetUpModel: continueSetUpModel,
            appearancePreferences: AppearancePreferences(
                persistor: MockAppearancePreferencesPersistor(),
                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                featureFlagger: MockFeatureFlagger()
            ),
            pixelHandler: pixelHandler
        )
    }

    override func tearDown() {
        provider = nil
        pixelHandler = nil
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
    func testWhenWillDisplayCardsWithAddToDockThenCardPresentedAndShownPixelsAreFired() {
        provider.willDisplayCards([.addAppToDockMac])

        XCTAssertEqual(pixelHandler.fireAddToDockPresentedPixelIfNeededCalledWith, [.addAppToDockMac])
        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.addAppToDockMac])
    }

    @MainActor
    func testWhenWillDisplayCardsWithDuckplayerThenShownPixelIsFired() {
        provider.willDisplayCards([.duckplayer])

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.duckplayer])
    }

    @MainActor
    func testWhenWillDisplayCardsWithSubscriptionThenShownPixelIsFired() {
        provider.willDisplayCards([.subscription])

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.subscription])
    }

    @MainActor
    func testWhenWillDisplayCardsWithDefaultAppThenShownPixelIsFired() {
        provider.willDisplayCards([.defaultApp])

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.defaultApp])
    }

    @MainActor
    func testWhenWillDisplayCardsWithBringStuffThenShownPixelIsFired() {
        provider.willDisplayCards([.bringStuff])

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.bringStuff])
    }

    @MainActor
    func testWhenWillDisplayCardsWithEmailProtectionThenShownPixelIsFired() {
        provider.willDisplayCards([.emailProtection])

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.emailProtection])
    }

    @MainActor
    func testWhenWillDisplayCardsWithMultipleCardsThenShownPixelIsFiredForEach() {
        provider.willDisplayCards([.duckplayer, .emailProtection, .bringStuff])

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.duckplayer, .emailProtection, .bringStuff])
    }
}

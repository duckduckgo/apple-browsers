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
    private var firedPixels: [(event: PixelKitEvent, frequency: PixelKit.Frequency, includesAppVersionParameter: Bool)] = []

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

        provider = NewTabPageNextStepsCardsProvider(
            continueSetUpModel: continueSetUpModel,
            appearancePreferences: AppearancePreferences(
                persistor: MockAppearancePreferencesPersistor(),
                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                featureFlagger: MockFeatureFlagger()
            ),
            pixelHandler: { event, frequency, includesAppVersionParameter in
                self.firedPixels.append((event, frequency, includesAppVersionParameter))
            }
        )
    }

    override func tearDown() {
        provider = nil
        firedPixels = []
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

        XCTAssertEqual(firedPixels.count, 2)

        // addAppToDockMac fires addToDockNewTabPageCardPresented
        let expectedPresentedEvent = GeneralPixel.addToDockNewTabPageCardPresented
        let actualPresentedEvent = firedPixels.first(where: { $0.event.name == expectedPresentedEvent.name })
        XCTAssertNotNil(actualPresentedEvent)
        XCTAssertEqual(actualPresentedEvent?.event.parameters, expectedPresentedEvent.parameters)
        XCTAssertEqual(actualPresentedEvent?.frequency, .uniqueByName)
        XCTAssertEqual(actualPresentedEvent?.includesAppVersionParameter, false)

        // addAppToDockMac fires nextStepsCardShown
        let expectedShownEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.addAppToDockMac.rawValue)
        let actualShownEvent = firedPixels.first(where: { $0.event.name == expectedShownEvent.name })
        XCTAssertNotNil(actualShownEvent)
        XCTAssertEqual(actualShownEvent?.event.parameters, expectedShownEvent.parameters)
        XCTAssertEqual(actualShownEvent?.frequency, .uniqueByNameAndParameters)
        XCTAssertEqual(actualShownEvent?.includesAppVersionParameter, false)
    }

    @MainActor
    func testWhenWillDisplayCardsWithDuckplayerThenShownPixelIsFired() {
        provider.willDisplayCards([.duckplayer])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.duckplayer.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.event.parameters, expectedEvent.parameters)
        XCTAssertEqual(firedPixels.first?.frequency, .uniqueByNameAndParameters)
        XCTAssertEqual(firedPixels.first?.includesAppVersionParameter, false)
    }

    @MainActor
    func testWhenWillDisplayCardsWithSubscriptionThenShownPixelIsFired() {
        provider.willDisplayCards([.subscription])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.subscription.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.event.parameters, expectedEvent.parameters)
    }

    @MainActor
    func testWhenWillDisplayCardsWithDefaultAppThenShownPixelIsFired() {
        provider.willDisplayCards([.defaultApp])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.defaultApp.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.event.parameters, expectedEvent.parameters)
    }

    @MainActor
    func testWhenWillDisplayCardsWithBringStuffThenShownPixelIsFired() {
        provider.willDisplayCards([.bringStuff])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.bringStuff.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.event.parameters, expectedEvent.parameters)
    }

    @MainActor
    func testWhenWillDisplayCardsWithEmailProtectionThenShownPixelIsFired() {
        provider.willDisplayCards([.emailProtection])

        XCTAssertEqual(firedPixels.count, 1)
        let expectedEvent = NewTabPagePixel.nextStepsCardShown(NewTabPageDataModel.CardID.emailProtection.rawValue)
        XCTAssertEqual(firedPixels.first?.event.name, expectedEvent.name)
        XCTAssertEqual(firedPixels.first?.event.parameters, expectedEvent.parameters)
    }

    @MainActor
    func testWhenWillDisplayCardsWithMultipleCardsThenShownPixelIsFiredForEach() {
        provider.willDisplayCards([.duckplayer, .emailProtection, .bringStuff])

        XCTAssertEqual(firedPixels.count, 3)

        XCTAssertTrue(firedPixels.allSatisfy { $0.event.name == NewTabPagePixel.nextStepsCardShown("").name })
        XCTAssertTrue(firedPixels.contains(where: { $0.event.parameters?["key"] == NewTabPageDataModel.CardID.duckplayer.rawValue }))
        XCTAssertTrue(firedPixels.contains(where: { $0.event.parameters?["key"] == NewTabPageDataModel.CardID.emailProtection.rawValue }))
        XCTAssertTrue(firedPixels.contains(where: { $0.event.parameters?["key"] == NewTabPageDataModel.CardID.bringStuff.rawValue }))
    }
}

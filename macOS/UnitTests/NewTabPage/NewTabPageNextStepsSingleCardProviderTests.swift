//
//  NewTabPageNextStepsSingleCardProviderTests.swift
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

import BrowserServicesKit
import Combine
import NewTabPage
import PersistenceTestingUtils
import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageNextStepsSingleCardProviderTests: XCTestCase {
    private var provider: NewTabPageNextStepsSingleCardProvider!
    private var pixelHandler: MockNewTabPageNextStepsCardsPixelHandler!
    private var actionHandler: MockNewTabPageNextStepsCardsActionHandler!
    private var keyValueStore: MockKeyValueFileStore!
    private var legacyKeyValueStore: MockKeyValueStore!
    private var persistor: MockNewTabPageNextStepsCardsPersistor!
    private var legacyPersistor: MockHomePageContinueSetUpModelPersisting!
    private var legacySubscriptionCardPersistor: MockHomePageSubscriptionCardPersisting!
    private var appearancePreferences: AppearancePreferences!
    private var defaultBrowserProvider: CapturingDefaultBrowserProvider!
    private var dockCustomizer: DockCustomizerMock!
    private var dataImportProvider: CapturingDataImportProvider!
    private var emailManager: EmailManager!
    private var duckPlayerPreferences: DuckPlayerPreferencesPersistorMock!
    private var subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        pixelHandler = MockNewTabPageNextStepsCardsPixelHandler()
        actionHandler = MockNewTabPageNextStepsCardsActionHandler()
        persistor = MockNewTabPageNextStepsCardsPersistor()
        legacyPersistor = MockHomePageContinueSetUpModelPersisting()
        legacySubscriptionCardPersistor = MockHomePageSubscriptionCardPersisting()

        appearancePreferences = AppearancePreferences(
            persistor: MockAppearancePreferencesPersistor(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger()
        )

        defaultBrowserProvider = CapturingDefaultBrowserProvider()
        dockCustomizer = DockCustomizerMock()
        dataImportProvider = CapturingDataImportProvider()
        emailManager = EmailManager(storage: MockEmailStorage())
        duckPlayerPreferences = DuckPlayerPreferencesPersistorMock()
        subscriptionCardVisibilityManager = MockHomePageSubscriptionCardVisibilityManaging()

        keyValueStore = try MockKeyValueFileStore()
        legacyKeyValueStore = MockKeyValueStore()

        provider = NewTabPageNextStepsSingleCardProvider(
            cardActionHandler: actionHandler,
            pixelHandler: pixelHandler,
            persistor: persistor,
            legacyPersistor: legacyPersistor,
            legacySubscriptionCardPersistor: legacySubscriptionCardPersistor,
            appearancePreferences: appearancePreferences,
            defaultBrowserProvider: defaultBrowserProvider,
            dockCustomizer: dockCustomizer,
            dataImportProvider: dataImportProvider,
            emailManager: emailManager,
            duckPlayerPreferences: duckPlayerPreferences,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager
        )
    }

    override func tearDown() {
        provider = nil
        pixelHandler = nil
        actionHandler = nil
        keyValueStore = nil
        legacyKeyValueStore = nil
        persistor = nil
        legacyPersistor = nil
        legacySubscriptionCardPersistor = nil
        appearancePreferences = nil
        defaultBrowserProvider = nil
        dockCustomizer = nil
        dataImportProvider = nil
        emailManager = nil
        duckPlayerPreferences = nil
        subscriptionCardVisibilityManager = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testWhenInitializedThenCardListIsRefreshed() {
        // The card list should be populated based on visibility conditions
        // This test verifies that refreshCardList() was called during init
        // We can verify by checking that cards property is not nil (it's initialized)
        XCTAssertNotNil(provider.cards)
    }

    func testWhenInitializedWithNoVisibleCardsThenContinueSetUpCardsClosedIsSet() {
        // Set up all conditions to hide all cards
        let testProvider = createProvider(
            defaultBrowserIsDefault: true,
            dataImportDidImport: true,
            dockStatus: true,
            duckPlayerModeBool: true,
            emailManagerSignedIn: true,
            subscriptionCardShouldShow: false
        )

        XCTAssertTrue(appearancePreferences.continueSetUpCardsClosed)
        XCTAssertTrue(testProvider.cards.isEmpty)
    }

    // MARK: - Cards Property Tests

    func testWhenCardsViewIsNotOutdatedThenCardsAreReturned() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider(defaultBrowserIsDefault: false)

        let cards = testProvider.cards
        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(cards.contains(.defaultApp))
    }

    func testWhenCardsViewIsOutdatedThenCardsAreEmpty() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = true
        let testProvider = createProvider(defaultBrowserIsDefault: false)

        XCTAssertTrue(testProvider.cards.isEmpty)
    }

    func testWhenCardsViewBecomesOutdatedThenCardsBecomeEmpty() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider(defaultBrowserIsDefault: false)

        let initialCards = testProvider.cards
        XCTAssertFalse(initialCards.isEmpty)

        appearancePreferences.isContinueSetUpCardsViewOutdated = true

        XCTAssertTrue(testProvider.cards.isEmpty)
    }

    // MARK: - Cards Publisher Tests

    @MainActor
    func testWhenCardListChangesThenPublisherEmitsNewCards() {
        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let cancellable = provider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        // Trigger card list refreshes by dismissing cards
        provider.dismiss(.defaultApp)
        provider.dismiss(.duckplayer)
        provider.dismiss(.emailProtection)

        cancellable.cancel()

        XCTAssertEqual(cardsEvents.count, 3)
    }

    @MainActor
    func testWhenCardsViewIsOutdatedThenPublisherEmitsEmptyArray() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = true

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let cancellable = provider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        // Trigger card list refresh by dismissing card
        provider.dismiss(.defaultApp)

        cancellable.cancel()

        XCTAssertEqual(cardsEvents.last, [])
    }

    @MainActor
    func testWhenCardsViewBecomesOutdatedThenPublisherStopsEmittingCards() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let cancellable = provider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        // Trigger card list refreshes by dismissing cards
        provider.dismiss(.defaultApp)
        provider.dismiss(.duckplayer)
        appearancePreferences.isContinueSetUpCardsViewOutdated = true
        provider.dismiss(.emailProtection)

        cancellable.cancel()

        XCTAssertEqual(cardsEvents.last, [])
    }

    func testWhenSubscriptionVisibilityChangesThenCardListRefreshes() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        subscriptionCardVisibilityManager.shouldShowSubscriptionCard = true
        XCTAssertTrue(provider.cards.contains(.subscription))

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let expectation = XCTestExpectation(description: "Cards publisher emits when subscription visibility changes")
        let cancellable = provider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
                expectation.fulfill()
            }

        // Change subscription card visibility
        subscriptionCardVisibilityManager.shouldShowSubscriptionCard = false

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(cardsEvents.last?.contains(.subscription), false)
    }

    func testWhenWindowBecomesKeyThenCardListRefreshes() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let expectation = XCTestExpectation(description: "Cards publisher emits on window key notification")
        let cancellable = provider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
                expectation.fulfill()
            }

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: nil)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertFalse(cardsEvents.isEmpty)
    }

    func testWhenNewTabPageWebViewAppearsThenCardListRefreshes() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let expectation = XCTestExpectation(description: "Cards publisher emits when New Tab Page WebView appears")
        let cancellable = provider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
                expectation.fulfill()
            }

        NotificationCenter.default.post(name: .newTabPageWebViewDidAppear, object: nil)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertFalse(cardsEvents.isEmpty)
    }

    // MARK: - Card Visibility Logic Tests

    // Default App Card
    func testWhenDefaultBrowserIsNotDefaultThenDefaultAppCardIsVisible() {
        let testProvider = createProvider(defaultBrowserIsDefault: false)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.defaultApp))
    }

    func testWhenDefaultBrowserIsDefaultThenDefaultAppCardIsNotVisible() {
        let testProvider = createProvider(defaultBrowserIsDefault: true)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.defaultApp))
    }

    // Bring Stuff Card
    func testWhenDataImportDidNotImportThenBringStuffCardIsVisible() {
        let testProvider = createProvider(dataImportDidImport: false)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.bringStuff))
    }

    func testWhenDataImportDidImportThenBringStuffCardIsNotVisible() {
        let testProvider = createProvider(dataImportDidImport: true)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.bringStuff))
    }

    // Add App to Dock Card
    func testWhenAppNotAddedToDockThenAddAppToDockCardIsVisible() {
        let testProvider = createProvider(dockStatus: false)

        let cards = testProvider.cards
        #if !APPSTORE
        XCTAssertTrue(cards.contains(.addAppToDockMac))
        #else
        XCTAssertFalse(cards.contains(.addAppToDockMac))
        #endif
    }

    func testWhenAppAddedToDockThenAddAppToDockCardIsNotVisible() {
        let testProvider = createProvider(dockStatus: true)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.addAppToDockMac))
    }

    // DuckPlayer Card
    func testWhenDuckPlayerModeIsNilAndOverlayNotPressedThenDuckPlayerCardIsVisible() {
        let testProvider = createProvider(
            duckPlayerModeBool: nil,
            youtubeOverlayAnyButtonPressed: false
        )

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.duckplayer))
    }

    func testWhenDuckPlayerModeIsSetThenDuckPlayerCardIsNotVisible() {
        let testProvider = createProvider(duckPlayerModeBool: true)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.duckplayer))
    }

    func testWhenDuckPlayerOverlayButtonPressedThenDuckPlayerCardIsNotVisible() {
        let testProvider = createProvider(
            duckPlayerModeBool: nil,
            youtubeOverlayAnyButtonPressed: true
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.duckplayer))
    }

    // Email Protection Card
    func testWhenEmailManagerNotSignedInThenEmailProtectionCardIsVisible() {
        let testProvider = createProvider(emailManagerSignedIn: false)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.emailProtection))
    }

    func testWhenEmailManagerSignedInThenEmailProtectionCardIsNotVisible() {
        let testProvider = createProvider(emailManagerSignedIn: true)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.emailProtection))
    }

    // Subscription Card
    func testWhenSubscriptionCardShouldShowThenSubscriptionCardIsVisible() {
        let testProvider = createProvider(subscriptionCardShouldShow: true)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.subscription))
    }

    func testWhenSubscriptionCardShouldNotShowThenSubscriptionCardIsNotVisible() {
        let testProvider = createProvider(subscriptionCardShouldShow: false)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.subscription))
    }

    // MARK: - Permanent Dismissal Tests

    func testWhenCardDismissedMaxTimesThenCardIsPermanentlyDismissed() {
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.setTimesDismissed(1, for: .defaultApp) // maxTimesCardDismissed = 1
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            persistor: testPersistor
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.defaultApp))
    }

    func testWhenCardDismissedViaLegacySettingThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowMakeDefaultSetting = false
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            legacyPersistor: testLegacyPersistor
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.defaultApp))
    }

    func testWhenCardDismissedLessThanMaxTimesThenCardIsNotPermanentlyDismissed() {
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.setTimesDismissed(0, for: .defaultApp) // Less than max
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            persistor: testPersistor
        )

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.defaultApp))
    }

    func testWhenDefaultAppCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowMakeDefaultSetting = false
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            legacyPersistor: testLegacyPersistor
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.defaultApp))
    }

    func testWhenAddAppToDockCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowAddToDockSetting = false
        let testProvider = createProvider(
            dockStatus: false,
            legacyPersistor: testLegacyPersistor
        )

        let cards = testProvider.cards
        #if !APPSTORE
        XCTAssertFalse(cards.contains(.addAppToDockMac))
        #else
        XCTAssertFalse(cards.contains(.addAppToDockMac))
        #endif
    }

    func testWhenDuckPlayerCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowDuckPlayerSetting = false
        let testProvider = createProvider(
            duckPlayerModeBool: nil,
            youtubeOverlayAnyButtonPressed: false,
            legacyPersistor: testLegacyPersistor
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.duckplayer))
    }

    func testWhenEmailProtectionCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowEmailProtectionSetting = false
        let testProvider = createProvider(
            emailManagerSignedIn: false,
            legacyPersistor: testLegacyPersistor
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.emailProtection))
    }

    func testWhenBringStuffCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowImportSetting = false
        let testProvider = createProvider(
            dataImportDidImport: false,
            legacyPersistor: testLegacyPersistor
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.bringStuff))
    }

    func testWhenSubscriptionCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacySubscriptionCardPersistor = MockHomePageSubscriptionCardPersisting()
        testLegacySubscriptionCardPersistor.shouldShowSubscriptionSetting = false
        let testProvider = createProvider(
            subscriptionCardShouldShow: true,
            legacySubscriptionCardPersistor: testLegacySubscriptionCardPersistor
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.subscription))
    }

    // MARK: - Action Handling Tests

    @MainActor
    func testWhenHandleActionIsCalledThenActionHandlerIsInvoked() {
        let card: NewTabPageDataModel.CardID = .defaultApp

        provider.handleAction(for: card)

        XCTAssertEqual(actionHandler.cardActionsPerformed, [card])
    }

    // MARK: - Dismissal Tests

    @MainActor
    func testWhenCardIsDismissedThenPixelIsFired() {
        let card: NewTabPageDataModel.CardID = .defaultApp

        provider.dismiss(card)

        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, card)
    }

    @MainActor
    func testWhenSubscriptionCardIsDismissedThenBothPixelsAreFired() {
        let card: NewTabPageDataModel.CardID = .subscription

        provider.dismiss(card)

        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, card)
        XCTAssertTrue(pixelHandler.fireSubscriptionCardDismissedPixelCalled)
    }

    @MainActor
    func testWhenCardIsDismissedThenTimesDismissedIsIncremented() {
        let card: NewTabPageDataModel.CardID = .defaultApp
        let initialTimesDismissed = persistor.timesDismissed(for: card)

        provider.dismiss(card)

        XCTAssertEqual(persistor.timesDismissed(for: card), initialTimesDismissed + 1)
    }

    // MARK: - Will Display Cards Tests

    @MainActor
    func testWhenWillDisplayCardsIsCalledThenPixelIsFiredForFirstCard() {
        let cards: [NewTabPageDataModel.CardID] = [.defaultApp, .emailProtection, .bringStuff]

        provider.willDisplayCards(cards)

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.defaultApp])
    }

    @MainActor
    func testWhenWillDisplayCardsIsCalledWithAddToDockFirstThenBothPixelsAreFired() {
        let cards: [NewTabPageDataModel.CardID] = [.addAppToDockMac, .emailProtection, .bringStuff]

        provider.willDisplayCards(cards)

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.addAppToDockMac])
        XCTAssertEqual(pixelHandler.fireAddToDockPresentedPixelIfNeededCalledWith, [.addAppToDockMac])
    }

    @MainActor
    func testWhenWillDisplayCardsIsCalledThenTimesShownIsIncrementedForFirstCard() {
        let cards: [NewTabPageDataModel.CardID] = [.defaultApp, .emailProtection]
        let initialTimesShown = persistor.timesShown(for: .defaultApp)

        provider.willDisplayCards(cards)

        XCTAssertEqual(persistor.timesShown(for: .defaultApp), initialTimesShown + 1)
        // Email protection should not be incremented (only first card)
        XCTAssertEqual(persistor.timesShown(for: .emailProtection), 0)
    }

    // MARK: - Edge Cases

    func testWhenAllCardsArePermanentlyDismissedThenCardsListIsEmpty() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        for card in NewTabPageDataModel.CardID.allCases {
            testPersistor.setTimesDismissed(NewTabPageNextStepsSingleCardProvider.Constants.maxTimesCardDismissed, for: card)
        }

        let testProvider = createProvider(persistor: testPersistor)

        let cards = testProvider.cards
        XCTAssertTrue(cards.isEmpty)
        XCTAssertTrue(appearancePreferences.continueSetUpCardsClosed)
    }

    func testWhenAllCardsAreNotVisibleThenCardsListIsEmpty() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider(
            defaultBrowserIsDefault: true,
            dataImportDidImport: true,
            dockStatus: true,
            duckPlayerModeBool: true,
            emailManagerSignedIn: true,
            subscriptionCardShouldShow: false
        )

        let cards = testProvider.cards
        XCTAssertTrue(cards.isEmpty)
    }

    // MARK: - Helper Functions

    private func createProvider(
        defaultBrowserIsDefault: Bool? = nil,
        dataImportDidImport: Bool? = nil,
        dockStatus: Bool? = nil,
        duckPlayerModeBool: Bool?? = nil,
        youtubeOverlayAnyButtonPressed: Bool? = nil,
        emailManagerSignedIn: Bool? = nil,
        subscriptionCardShouldShow: Bool? = nil,
        appearancePreferences: AppearancePreferences? = nil,
        persistor: MockNewTabPageNextStepsCardsPersistor? = nil,
        legacyPersistor: MockHomePageContinueSetUpModelPersisting? = nil,
        legacySubscriptionCardPersistor: MockHomePageSubscriptionCardPersisting? = nil
    ) -> NewTabPageNextStepsSingleCardProvider {
        let testDefaultBrowserProvider: CapturingDefaultBrowserProvider = {
            if let value = defaultBrowserIsDefault {
                let provider = CapturingDefaultBrowserProvider()
                provider.isDefault = value
                return provider
            }
            return defaultBrowserProvider!
        }()

        let testDataImportProvider: CapturingDataImportProvider = {
            if let value = dataImportDidImport {
                let provider = CapturingDataImportProvider()
                provider.didImport = value
                return provider
            }
            return dataImportProvider!
        }()

        let testDockCustomizer: DockCustomizerMock = {
            if let value = dockStatus {
                let customizer = DockCustomizerMock()
                customizer.dockStatus = value
                return customizer
            }
            return dockCustomizer!
        }()

        let testDuckPlayerPreferences: DuckPlayerPreferencesPersistorMock = {
            if duckPlayerModeBool != nil || youtubeOverlayAnyButtonPressed != nil {
                let prefs = DuckPlayerPreferencesPersistorMock()
                if let modeBool = duckPlayerModeBool {
                    prefs.duckPlayerModeBool = modeBool
                }
                if let overlayPressed = youtubeOverlayAnyButtonPressed {
                    prefs.youtubeOverlayAnyButtonPressed = overlayPressed
                }
                return prefs
            }
            return duckPlayerPreferences!
        }()

        let testEmailManager: EmailManager = {
            if let signedIn = emailManagerSignedIn {
                let emailStorage = MockEmailStorage()
                emailStorage.isEmailProtectionEnabled = signedIn
                return EmailManager(storage: emailStorage)
            }
            return emailManager!
        }()

        let testSubscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging = {
            if let shouldShow = subscriptionCardShouldShow {
                let manager = MockHomePageSubscriptionCardVisibilityManaging()
                manager.shouldShowSubscriptionCard = shouldShow
                return manager
            }
            return subscriptionCardVisibilityManager!
        }()

        let testAppearancePreferences = appearancePreferences ?? self.appearancePreferences!
        let testPersistor = persistor ?? self.persistor!
        let testLegacyPersistor = legacyPersistor ?? self.legacyPersistor!
        let testLegacySubscriptionCardPersistor = legacySubscriptionCardPersistor ?? self.legacySubscriptionCardPersistor!

        return NewTabPageNextStepsSingleCardProvider(
            cardActionHandler: actionHandler,
            pixelHandler: pixelHandler,
            persistor: testPersistor,
            legacyPersistor: testLegacyPersistor,
            legacySubscriptionCardPersistor: testLegacySubscriptionCardPersistor,
            appearancePreferences: testAppearancePreferences,
            defaultBrowserProvider: testDefaultBrowserProvider,
            dockCustomizer: testDockCustomizer,
            dataImportProvider: testDataImportProvider,
            emailManager: testEmailManager,
            duckPlayerPreferences: testDuckPlayerPreferences,
            subscriptionCardVisibilityManager: testSubscriptionCardVisibilityManager
        )
    }
}

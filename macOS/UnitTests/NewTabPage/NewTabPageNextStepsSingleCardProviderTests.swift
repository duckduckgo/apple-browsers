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
import DDGSync
import FeatureFlags
import NewTabPage
import PersistenceTestingUtils
import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageNextStepsSingleCardProviderTests: XCTestCase {
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
    private var syncService: MockDDGSyncing!
    private var featureFlagger: MockFeatureFlagger!

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
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )

        defaultBrowserProvider = CapturingDefaultBrowserProvider()
        dockCustomizer = DockCustomizerMock()
        dataImportProvider = CapturingDataImportProvider()
        emailManager = EmailManager(storage: MockEmailStorage())
        duckPlayerPreferences = DuckPlayerPreferencesPersistorMock()
        subscriptionCardVisibilityManager = MockHomePageSubscriptionCardVisibilityManaging()
        syncService = MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
        featureFlagger = MockFeatureFlagger()

        keyValueStore = MockKeyValueFileStore()
        legacyKeyValueStore = MockKeyValueStore()
    }

    override func tearDown() {
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
        syncService = nil
        featureFlagger = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testWhenInitializedThenCardListIsRefreshed() {
        featureFlagger.enabledFeatureFlags = []
        let testProvider = createProvider()

#if !APPSTORE
        let expectedCards = NewTabPageNextStepsSingleCardProvider.defaultStandardCards
#else
        let expectedCards =  NewTabPageNextStepsSingleCardProvider.defaultStandardCards.filter { $0 != .addAppToDockMac }
#endif

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenInitializedWithNoVisibleCardsThenContinueSetUpCardsClosedIsSet() {
        // Set up all conditions to hide all cards
        let testAppearancePreferences = createAppearancePrefs(didChangeAnyCustomizationSetting: true)
        let testProvider = createProvider(
            defaultBrowserIsDefault: true,
            dataImportDidImport: true,
            dockStatus: true,
            duckPlayerModeBool: true,
            emailManagerSignedIn: true,
            subscriptionCardShouldShow: false,
            syncConnected: true,
            appearancePreferences: testAppearancePreferences
        )

        XCTAssertTrue(testAppearancePreferences.continueSetUpCardsClosed)
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
        let testProvider = createProvider()
        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let cancellable = testProvider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        // Trigger card list refreshes by dismissing cards
        testProvider.dismiss(.defaultApp)
        testProvider.dismiss(.duckplayer)
        testProvider.dismiss(.emailProtection)

        cancellable.cancel()

        XCTAssertEqual(cardsEvents.count, 3)
    }

    @MainActor
    func testWhenCardsViewIsOutdatedThenPublisherEmitsEmptyArray() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = true
        let testProvider = createProvider()

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let cancellable = testProvider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        // Trigger card list refresh by dismissing card
        testProvider.dismiss(.defaultApp)

        cancellable.cancel()

        XCTAssertEqual(cardsEvents.last, [])
    }

    @MainActor
    func testWhenCardsViewBecomesOutdatedThenPublisherStopsEmittingCards() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider()

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let cancellable = testProvider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        // Trigger card list refreshes by dismissing cards
        testProvider.dismiss(.defaultApp)
        testProvider.dismiss(.duckplayer)
        appearancePreferences.isContinueSetUpCardsViewOutdated = true
        testProvider.dismiss(.emailProtection)

        cancellable.cancel()

        XCTAssertEqual(cardsEvents.last, [])
    }

    func testWhenSubscriptionVisibilityChangesThenCardListRefreshes() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        subscriptionCardVisibilityManager.shouldShowSubscriptionCard = true
        let testProvider = createProvider()
        XCTAssertTrue(testProvider.cards.contains(.subscription))

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let expectation = XCTestExpectation(description: "Cards publisher emits when subscription visibility changes")
        let cancellable = testProvider.cardsPublisher
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
        let testProvider = createProvider()

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let expectation = XCTestExpectation(description: "Cards publisher emits on window key notification")
        let cancellable = testProvider.cardsPublisher
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
        let testProvider = createProvider()

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let expectation = XCTestExpectation(description: "Cards publisher emits when New Tab Page WebView appears")
        let cancellable = testProvider.cardsPublisher
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

    // Personalize Browser Card
    func testWhenCustomizationNotChangedThenPersonalizeBrowserCardIsVisible() {
        let testAppearancePreferences = createAppearancePrefs(didChangeAnyCustomizationSetting: false)
        let testProvider = createProvider(appearancePreferences: testAppearancePreferences)

        XCTAssertTrue(testProvider.cards.contains(.personalizeBrowser))
    }

    func testWhenCustomizationChangedThenPersonalizeBrowserCardIsNotVisible() {
        let testAppearancePreferences = createAppearancePrefs(didChangeAnyCustomizationSetting: true)
        let testProvider = createProvider(appearancePreferences: testAppearancePreferences)

        XCTAssertFalse(testProvider.cards.contains(.personalizeBrowser))
    }

    // Sync Card
    func testWhenSyncCardShouldShowThenSyncCardIsVisible() {
        let testProvider = createProvider(syncConnected: false)

        XCTAssertTrue(testProvider.cards.contains(.sync))
    }

    func testWhenSyncCardShouldNotShowThenSyncCardIsNotVisible() {
        let testProvider = createProvider(syncConnected: true)

        XCTAssertFalse(testProvider.cards.contains(.sync))
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
        let testProvider = createProvider()
        let card: NewTabPageDataModel.CardID = .defaultApp

        testProvider.handleAction(for: card)

        XCTAssertEqual(actionHandler.cardActionsPerformed, [card])
    }

    // MARK: - Dismissal Tests

    @MainActor
    func testWhenCardIsDismissedThenPixelIsFired() {
        let testProvider = createProvider()
        let card: NewTabPageDataModel.CardID = .defaultApp

        testProvider.dismiss(card)

        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, card)
    }

    @MainActor
    func testWhenSubscriptionCardIsDismissedThenBothPixelsAreFired() {
        let testProvider = createProvider()
        let card: NewTabPageDataModel.CardID = .subscription

        testProvider.dismiss(card)

        XCTAssertEqual(pixelHandler.fireNextStepsCardDismissedPixelCalledWith, card)
        XCTAssertTrue(pixelHandler.fireSubscriptionCardDismissedPixelCalled)
    }

    @MainActor
    func testWhenCardIsDismissedThenTimesDismissedIsIncremented() {
        let testProvider = createProvider()
        let card: NewTabPageDataModel.CardID = .defaultApp
        let initialTimesDismissed = persistor.timesDismissed(for: card)

        testProvider.dismiss(card)

        XCTAssertEqual(persistor.timesDismissed(for: card), initialTimesDismissed + 1)
    }

    // MARK: - Will Display Cards Tests

    @MainActor
    func testWhenWillDisplayCardsIsCalledThenPixelIsFiredForFirstCard() {
        let testProvider = createProvider()
        let cards: [NewTabPageDataModel.CardID] = [.defaultApp, .emailProtection, .bringStuff]

        testProvider.willDisplayCards(cards)

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.defaultApp])
    }

    @MainActor
    func testWhenWillDisplayCardsIsCalledWithAddToDockFirstThenBothPixelsAreFired() {
        let testProvider = createProvider()
        let cards: [NewTabPageDataModel.CardID] = [.addAppToDockMac, .emailProtection, .bringStuff]

        testProvider.willDisplayCards(cards)

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.addAppToDockMac])
        XCTAssertEqual(pixelHandler.fireAddToDockPresentedPixelIfNeededCalledWith, [.addAppToDockMac])
    }

    @MainActor
    func testWhenWillDisplayCardsIsCalledThenTimesShownIsIncrementedForFirstCard() {
        let testProvider = createProvider()
        let cards: [NewTabPageDataModel.CardID] = [.defaultApp, .emailProtection]
        let initialTimesShown = persistor.timesShown(for: .defaultApp)

        testProvider.willDisplayCards(cards)

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
        let testAppearancePreferences = createAppearancePrefs(didChangeAnyCustomizationSetting: true)
        testAppearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider(
            defaultBrowserIsDefault: true,
            dataImportDidImport: true,
            dockStatus: true,
            duckPlayerModeBool: true,
            emailManagerSignedIn: true,
            subscriptionCardShouldShow: false,
            syncConnected: true,
            appearancePreferences: testAppearancePreferences
        )

        let cards = testProvider.cards
        XCTAssertTrue(cards.isEmpty)
    }

    // MARK: - Card Ordering Tests (nextStepsListAdvancedCardOrdering enabled)

    func testWhenNoPersistedOrder_WithAdvancedOrderingEnabled_ThenDefaultOrderIsUsed() {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.orderedCardIDs = nil
        let testProvider = createProvider(persistor: testPersistor, featureFlagger: testFeatureFlagger)

#if !APPSTORE
        let expectedCards = NewTabPageNextStepsSingleCardProvider.defaultAdvancedCards
#else
        let expectedCards = NewTabPageNextStepsSingleCardProvider.defaultAdvancedCards.filter { $0 != .addAppToDockMac }
#endif

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenPersistedOrderExists_WithAdvancedOrderingEnabled_ThenPersistedOrderIsUsed() {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        let persistedOrder: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .addAppToDockMac, .duckplayer, .bringStuff, .subscription, .personalizeBrowser, .sync]
        testPersistor.orderedCardIDs = persistedOrder
        let testProvider = createProvider(persistor: testPersistor, featureFlagger: testFeatureFlagger)

#if !APPSTORE
        let expectedCards = persistedOrder
#else
        let expectedCards = persistedOrder.filter { $0 != .addAppToDockMac }
#endif

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenFirstCardLevelIsLevel1AndDaysLessThanMaxDays_WithAdvancedOrderingEnabled_ThenLevel1CardsFirst() throws {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.firstCardLevel = .level1
        testPersistor.orderedCardIDs = nil
        let testAppearancePrefs = createAppearancePrefs(demonstrationDays: 1)
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            appearancePreferences: testAppearancePrefs,
            persistor: testPersistor,
            featureFlagger: testFeatureFlagger
        )

        let cards = testProvider.cards
        // Level 1 cards should appear before level 2 cards
        let level1Cards: [NewTabPageDataModel.CardID] = [.personalizeBrowser, .sync, .emailProtection]
        let level2Cards: [NewTabPageDataModel.CardID] = [.defaultApp, .addAppToDockMac, .duckplayer, .bringStuff, .subscription]

        let firstLevel1Index = try XCTUnwrap(cards.firstIndex(where: { level1Cards.contains($0) }))
        let firstLevel2Index = try XCTUnwrap(cards.firstIndex(where: { level2Cards.contains($0) }))
        XCTAssertLessThan(firstLevel1Index, firstLevel2Index, "Level 1 cards should come before level 2 cards")
    }

    func testWhenFirstCardLevelIsLevel1AndDaysGreaterThanOrEqualToMaxDays_WithAdvancedOrderingEnabled_ThenLevel2CardsFirst() throws {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.firstCardLevel = .level1
        testPersistor.orderedCardIDs = nil
        let testAppearancePrefs = createAppearancePrefs(demonstrationDays: 2)
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            appearancePreferences: testAppearancePrefs,
            persistor: testPersistor,
            featureFlagger: testFeatureFlagger
        )

        let cards = testProvider.cards

        // Level 2 cards should appear before level 1 cards after swap
        let level1Cards: [NewTabPageDataModel.CardID] = [.personalizeBrowser, .sync, .emailProtection]
        let level2Cards: [NewTabPageDataModel.CardID] = [.defaultApp, .addAppToDockMac, .duckplayer, .bringStuff, .subscription]

        let firstLevel1Index = try XCTUnwrap(cards.firstIndex(where: { level1Cards.contains($0) }))
        let firstLevel2Index = try XCTUnwrap(cards.firstIndex(where: { level2Cards.contains($0) }))
        XCTAssertLessThan(firstLevel2Index, firstLevel1Index, "Level 2 cards should come before level 1 cards after swap")

        // Verify firstCardLevel was updated
        XCTAssertEqual(testPersistor.firstCardLevel, .level2, "firstCardLevel should be updated when swap occurs")
    }

    func testWhenLevelOrderSwaps_WithAdvancedOrderingEnabled_ThenOrderIsPersisted() {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.firstCardLevel = .level1
        testPersistor.orderedCardIDs = nil
        let testAppearancePrefs = createAppearancePrefs(demonstrationDays: 3)
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            appearancePreferences: testAppearancePrefs,
            persistor: testPersistor,
            featureFlagger: testFeatureFlagger
        )

        _ = testProvider.cards

        let expectedCards: [NewTabPageDataModel.CardID] = [.defaultApp, .addAppToDockMac, .duckplayer, .bringStuff, .subscription, .personalizeBrowser, .sync, .emailProtection]

        XCTAssertEqual(testPersistor.orderedCardIDs, expectedCards, "Order should be persisted after swap")
    }

    func testWhenDefaultOrderIsUsed_WithAdvancedOrderingEnabled_ThenOrderIsPersisted() {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.orderedCardIDs = nil
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            persistor: testPersistor,
            featureFlagger: testFeatureFlagger
        )

        _ = testProvider.cards

        let expectedCards = NewTabPageNextStepsSingleCardProvider.defaultAdvancedCards

        XCTAssertEqual(testPersistor.orderedCardIDs, expectedCards, "Default order should be persisted on first use")
    }

    @MainActor
    func testWhenCardShownMaxTimes_WithAdvancedOrderingEnabled_ThenCardMovesToBack() throws {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.setTimesShown(10, for: .personalizeBrowser)
        testPersistor.orderedCardIDs = [.personalizeBrowser, .sync, .emailProtection]
        let testProvider = createProvider(persistor: testPersistor, featureFlagger: testFeatureFlagger)

        let cards = testProvider.cards

        XCTAssertEqual(cards.last, .personalizeBrowser, "Card should move to back of list")
        XCTAssertEqual(cards.first, .sync, "Next card should be first")
    }

    @MainActor
    func testWhenCardShownMaxTimes_WithAdvancedOrderingEnabled_ThenTimesShownResets() {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.setTimesShown(10, for: .personalizeBrowser)
        testPersistor.orderedCardIDs = [.personalizeBrowser, .sync, .emailProtection]
        let testProvider = createProvider(persistor: testPersistor, featureFlagger: testFeatureFlagger)

        _ = testProvider.cards

        XCTAssertEqual(testPersistor.timesShown(for: .personalizeBrowser), 0, "Times shown should reset to 0")
    }

    // MARK: - Card Ordering Tests (nextStepsListAdvancedCardOrdering disabled)

    @MainActor
    func testFirstSession_WhenAdvancedOrderingDisabled_ThenDuckplayerIsFirst() {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = []

        let testProvider = createProvider(
            featureFlagger: testFeatureFlagger,
            isFirstSession: true
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.isEmpty, "Should have cards")
        XCTAssertEqual(cards.first, .duckplayer, "Duckplayer should be first in first session")
    }

    @MainActor
    func testSubsequentSession_WhenAdvancedOrderingDisabled_ThenDefaultAppIsFirst() {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = []

        let testProvider = createProvider(
            featureFlagger: testFeatureFlagger,
            isFirstSession: false
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.isEmpty, "Should have cards")
        XCTAssertEqual(cards.first, .defaultApp, "DefaultApp should be first in subsequent sessions")
    }

    func testFirstSession_WhenNewHomePageTabOpens_ThenCardsAreNotShuffled_AndIsFirstSessionIsSet() {
        featureFlagger.enabledFeatureFlags = []
        let testProvider = createProvider(isFirstSession: true)
        let initialCards = testProvider.standardCards
        let expectation = XCTestExpectation(description: "New tab page open notification is published")
        let cancellable = NotificationCenter.default.publisher(for: HomePage.Models.newHomePageTabOpen)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                expectation.fulfill()
            }

        NotificationCenter.default.post(name: HomePage.Models.newHomePageTabOpen, object: nil)
        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertFalse(persistor.isFirstSession)
        XCTAssertEqual(testProvider.standardCards, initialCards, "Standard cards should remain the same when new tab page open notification is received in the first session")
    }

    func testSubsequentSession_WhenNewHomePageTabOpens_ThenCardsAreShuffled() {
        featureFlagger.enabledFeatureFlags = []
        let testProvider = createProvider(isFirstSession: false)
        let initialCards = testProvider.standardCards
        let expectation = XCTestExpectation(description: "New tab page open notification is published")
        let cancellable = NotificationCenter.default.publisher(for: HomePage.Models.newHomePageTabOpen)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                expectation.fulfill()
            }

        NotificationCenter.default.post(name: HomePage.Models.newHomePageTabOpen, object: nil)
        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertFalse(persistor.isFirstSession)
        XCTAssertNotEqual(testProvider.standardCards, initialCards, "Standard cards should be shuffled when new tab page open notification is received in subsequent sessions")
    }

    func testSubsequentSession_WhenWindowBecomesKey_ThenCardOrderRemainsStable() {
        featureFlagger.enabledFeatureFlags = []
        let testProvider = createProvider(isFirstSession: false)
        let initialCards = testProvider.standardCards
        let expectation = XCTestExpectation(description: "Window becomes key notification is published")
        let cancellable = NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                expectation.fulfill()
            }

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(testProvider.standardCards, initialCards, "Standard card order should remain the same when window becomes key")
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
        syncConnected: Bool? = nil,
        appearancePreferences: AppearancePreferences? = nil,
        persistor: MockNewTabPageNextStepsCardsPersistor? = nil,
        legacyPersistor: MockHomePageContinueSetUpModelPersisting? = nil,
        legacySubscriptionCardPersistor: MockHomePageSubscriptionCardPersisting? = nil,
        featureFlagger: MockFeatureFlagger? = nil,
        isFirstSession: Bool? = nil
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

        let testSyncService: MockDDGSyncing = {
            if let syncConnected {
                let authState: SyncAuthState = syncConnected ? .active : .inactive
                return MockDDGSyncing(authState: authState, isSyncInProgress: false)
            }
            return syncService!
        }()

        let testAppearancePreferences = appearancePreferences ?? self.appearancePreferences!
        let testPersistor = persistor ?? self.persistor!
        let testLegacyPersistor = legacyPersistor ?? self.legacyPersistor!
        let testLegacySubscriptionCardPersistor = legacySubscriptionCardPersistor ?? self.legacySubscriptionCardPersistor!
        let testFeatureFlagger = featureFlagger ?? self.featureFlagger!

        if let isFirstSession = isFirstSession {
            testPersistor.isFirstSession = isFirstSession
        }

        return NewTabPageNextStepsSingleCardProvider(
            cardActionHandler: actionHandler,
            pixelHandler: pixelHandler,
            persistor: testPersistor,
            legacyPersistor: testLegacyPersistor,
            legacySubscriptionCardPersistor: testLegacySubscriptionCardPersistor,
            appearancePreferences: testAppearancePreferences,
            featureFlagger: testFeatureFlagger,
            defaultBrowserProvider: testDefaultBrowserProvider,
            dockCustomizer: testDockCustomizer,
            dataImportProvider: testDataImportProvider,
            emailManager: testEmailManager,
            duckPlayerPreferences: testDuckPlayerPreferences,
            subscriptionCardVisibilityManager: testSubscriptionCardVisibilityManager,
            syncService: testSyncService
        )
    }

    private func createAppearancePrefs(didChangeAnyCustomizationSetting: Bool = false,
                                       demonstrationDays: Int = 0) -> AppearancePreferences {
        let persistor = MockAppearancePreferencesPersistor(
            continueSetUpCardsNumberOfDaysDemonstrated: demonstrationDays,
            didChangeAnyNewTabPageCustomizationSetting: didChangeAnyCustomizationSetting
        )
        return AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )
    }
}

extension NewTabPageNextStepsSingleCardProvider {
    static let defaultStandardCards: [NewTabPageDataModel.CardID] = [.duckplayer, .emailProtection, .defaultApp, .addAppToDockMac, .bringStuff, .subscription, .personalizeBrowser, .sync]

    static let defaultAdvancedCards: [NewTabPageDataModel.CardID] = [.personalizeBrowser, .sync, .emailProtection, .defaultApp, .addAppToDockMac, .duckplayer, .bringStuff, .subscription]
}

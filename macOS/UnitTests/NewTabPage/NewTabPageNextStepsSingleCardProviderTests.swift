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

import AppKitExtensions

import BrowserServicesKit
import Combine
import DDGSync
import FeatureFlags_macOS
import NewTabPage
@_spi(Testing) import Persistence
import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
import SubscriptionTestingUtilities
import WebExtensions
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

        appearancePreferences = createAppearancePrefs(
            demonstrationDays: 1,
            lastDemonstrated: Date()
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

    // MARK: - Cards Property Tests

    func testWhenCardsViewIsNotOutdatedThenCardsAreReturned() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider(defaultBrowserIsDefault: false)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(cards.contains(.defaultApp))
    }

    func testWhenCardsViewIsOutdatedThenCardsAreEmpty() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = true
        let testProvider = createProvider(defaultBrowserIsDefault: false)
        triggerNewTabPageView(on: testProvider)

        XCTAssertTrue(testProvider.cards.isEmpty)
    }

    func testWhenCardsViewBecomesOutdatedThenCardsBecomeEmpty() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider(defaultBrowserIsDefault: false)
        triggerNewTabPageView(on: testProvider)

        let initialCards = testProvider.cards
        XCTAssertFalse(initialCards.isEmpty)

        appearancePreferences.isContinueSetUpCardsViewOutdated = true

        XCTAssertTrue(testProvider.cards.isEmpty)
    }

    func testWhenNextStepsPreviouslyClosedThenCardsAreEmpty() {
        appearancePreferences.continueSetUpCardsClosed = true
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider(defaultBrowserIsDefault: false)
        triggerNewTabPageView(on: testProvider)

        XCTAssertTrue(testProvider.cards.isEmpty)
    }

    // MARK: - Cards Publisher Tests

    @MainActor
    func testWhenCardListChangesThenPublisherEmitsNewCards() {
        let testProvider = createProvider()
        triggerNewTabPageView(on: testProvider)
        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let cancellable = testProvider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        // Trigger card list refreshes by dismissing visible cards
        testProvider.dismiss(.defaultApp)
        testProvider.dismiss(.emailProtection)
        testProvider.dismiss(.personalizeBrowser)

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
    func testWhenNextStepsPreviouslyClosedThenPublisherEmitsEmptyArray() {
        appearancePreferences.continueSetUpCardsClosed = true
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider()

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let expectation = XCTestExpectation(description: "Cards publisher emits card list")
        let cancellable = testProvider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
                expectation.fulfill()
            }

        // Trigger card list refresh
        NotificationCenter.default.post(name: .newTabPageWebViewDidAppear, object: nil)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(cardsEvents.last, [])
    }

    @MainActor
    func testWhenCardsViewBecomesOutdatedThenPublisherStopsEmittingCards() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider()
        triggerNewTabPageView(on: testProvider)

        var cardsEvents = [[NewTabPageDataModel.CardID]]()
        let cancellable = testProvider.cardsPublisher
            .sink { cards in
                cardsEvents.append(cards)
            }

        // Trigger card list refreshes by dismissing cards
        testProvider.dismiss(.defaultApp)
        testProvider.dismiss(.bringStuff)
        appearancePreferences.isContinueSetUpCardsViewOutdated = true
        testProvider.dismiss(.emailProtection)

        cancellable.cancel()

        XCTAssertEqual(cardsEvents.last, [])
    }

    func testWhenSubscriptionVisibilityChangesThenCardListRefreshes() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        subscriptionCardVisibilityManager.shouldShowSubscriptionCard = true
        persistor.orderedCardIDs = [.subscription]
        let testProvider = createProvider()
        triggerNewTabPageView(on: testProvider)
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

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: NSWindow())

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertFalse(cardsEvents.isEmpty)
    }

    @MainActor
    func testWhenNewTabPageWebViewAppearsThenTimesShownIsIncrementedForFirstCard() {
        // GIVEN
        let firstCard = NewTabPageNextStepsSingleCardProvider.defaultAdvancedCards[0]
        let secondCard = NewTabPageNextStepsSingleCardProvider.defaultAdvancedCards[1]
        persistor.setTimesShown(0, for: firstCard)
        persistor.setTimesShown(0, for: secondCard)
        let testProvider = createProvider()

        // WHEN
        triggerNewTabPageView(on: testProvider)

        // THEN
        XCTAssertEqual(persistor.timesShown(for: firstCard), 1)
        // Second card should not be incremented
        XCTAssertEqual(persistor.timesShown(for: secondCard), 0)
    }

    @MainActor
    func testWhenNewTabPageWebViewAppearsThenNtpImpressionCountIsIncremented() {
        // GIVEN
        persistor.ntpImpressionCount = 0
        let testProvider = createProvider()

        // WHEN
        triggerNewTabPageView(on: testProvider)

        // THEN
        XCTAssertEqual(persistor.ntpImpressionCount, 1)
    }

    @MainActor
    func testWhenNewTabPageWebViewAppearsThenNtpImpressionCountIsNotIncrementedIfNextStepsCardsComplete() {
        // GIVEN
        persistor.ntpImpressionCount = 0
        appearancePreferences.isContinueSetUpCardsViewOutdated = true
        let testProvider = createProvider()

        // WHEN
        triggerNewTabPageView(on: testProvider)

        // THEN
        XCTAssertEqual(persistor.ntpImpressionCount, 0)
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
        persistor.orderedCardIDs = [.defaultApp]
        let testProvider = createProvider(defaultBrowserIsDefault: false)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.defaultApp))
    }

    func testWhenDefaultBrowserIsDefaultThenDefaultAppCardIsNotVisible() {
        persistor.orderedCardIDs = [.defaultApp]
        let testProvider = createProvider(defaultBrowserIsDefault: true)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.defaultApp))
    }

    // Bring Stuff Card
    func testWhenDataImportDidNotImportThenBringStuffCardIsVisible() {
        persistor.orderedCardIDs = [.bringStuff]
        let testProvider = createProvider(dataImportDidImport: false)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.bringStuff))
    }

    func testWhenDataImportDidImportThenBringStuffCardIsNotVisible() {
        persistor.orderedCardIDs = [.bringStuff]
        let testProvider = createProvider(dataImportDidImport: true)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.bringStuff))
    }

    // Add App to Dock Card
    func testWhenAppNotAddedToDockAndNotAppStoreThenAddAppToDockCardIsVisible() {
        persistor.orderedCardIDs = [.addAppToDockMac]
        let testProvider = createProvider(dockStatus: false, isAppStoreBuild: false)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.addAppToDockMac))
    }

    func testWhenAppNotAddedToDockAndAppStoreThenAddAppToDockCardIsNotVisible() {
        persistor.orderedCardIDs = [.addAppToDockMac]
        let testProvider = createProvider(dockStatus: false, isAppStoreBuild: true)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.addAppToDockMac))
    }

    func testWhenAppAddedToDockThenAddAppToDockCardIsNotVisible() {
        persistor.orderedCardIDs = [.addAppToDockMac]
        let testProvider = createProvider(dockStatus: true)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.addAppToDockMac))
    }

    // Email Protection Card
    func testWhenEmailManagerNotSignedInThenEmailProtectionCardIsVisible() {
        persistor.orderedCardIDs = [.emailProtection]
        let testProvider = createProvider(emailManagerSignedIn: false)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.emailProtection))
    }

    func testWhenEmailManagerSignedInThenEmailProtectionCardIsNotVisible() {
        persistor.orderedCardIDs = [.emailProtection]
        let testProvider = createProvider(emailManagerSignedIn: true)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.emailProtection))
    }

    // Subscription Card
    func testWhenSubscriptionCardShouldShowThenSubscriptionCardIsVisible() {
        persistor.orderedCardIDs = [.subscription]
        let testProvider = createProvider(subscriptionCardShouldShow: true)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.subscription))
    }

    func testWhenSubscriptionCardShouldNotShowThenSubscriptionCardIsNotVisible() {
        persistor.orderedCardIDs = [.subscription]
        let testProvider = createProvider(subscriptionCardShouldShow: false)
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.subscription))
    }

    // Personalize Browser Card
    func testWhenCustomizationNotChangedThenPersonalizeBrowserCardIsVisible() {
        let testAppearancePreferences = createAppearancePrefs(didChangeAnyCustomizationSetting: false)
        persistor.orderedCardIDs = [.personalizeBrowser]
        let testProvider = createProvider(appearancePreferences: testAppearancePreferences)
        triggerNewTabPageView(on: testProvider)

        XCTAssertTrue(testProvider.cards.contains(.personalizeBrowser))
    }

    func testWhenCustomizationChangedThenPersonalizeBrowserCardIsNotVisible() {
        let testAppearancePreferences = createAppearancePrefs(didChangeAnyCustomizationSetting: true)
        persistor.orderedCardIDs = [.personalizeBrowser]
        let testProvider = createProvider(appearancePreferences: testAppearancePreferences)
        triggerNewTabPageView(on: testProvider)

        XCTAssertFalse(testProvider.cards.contains(.personalizeBrowser))
    }

    // Sync Card
    func testWhenSyncCardShouldShowThenSyncCardIsVisible() {
        persistor.orderedCardIDs = [.sync]
        let testProvider = createProvider(syncConnected: false)
        triggerNewTabPageView(on: testProvider)

        XCTAssertTrue(testProvider.cards.contains(.sync))
    }

    func testWhenSyncCardShouldNotShowThenSyncCardIsNotVisible() {
        persistor.orderedCardIDs = [.sync]
        let testProvider = createProvider(syncConnected: true)
        triggerNewTabPageView(on: testProvider)

        XCTAssertFalse(testProvider.cards.contains(.sync))
    }

    // MARK: - Permanent Dismissal Tests

    func testWhenCardDismissedMaxTimesThenCardIsPermanentlyDismissed() {
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.setTimesDismissed(1, for: .defaultApp) // maxTimesCardDismissed = 1
        testPersistor.orderedCardIDs = [.defaultApp]
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            persistor: testPersistor
        )
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.defaultApp))
    }

    func testWhenCardDismissedViaLegacySettingThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowMakeDefaultSetting = false
        persistor.orderedCardIDs = [.defaultApp]
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            legacyPersistor: testLegacyPersistor
        )
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.defaultApp))
    }

    func testWhenCardDismissedLessThanMaxTimesThenCardIsNotPermanentlyDismissed() {
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        testPersistor.setTimesDismissed(0, for: .defaultApp) // Less than max
        testPersistor.orderedCardIDs = [.defaultApp]
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            persistor: testPersistor
        )
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.defaultApp))
    }

    func testWhenDefaultAppCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowMakeDefaultSetting = false
        persistor.orderedCardIDs = [.defaultApp]
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            legacyPersistor: testLegacyPersistor
        )
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.defaultApp))
    }

    func testWhenAddAppToDockCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowAddToDockSetting = false
        persistor.orderedCardIDs = [.addAppToDockMac]
        let testProvider = createProvider(
            dockStatus: false,
            legacyPersistor: testLegacyPersistor,
            isAppStoreBuild: false
        )
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.addAppToDockMac))
    }

    func testWhenEmailProtectionCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowEmailProtectionSetting = false
        persistor.orderedCardIDs = [.emailProtection]
        let testProvider = createProvider(
            emailManagerSignedIn: false,
            legacyPersistor: testLegacyPersistor
        )
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.emailProtection))
    }

    func testWhenBringStuffCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowImportSetting = false
        persistor.orderedCardIDs = [.bringStuff]
        let testProvider = createProvider(
            dataImportDidImport: false,
            legacyPersistor: testLegacyPersistor
        )
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.bringStuff))
    }

    func testWhenSubscriptionCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacySubscriptionCardPersistor = MockHomePageSubscriptionCardPersisting()
        testLegacySubscriptionCardPersistor.shouldShowSubscriptionSetting = false
        persistor.orderedCardIDs = [.subscription]
        let testProvider = createProvider(
            subscriptionCardShouldShow: true,
            legacySubscriptionCardPersistor: testLegacySubscriptionCardPersistor
        )
        triggerNewTabPageView(on: testProvider)

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
    func testWhenWillDisplayCardsIsCalledWithSubscriptionFirstThenSubscriptionShownPixelIsFired() {
        let testProvider = createProvider()
        let cards: [NewTabPageDataModel.CardID] = [.subscription, .emailProtection, .bringStuff]

        testProvider.willDisplayCards(cards)

        XCTAssertEqual(pixelHandler.fireNextStepsCardShownPixelsCalledWith, [.subscription])
        XCTAssertTrue(pixelHandler.fireSubscriptionCardShownPixelCalled)
    }

    @MainActor
    func testWhenWillDisplayCardsIsCalledWithSubscriptionNotFirstThenSubscriptionShownPixelIsNotFired() {
        let testProvider = createProvider()
        let cards: [NewTabPageDataModel.CardID] = [.emailProtection, .subscription, .bringStuff]

        testProvider.willDisplayCards(cards)

        XCTAssertFalse(pixelHandler.fireSubscriptionCardShownPixelCalled)
    }

    // MARK: - Edge Cases

    func testWhenAllCardsArePermanentlyDismissedThenCardsListIsEmpty() {
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testPersistor = MockNewTabPageNextStepsCardsPersistor()
        for card in NewTabPageDataModel.CardID.allCases {
            testPersistor.setTimesDismissed(NewTabPageNextStepsSingleCardProvider.Constants.maxTimesCardDismissed, for: card)
        }

        let testProvider = createProvider(persistor: testPersistor)
        triggerNewTabPageView(on: testProvider)

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
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertTrue(cards.isEmpty)
    }

    // MARK: - 3-Card Stack Tests

    func testWhenInitializedThenCardsAreEmptyUntilNTPAppears() {
        let testProvider = createProvider(
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true),
            isAppStoreBuild: false
        )

        XCTAssertTrue(testProvider.cards.isEmpty)

        triggerNewTabPageView(on: testProvider)

        XCTAssertEqual(testProvider.cards, [.personalizeBrowser, .emailProtection, .defaultApp])
        XCTAssertEqual(persistor.dailyVisibleStack, [.personalizeBrowser, .emailProtection, .defaultApp])
        XCTAssertEqual(persistor.visibleStackDayIdentifier, 1)
    }

    @MainActor
    func testThenDismissPrunesWithoutRefill() {
        persistor.orderedCardIDs = nil
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            isAppStoreBuild: false
        )
        triggerNewTabPageView(on: testProvider)

        XCTAssertEqual(testProvider.cards, [.personalizeBrowser, .emailProtection, .defaultApp])

        testProvider.dismiss(.personalizeBrowser)

        XCTAssertEqual(testProvider.cards, [.emailProtection, .defaultApp])
        XCTAssertEqual(persistor.dailyVisibleStack, [.emailProtection, .defaultApp])
    }

    @MainActor
    func testThenTopCardRotatesToBackOfFullListAndPullsNextCard() {
        persistor.orderedCardIDs = [.personalizeBrowser, .sync, .emailProtection, .defaultApp, .addAppToDockMac]
        persistor.setTimesShown(NewTabPageNextStepsSingleCardProvider.Constants.maxTimesCardShown, for: .personalizeBrowser)
        let testProvider = createProvider(defaultBrowserIsDefault: false, isAppStoreBuild: false)

        triggerNewTabPageView(on: testProvider)

        XCTAssertEqual(testProvider.cards, [.sync, .emailProtection, .defaultApp])
        XCTAssertEqual(persistor.orderedCardIDs, [.sync, .emailProtection, .defaultApp, .addAppToDockMac, .personalizeBrowser])
        XCTAssertEqual(persistor.dailyVisibleStack, [.sync, .emailProtection, .defaultApp])
    }

    @MainActor
    func testThenTwoCardStackRotationPullsFromBacklog() {
        persistor.orderedCardIDs = [.sync, .emailProtection, .personalizeBrowser, .defaultApp]
        persistor.dailyVisibleStack = [.sync, .emailProtection]
        persistor.visibleStackDayIdentifier = 1
        persistor.setTimesDismissed(1, for: .personalizeBrowser)
        persistor.setTimesShown(NewTabPageNextStepsSingleCardProvider.Constants.maxTimesCardShown, for: .sync)
        let testProvider = createProvider(defaultBrowserIsDefault: false)

        triggerNewTabPageView(on: testProvider)

        XCTAssertEqual(testProvider.cards, [.emailProtection, .defaultApp])
        XCTAssertEqual(persistor.orderedCardIDs, [.emailProtection, .defaultApp, .personalizeBrowser, .sync])
    }

    @MainActor
    func testThenSameDayNTPRevisitDoesNotRefillDismissedSlots() {
        persistor.orderedCardIDs = nil
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true),
            isAppStoreBuild: false
        )
        triggerNewTabPageView(on: testProvider)
        testProvider.dismiss(.personalizeBrowser)

        XCTAssertEqual(testProvider.cards, [.emailProtection, .defaultApp])

        triggerNewTabPageView(on: testProvider)

        XCTAssertEqual(testProvider.cards, [.emailProtection, .defaultApp])
    }

    @MainActor
    func testThenNewActiveUsageDayRefillsToThreeCards() {
        persistor.orderedCardIDs = nil
        persistor.firstCardLevel = .level2
        let mockAppearancePersistor = MockAppearancePreferencesPersistor(
            continueSetUpCardsLastDemonstrated: Date(),
            continueSetUpCardsNumberOfDaysDemonstrated: 2
        )
        let testAppearancePreferences = AppearancePreferences(
            persistor: mockAppearancePersistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            dateTimeProvider: { Date() },
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            appearancePreferences: testAppearancePreferences,
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true),
            isAppStoreBuild: false
        )
        triggerNewTabPageView(on: testProvider)
        testProvider.dismiss(.personalizeBrowser)

        XCTAssertEqual(testProvider.cards, [.emailProtection, .defaultApp])

        mockAppearancePersistor.continueSetUpCardsNumberOfDaysDemonstrated = 3
        triggerNewTabPageView(on: testProvider)

        XCTAssertEqual(testProvider.cards, [.emailProtection, .defaultApp, .youtubeAdBlocking])
        XCTAssertEqual(persistor.visibleStackDayIdentifier, 3)
    }

    @MainActor
    func testWhenStackClearedThenSectionStaysOpenUntilCardsExhausted() {
        persistor.orderedCardIDs = nil
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            isAppStoreBuild: false
        )
        triggerNewTabPageView(on: testProvider)
        testProvider.dismiss(.personalizeBrowser)
        testProvider.dismiss(.emailProtection)
        testProvider.dismiss(.defaultApp)

        XCTAssertTrue(testProvider.cards.isEmpty)
        XCTAssertFalse(appearancePreferences.continueSetUpCardsClosed)
    }

    func testWhenAllCardsIneligibleThenSectionCloses() {
        let testAppearancePreferences = createAppearancePrefs(didChangeAnyCustomizationSetting: true)
        let testProvider = createProvider(
            defaultBrowserIsDefault: true,
            dataImportDidImport: true,
            dockStatus: true,
            emailManagerSignedIn: true,
            subscriptionCardShouldShow: false,
            syncConnected: true,
            appearancePreferences: testAppearancePreferences,
            isAppStoreBuild: true
        )
        triggerNewTabPageView(on: testProvider)

        XCTAssertTrue(testProvider.cards.isEmpty)
        XCTAssertTrue(testAppearancePreferences.continueSetUpCardsClosed)
    }

    // MARK: - Card Ordering Tests

    func testWhenNoPersistedOrder_ThenDefaultOrderIsUsed_ForNonAppStore() {
        persistor.orderedCardIDs = nil
        let testProvider = createProvider(
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true),
            isAppStoreBuild: false
        )
        triggerNewTabPageView(on: testProvider)
        let expectedCards: [NewTabPageDataModel.CardID] = [.personalizeBrowser, .emailProtection, .defaultApp]

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenNoPersistedOrder_ThenDefaultOrderIsUsed_ForAppStore() {
        persistor.orderedCardIDs = nil
        let testProvider = createProvider(
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true),
            isAppStoreBuild: true
        )
        triggerNewTabPageView(on: testProvider)
        let expectedCards: [NewTabPageDataModel.CardID] = [.personalizeBrowser, .emailProtection, .defaultApp]

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenPersistedOrderExists_ThenPersistedOrderIsUsed_ForNonAppStore() {
        let persistedOrder: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .addAppToDockMac, .bringStuff, .subscription, .personalizeBrowser, .sync]
        persistor.orderedCardIDs = persistedOrder
        let testProvider = createProvider(isAppStoreBuild: false)
        triggerNewTabPageView(on: testProvider)
        let expectedCards: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .addAppToDockMac]

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenPersistedOrderExists_ThenPersistedOrderIsUsed_ForAppStore() {
        let persistedOrder: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .addAppToDockMac, .bringStuff, .subscription, .personalizeBrowser, .sync]
        persistor.orderedCardIDs = persistedOrder
        let testProvider = createProvider(isAppStoreBuild: true)
        triggerNewTabPageView(on: testProvider)
        let expectedCards: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .bringStuff]

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenFirstCardLevelIsLevel1AndDaysLessThanMaxDays_ThenLevel1CardsFirst() throws {
        persistor.firstCardLevel = .level1
        let testAppearancePrefs = createAppearancePrefs(demonstrationDays: 1)
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            appearancePreferences: testAppearancePrefs
        )
        triggerNewTabPageView(on: testProvider)

        let cards = testProvider.cards
        XCTAssertEqual(cards, [.personalizeBrowser, .emailProtection, .defaultApp])
    }

    func testWhenFirstCardLevelIsLevel1AndDaysGreaterThanOrEqualToMaxDays_ThenLevel2CardsFirst() throws {
        persistor.firstCardLevel = .level1
        let testAppearancePrefs = createAppearancePrefs(demonstrationDays: 2)
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            appearancePreferences: testAppearancePrefs,
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true),
            isAppStoreBuild: false
        )
        triggerNewTabPageView(on: testProvider)

        XCTAssertEqual(testProvider.cards, [.defaultApp, .youtubeAdBlocking, .addAppToDockMac])
        XCTAssertEqual(persistor.dailyVisibleStack, [.defaultApp, .youtubeAdBlocking, .addAppToDockMac])
        XCTAssertEqual(persistor.firstCardLevel, .level2)
    }

    func testWhenLevelOrderSwaps_ThenOrderIsPersisted() {
        persistor.firstCardLevel = .level1
        let testAppearancePrefs = createAppearancePrefs(demonstrationDays: 3)
        let testProvider = createProvider(
            defaultBrowserIsDefault: false,
            appearancePreferences: testAppearancePrefs,
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true)
        )

        triggerNewTabPageView(on: testProvider)

        let expectedCards: [NewTabPageDataModel.CardID] = [.defaultApp, .youtubeAdBlocking, .addAppToDockMac, .bringStuff, .subscription, .personalizeBrowser, .emailProtection, .sync]

        XCTAssertEqual(persistor.orderedCardIDs, expectedCards, "Order should be persisted after swap")
        XCTAssertEqual(testProvider.cards, [.defaultApp, .youtubeAdBlocking, .addAppToDockMac])
    }

    func testWhenDefaultOrderIsUsed_ThenOrderIsPersisted() {
        let testProvider = createProvider(defaultBrowserIsDefault: false)

        triggerNewTabPageView(on: testProvider)

        let expectedCards = NewTabPageNextStepsSingleCardProvider.defaultAdvancedCards

        XCTAssertEqual(persistor.orderedCardIDs, expectedCards, "Default order should be persisted on first use")
    }

    @MainActor
    func testWhenCardsAreRefreshedWithNewFirstCardThenTimesShownIsIncrementedForFirstCard() {
        persistor.orderedCardIDs = [.personalizeBrowser, .sync, .emailProtection]
        let testProvider = createProvider()
        triggerNewTabPageView(on: testProvider)

        var cardList = [NewTabPageDataModel.CardID]()
        let cancellable = testProvider.cardsPublisher
            .sink { cards in
                cardList = cards
            }

        testProvider.dismiss(.personalizeBrowser)

        cancellable.cancel()

        XCTAssertEqual(cardList.first, .sync, "Next card should be first after dismissing the first card")
        XCTAssertEqual(persistor.timesShown(for: .sync), 1)
    }

    // MARK: - YouTube Ad Blocking visibility

    func testWhenYTAdBlockingFeatureUnavailableThenYTAdBlockingCardIsNotVisible() {
        persistor.orderedCardIDs = [.youtubeAdBlocking]
        let testProvider = createProvider(adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: false, isEnabledByUser: true))
        triggerNewTabPageView(on: testProvider)

        XCTAssertFalse(testProvider.cards.contains(.youtubeAdBlocking))
    }

    func testWhenYTAdBlockingUserNotOptedInThenYTAdBlockingCardIsNotVisible() {
        persistor.orderedCardIDs = [.youtubeAdBlocking]
        let testProvider = createProvider(adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: false))
        triggerNewTabPageView(on: testProvider)

        XCTAssertFalse(testProvider.cards.contains(.youtubeAdBlocking))
    }

    func testWhenYTAdBlockingFullyEnabledThenYTAdBlockingCardIsVisible() {
        persistor.orderedCardIDs = [.youtubeAdBlocking]
        let testProvider = createProvider(adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true))
        triggerNewTabPageView(on: testProvider)

        XCTAssertTrue(testProvider.cards.contains(.youtubeAdBlocking))
    }

    // MARK: - YouTube Ad Blocking permanent dismissal

    func testWhenYouTubeAdBlockingCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowYouTubeAdBlockingSetting = false
        persistor.orderedCardIDs = [.youtubeAdBlocking]
        let testProvider = createProvider(
            legacyPersistor: testLegacyPersistor,
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true)
        )
        triggerNewTabPageView(on: testProvider)

        XCTAssertFalse(testProvider.cards.contains(.youtubeAdBlocking))
    }

    // MARK: - Helper Functions

    @MainActor
    func testSkippedNonBlockingPrioritizesDefaultAndDock() {
        let wasFinished = OnboardingActionsManager.isOnboardingFinished
        defer { OnboardingActionsManager.isOnboardingFinished = wasFinished }
        OnboardingActionsManager.isOnboardingFinished = true
        let flags = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)
        var skipped = false
        let provider = createProvider(defaultBrowserIsDefault: false, dockStatus: false,
                                      featureFlagger: flags, isAppStoreBuild: false,
                                      didSkipOnboarding: { skipped })
        skipped = true
        NotificationCenter.default.post(name: NonBlockingOnboardingPersistor.outcomeDidChange, object: nil)

        triggerNewTabPageView(on: provider)
        XCTAssertEqual(Array(provider.cards.prefix(2)), [.defaultApp, .addAppToDockMac])
        provider.dismiss(.defaultApp)
        XCTAssertFalse(provider.cards.contains(.defaultApp))
        XCTAssertEqual(provider.cards.first, .addAppToDockMac)
    }

    @MainActor
    func testUnfinishedNonBlockingPrioritizesEligibleDefaultAndDock() {
        let wasFinished = OnboardingActionsManager.isOnboardingFinished
        defer { OnboardingActionsManager.isOnboardingFinished = wasFinished }
        OnboardingActionsManager.isOnboardingFinished = false

        let flags = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)
        let provider = createProvider(defaultBrowserIsDefault: false, dockStatus: false,
                                      featureFlagger: flags, isAppStoreBuild: false)
        triggerNewTabPageView(on: provider)
        XCTAssertEqual(Array(provider.cards.prefix(2)), [.defaultApp, .addAppToDockMac])

        provider.dismiss(.defaultApp)
        XCTAssertFalse(provider.cards.contains(.defaultApp))
        XCTAssertEqual(provider.cards.first, .addAppToDockMac)
        provider.dismiss(.addAppToDockMac)
        XCTAssertFalse(provider.cards.contains(.addAppToDockMac))
    }

    @MainActor
    func testNonBlockingSetupCardsRotateWithoutBeingPromotedAgain() {
        let wasFinished = OnboardingActionsManager.isOnboardingFinished
        defer { OnboardingActionsManager.isOnboardingFinished = wasFinished }
        OnboardingActionsManager.isOnboardingFinished = false
        let flags = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)
        let provider = createProvider(defaultBrowserIsDefault: false, dockStatus: false,
                                      featureFlagger: flags, isAppStoreBuild: false)
        triggerNewTabPageView(on: provider)
        let initialStack = provider.cards
        persistor.setTimesShown(5, for: .defaultApp)

        NotificationCenter.default.post(name: NonBlockingOnboardingPersistor.outcomeDidChange, object: nil)
        XCTAssertEqual(provider.cards, initialStack, "Outcome changes must not rotate the visible stack")
        triggerNewTabPageView(on: provider)
        XCTAssertEqual(provider.cards.first, .addAppToDockMac)
        XCTAssertEqual(persistor.orderedCardIDs?.last, .defaultApp)
        XCTAssertEqual(provider.cards.count, 3)

        persistor.setTimesShown(5, for: .addAppToDockMac)
        triggerNewTabPageView(on: provider)
        XCTAssertFalse(provider.cards.contains(.defaultApp))
        XCTAssertFalse(provider.cards.contains(.addAppToDockMac))
        XCTAssertEqual(persistor.orderedCardIDs?.last, .addAppToDockMac)
        XCTAssertEqual(persistor.dailyVisibleStack, provider.cards)
    }

    @MainActor
    func testLevelSwapPreservesOnlyUnexhaustedSetupPriority() {
        let wasFinished = OnboardingActionsManager.isOnboardingFinished
        defer { OnboardingActionsManager.isOnboardingFinished = wasFinished }
        OnboardingActionsManager.isOnboardingFinished = false
        appearancePreferences = createAppearancePrefs(demonstrationDays: 2, lastDemonstrated: Date())
        persistor.firstCardLevel = .level1
        persistor.visibleStackDayIdentifier = 1
        persistor.dailyVisibleStack = [.defaultApp, .personalizeBrowser, .emailProtection]
        persistor.setTimesShown(5, for: .defaultApp)
        let flags = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)
        let provider = createProvider(defaultBrowserIsDefault: false, dockStatus: false,
                                      featureFlagger: flags, isAppStoreBuild: false)
        triggerNewTabPageView(on: provider)

        XCTAssertEqual(persistor.firstCardLevel, .level2)
        XCTAssertEqual(provider.cards.first, .addAppToDockMac)
        XCTAssertEqual(provider.cards.count, 3)
        XCTAssertEqual(persistor.dailyVisibleStack, provider.cards)
    }

    @MainActor
    func testLateNonBlockingPriorityReconcilesSavedStackOnNextAppearance() {
        let wasFinished = OnboardingActionsManager.isOnboardingFinished
        defer { OnboardingActionsManager.isOnboardingFinished = wasFinished }
        OnboardingActionsManager.isOnboardingFinished = true
        let flags = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)
        var skipped = false
        let provider = createProvider(defaultBrowserIsDefault: false, dockStatus: false,
                                      featureFlagger: flags, isAppStoreBuild: false, didSkipOnboarding: { skipped })
        triggerNewTabPageView(on: provider)
        let savedStack = provider.cards

        skipped = true
        NotificationCenter.default.post(name: NonBlockingOnboardingPersistor.outcomeDidChange, object: nil)
        XCTAssertEqual(provider.cards, savedStack)
        triggerNewTabPageView(on: provider)
        XCTAssertEqual(Array(provider.cards.prefix(2)), [.defaultApp, .addAppToDockMac])
        XCTAssertEqual(provider.cards.count, 3)
        XCTAssertEqual(persistor.dailyVisibleStack, provider.cards)
        XCTAssertEqual(Array((persistor.orderedCardIDs ?? []).prefix(3)), provider.cards)
    }

    @MainActor
    func testUnfinishedNonBlockingDoesNotShowAlreadyCompletedSetupCards() {
        let wasFinished = OnboardingActionsManager.isOnboardingFinished
        defer { OnboardingActionsManager.isOnboardingFinished = wasFinished }
        OnboardingActionsManager.isOnboardingFinished = false
        let flags = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)
        let provider = createProvider(defaultBrowserIsDefault: true, dockStatus: true,
                                      featureFlagger: flags, isAppStoreBuild: false)
        triggerNewTabPageView(on: provider)
        XCTAssertFalse(provider.cards.contains(.defaultApp))
        XCTAssertFalse(provider.cards.contains(.addAppToDockMac))
    }

    @MainActor
    func testCompletedNonBlockingAndUnfinishedBlockingUseNormalPriority() {
        let wasFinished = OnboardingActionsManager.isOnboardingFinished
        defer { OnboardingActionsManager.isOnboardingFinished = wasFinished }
        for isNonBlocking in [false, true] {
            OnboardingActionsManager.isOnboardingFinished = isNonBlocking
            let flags = MockFeatureFlagger(resolveCohortStub: isNonBlocking ? FeatureFlag.OnboardingNonBlockingCohort.treatment : FeatureFlag.OnboardingNonBlockingCohort.control)
            let provider = createProvider(defaultBrowserIsDefault: false, dockStatus: false,
                                          featureFlagger: flags, isAppStoreBuild: false)
            triggerNewTabPageView(on: provider)
            XCTAssertNotEqual(Array(provider.cards.prefix(2)), [.defaultApp, .addAppToDockMac])
        }
    }

    @MainActor
    func testSkippedBlockingOnboardingDoesNotGetCardPriority() {
        let provider = createProvider(defaultBrowserIsDefault: false, dockStatus: false,
                                      isAppStoreBuild: false, didSkipOnboarding: { true })
        triggerNewTabPageView(on: provider)
        XCTAssertNotEqual(Array(provider.cards.prefix(2)), [.defaultApp, .addAppToDockMac])
    }

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
        adBlockingAvailability: MockAdBlockingAvailability? = nil,
        isAppStoreBuild: Bool? = nil,
        didSkipOnboarding: @escaping () -> Bool = { false }
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
        let testAdBlockingAvailability = adBlockingAvailability ?? MockAdBlockingAvailability()
        let testApplicationBuildType: MockApplicationBuildType = {
            let buildType = MockApplicationBuildType()
            if let isAppStoreBuild {
                buildType.isAppStoreBuild = isAppStoreBuild
            }
            return buildType
        }()

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
            syncService: testSyncService,
            adBlockingAvailability: testAdBlockingAvailability,
            applicationBuildType: testApplicationBuildType,
            scheduler: .immediate,
            didSkipOnboarding: didSkipOnboarding
        )
    }

    private func createAppearancePrefs(didChangeAnyCustomizationSetting: Bool = false,
                                       demonstrationDays: Int = 0,
                                       lastDemonstrated: Date? = nil,
                                       now: Date = Date()) -> AppearancePreferences {
        let persistor = MockAppearancePreferencesPersistor(
            continueSetUpCardsLastDemonstrated: lastDemonstrated,
            continueSetUpCardsNumberOfDaysDemonstrated: demonstrationDays,
            didChangeAnyNewTabPageCustomizationSetting: didChangeAnyCustomizationSetting
        )
        return AppearancePreferences(
            persistor: persistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            dateTimeProvider: { now },
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )
    }

    private func triggerNewTabPageView(on testProvider: NewTabPageNextStepsSingleCardProvider) {
        let expectation = XCTestExpectation(description: "Cards publisher emits card list")
        let cancellable = testProvider.cardsPublisher
            .sink { cards in
                expectation.fulfill()
            }

        NotificationCenter.default.post(name: .newTabPageWebViewDidAppear, object: nil)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
}

extension NewTabPageNextStepsSingleCardProvider {
    static let defaultAdvancedCards: [NewTabPageDataModel.CardID] = [.personalizeBrowser, .emailProtection, .defaultApp, .youtubeAdBlocking, .addAppToDockMac, .bringStuff, .sync, .subscription]
}

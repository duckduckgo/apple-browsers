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

    // MARK: - Initialization Tests

    func testWhenInitializedThenCardListIsRefreshed_ForNonAppStore() {
        featureFlagger.enabledFeatureFlags = []
        let testProvider = createProvider(isAppStoreBuild: false)
        let expectedCards = NewTabPageNextStepsSingleCardProvider.defaultStandardCards

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenInitializedThenCardListIsRefreshed_ForAppStore() {
        featureFlagger.enabledFeatureFlags = []
        let testProvider = createProvider(isAppStoreBuild: true)
        let expectedCards = NewTabPageNextStepsSingleCardProvider.defaultStandardCards.filter { $0 != .addAppToDockMac }

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

    func testWhenNextStepsPreviouslyClosedThenCardsAreEmpty() {
        appearancePreferences.continueSetUpCardsClosed = true
        appearancePreferences.isContinueSetUpCardsViewOutdated = false
        let testProvider = createProvider(defaultBrowserIsDefault: false)

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
        testProvider.dismiss(.bringStuff)
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

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: NSWindow())

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertFalse(cardsEvents.isEmpty)
    }

    @MainActor
    func testWhenNewTabPageWebViewAppearsThenTimesShownIsIncrementedForFirstCard() {
        // GIVEN
        let firstCard = NewTabPageNextStepsSingleCardProvider.defaultStandardCards[0]
        let secondCard = NewTabPageNextStepsSingleCardProvider.defaultStandardCards[1]
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
    func testWhenAppNotAddedToDockAndNotAppStoreThenAddAppToDockCardIsVisible() {
        let testProvider = createProvider(dockStatus: false, isAppStoreBuild: false)

        let cards = testProvider.cards
        XCTAssertTrue(cards.contains(.addAppToDockMac))
    }

    func testWhenAppNotAddedToDockAndAppStoreThenAddAppToDockCardIsNotVisible() {
        let testProvider = createProvider(dockStatus: false, isAppStoreBuild: true)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.addAppToDockMac))
    }

    func testWhenAppAddedToDockThenAddAppToDockCardIsNotVisible() {
        let testProvider = createProvider(dockStatus: true)

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.addAppToDockMac))
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
            legacyPersistor: testLegacyPersistor,
            isAppStoreBuild: false
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.contains(.addAppToDockMac))
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

    // MARK: - 3-Card Stack Tests (nextStepsListAdvancedCardOrdering enabled)

    func testWhenAdvancedOrderingEnabledThenCardsAreEmptyUntilNTPAppears() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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
    func testWhenAdvancedOrderingEnabledThenDismissPrunesWithoutRefill() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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
    func testWhenAdvancedOrderingEnabledThenTopCardRotatesToBackOfFullListAndPullsNextCard() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        persistor.orderedCardIDs = [.personalizeBrowser, .sync, .emailProtection, .defaultApp, .addAppToDockMac]
        persistor.setTimesShown(NewTabPageNextStepsSingleCardProvider.Constants.maxTimesCardShown, for: .personalizeBrowser)
        let testProvider = createProvider(defaultBrowserIsDefault: false, isAppStoreBuild: false)

        triggerNewTabPageView(on: testProvider)

        XCTAssertEqual(testProvider.cards, [.sync, .emailProtection, .defaultApp])
        XCTAssertEqual(persistor.orderedCardIDs, [.sync, .emailProtection, .defaultApp, .addAppToDockMac, .personalizeBrowser])
        XCTAssertEqual(persistor.dailyVisibleStack, [.sync, .emailProtection, .defaultApp])
    }

    @MainActor
    func testWhenAdvancedOrderingEnabledThenTwoCardStackRotationPullsFromBacklog() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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
    func testWhenAdvancedOrderingEnabledThenSameDayNTPRevisitDoesNotRefillDismissedSlots() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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
    func testWhenAdvancedOrderingEnabledThenNewActiveUsageDayRefillsToThreeCards() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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
    func testWhenAdvancedOrderingEnabledAndStackClearedThenSectionStaysOpenUntilCardsExhausted() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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

    func testWhenAdvancedOrderingEnabledAndAllCardsIneligibleThenSectionCloses() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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

    // MARK: - Card Ordering Tests (nextStepsListAdvancedCardOrdering enabled)

    func testWhenNoPersistedOrder_WithAdvancedOrderingEnabled_ThenDefaultOrderIsUsed_ForNonAppStore() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        persistor.orderedCardIDs = nil
        let testProvider = createProvider(
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true),
            isAppStoreBuild: false
        )
        triggerNewTabPageView(on: testProvider)
        let expectedCards: [NewTabPageDataModel.CardID] = [.personalizeBrowser, .emailProtection, .defaultApp]

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenNoPersistedOrder_WithAdvancedOrderingEnabled_ThenDefaultOrderIsUsed_ForAppStore() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        persistor.orderedCardIDs = nil
        let testProvider = createProvider(
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true),
            isAppStoreBuild: true
        )
        triggerNewTabPageView(on: testProvider)
        let expectedCards: [NewTabPageDataModel.CardID] = [.personalizeBrowser, .emailProtection, .defaultApp]

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenPersistedOrderExists_WithAdvancedOrderingEnabled_ThenPersistedOrderIsUsed_ForNonAppStore() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let persistedOrder: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .addAppToDockMac, .bringStuff, .subscription, .personalizeBrowser, .sync]
        persistor.orderedCardIDs = persistedOrder
        let testProvider = createProvider(isAppStoreBuild: false)
        triggerNewTabPageView(on: testProvider)
        let expectedCards: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .addAppToDockMac]

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenPersistedOrderExists_WithAdvancedOrderingEnabled_ThenPersistedOrderIsUsed_ForAppStore() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let persistedOrder: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .addAppToDockMac, .bringStuff, .subscription, .personalizeBrowser, .sync]
        persistor.orderedCardIDs = persistedOrder
        let testProvider = createProvider(isAppStoreBuild: true)
        triggerNewTabPageView(on: testProvider)
        let expectedCards: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .bringStuff]

        XCTAssertEqual(testProvider.cards, expectedCards)
    }

    func testWhenFirstCardLevelIsLevel1AndDaysLessThanMaxDays_WithAdvancedOrderingEnabled_ThenLevel1CardsFirst() throws {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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

    func testWhenFirstCardLevelIsLevel1AndDaysGreaterThanOrEqualToMaxDays_WithAdvancedOrderingEnabled_ThenLevel2CardsFirst() throws {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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

    func testWhenLevelOrderSwaps_WithAdvancedOrderingEnabled_ThenOrderIsPersisted() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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

    func testWhenDefaultOrderIsUsed_WithAdvancedOrderingEnabled_ThenOrderIsPersisted() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
        let testProvider = createProvider(defaultBrowserIsDefault: false)

        triggerNewTabPageView(on: testProvider)

        let expectedCards = NewTabPageNextStepsSingleCardProvider.defaultAdvancedCards

        XCTAssertEqual(persistor.orderedCardIDs, expectedCards, "Default order should be persisted on first use")
    }

    @MainActor
    func testWhenCardsAreRefreshedWithNewFirstCardThenTimesShownIsIncrementedForFirstCard() {
        featureFlagger.enabledFeatureFlags = [.nextStepsListAdvancedCardOrdering]
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

    // MARK: - Card Ordering Tests (nextStepsListAdvancedCardOrdering disabled)

    @MainActor
    func testFirstSession_WhenAdvancedOrderingDisabled_ThenCardsFollowDefaultOrder() {
        let testFeatureFlagger = MockFeatureFlagger()
        testFeatureFlagger.enabledFeatureFlags = []

        let testProvider = createProvider(
            featureFlagger: testFeatureFlagger,
            isFirstSession: true
        )

        let cards = testProvider.cards
        XCTAssertFalse(cards.isEmpty, "Should have cards")
        XCTAssertEqual(cards.first, .emailProtection, "Email protection should be first in first session under default mock state (YouTube ad-blocking hidden)")
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

    func testFirstSession_WhenNewTabPageOpens_ThenCardsAreNotShuffled_AndIsFirstSessionIsSet() {
        featureFlagger.enabledFeatureFlags = []
        let testProvider = createProvider(isFirstSession: true)
        let initialCards = testProvider.standardCards
        let expectation = XCTestExpectation(description: "New tab page open notification is published")
        let cancellable = NotificationCenter.default.publisher(for: .newTabPageOpen)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                expectation.fulfill()
            }

        NotificationCenter.default.post(name: .newTabPageOpen, object: nil)
        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertFalse(persistor.isFirstSession)
        XCTAssertEqual(testProvider.standardCards, initialCards, "Standard cards should remain the same when new tab page open notification is received in the first session")
    }

    func testSubsequentSession_WhenNewTabPageOpens_ThenCardsAreShuffled() {
        featureFlagger.enabledFeatureFlags = []
        let testProvider = createProvider(isFirstSession: false)
        let initialCards = testProvider.standardCards
        let expectation = XCTestExpectation(description: "New tab page open notification is published")
        let cancellable = NotificationCenter.default.publisher(for: .newTabPageOpen)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                expectation.fulfill()
            }

        NotificationCenter.default.post(name: .newTabPageOpen, object: nil)
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

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: NSWindow())
        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(testProvider.standardCards, initialCards, "Standard card order should remain the same when window becomes key")
    }

    // MARK: - YouTube Ad Blocking visibility

    func testWhenYTAdBlockingFeatureUnavailableThenYTAdBlockingCardIsNotVisible() {
        let testProvider = createProvider(adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: false, isEnabledByUser: true))

        XCTAssertFalse(testProvider.cards.contains(.youtubeAdBlocking))
    }

    func testWhenYTAdBlockingUserNotOptedInThenYTAdBlockingCardIsNotVisible() {
        let testProvider = createProvider(adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: false))

        XCTAssertFalse(testProvider.cards.contains(.youtubeAdBlocking))
    }

    func testWhenYTAdBlockingFullyEnabledThenYTAdBlockingCardIsVisible() {
        let testProvider = createProvider(adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true))

        XCTAssertTrue(testProvider.cards.contains(.youtubeAdBlocking))
    }

    // MARK: - YouTube Ad Blocking permanent dismissal

    func testWhenYouTubeAdBlockingCardLegacySettingIsFalseThenCardIsPermanentlyDismissed() {
        let testLegacyPersistor = MockHomePageContinueSetUpModelPersisting()
        testLegacyPersistor.shouldShowYouTubeAdBlockingSetting = false
        let testProvider = createProvider(
            legacyPersistor: testLegacyPersistor,
            adBlockingAvailability: MockAdBlockingAvailability(isFeatureSupported: true, isEnabledByUser: true)
        )

        XCTAssertFalse(testProvider.cards.contains(.youtubeAdBlocking))
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
        adBlockingAvailability: MockAdBlockingAvailability? = nil,
        isFirstSession: Bool? = nil,
        isAppStoreBuild: Bool? = nil
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
            syncService: testSyncService,
            adBlockingAvailability: testAdBlockingAvailability,
            applicationBuildType: testApplicationBuildType,
            scheduler: .immediate
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
    static let defaultStandardCards: [NewTabPageDataModel.CardID] = [.emailProtection, .defaultApp, .addAppToDockMac, .bringStuff, .subscription, .personalizeBrowser, .sync]

    static let defaultAdvancedCards: [NewTabPageDataModel.CardID] = [.personalizeBrowser, .emailProtection, .defaultApp, .youtubeAdBlocking, .addAppToDockMac, .bringStuff, .sync, .subscription]
}

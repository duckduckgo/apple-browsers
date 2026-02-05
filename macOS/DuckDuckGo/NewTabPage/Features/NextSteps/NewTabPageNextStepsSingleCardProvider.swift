//
//  NewTabPageNextStepsSingleCardProvider.swift
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

import AppKit
import BrowserServicesKit
import Combine
import DDGSync
import Foundation
import NewTabPage

extension NewTabPageDataModel {
    /// Levels assigned to Next Steps cards to control their display order.
    enum CardLevel: Int {
        case level1 = 1
        case level2 = 2
    }
}

/// Provides the Next Steps cards to be displayed on the New Tab Page.
/// This provider expects a single card (the first card in the list) to be displayed at a time and should not be used with the legacy Next Steps widget.
///
final class NewTabPageNextStepsSingleCardProvider: NewTabPageNextStepsCardsProviding {
    private let cardActionHandler: NewTabPageNextStepsCardsActionHandling
    private let pixelHandler: NewTabPageNextStepsCardsPixelHandling
    private var persistor: NewTabPageNextStepsCardsPersisting
    private let legacyPersistor: HomePageContinueSetUpModelPersisting
    private let legacySubscriptionCardPersistor: HomePageSubscriptionCardPersisting
    private let appearancePreferences: AppearancePreferences

    private let defaultBrowserProvider: DefaultBrowserProvider
    private let dockCustomizer: DockCustomization
    private let dataImportProvider: DataImportStatusProviding
    private let emailManager: EmailManager
    private let duckPlayerPreferences: DuckPlayerPreferencesPersistor
    private let subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging
    private let syncService: DDGSyncing?

    private var debugPersistor: NewTabPageNextStepsCardsDebugPersistor = {
        NewTabPageNextStepsCardsDebugPersistor()
    }()

    enum Constants {
        /// Maximum times a card can be dismissed before it is permanently hidden.
        ///
        /// This value can be increased to allow cards to resurface after being dismissed.
        static let maxTimesCardDismissed = 1

        /// Maximum times a card can be shown before it is moved to the back of the card list.
        static let maxTimesCardShown = 10

        /// How many days to prioritize Level 1 cards before highlighting Level 2 cards.
        static let cardLevel1PriorityDays = 2
    }

    /// Which card level to show first in the list of cards.
    /// This is used to swap the card order after `cardLevel1DemonstrationDays` have passed.
    private var firstCardLevel: NewTabPageDataModel.CardLevel {
        get { persistor.firstCardLevel }
        set { persistor.firstCardLevel = newValue }
    }

    struct LeveledCard {
        let cardID: NewTabPageDataModel.CardID
        let level: NewTabPageDataModel.CardLevel
    }

    /// Cards sorted in default order, grouped according to their level.
    let defaultCards = [
        LeveledCard(cardID: .personalizeBrowser, level: .level1),
        LeveledCard(cardID: .sync, level: .level1),
        LeveledCard(cardID: .emailProtection, level: .level1),
        LeveledCard(cardID: .defaultApp, level: .level2),
        LeveledCard(cardID: .addAppToDockMac, level: .level2),
        LeveledCard(cardID: .duckplayer, level: .level2),
        LeveledCard(cardID: .bringStuff, level: .level2),
        LeveledCard(cardID: .subscription, level: .level2)
    ]

    private var cancellables: Set<AnyCancellable> = []

    /// For protocol conformance; this provider expects to display a single card at a time (not expandable).
    @Published var isViewExpanded: Bool = false

    /// For protocol conformance; this provider expects to display a single card at a time (not expandable).
    var isViewExpandedPublisher: AnyPublisher<Bool, Never> {
        $isViewExpanded.dropFirst().eraseToAnyPublisher()
    }

    @Published private var cardList: [NewTabPageDataModel.CardID] = []

    /// Returns the list of cards to be displayed, or an empty list if the continue set up cards view is considered outdated.
    /// The widget only shows the first card in the list, but we provide the full list of available cards so it can show a progress indicator.
    var cards: [NewTabPageDataModel.CardID] {
        guard !appearancePreferences.isContinueSetUpCardsViewOutdated else {
            return []
        }
        return cardList
    }

    var cardsPublisher: AnyPublisher<[NewTabPageDataModel.CardID], Never> {
        let cards = $cardList.dropFirst().removeDuplicates()
        let cardsDidBecomeOutdated = appearancePreferences.$isContinueSetUpCardsViewOutdated.removeDuplicates()

        return Publishers.CombineLatest(cards, cardsDidBecomeOutdated)
            .map { cards, isOutdated -> [NewTabPageDataModel.CardID] in
                guard !isOutdated else {
                    return []
                }
                return cards
            }
            .eraseToAnyPublisher()
    }

    init(cardActionHandler: NewTabPageNextStepsCardsActionHandling,
         pixelHandler: NewTabPageNextStepsCardsPixelHandling,
         persistor: NewTabPageNextStepsCardsPersisting,
         legacyPersistor: HomePageContinueSetUpModelPersisting,
         legacySubscriptionCardPersistor: HomePageSubscriptionCardPersisting,
         appearancePreferences: AppearancePreferences,
         defaultBrowserProvider: DefaultBrowserProvider,
         dockCustomizer: DockCustomization,
         dataImportProvider: DataImportStatusProviding,
         emailManager: EmailManager = EmailManager(),
         duckPlayerPreferences: DuckPlayerPreferencesPersistor,
         subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging,
         syncService: DDGSyncing?) {
        self.cardActionHandler = cardActionHandler
        self.pixelHandler = pixelHandler
        self.persistor = persistor
        self.legacyPersistor = legacyPersistor
        self.legacySubscriptionCardPersistor = legacySubscriptionCardPersistor
        self.appearancePreferences = appearancePreferences
        self.defaultBrowserProvider = defaultBrowserProvider
        self.dockCustomizer = dockCustomizer
        self.dataImportProvider = dataImportProvider
        self.emailManager = emailManager
        self.duckPlayerPreferences = duckPlayerPreferences
        self.subscriptionCardVisibilityManager = subscriptionCardVisibilityManager
        self.syncService = syncService

        refreshCardList()
        observeCardVisibilityChanges()
        observeKeyWindowChanges()
        observeNewTabPageWebViewDidAppear()
    }

    @MainActor
    func handleAction(for card: NewTabPageDataModel.CardID) {
        cardActionHandler.performAction(for: card) { [weak self] in
            self?.refreshCardList()
        }
    }

    @MainActor
    func dismiss(_ card: NewTabPageDataModel.CardID) {
        pixelHandler.fireNextStepsCardDismissedPixel(card)
        if card == .subscription {
            pixelHandler.fireSubscriptionCardDismissedPixel()
        }
        persistor.incrementTimesDismissed(for: card)
        refreshCardList()
    }

    @MainActor
    func willDisplayCards(_ cards: [NewTabPageDataModel.CardID]) {
        appearancePreferences.continueSetUpCardsViewDidAppear()
        if let card = cards.first {
            pixelHandler.fireNextStepsCardShownPixels([card])
            pixelHandler.fireAddToDockPresentedPixelIfNeeded([card])
            persistor.incrementTimesShown(for: card)
        }
    }
}

// MARK: Assemble & refresh card list

private extension NewTabPageNextStepsSingleCardProvider {

    func refreshCardList() {
        let cards = getOrderedCards()
        if cards.isEmpty {
            appearancePreferences.continueSetUpCardsClosed = true
        }
        cardList = cards
    }

    /// Gets a list of cards, sorted by card level and persisted card order.
    /// Returns only the visible cards (filtered by shouldShowCard).
    func getOrderedCards() -> [NewTabPageDataModel.CardID] {
        // Get the card list based on persisted or default order
        var orderedCards = persistor.orderedCardIDs ?? defaultCards.map { $0.cardID }

        // Check if the first visible card has been shown 10+ times, and move it to the end of the list
        if let firstVisibleCard = orderedCards.first(where: shouldShowCard),
           persistor.timesShown(for: firstVisibleCard) >= Constants.maxTimesCardShown,
           let index = orderedCards.firstIndex(where: { $0 == firstVisibleCard }) {
            let card = orderedCards.remove(at: index)
            orderedCards.append(card)
            persistor.setTimesShown(0, for: card)
        }

        // Swap the order of levels if needed.
        // This refreshes the list to highlight level 2 cards after level 1 cards are done being prioritized.
        if firstCardLevel == .level1 && appearancePreferences.nextStepsCardsDemonstrationDays >= Constants.cardLevel1PriorityDays {
            firstCardLevel = .level2
            orderedCards = orderedCards
                .compactMap { cardID in defaultCards.first(where: { $0.cardID == cardID }) }
                .sorted { $0.level.rawValue > $1.level.rawValue }
                .map { $0.cardID }
        }

        // Persist the full ordered list if needed.
        if persistor.orderedCardIDs != orderedCards {
            persistor.orderedCardIDs = orderedCards
        }

        let orderedVisibleCards = orderedCards.filter(shouldShowCard)

#if DEBUG || REVIEW || ALPHA
        // Persist visible cards for debug menu actions
        // Otherwise, we don't need to persist this because we want to check card visibility each time cards are shown
        debugPersistor.debugVisibleCards = orderedVisibleCards
#endif

        // Return only the visible cards
        return orderedVisibleCards
    }

    /// Returns whether the card should be shown in the list of visible cards.
    /// This checks both if the card has been permanently dismissed and if the card's specific visibility conditions are met.
    func shouldShowCard(_ card: NewTabPageDataModel.CardID) -> Bool {
        guard !isCardPermanentlyDismissed(card) else {
            return false
        }

        switch card {
        case .defaultApp:
            return !defaultBrowserProvider.isDefault
        case .bringStuff:
            return !dataImportProvider.didImport
        case .addAppToDockMac:
#if !APPSTORE
            return !dockCustomizer.isAddedToDock
#else
            return false
#endif
        case .duckplayer:
            return duckPlayerPreferences.duckPlayerModeBool == nil && !duckPlayerPreferences.youtubeOverlayAnyButtonPressed
        case .emailProtection:
            return !emailManager.isSignedIn
        case .subscription:
            return subscriptionCardVisibilityManager.shouldShowSubscriptionCard
        case .personalizeBrowser:
            return !appearancePreferences.didChangeAnyNewTabPageCustomizationSetting
        case .sync:
            return syncService?.featureFlags.contains(.all) == true && syncService?.authState == .inactive
        }
    }

    func isCardPermanentlyDismissed(_ card: NewTabPageDataModel.CardID) -> Bool {
        let dismissedLegacySetting: Bool
        switch card {
        case .defaultApp:
            dismissedLegacySetting = !legacyPersistor.shouldShowMakeDefaultSetting
        case .addAppToDockMac:
            dismissedLegacySetting = !legacyPersistor.shouldShowAddToDockSetting
        case .duckplayer:
            dismissedLegacySetting = !legacyPersistor.shouldShowDuckPlayerSetting
        case .emailProtection:
            dismissedLegacySetting = !legacyPersistor.shouldShowEmailProtectionSetting
        case .bringStuff:
            dismissedLegacySetting = !legacyPersistor.shouldShowImportSetting
        case .subscription:
            dismissedLegacySetting = !legacySubscriptionCardPersistor.shouldShowSubscriptionSetting
        default:
            dismissedLegacySetting = false // No legacy setting for other (new) cards
        }

        // Checks the card's legacy setting first, to respect if the card was dismissed in the previous Next Steps implementation.
        // Otherwise, checks if the card has been dismissed the maximum possible times.
        if dismissedLegacySetting {
            return true
        } else {
            return persistor.timesDismissed(for: card) >= Constants.maxTimesCardDismissed
        }
    }

    func observeCardVisibilityChanges() {
        subscriptionCardVisibilityManager.shouldShowSubscriptionCardPublisher.removeDuplicates()
            .combineLatest(appearancePreferences.$didChangeAnyNewTabPageCustomizationSetting.removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCardList()
            }
            .store(in: &cancellables)
    }

    func observeKeyWindowChanges() {
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCardList()
            }
            .store(in: &cancellables)
    }

    func observeNewTabPageWebViewDidAppear() {
        // HTML New Tab Page doesn't refresh on appear so we have to connect to the appear signal
        // (the notification in this case) to trigger a refresh.
        NotificationCenter.default.publisher(for: .newTabPageWebViewDidAppear)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshCardList()
            }
            .store(in: &cancellables)
    }
}

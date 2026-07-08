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
import CombineSchedulers
import DDGSync
import Foundation
import NewTabPage
import PrivacyConfig
import WebExtensions

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
    private let featureFlagger: FeatureFlagger

    private let defaultBrowserProvider: DefaultBrowserProvider
    private let dockCustomizer: DockCustomization
    private let dataImportProvider: DataImportStatusProviding
    private let emailManager: EmailManager
    private let duckPlayerPreferences: DuckPlayerPreferencesPersistor
    private let subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging
    private let syncService: DDGSyncing?
    private let adBlockingAvailability: AdBlockingAvailabilityProviding
    private let isAppStoreBuild: Bool

    private let scheduler: AnySchedulerOf<DispatchQueue>

    private var debugPersistor: NewTabPageNextStepsCardsDebugPersistor = {
        NewTabPageNextStepsCardsDebugPersistor()
    }()

    enum Constants {
        /// Maximum times a card can be dismissed before it is permanently hidden.
        ///
        /// This value can be increased to allow cards to resurface after being dismissed.
        static let maxTimesCardDismissed = 1

        /// Maximum times a card can be shown before it is moved to the back of the card list, to avoid card blindness.
        static let maxTimesCardShown = 5

        /// How many days to prioritize Level 1 cards before highlighting Level 2 cards.
        /// This is used with advanced ordering to swap the card order, to highlight higher impact, higher effort cards.
        static let cardLevel1PriorityDays = 2

        /// Maximum number of Next Steps cards shown in the visible stack at once (advanced ordering), to avoid overwhelm.
        static let maxVisibleCards = 3
    }

    /// Whether to use standard or advanced ordering for the card list.
    private var shouldUseAdvancedCardOrdering: Bool

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

    /// Cards for the card list, with standard ordering.
    ///
    /// Cards are shown in default order for first session, and then randomized.
    private(set) var standardCards: [NewTabPageDataModel.CardID]

    /// Cards sorted in default order, for standard ordering.
    private let defaultStandardCards: [NewTabPageDataModel.CardID] = [
        .youtubeAdBlocking,
        .emailProtection,
        .defaultApp,
        .addAppToDockMac,
        .bringStuff,
        .subscription,
        .personalizeBrowser,
        .sync
    ]

    /// Cards for the card list sorted in default order, grouped according to their level.
    ///
    /// This is used for advanced card ordering with the feature flag `nextStepsListAdvancedCardOrdering`.
    private let defaultAdvancedCards = [
        LeveledCard(cardID: .personalizeBrowser, level: .level1),
        LeveledCard(cardID: .emailProtection, level: .level1),
        LeveledCard(cardID: .defaultApp, level: .level2),
        LeveledCard(cardID: .youtubeAdBlocking, level: .level2),
        LeveledCard(cardID: .addAppToDockMac, level: .level2),
        LeveledCard(cardID: .bringStuff, level: .level2),
        LeveledCard(cardID: .sync, level: .level1),
        LeveledCard(cardID: .subscription, level: .level2)
    ]

    private var cancellables: Set<AnyCancellable> = []

    /// For protocol conformance; this provider expects to display a single card at a time (not expandable).
    @Published var isViewExpanded: Bool = false

    /// For protocol conformance; this provider expects to display a single card at a time (not expandable).
    var isViewExpandedPublisher: AnyPublisher<Bool, Never> {
        $isViewExpanded.dropFirst()
            .subscribe(on: scheduler)
            .eraseToAnyPublisher()
    }

    @Published private var cardList: [NewTabPageDataModel.CardID] = []

    var isNextStepsCardsComplete: Bool {
        appearancePreferences.isContinueSetUpCardsViewOutdated || appearancePreferences.continueSetUpCardsClosed
    }

    /// Returns the list of cards to be displayed, or an empty list if the continue set up cards view is considered outdated or was previously closed.
    /// The widget only shows the first card in the list, but we provide the full list of available cards so it can show a progress indicator.
    var cards: [NewTabPageDataModel.CardID] {
        guard !isNextStepsCardsComplete else {
            return []
        }
        return cardList
    }

    var cardsPublisher: AnyPublisher<[NewTabPageDataModel.CardID], Never> {
        let cards = $cardList.dropFirst().removeDuplicates()
        let cardsAreVisible = appearancePreferences.$isContinueSetUpCardsViewOutdated
            .combineLatest(appearancePreferences.$continueSetUpCardsClosed)
            .map { isOutdated, isClosed in
                !(isOutdated || isClosed)
            }
            .removeDuplicates()

        return Publishers.CombineLatest(cards, cardsAreVisible)
            .subscribe(on: scheduler)
            .map { cards, areVisible -> [NewTabPageDataModel.CardID] in
                guard areVisible else {
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
         featureFlagger: FeatureFlagger,
         defaultBrowserProvider: DefaultBrowserProvider,
         dockCustomizer: DockCustomization,
         dataImportProvider: DataImportStatusProviding,
         emailManager: EmailManager = EmailManager(),
         duckPlayerPreferences: DuckPlayerPreferencesPersistor,
         subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging,
         syncService: DDGSyncing?,
         adBlockingAvailability: AdBlockingAvailabilityProviding,
         applicationBuildType: ApplicationBuildType = StandardApplicationBuildType(),
         scheduler: AnySchedulerOf<DispatchQueue> = DispatchQueue.main.eraseToAnyScheduler()) {
        self.cardActionHandler = cardActionHandler
        self.pixelHandler = pixelHandler
        self.persistor = persistor
        self.legacyPersistor = legacyPersistor
        self.legacySubscriptionCardPersistor = legacySubscriptionCardPersistor
        self.appearancePreferences = appearancePreferences
        self.featureFlagger = featureFlagger
        self.defaultBrowserProvider = defaultBrowserProvider
        self.dockCustomizer = dockCustomizer
        self.dataImportProvider = dataImportProvider
        self.emailManager = emailManager
        self.duckPlayerPreferences = duckPlayerPreferences
        self.subscriptionCardVisibilityManager = subscriptionCardVisibilityManager
        self.syncService = syncService
        self.adBlockingAvailability = adBlockingAvailability
        self.isAppStoreBuild = applicationBuildType.isAppStoreBuild
        self.scheduler = scheduler
        self.shouldUseAdvancedCardOrdering = featureFlagger.isFeatureOn(.nextStepsListAdvancedCardOrdering)
        self.standardCards = defaultStandardCards

        // Migrate isFirstSession from legacy persistor if needed
        if persistor.isFirstSession && !legacyPersistor.isFirstSession {
            self.persistor.isFirstSession = false
        }

        shuffleStandardCardsIfNeeded()
        if !shouldUseAdvancedCardOrdering {
            refreshCardList(recordNewCardImpression: false)
        }
        observeCardVisibilityChanges()
        observeKeyWindowChanges()
        observeNewTabPageWebViewDidAppear()
        observeNewTabPageOpen()
        observeFeatureFlagChanges()
        observeNextStepsCardsDebugReset()
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
        }
    }
}

// MARK: Assemble & refresh card list

private extension NewTabPageNextStepsSingleCardProvider {

    /// Refreshes the card list based on card visibility conditions and ordering logic.
    ///
    /// - Parameters:
    ///   - updateOrder: When true, refreshes the full advanced-ordering stack (NTP appear only). Mid-session refreshes prune the current stack without reordering.
    ///   - recordNewCardImpression: Whether to record an impression for the newly visible card if the first card in the list has changed after the refresh. Defaults to true.
    func refreshCardList(updateOrder: Bool = false, recordNewCardImpression: Bool = true) {
        let cards = visibleCards(updateOrder: updateOrder)

        if cards.isEmpty && !hasRemainingEligibleCards() {
            appearancePreferences.continueSetUpCardsClosed = true
        }

        if recordNewCardImpression, let newVisibleCard = cards.first, newVisibleCard != self.cards.first {
            recordImpression(for: newVisibleCard)
        }

        cardList = cards
    }

    /// Returns visible cards. When `updateOrder` is true and advanced ordering is enabled, refreshes the visible stack with advanced ordering.
    func visibleCards(updateOrder: Bool) -> [NewTabPageDataModel.CardID] {
        guard shouldUseAdvancedCardOrdering else {
            return standardCards.filter(shouldShowCard)
        }
        if updateOrder {
            return refreshVisibleStackWithAdvancedOrdering()
        } else {
            let prunedStack = cardList.filter(shouldShowCard)
            if !cardList.isEmpty, prunedStack != persistor.dailyVisibleStack {
                persistor.dailyVisibleStack = prunedStack
            }
            return prunedStack
        }
    }

    /// Refreshes the persisted visible stack for a New Tab Page appear.
    /// Applies level swap, rotation, and day-boundary rules to reduce card blindness and overwhelm.
    /// Reconciles stored order and `dailyVisibleStack` with current eligibility, then writes
    /// the updated stack and order back to the persistor.
    func refreshVisibleStackWithAdvancedOrdering() -> [NewTabPageDataModel.CardID] {
        let currentDayIdentifier = appearancePreferences.nextStepsCardsDemonstrationDays
        var resolvedOrder = persistor.orderedCardIDs ?? defaultAdvancedCards.map(\.cardID)
        let didLevelSwap = applyLevelSwapIfNeeded(to: &resolvedOrder)

        let isNewDay = persistor.visibleStackDayIdentifier != currentDayIdentifier
        var visibleStack: [NewTabPageDataModel.CardID]
        if isNewDay {
            visibleStack = buildStackForNewDay(didLevelSwap, resolvedOrder)
        } else {
            visibleStack = (persistor.dailyVisibleStack ?? [])
                .filter(shouldShowCard)
        }

        applyRotationIfNeeded(to: &visibleStack, orderedCardIDs: &resolvedOrder)

        persistor.dailyVisibleStack = visibleStack
        if isNewDay {
            persistor.visibleStackDayIdentifier = currentDayIdentifier
        }
        if persistor.orderedCardIDs != resolvedOrder {
            persistor.orderedCardIDs = resolvedOrder
        }

        persistDebugVisibleCardsIfNeeded(visibleStack)
        return visibleStack
    }

    func applyLevelSwapIfNeeded(to orderedCards: inout [NewTabPageDataModel.CardID]) -> Bool {
        guard firstCardLevel == .level1,
              appearancePreferences.nextStepsCardsDemonstrationDays >= Constants.cardLevel1PriorityDays else {
            return false
        }

        firstCardLevel = .level2
        orderedCards = orderedCards
            .compactMap { cardID in defaultAdvancedCards.first(where: { $0.cardID == cardID }) }
            .sorted { $0.level.rawValue > $1.level.rawValue }
            .map(\.cardID)
        return true
    }

    func buildStackForNewDay(_ didLevelSwap: Bool, _ resolvedOrder: [NewTabPageDataModel.CardID]) -> [NewTabPageDataModel.CardID] {
        guard !didLevelSwap else {
            return topEligibleVisibleCards(from: resolvedOrder)
        }

        var visibleStack = (persistor.dailyVisibleStack ?? [])
            .filter(shouldShowCard)

        if visibleStack.isEmpty {
            visibleStack = topEligibleVisibleCards(from: resolvedOrder)
        } else {
            refillVisibleStack(&visibleStack, from: resolvedOrder)
        }

        return visibleStack
    }

    func topEligibleVisibleCards(from orderedCardIDs: [NewTabPageDataModel.CardID]) -> [NewTabPageDataModel.CardID] {
        Array(
            orderedCardIDs
                .filter(shouldShowCard)
                .prefix(Constants.maxVisibleCards)
        )
    }

    func applyRotationIfNeeded(to visibleStack: inout [NewTabPageDataModel.CardID],
                               orderedCardIDs: inout [NewTabPageDataModel.CardID]) {
        guard let topCard = visibleStack.first else { return }

        let impressions = persistor.timesShown(for: topCard)
        guard impressions > 0, impressions.isMultiple(of: Constants.maxTimesCardShown) else { return }

        visibleStack.removeFirst()
        orderedCardIDs.removeAll { $0 == topCard }
        orderedCardIDs.append(topCard)

        if visibleStack.count < Constants.maxVisibleCards {
            pullNextEligibleCard(into: &visibleStack, from: orderedCardIDs)
        }

        let visibleSet = Set(visibleStack)
        let backlog = orderedCardIDs.filter { !visibleSet.contains($0) }
        orderedCardIDs = visibleStack + backlog
    }

    func refillVisibleStack(_ visibleStack: inout [NewTabPageDataModel.CardID],
                            from orderedCardIDs: [NewTabPageDataModel.CardID]) {
        while visibleStack.count < Constants.maxVisibleCards {
            guard pullNextEligibleCard(into: &visibleStack, from: orderedCardIDs) else {
                break
            }
        }
    }

    @discardableResult
    func pullNextEligibleCard(into visibleStack: inout [NewTabPageDataModel.CardID],
                              from orderedCardIDs: [NewTabPageDataModel.CardID]) -> Bool {
        let visibleSet = Set(visibleStack)
        guard let nextCard = orderedCardIDs.first(where: { shouldShowCard($0) && !visibleSet.contains($0) }) else {
            return false
        }
        visibleStack.append(nextCard)
        return true
    }

    func persistDebugVisibleCardsIfNeeded(_ visibleCards: [NewTabPageDataModel.CardID]) {
        let buildType = StandardApplicationBuildType()
        if buildType.isDebugBuild || buildType.isReviewBuild || buildType.isAlphaBuild {
            debugPersistor.debugVisibleCards = visibleCards
        }
    }

    /// Records an impression for the provided card.
    func recordImpression(for card: NewTabPageDataModel.CardID?) {
        guard !isNextStepsCardsComplete, let card else { return }
        persistor.incrementTimesShown(for: card)
    }

    /// If this is not the first session, sorts `standardCards` with the `defaultApp` card first, and the remaining cards in random order.
    func shuffleStandardCardsIfNeeded() {
        guard !persistor.isFirstSession else { return }
        let shuffledCards = defaultStandardCards.filter { $0 != .defaultApp }.shuffled()
        standardCards = [.defaultApp] + shuffledCards
    }

    /// Returns whether the card should be shown in the list of visible cards.
    /// This checks the following conditions:
    /// - Whether the card has been permanently dismissed
    /// - Whether the card's specific visibility conditions are met.
    func shouldShowCard(_ card: NewTabPageDataModel.CardID) -> Bool {
        guard !isCardPermanentlyDismissed(card) else { return false }

        switch card {
        case .defaultApp:
            return !defaultBrowserProvider.isDefault
        case .bringStuff:
            return !dataImportProvider.didImport
        case .addAppToDockMac:
            return !isAppStoreBuild && !dockCustomizer.isAddedToDock
        case .duckplayer:
            return false
        case .emailProtection:
            return !emailManager.isSignedIn
        case .subscription:
            return subscriptionCardVisibilityManager.shouldShowSubscriptionCard
        case .personalizeBrowser:
            return !appearancePreferences.didChangeAnyNewTabPageCustomizationSetting
        case .sync:
            return syncService?.featureFlags.contains(.all) == true && syncService?.authState == .inactive
        case .youtubeAdBlocking:
            return adBlockingAvailability.isEnabled
        }
    }

    func hasRemainingEligibleCards() -> Bool {
        guard shouldUseAdvancedCardOrdering else { return false }
        let ordered = persistor.orderedCardIDs ?? defaultAdvancedCards.map(\.cardID)
        return ordered.contains(where: shouldShowCard)
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
        case .youtubeAdBlocking:
            dismissedLegacySetting = !legacyPersistor.shouldShowYouTubeAdBlockingSetting
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
        // Async dispatch allows the default browser setting to propagate after being changed in the system dialog.
        // We schedule this in the sink block (not receiving it directly on the main queue) to avoid the main queue
        // holding a reference to the block and preventing full deallocation in integration tests that end immediately
        // after opening the New Tab Page, which would require flushing the queue.
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { _ in
                DispatchQueue.main.async { [weak self] in
                    self?.refreshCardList()
                }
            }
            .store(in: &cancellables)
    }

    func observeNewTabPageWebViewDidAppear() {
        // HTML New Tab Page doesn't refresh on appear so we have to connect to the appear signal
        // (the notification in this case) to trigger a refresh.
        NotificationCenter.default.publisher(for: .newTabPageWebViewDidAppear)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }

                let buildType = StandardApplicationBuildType()
                if buildType.isDebugBuild || buildType.isReviewBuild || buildType.isAlphaBuild {
                    // Reset standard card list and mark first session as complete for debug menu reset action, if needed
                    if persistor.isFirstSession {
                        persistor.isFirstSession = false
                        standardCards = defaultStandardCards
                    }
                }
                if !isNextStepsCardsComplete {
                    appearancePreferences.continueSetUpCardsViewDidAppear()
                }
                // We record an impression for the visible card unconditionally when the New Tab Page is opened,
                // not only when a new card is visible due to the card list refresh.
                refreshCardList(updateOrder: true, recordNewCardImpression: false)
                if !isNextStepsCardsComplete {
                    recordImpression(for: cards.first)
                    persistor.ntpImpressionCount += 1
                }
            }
            .store(in: &cancellables)
    }

    /// Observes the `newTabPageOpen` notification to reshuffle the cards, if needed.
    ///
    func observeNewTabPageOpen() {
        NotificationCenter.default.publisher(for: .newTabPageOpen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                shuffleStandardCardsIfNeeded()
                // Mark first session as complete when cards are shown after onboarding is finished
                if persistor.isFirstSession {
                    let buildType = StandardApplicationBuildType()
                    if OnboardingActionsManager.isOnboardingFinished || buildType.isDebugBuild || buildType.isReviewBuild || buildType.isAlphaBuild {
                        persistor.isFirstSession = false
                    }
                }
            }
            .store(in: &cancellables)
    }

    func observeFeatureFlagChanges() {
        featureFlagger.updatesPublisher
            .compactMap { [weak self] in
                self?.featureFlagger.isFeatureOn(.nextStepsListAdvancedCardOrdering)
            }
            .prepend(featureFlagger.isFeatureOn(.nextStepsListAdvancedCardOrdering))
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAdvancedOrderingOn in
                guard let self else { return }
                shouldUseAdvancedCardOrdering = isAdvancedOrderingOn
                refreshCardList()
            }
            .store(in: &cancellables)
    }

    func observeNextStepsCardsDebugReset() {
        NotificationCenter.default.publisher(for: .nextStepsCardsDebugDidReset)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cardList = []
            }
            .store(in: &cancellables)
    }
}

extension Notification.Name {
    static let newTabPageOpen = Notification.Name("newTabPageOpen")
    static let nextStepsCardsDebugDidReset = Notification.Name("nextStepsCardsDebugDidReset")
}

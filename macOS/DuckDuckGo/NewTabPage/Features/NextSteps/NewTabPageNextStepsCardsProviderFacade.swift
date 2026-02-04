//
//  NewTabPageNextStepsCardsProviderFacade.swift
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
import DDGSync
import FeatureFlags
import Foundation
import NewTabPage
import PrivacyConfig

final class NewTabPageNextStepsCardsProviderFacade: NewTabPageNextStepsCardsProviding {
    private let featureFlagger: FeatureFlagger
    private let singleCardProvider: NewTabPageNextStepsSingleCardProvider
    private let legacyCardsProvider: NewTabPageNextStepsCardsProvider
    private var cancellables: Set<AnyCancellable> = []
    @Published private(set) var activeProvider: NewTabPageNextStepsCardsProviding

    init(featureFlagger: FeatureFlagger,
         dataImportProvider: DataImportStatusProviding,
         subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging,
         legacyPersistor: HomePageContinueSetUpModelPersisting,
         pixelHandler: NewTabPageNextStepsCardsPixelHandling,
         cardActionsHandler: NewTabPageNextStepsCardsActionHandling,
         appearancePreferences: AppearancePreferences,
         legacySubscriptionCardPersistor: HomePageSubscriptionCardPersisting,
         persistor: NewTabPageNextStepsCardsPersisting,
         duckPlayerPreferences: DuckPlayerPreferencesPersistor,
         syncService: DDGSyncing?) {
        let singleCardProvider = NewTabPageNextStepsSingleCardProvider(
            cardActionHandler: cardActionsHandler,
            pixelHandler: pixelHandler,
            persistor: persistor,
            legacyPersistor: legacyPersistor,
            legacySubscriptionCardPersistor: legacySubscriptionCardPersistor,
            appearancePreferences: appearancePreferences,
            defaultBrowserProvider: SystemDefaultBrowserProvider(),
            dockCustomizer: DockCustomizer(),
            dataImportProvider: dataImportProvider,
            duckPlayerPreferences: duckPlayerPreferences,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            syncService: syncService
        )
        let legacyCardsProvider = NewTabPageNextStepsCardsProvider(
            continueSetUpModel: HomePage.Models.ContinueSetUpModel(
                dataImportProvider: dataImportProvider,
                subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
                persistor: legacyPersistor,
                pixelHandler: pixelHandler,
                cardActionsHandler: cardActionsHandler
            ),
            appearancePreferences: appearancePreferences,
            pixelHandler: pixelHandler
        )
        self.featureFlagger = featureFlagger
        self.singleCardProvider = singleCardProvider
        self.legacyCardsProvider = legacyCardsProvider

        func getActiveProvider() -> NewTabPageNextStepsCardsProviding {
            featureFlagger.isFeatureOn(.nextStepsListWidget) ? singleCardProvider : legacyCardsProvider
        }

        activeProvider = getActiveProvider()

        featureFlagger.updatesPublisher
            .compactMap { [weak self] in
                self?.featureFlagger.isFeatureOn(.nextStepsListWidget)
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFlagEnabled in
                guard let self else { return }
                activeProvider = getActiveProvider()
            }
            .store(in: &cancellables)
    }

    var isViewExpanded: Bool {
        get {
            activeProvider.isViewExpanded
        }
        set {
            activeProvider.isViewExpanded = newValue
        }
    }

    private(set) lazy var isViewExpandedPublisher: AnyPublisher<Bool, Never> = {
        $activeProvider
            .receive(on: DispatchQueue.main)
            .flatMap { provider in
                provider.isViewExpandedPublisher
            }
            .eraseToAnyPublisher()
    }()

    var cards: [NewTabPageDataModel.CardID] {
        activeProvider.cards
    }

    private(set) lazy var cardsPublisher: AnyPublisher<[NewTabPageDataModel.CardID], Never> = {
        $activeProvider
            .receive(on: DispatchQueue.main)
            .flatMap { provider in
                provider.cardsPublisher
            }
            .eraseToAnyPublisher()
    }()

    @MainActor
    func handleAction(for card: NewTabPageDataModel.CardID) {
        activeProvider.handleAction(for: card)
    }

    @MainActor
    func dismiss(_ card: NewTabPageDataModel.CardID) {
        activeProvider.dismiss(card)
    }

    @MainActor
    func willDisplayCards(_ cards: [NewTabPageDataModel.CardID]) {
        activeProvider.willDisplayCards(cards)
    }
}

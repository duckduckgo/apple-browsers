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
import FeatureFlags
import Foundation
import NewTabPage
import PrivacyConfig

final class NewTabPageNextStepsCardsProviderFacade: NewTabPageNextStepsCardsProviding {
    private let featureFlagger: FeatureFlagger
    private let singleCardProvider: NewTabPageNextStepsSingleCardProvider
    private let legacyProvider: NewTabPageNextStepsCardsProvider

    private var activeProvider: NewTabPageNextStepsCardsProviding {
        featureFlagger.isFeatureOn(.nextStepsSingleCardIteration) ? singleCardProvider : legacyProvider
    }

    init(featureFlagger: FeatureFlagger,
         singleCardProvider: NewTabPageNextStepsSingleCardProvider,
         legacyProvider: NewTabPageNextStepsCardsProvider) {
        self.featureFlagger = featureFlagger
        self.singleCardProvider = singleCardProvider
        self.legacyProvider = legacyProvider
    }

    var isViewExpanded: Bool {
        get {
            activeProvider.isViewExpanded
        }
        set {
            activeProvider.isViewExpanded = newValue
        }
    }

    var isViewExpandedPublisher: AnyPublisher<Bool, Never> {
        activeProvider.isViewExpandedPublisher
    }

    var cards: [NewTabPageDataModel.CardID] {
        activeProvider.cards
    }

    var cardsPublisher: AnyPublisher<[NewTabPageDataModel.CardID], Never> {
        activeProvider.cardsPublisher
    }

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


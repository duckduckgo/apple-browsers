//
//  NextStepsCardsPromoDelegate.swift
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
import Foundation
import NewTabPage

/// Promo delegate for Next Steps cards on the New Tab Page.
/// Observes cards in NewTabPageNextStepsCardsProviding and publishes visibility to PromoService.
/// External promo: PromoService subscribes to isVisiblePublisher and applies fixed result on dismiss.
final class NextStepsCardsPromoDelegate: ExternalPromoDelegate {

    private let cardsProvider: NewTabPageNextStepsCardsProviding
    private let visibilitySubject: CurrentValueSubject<Bool, Never>
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool { visibilitySubject.value }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { visibilitySubject.eraseToAnyPublisher() }

    /// When cards are hidden (user closed, user actioned all, or max-time), permanently dismiss.
    var resultWhenHidden: PromoResult { .ignored() }

    init(cardsProvider: NewTabPageNextStepsCardsProviding) {
        self.cardsProvider = cardsProvider
        self.visibilitySubject = CurrentValueSubject(!cardsProvider.cards.isEmpty)

        cardsProvider.cardsPublisher
            .map { !$0.isEmpty }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.visibilitySubject.send(visible)
            }
            .store(in: &cancellables)
    }
}

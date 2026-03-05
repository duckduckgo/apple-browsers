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

/// Promo delegate for Next Steps (nextStepsList and nextSteps widgets) on the NTP.
/// Eligibility is derived from the cards provider; when all cards are dismissed or actioned,
/// the promo is permanently dismissed (.ignored()). Max-time expiry flows through eligibility loss (.noChange).
final class NextStepsCardsPromoDelegate: PromoDelegate {

    private let cardsProvider: NewTabPageNextStepsCardsProviding
    private let appearancePreferences: AppearancePreferences
    private weak var promoService: PromoService?

    private let eligibilitySubject: CurrentValueSubject<Bool, Never>
    private var cancellables = Set<AnyCancellable>()

    /// Continuation for show(). Resumed when user dismisses/actions all (continueSetUpCardsClosed) or hide() (max time / eligibility lost).
    private var continuation: CheckedContinuation<PromoResult, Never>?

    var isEligible: Bool { eligibilitySubject.value }
    var isEligiblePublisher: AnyPublisher<Bool, Never> { eligibilitySubject.eraseToAnyPublisher() }

    init(
        cardsProvider: NewTabPageNextStepsCardsProviding,
        appearancePreferences: AppearancePreferences,
        promoService: PromoService?
    ) {
        self.cardsProvider = cardsProvider
        self.appearancePreferences = appearancePreferences
        self.promoService = promoService
        self.eligibilitySubject = CurrentValueSubject(!cardsProvider.cards.isEmpty)

        cardsProvider.cardsPublisher
            .map { !$0.isEmpty }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] eligible in
                self?.eligibilitySubject.send(eligible)
            }
            .store(in: &cancellables)

        appearancePreferences.$continueSetUpCardsClosed
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] closed in
                self?.handleContinueSetUpCardsClosed(closed)
            }
            .store(in: &cancellables)

        refreshEligibility()
    }

    func refreshEligibility() {
        let eligible = !cardsProvider.cards.isEmpty
        eligibilitySubject.send(eligible)
    }

    @MainActor
    func show(history: PromoHistoryRecord) async -> PromoResult {
        if appearancePreferences.continueSetUpCardsClosed {
            return .ignored()
        }
        return await withCheckedContinuation { cont in
            continuation = cont
        }
    }

    @MainActor
    func hide() {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: .noChange)
    }

    private func handleContinueSetUpCardsClosed(_ closed: Bool) {
        guard closed else { return }
        guard let cont = continuation else { return }
        continuation = nil
        promoService?.dismiss(promoId: "next-steps-cards", result: .ignored())
        Task { @MainActor in
            cont.resume(returning: .ignored())
        }
    }
}

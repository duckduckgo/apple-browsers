//
//  AutofillEmptyStatePromoDelegate.swift
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
import FeatureFlags_macOS
import Foundation
import PrivacyConfig

protocol AutofillEmptyStatePromoPresenting: AnyObject {
    var isPromoActive: Bool { get }
    var isPromoActivePublisher: AnyPublisher<Bool, Never> { get }
}

/// Shows the import/sync CTAs of the Passwords panel empty states through the promo queue.
final class AutofillEmptyStatePromoDelegate: InternalPromoDelegate, AutofillEmptyStatePromoPresenting {

    private let featureFlagger: FeatureFlagger
    private let isAnyCategoryEmptyProvider: () -> Bool
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)
    private let isPromoActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private let eligibilityQueue = DispatchQueue(label: "com.duckduckgo.autofillEmptyStatePromo.eligibility", qos: .utility)
    private var cancellables = Set<AnyCancellable>()

    /// - Parameter isAnyCategoryEmptyProvider: Whether passwords, identities or credit cards has no items.
    ///   Must be synchronous and safe to call off the main thread.
    init(featureFlagger: FeatureFlagger,
         isAnyCategoryEmptyProvider: @escaping () -> Bool) {
        self.featureFlagger = featureFlagger
        self.isAnyCategoryEmptyProvider = isAnyCategoryEmptyProvider

        featureFlagger.updatesPublisher
            .receive(on: eligibilityQueue)
            .sink { [weak self] in
                self?.refreshEligibility()
            }
            .store(in: &cancellables)
    }

    // MARK: - Promo queue eligibility

    var isEligible: Bool {
        isEligibleSubject.value
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func refreshEligibility() {
        isEligibleSubject.send(featureFlagger.isFeatureOn(.promoQueueAutofillEmptyStatePromo) && isAnyCategoryEmptyProvider())
    }

    // MARK: - Promo queue display

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        resolve(with: .noChange)
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
            isPromoActiveSubject.send(true)
        }
    }

    @MainActor
    func hide() {
        resolve(with: .noChange)
    }

    var isPromoActive: Bool {
        isPromoActiveSubject.value
    }

    var isPromoActivePublisher: AnyPublisher<Bool, Never> {
        isPromoActiveSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    private func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        isPromoActiveSubject.send(false)
        continuation.resume(returning: result)
    }
}

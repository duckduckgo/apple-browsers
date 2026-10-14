//
//  BookmarksEmptyStatePromoDelegate.swift
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

protocol BookmarksEmptyStatePromoPresenting: AnyObject {
    var isPromoActivePublisher: AnyPublisher<Bool, Never> { get }
}

/// Shows the message and import/sync CTAs of the "No bookmarks yet" empty state through the promo queue.
final class BookmarksEmptyStatePromoDelegate: InternalPromoDelegate, BookmarksEmptyStatePromoPresenting {

    private let featureFlagger: FeatureFlagger
    private let hasTopLevelEntitiesProvider: () -> Bool
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)
    private let isPromoActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private let eligibilityQueue = DispatchQueue(label: "com.duckduckgo.bookmarksEmptyStatePromo.eligibility", qos: .utility)
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - hasTopLevelEntitiesProvider: Must be synchronous and safe to call off the main thread.
    ///   - bookmarksChangedPublisher: Emits whenever bookmarks are added or removed.
    init(featureFlagger: FeatureFlagger,
         hasTopLevelEntitiesProvider: @escaping () -> Bool,
         bookmarksChangedPublisher: AnyPublisher<Void, Never>) {
        self.featureFlagger = featureFlagger
        self.hasTopLevelEntitiesProvider = hasTopLevelEntitiesProvider

        featureFlagger.updatesPublisher
            .merge(with: bookmarksChangedPublisher)
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
        isEligibleSubject.send(featureFlagger.isFeatureOn(.promoQueueBookmarksEmptyStatePromo) && !hasTopLevelEntitiesProvider())
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

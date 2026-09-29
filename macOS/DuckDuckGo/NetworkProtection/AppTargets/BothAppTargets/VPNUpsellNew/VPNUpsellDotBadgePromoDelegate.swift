//
//  VPNUpsellDotBadgePromoDelegate.swift
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
import PrivacyConfig

/// Shows the notification dot on the VPN upsell toolbar button through the promo queue.
final class VPNUpsellDotBadgePromoDelegate: InternalPromoDelegate {

    private let featureFlagger: FeatureFlagger
    private let visibilityManager: VPNUpsellVisibilityManager
    private let persistor: VPNUpsellUserDefaultsPersisting
    private let dateProvider: () -> Date
    private let eligibilitySubject = CurrentValueSubject<Bool, Never>(false)
    private let isShowingSubject = CurrentValueSubject<Bool, Never>(false)
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(featureFlagger: FeatureFlagger,
         visibilityManager: VPNUpsellVisibilityManager,
         persistor: VPNUpsellUserDefaultsPersisting,
         dateProvider: @escaping () -> Date = Date.init) {
        self.featureFlagger = featureFlagger
        self.visibilityManager = visibilityManager
        self.persistor = persistor
        self.dateProvider = dateProvider

        let isFlagOn = { featureFlagger.isFeatureOn(.promoQueueVPNUpsellPromo) }
        Publishers.CombineLatest(
            featureFlagger.updatesPublisher.map { _ in isFlagOn() }.prepend(isFlagOn()),
            visibilityManager.$state.map { $0 == .eligible }
        )
        .map { $0 && $1 }
        .removeDuplicates()
        .sink { [eligibilitySubject] in eligibilitySubject.send($0) }
        .store(in: &cancellables)
    }

    var isEligible: Bool {
        eligibilitySubject.value
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        eligibilitySubject.removeDuplicates().eraseToAnyPublisher()
    }

    var isShowingPublisher: AnyPublisher<Bool, Never> {
        isShowingSubject.removeDuplicates().eraseToAnyPublisher()
    }

    @MainActor
    func hide() {
        isShowingSubject.send(false)
        resume(with: .noChange)
    }

    @MainActor
    func handlePinningChange(isPinned: Bool) {
        guard resultContinuation != nil, !isPinned else { return }
        resume(with: .ignored())
    }

    private func resume(with result: PromoResult) {
        isShowingSubject.send(false)
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        continuation.resume(returning: result)
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        if !force, persistor.legacyPopoverViewed || persistor.isLegacyUpsellFinished(asOf: dateProvider()) {
            return .retired
        }

        isShowingSubject.send(true)

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    @MainActor
    func buttonClicked() {
        guard resultContinuation != nil else { return }
        resume(with: .actioned)
    }
}

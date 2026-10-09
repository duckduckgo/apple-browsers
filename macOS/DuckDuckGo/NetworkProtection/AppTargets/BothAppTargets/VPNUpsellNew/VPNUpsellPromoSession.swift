//
//  VPNUpsellPromoSession.swift
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

/// Mechanics shared by the VPN upsell Promo Queue delegates: the eligibility pipeline and a suspend-until-resolved show lifecycle.
///
/// Deliberately not `@MainActor` at type level: `isEligible` is read from PromoService's background queue.
final class VPNUpsellPromoSession {

    private let eligibilitySubject = CurrentValueSubject<Bool, Never>(false)
    private let isShowingSubject = CurrentValueSubject<Bool, Never>(false)
    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(featureFlagger: FeatureFlagger, visibilityManager: VPNUpsellVisibilityManager) {
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
    var isActive: Bool {
        resultContinuation != nil
    }

    @MainActor
    func begin() async -> PromoResult {
        // A continuation that is overwritten without being resumed would leak its awaiting task.
        resolve(.noChange)
        isShowingSubject.send(true)
        return await withCheckedContinuation { resultContinuation = $0 }
    }

    @MainActor
    func resolve(_ result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        isShowingSubject.send(false)
        continuation.resume(returning: result)
    }

    @MainActor
    func end() {
        isShowingSubject.send(false)
        resolve(.noChange)
    }
}

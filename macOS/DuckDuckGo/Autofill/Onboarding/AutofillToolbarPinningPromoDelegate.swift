//
//  AutofillToolbarPinningPromoDelegate.swift
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

/// Presents the "Add passwords shortcut?" popover on behalf of the promo queue.
///
/// Implemented by `NavigationBarViewController` because presentation depends on state only it owns:
/// it is the popover's `NSPopoverDelegate`, and anchoring un-hides the password button that is
/// otherwise hidden whenever autofill is unpinned — which is always the case when this promo shows.
@MainActor
protocol AutofillToolbarPinningPromoPresenting: AnyObject {
    func presentAutofillToolbarPinningPromo(completion: @escaping (PromoResult) -> Void)
    func retractAutofillToolbarPinningPromo()
}

/// Offers to pin the passwords shortcut to the toolbar right after the user saves their first password
final class AutofillToolbarPinningPromoDelegate: InternalPromoDelegate {

    private let featureFlagger: FeatureFlagger
    private let pinningManager: PinningManager
    private let presenterProvider: @MainActor () -> AutofillToolbarPinningPromoPresenting?
    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)

    init(featureFlagger: FeatureFlagger,
         pinningManager: PinningManager,
         presenterProvider: @escaping @MainActor () -> AutofillToolbarPinningPromoPresenting?) {
        self.featureFlagger = featureFlagger
        self.pinningManager = pinningManager
        self.presenterProvider = presenterProvider
    }

    var isEligible: Bool { computeEligibility() }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func refreshEligibility() {
        isEligibleSubject.send(computeEligibility())
    }

    private func computeEligibility() -> Bool {
        featureFlagger.isFeatureOn(.promoQueueAutofillToolbarPinningPromo)
            && !pinningManager.isPinned(.autofill)
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let presenter = presenterProvider() else {
            return .noChange
        }

        return await withCheckedContinuation { continuation in
            resume(with: .noChange)
            showContinuation = continuation

            presenter.presentAutofillToolbarPinningPromo { [weak self] result in
                self?.resume(with: result)
            }
        }
    }

    @MainActor
    func hide() {
        presenterProvider()?.retractAutofillToolbarPinningPromo()
        resume(with: .noChange)
    }
}

private extension AutofillToolbarPinningPromoDelegate {

    func resume(with result: PromoResult) {
        showContinuation?.resume(returning: result)
        showContinuation = nil
    }
}

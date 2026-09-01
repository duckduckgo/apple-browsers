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

/// Offers to pin the passwords shortcut to the toolbar right after the user saves their first password
/// (migrated from the standalone `showPasswordsPinningOption` notification observer that
/// `NavigationBarViewController` used to own).
final class AutofillToolbarPinningPromoDelegate: InternalPromoDelegate {

    private let featureFlagger: FeatureFlagger
    private let pinningManager: PinningManager
    private let presenterProvider: @MainActor () -> AutofillToolbarPinningPromoPresenting?
    private var showContinuation: CheckedContinuation<PromoResult, Never>?

    /// Guards `hasResolvedCurrentShow`, which is written on the main actor by `show`/`hide`/`resume`
    /// but read on whatever thread delivers an eligibility notification to `isEligiblePublisher`.
    private let lock = NSLock()
    private var _hasResolvedCurrentShow = false

    /// True once the current show has produced a result. While set, eligibility retractions are
    /// swallowed: see `isEligiblePublisher`.
    private var hasResolvedCurrentShow: Bool {
        get { lock.withLock { _hasResolvedCurrentShow } }
        set { lock.withLock { _hasResolvedCurrentShow = newValue } }
    }

    init(featureFlagger: FeatureFlagger,
         pinningManager: PinningManager,
         presenterProvider: @escaping @MainActor () -> AutofillToolbarPinningPromoPresenting?) {
        self.featureFlagger = featureFlagger
        self.pinningManager = pinningManager
        self.presenterProvider = presenterProvider
    }

    var isEligible: Bool {
        featureFlagger.isFeatureOn(.promoQueueAutofillToolbarPinningPromo)
            && !pinningManager.isPinned(.autofill)
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        Publishers.Merge(
            featureFlagger.updatesPublisher.map { _ in () },
            NotificationCenter.default.publisher(for: .PinnedViewsChanged).map { _ in () }
        )
        .compactMap { [weak self] _ -> Bool? in
            guard let self else { return false }
            // Once the user has acted, a retraction is meaningless — and actively harmful here.
            // Accepting the CTA pins autofill, `LocalPinningManager` posts `.PinnedViewsChanged`
            // synchronously, and the resulting `false` would reach `PromoService` ahead of the
            // `.actioned` result the resumed continuation is still on its way to deliver. The queue
            // records first-write-wins, so the promo's success would be filed as a no-op.
            guard !hasResolvedCurrentShow else { return nil }
            return isEligible
        }
        .prepend(isEligible)
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let presenter = presenterProvider() else {
            return .noChange
        }

        return await withCheckedContinuation { continuation in
            // The debug menu's `forceShow` skips the "no active session" guard that trigger
            // evaluation applies, so `show()` can be re-entered while a continuation is live.
            // Overwriting an unresumed continuation traps, so end the previous show first.
            resume(with: .noChange)
            hasResolvedCurrentShow = false
            showContinuation = continuation

            presenter.presentAutofillToolbarPinningPromo { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .actioned(let pin):
                    // `resume` marks the show resolved before the pin lands, which is what stops
                    // our own `.PinnedViewsChanged` from being read as a retraction.
                    resume(with: .actioned)
                    if pin {
                        pinningManager.pin(.autofill)
                    }
                case .dismissed:
                    resume(with: .ignored())
                case .notPresented:
                    resume(with: .noChange)
                }
            }
        }
    }

    @MainActor
    func hide() {
        presenterProvider()?.dismissAutofillToolbarPinningPromo()
        resume(with: .noChange)
        // The session is over, so a later show starts with retractions enabled again.
        hasResolvedCurrentShow = false
    }
}

private extension AutofillToolbarPinningPromoDelegate {

    func resume(with result: PromoResult) {
        hasResolvedCurrentShow = true
        showContinuation?.resume(returning: result)
        showContinuation = nil
    }
}

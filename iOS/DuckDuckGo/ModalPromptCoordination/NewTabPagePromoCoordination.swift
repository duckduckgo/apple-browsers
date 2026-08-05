//
//  NewTabPagePromoCoordination.swift
//  DuckDuckGo
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

enum VisiblePromoAdmissionResult {
    /// Admitted: the caller owns the lease and must release it.
    case acquired(PromoQueueVisiblePromoLease)
    /// A coordinated modal attempt owns the slot.
    case blockedByModal
    /// The requesting surface's `(surfaceID, promoType)` slot already holds a lease; carries the occupying identity.
    case occupiedSurfaceSlot(VisiblePromoIdentity)
    /// The `promoPresentationCoordination` flag is off, so admission is not arbitrated.
    case featureDisabled
    /// A flag transition barrier is up; the caller should retry after the transition.
    case unavailableDuringTransition
}

typealias VisiblePromoAdmissionHandler = @MainActor (VisiblePromoIdentity) -> VisiblePromoAdmissionResult

/// A mounted NTP surface that can refresh and retry its retained visible-promo candidate.
@MainActor
protocol NewTabPagePromoRetrying: AnyObject {
    var isActiveForPromoRetry: Bool { get }

    /// Refreshes the retained candidate and retries it through the admission route supplied by the coordination owner.
    ///
    /// The handler is synchronous and nonescaping so the coordination owner controls admission for the entire retry.
    func retryVisiblePromoAdmission(using admissionHandler: VisiblePromoAdmissionHandler)
    func promoQueueWillTransition(to targetState: PromoQueueFeatureTargetState)
    func promoQueueDidTransition(to targetState: PromoQueueFeatureTargetState)
}

extension NewTabPagePromoRetrying {
    func promoQueueWillTransition(to targetState: PromoQueueFeatureTargetState) {}
    func promoQueueDidTransition(to targetState: PromoQueueFeatureTargetState) {}
}

/// An idempotently removable registration for NTP visible-promo retries.
@MainActor
final class NewTabPagePromoRetryRegistration {
    private var deregistrationHandler: (@MainActor () -> Void)?

    init(deregistrationHandler: (@MainActor () -> Void)? = nil) {
        self.deregistrationHandler = deregistrationHandler
    }

    func deregister() {
        let deregistrationHandler = deregistrationHandler
        self.deregistrationHandler = nil
        deregistrationHandler?()
    }
}

/// Coordinates NTP visible-promo admission, lease release, and retry registration.
@MainActor
protocol NewTabPagePromoCoordinating: AnyObject {
    var promoQueueFeatureState: PromoQueueFeatureState { get }
    /// Emits the current state on subscription, followed by serialized transition states. Stable states are emitted
    /// only after their transition barrier has been lowered.
    var promoQueueFeatureStatePublisher: AnyPublisher<PromoQueueFeatureState, Never> { get }

    func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult
    func releaseVisiblePromoLease(_ lease: PromoQueueVisiblePromoLease)
    func registerVisiblePromoRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration
}

extension NewTabPagePromoCoordinating {
    var promoQueueFeatureStatePublisher: AnyPublisher<PromoQueueFeatureState, Never> {
        Just(promoQueueFeatureState).eraseToAnyPublisher()
    }
}

/// Emits when promo coordination reaches enabled after the initial feature-state value.
func promoQueueEnablementPublisher(
    _ featureStatePublisher: AnyPublisher<PromoQueueFeatureState, Never>
) -> AnyPublisher<Void, Never> {
    featureStatePublisher
        .removeDuplicates()
        .dropFirst()
        .filter { $0 == .enabled }
        .map { _ in () }
        .eraseToAnyPublisher()
}

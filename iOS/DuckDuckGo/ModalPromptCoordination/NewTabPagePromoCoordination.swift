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

import Foundation

enum VisiblePromoAdmissionResult {
    /// Admitted: the caller owns the lease and must release it.
    case acquired(PromoQueueVisiblePromoLease)
    /// A coordinated modal attempt owns the slot.
    case blockedByModal
    /// The requesting surface's `(surfaceID, promoType)` slot already holds a lease; carries the occupying identity.
    case occupiedSurfaceSlot(VisiblePromoIdentity)
    /// This process selected legacy mode at construction, so admission is not arbitrated.
    case featureDisabled
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
    var promoCoordinationMode: PromoCoordinationMode { get }

    func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult
    func releaseVisiblePromoLease(_ lease: PromoQueueVisiblePromoLease)
    func registerVisiblePromoRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration
}

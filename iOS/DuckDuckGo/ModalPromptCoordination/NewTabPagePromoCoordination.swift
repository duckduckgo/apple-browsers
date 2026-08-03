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
    /// The `promoPresentationCoordination` flag is off, so admission is not arbitrated.
    case featureDisabled
    /// A flag transition barrier is up; the caller should retry after the transition.
    case unavailableDuringTransition
}

typealias VisiblePromoAdmissionHandler = @MainActor (VisiblePromoIdentity) -> VisiblePromoAdmissionResult

@MainActor
protocol NewTabPagePromoRetrying: AnyObject {
    var isActiveForPromoRetry: Bool { get }

    /// Refreshes the retained candidate and retries it through the admission route supplied by the coordination owner.
    ///
    /// The handler is synchronous and nonescaping so a feature transition can grant admission only to its own retry
    /// pass while the public admission barrier remains active.
    func retryVisiblePromoAdmission(using admissionHandler: VisiblePromoAdmissionHandler)
}

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

@MainActor
protocol NewTabPagePromoCoordinating: AnyObject {
    var promoQueueFeatureState: PromoQueueFeatureState { get }

    func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult
    func releaseVisiblePromoLease(_ lease: PromoQueueVisiblePromoLease)
    func registerVisiblePromoRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration
}

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

enum PromoQueueRemoteMessageAdmissionResult {
    /// Admitted: the caller owns the identity-bound admission and must release it.
    case acquired(PromoQueueRemoteMessageAdmission)
    /// The retained candidate can be reconsidered at a later checkpoint.
    case deferred
}

/// Strongly owns one raw visible lease and releases it at most once. Q2 deliberately records no appearance history.
@MainActor
final class PromoQueueRemoteMessageAdmission {
    private enum State {
        case active
        case released
    }

    private var state = State.active
    private let releaseHandler: () -> Void

    init(releaseHandler: @escaping () -> Void) {
        self.releaseHandler = releaseHandler
    }

    func release() {
        guard case .active = state else {
            return
        }

        state = .released
        releaseHandler()
    }
}

typealias PromoQueueRemoteMessageAdmissionHandler = @MainActor (VisiblePromoIdentity) -> PromoQueueRemoteMessageAdmissionResult

/// A mounted NTP surface that can refresh and retry its retained remote-message candidate.
@MainActor
protocol NewTabPagePromoRetrying: AnyObject {
    var isActiveForPromoRetry: Bool { get }

    /// Refreshes the retained candidate and retries it through the admission route supplied by the coordination owner.
    ///
    /// The handler is synchronous and nonescaping so the coordination owner controls admission for the entire retry.
    func retryRemoteMessageAdmission(using admissionHandler: PromoQueueRemoteMessageAdmissionHandler)
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

/// Coordinates NTP remote-message admission and retry registration.
@MainActor
protocol NewTabPagePromoCoordinating: AnyObject {
    var promoCoordinationMode: PromoCoordinationMode { get }

    func admitRemoteMessage(_ identity: VisiblePromoIdentity) -> PromoQueueRemoteMessageAdmissionResult
    func registerRemoteMessageRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration
}

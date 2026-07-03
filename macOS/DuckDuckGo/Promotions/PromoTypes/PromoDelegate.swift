//
//  PromoDelegate.swift
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

/// Base protocol for all promo delegates. Used as the type-erased delegate type on `Promo`.
///
/// Conform to `InternalPromoDelegate` for promos that PromoService controls (show, hide, eligibility).
/// Conform to `ExternalPromoDelegate` for promos whose visibility is controlled by an external
/// system (e.g. Remote Messaging Framework); PromoService only observes their visibility.
protocol PromoDelegate: AnyObject { }

/// Delegate for promos that PromoService controls.
///
/// PromoService evaluates triggers, checks eligibility, and calls `show()` / `hide()` to manage
/// visibility. The delegate provides eligibility state and implements the UI for showing and hiding.
/// Conformances are set on `Promo` structs when feature modules are ready.
protocol InternalPromoDelegate: PromoDelegate {
    /// Current eligibility state. Use isEligiblePublisher to observe changes.
    var isEligible: Bool { get }

    /// Publisher indicating whether this promo is currently eligible.
    /// Must emit a current value immediately on subscription (use CurrentValueSubject).
    var isEligiblePublisher: AnyPublisher<Bool, Never> { get }

    /// Called by PromoService before reading `isEligible` to give the delegate
    /// a chance to recompute its eligibility state. Default: no-op.
    func refreshEligibility()

    /// Shows the promo. Returns when user interacts, promo retracts, or hide() is called.
    /// Receives the promo's own history for result decisions (e.g. varying cooldown by timesDismissed).
    /// Use `force` to force show the promo (for debug menu).
    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult

    /// Hides the promo. Must be idempotent.
    /// PromoService calls hide() after recording any result, so a delegate that has
    /// already hidden its own UI will receive a second hide() that should be a no-op.
    @MainActor
    func hide()
}

extension InternalPromoDelegate {
    func refreshEligibility() { }
}

/// Delegate for promos whose visibility is controlled outside PromoService.
///
/// PromoService subscribes to `isVisiblePublisher` to observe visibility, record history, and apply
/// global cooldowns—it never calls `show()` or `hide()`.
protocol ExternalPromoDelegate: PromoDelegate {
    /// Current visibility state. Use isVisiblePublisher to observe changes.
    var isVisible: Bool { get }

    /// Publisher indicating whether this promo is currently visible.
    /// Must emit a current value immediately on subscription (use CurrentValueSubject).
    var isVisiblePublisher: AnyPublisher<Bool, Never> { get }

    /// Result to apply when the external promo is hidden.
    var resultWhenHidden: PromoResult { get }
}

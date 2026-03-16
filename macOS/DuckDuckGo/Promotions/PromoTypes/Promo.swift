//
//  Promo.swift
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

/// Static metadata for a promo. Priority is defined by array order when passed to PromoService.
struct Promo {
    /// Unique identifier
    let id: String

    /// Which trigger(s) this promo responds to
    let triggers: Set<PromoTrigger>

    /// How this promo was initiated and its cooldown
    let initiated: PromoInitiated

    /// Display metadata (severity, timeout)
    let promoType: PromoType

    /// Where this promo appears
    let context: PromoContext

    /// IDs of promos that can be visible simultaneously with this one.
    /// Promos can appear together when all visible promos that would conflict
    /// are in this set and this promo is in all of theirs (mutual coexistence).
    /// This should be used only in very rare cases that are pre-validated (e.g. with a PFR).
    /// Default: empty (no coexistence exceptions).
    let coexistingPromoIDs: Set<String>

    /// When false, this promo can show even if the global cooldown for its PromoInitiated type hasn't elapsed.
    /// Default: true.
    let respectsGlobalCooldown: Bool

    /// When false, dismissing this promo does not count toward the global cooldown for its PromoInitiated type.
    /// Default: true.
    let setsGlobalCooldown: Bool

    /// Provides dynamic promo behavior (eligibility, show, hide).
    /// Delegate should be set by feature module when their dependencies are ready.
    var delegate: (any AnyPromoDelegate)?

    init(id: String,
         triggers: Set<PromoTrigger>,
         initiated: PromoInitiated,
         promoType: PromoType,
         context: PromoContext,
         coexistingPromoIDs: Set<String> = [],
         respectsGlobalCooldown: Bool = true,
         setsGlobalCooldown: Bool = true,
         delegate: (any AnyPromoDelegate)? = nil) {
        self.id = id
        self.triggers = triggers
        self.initiated = initiated
        self.promoType = promoType
        self.context = context
        self.coexistingPromoIDs = coexistingPromoIDs
        self.respectsGlobalCooldown = respectsGlobalCooldown
        self.setsGlobalCooldown = setsGlobalCooldown
        self.delegate = delegate
    }
}

/// Base protocol for all promo delegates. Used as the type-erased delegate type on `Promo`.
///
/// Conform to `PromoDelegate` for promos that PromoService controls (show, hide, eligibility).
/// Conform to `ExternalPromoDelegate` for promos whose visibility is controlled by an external
/// system (e.g. Remote Messaging Framework); PromoService only observes their visibility.
protocol AnyPromoDelegate: AnyObject { }

/// Delegate for promos that PromoService controls. Use this for most promos.
///
/// PromoService evaluates triggers, checks eligibility, and calls `show()` / `hide()` to manage
/// visibility. The delegate provides eligibility state and implements the UI for showing and hiding.
/// Conformances are set on `Promo` structs when feature modules are ready.
protocol PromoDelegate: AnyPromoDelegate {
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

extension PromoDelegate {
    func refreshEligibility() { }
}

/// Delegate for promos whose visibility is controlled outside PromoService.
///
/// Use when another system (e.g. Remote Messaging Framework) decides when to show or hide the promo.
/// PromoService subscribes to `isVisiblePublisher` to observe visibility, record history, and apply
/// global cooldowns—it never calls `show()` or `hide()`. Use sparingly; most promos should conform
/// to `PromoDelegate` instead.
protocol ExternalPromoDelegate: AnyPromoDelegate {
    /// Current visibility state. Use isVisiblePublisher to observe changes.
    var isVisible: Bool { get }

    /// Publisher indicating whether this promo is currently visible.
    /// Must emit a current value immediately on subscription (use CurrentValueSubject).
    var isVisiblePublisher: AnyPublisher<Bool, Never> { get }

    /// Result to apply when the external promo is hidden.
    var resultWhenHidden: PromoResult { get }
}

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
protocol Promo {
    /// Unique identifier
    var id: String { get }

    /// Which trigger(s) this promo responds to
    var triggers: Set<PromoTrigger> { get }

    /// How this promo was initiated and its cooldown
    var initiated: PromoInitiated { get }

    /// Display metadata (severity, timeout)
    var promoType: PromoType { get }

    /// Where this promo appears
    var context: PromoContext { get }

    /// IDs of promos that can be visible simultaneously with this one.
    ///
    /// Promos can appear together when all visible promos that would conflict
    /// are in this set and this promo is in all of theirs (mutual coexistence).
    /// This should be used only in very rare cases that are pre-validated (e.g. with a PFR).
    /// External promos can always coexist with each other, but must use this property to coexist with internal promos.
    /// Default: empty (no coexistence exceptions).
    var coexistingPromoIDs: Set<String> { get }

    /// When false, this promo can show even if the global cooldown for its PromoInitiated type hasn't elapsed.
    /// Default: true for internal promos; false for external promos.
    var respectsGlobalCooldown: Bool { get }

    /// When false, dismissing this promo does not count toward the global cooldown for its PromoInitiated type.
    /// Default: true.
    var setsGlobalCooldown: Bool { get }

    /// Provides dynamic promo behavior (eligibility, show, hide).
    /// Delegate should be set by feature module when their dependencies are ready.
    var delegate: (any PromoDelegate)? { get set }
}

/// Static metadata for an internal promo. Use this for most promos.
///
/// Internal promo visibility is managed by `PromoService` based on triggers and eligibility.
struct InternalPromo: Promo {
    let id: String
    let triggers: Set<PromoTrigger>
    let initiated: PromoInitiated
    let promoType: PromoType
    let context: PromoContext
    let coexistingPromoIDs: Set<String>
    let respectsGlobalCooldown: Bool
    let setsGlobalCooldown: Bool

    var delegate: (any PromoDelegate)?

    init(id: String,
         triggers: Set<PromoTrigger>,
         initiated: PromoInitiated,
         promoType: PromoType,
         context: PromoContext,
         coexistingPromoIDs: Set<String> = [],
         respectsGlobalCooldown: Bool = true,
         setsGlobalCooldown: Bool = true,
         delegate: InternalPromoDelegate? = nil) {
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

/// Static metadata for an external promo, whose visibility is controlled outside PromoService.
///
/// Use when another system (e.g. Remote Messaging Framework) decides when to show or hide the promo.
/// `PromoService` observes the promo's visibility and uses it to manage internal promos.
/// Use sparingly; most promos should use `InternalPromo` instead.
struct ExternalPromo: Promo {
    let id: String
    let initiated: PromoInitiated
    let promoType: PromoType
    let context: PromoContext
    let coexistingPromoIDs: Set<String>
    let setsGlobalCooldown: Bool

    /// External promos show themselves without PromoService triggers
    let triggers: Set<PromoTrigger> = []

    /// External promos control when they will show; they don't respect PromoService cooldowns
    let respectsGlobalCooldown: Bool = false

    var delegate: (any PromoDelegate)?

    init(id: String,
         initiated: PromoInitiated,
         promoType: PromoType,
         context: PromoContext,
         coexistingPromoIDs: Set<String> = [],
         setsGlobalCooldown: Bool = true,
         delegate: ExternalPromoDelegate? = nil) {
        self.id = id
        self.initiated = initiated
        self.promoType = promoType
        self.context = context
        self.coexistingPromoIDs = coexistingPromoIDs
        self.setsGlobalCooldown = setsGlobalCooldown
        self.delegate = delegate
    }
}

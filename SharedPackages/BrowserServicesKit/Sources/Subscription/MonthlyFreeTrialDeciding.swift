//
//  MonthlyFreeTrialDeciding.swift
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

/// Decides whether the monthly subscription plans should be offered with a free trial.
///
/// The decision is queried at the point the paywall products are requested, so it can reflect
/// experiment cohort assignment made at that moment rather than a value frozen earlier.
public protocol MonthlyFreeTrialDeciding {
    func shouldOfferMonthlyFreeTrial() -> Bool
}

/// A decider that always offers the monthly free trial (the current, pre-experiment behavior).
///
/// Intended for contexts that never present the paywall — e.g. app extensions, or the shared
/// subscription configuration used across many targets — which need to satisfy the API but never
/// consult the decision. The cohort-aware deciders live in the app targets that actually run the
/// experiment.
public struct DefaultMonthlyFreeTrialDecider: MonthlyFreeTrialDeciding {

    public init() {}

    public func shouldOfferMonthlyFreeTrial() -> Bool {
        true
    }
}

extension MonthlyFreeTrialDeciding {

    /// Filters products according to the current monthly free-trial decision.
    ///
    /// See the identifier-based overload for the filtering rule; this simply applies it to a set of
    /// products, keeping only those whose identifier survives.
    func filteringMonthlyFreeTrialPreference(from products: [any SubscriptionProduct]) -> [any SubscriptionProduct] {
        let allowedIdentifiers = Set(filteringMonthlyFreeTrialPreference(from: products.map(\.id)))
        return products.filter { allowedIdentifiers.contains($0.id) }
    }

    /// Filters product identifiers according to the current monthly free-trial decision.
    ///
    /// A monthly identifier is only filtered out when the opposite free-trial variant of the *same* plan
    /// is also present. In that case only the variant matching `shouldOfferMonthlyFreeTrial()` survives.
    /// A monthly identifier without a matching sibling, and every non-monthly identifier, passes through
    /// unchanged — so a lone monthly plan is never hidden.
    func filteringMonthlyFreeTrialPreference(from identifiers: [String]) -> [String] {
        let offerMonthlyFreeTrial = shouldOfferMonthlyFreeTrial()

        return identifiers.filter { identifier in
            guard identifier.isMonthlySubscriptionIdentifier else { return true }

            let planKey = identifier.trialAgnosticMonthlyIdentifier
            let hasOppositeTrialSibling = identifiers.contains { other in
                other != identifier
                    && other.isMonthlySubscriptionIdentifier
                    && other.trialAgnosticMonthlyIdentifier == planKey
                    && other.includesFreeTrial != identifier.includesFreeTrial
            }

            guard hasOppositeTrialSibling else { return true }

            return offerMonthlyFreeTrial ? identifier.includesFreeTrial : !identifier.includesFreeTrial
        }
    }
}

private extension String {

    var isMonthlySubscriptionIdentifier: Bool {
        let components = split(separator: ".")
        return components.contains("monthly") || components.contains("1month")
    }

    var includesFreeTrial: Bool {
        split(separator: ".").contains { $0 == StoreSubscriptionConstants.freeTrialIdentifer }
    }

    /// The identifier with any free-trial marker removed, so a free-trial plan and its no-trial
    /// counterpart resolve to the same key (e.g. `…monthly.renews.us.freetrial` and
    /// `…monthly.renews.us`, or `…1month.freetrial.dev.pro` and `…1month.dev.pro`).
    var trialAgnosticMonthlyIdentifier: String {
        split(separator: ".")
            .filter { $0 != StoreSubscriptionConstants.freeTrialIdentifer }
            .joined(separator: ".")
    }
}

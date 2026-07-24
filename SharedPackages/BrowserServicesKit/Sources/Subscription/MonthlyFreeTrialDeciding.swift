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

/// Determines whether monthly subscriptions should include a free trial.
public protocol MonthlyFreeTrialDeciding {
    func shouldOfferMonthlyFreeTrial() -> Bool
}

/// Always offers the monthly free trial.
public struct DefaultMonthlyFreeTrialDecider: MonthlyFreeTrialDeciding {

    public init() {}

    public func shouldOfferMonthlyFreeTrial() -> Bool {
        true
    }
}

extension MonthlyFreeTrialDeciding {

    func filteringMonthlyFreeTrialPreference(from products: [any SubscriptionProduct]) -> [any SubscriptionProduct] {
        let allowedIdentifiers = Set(filteringMonthlyFreeTrialPreference(from: products.map(\.id)))
        return products.filter { allowedIdentifiers.contains($0.id) }
    }

    /// Filters paired monthly SKUs down to a single variant based on the trial preference.
    ///
    /// Two monthly identifiers are a "pair" when they're identical except for the `freetrial`
    /// component, e.g. `ios.subscription.1month.freetrial.dev` and `ios.subscription.1month.dev`.
    ///
    /// For each such pair,
    /// * it keeps the free-trial SKU when `shouldOfferMonthlyFreeTrial()` is `true`
    /// * it keeps the 'no-trial' SKU otherwise
    ///
    /// Unpaired identifiers (yearly, weekly, …) pass through unchanged.
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

    /// Removes the free-trial component for SKU matching.
    var trialAgnosticMonthlyIdentifier: String {
        split(separator: ".")
            .filter { $0 != StoreSubscriptionConstants.freeTrialIdentifer }
            .joined(separator: ".")
    }
}

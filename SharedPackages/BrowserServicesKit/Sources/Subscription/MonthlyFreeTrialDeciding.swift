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

/// A pair of interchangeable monthly SKUs for the free-trial experiment.
///
/// `control` is the SKU that includes a free trial; `treatment` is the equivalent SKU without one.
/// Trial eligibility is a StoreKit product property, not encoded in the identifier, so the two are
/// matched explicitly rather than by parsing the identifier string.
struct MonthlyFreeTrialSKUPair {
    let control: String
    let treatment: String
}

extension MonthlyFreeTrialDeciding {

    /// Monthly SKUs swapped based on the experiment cohort. Production IDs to be added.
    static var monthlyFreeTrialSKUPairs: [MonthlyFreeTrialSKUPair] {
        [
            MonthlyFreeTrialSKUPair(control: "ios.subscription.1month.freetrial.dev",
                                    treatment: "ios.subscription.1month"),
            MonthlyFreeTrialSKUPair(control: "ios.subscription.1month.row.freetrial.dev",
                                    treatment: "ios.subscription.1month.row"),
            MonthlyFreeTrialSKUPair(control: "ios.subscription.1month.freetrial.dev.pro",
                                    treatment: "ios.subscription.1month.dev.pro"),
            MonthlyFreeTrialSKUPair(control: "ios.subscription.1month.row.freetrial.dev.pro",
                                    treatment: "ios.subscription.1month.row.dev.pro")
        ]
    }

    func filteringMonthlyFreeTrialPreference(from products: [any SubscriptionProduct]) -> [any SubscriptionProduct] {
        let allowedIdentifiers = Set(filteringMonthlyFreeTrialPreference(from: products.map(\.id)))
        return products.filter { allowedIdentifiers.contains($0.id) }
    }

    /// For each configured SKU pair whose control and treatment variants are both present, keeps the
    /// variant matching the cohort and drops the other. Identifiers not in a pair pass through
    /// unchanged, and a pair with only one variant present is left untouched.
    func filteringMonthlyFreeTrialPreference(from identifiers: [String]) -> [String] {
        let offerMonthlyFreeTrial = shouldOfferMonthlyFreeTrial()
        let present = Set(identifiers)

        let identifiersToRemove = Set(Self.monthlyFreeTrialSKUPairs.compactMap { pair -> String? in
            guard present.contains(pair.control), present.contains(pair.treatment) else { return nil }
            return offerMonthlyFreeTrial ? pair.treatment : pair.control
        })

        return identifiers.filter { !identifiersToRemove.contains($0) }
    }
}

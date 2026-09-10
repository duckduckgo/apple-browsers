//
//  FreemiumDBPPurchaseURLRouter.swift
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
import Subscription

/// How a URL surfaced from the freemium DBP web UI should be handled.
public enum FreemiumDBPPurchaseURLRoute: Equatable {
    /// The URL points at the subscription purchase flow and the user is eligible to purchase.
    /// Carries the components used to seed that flow.
    case subscriptionPurchaseFlow(URLComponents)
    /// The URL should be opened as a normal quick link.
    case quickLink(URL)
}

/// Decides whether a URL opened from the freemium DBP web UI should start the subscription
/// purchase flow or be opened as a quick link.
///
/// Pure and side-effect free: the caller owns the actual navigation (posting a notification,
/// opening a deep link, …) so the routing decision can be unit tested in isolation.
public struct FreemiumDBPPurchaseURLRouter {

    public init() {}

    /// - Parameters:
    ///   - url: the URL requested by the web UI.
    ///   - isPurchaseEligible: whether the user can currently begin a subscription purchase.
    /// - Returns: the route the caller should perform.
    ///
    /// The purchase flow is chosen only when the URL resolves to a known subscription purchase
    /// path *and* the user is eligible to purchase; every other case (non-purchase path,
    /// ineligible user, or an unparseable URL) falls back to opening a quick link.
    public func route(for url: URL, isPurchaseEligible: Bool) -> FreemiumDBPPurchaseURLRoute {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              SubscriptionPurchaseFlowPath.contains(components.path),
              isPurchaseEligible else {
            return .quickLink(url)
        }
        return .subscriptionPurchaseFlow(components)
    }
}

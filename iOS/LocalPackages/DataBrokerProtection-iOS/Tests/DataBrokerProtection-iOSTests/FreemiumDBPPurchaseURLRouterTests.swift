//
//  FreemiumDBPPurchaseURLRouterTests.swift
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

import XCTest
import Subscription
@testable import DataBrokerProtection_iOS

final class FreemiumDBPPurchaseURLRouterTests: XCTestCase {

    private let router = FreemiumDBPPurchaseURLRouter()

    // MARK: - Purchase path + eligible -> subscription purchase flow

    func testWhenURLIsPurchasePathAndUserIsEligibleThenRoutesToSubscriptionPurchaseFlow() {
        let url = URL(string: "https://duckduckgo.com\(SubscriptionPurchaseFlowPath.purchase.rawValue)?origin=funnel")!

        let route = router.route(for: url, isPurchaseEligible: true)

        let expectedComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(route, .subscriptionPurchaseFlow(expectedComponents))
    }

    func testWhenURLIsPlansPathAndUserIsEligibleThenRoutesToSubscriptionPurchaseFlow() {
        let url = URL(string: "https://duckduckgo.com\(SubscriptionPurchaseFlowPath.plans.rawValue)")!

        let route = router.route(for: url, isPurchaseEligible: true)

        let expectedComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(route, .subscriptionPurchaseFlow(expectedComponents))
    }

    // MARK: - Purchase path + not eligible -> quick link

    func testWhenURLIsPurchasePathButUserIsNotEligibleThenRoutesToQuickLink() {
        let url = URL(string: "https://duckduckgo.com\(SubscriptionPurchaseFlowPath.purchase.rawValue)")!

        let route = router.route(for: url, isPurchaseEligible: false)

        XCTAssertEqual(route, .quickLink(url))
    }

    // MARK: - Non-purchase path -> quick link (regardless of eligibility)

    func testWhenURLIsNotAPurchasePathThenRoutesToQuickLinkEvenWhenEligible() {
        let url = URL(string: "https://duckduckgo.com/some/other/page")!

        let route = router.route(for: url, isPurchaseEligible: true)

        XCTAssertEqual(route, .quickLink(url))
    }

    func testWhenURLIsNotAPurchasePathAndUserIsNotEligibleThenRoutesToQuickLink() {
        let url = URL(string: "https://duckduckgo.com/settings")!

        let route = router.route(for: url, isPurchaseEligible: false)

        XCTAssertEqual(route, .quickLink(url))
    }

    // MARK: - Every known purchase path is recognised when eligible

    func testAllKnownPurchasePathsRouteToSubscriptionPurchaseFlowWhenEligible() {
        for path in SubscriptionPurchaseFlowPath.allCases {
            let url = URL(string: "https://duckduckgo.com\(path.rawValue)")!

            let route = router.route(for: url, isPurchaseEligible: true)

            let expectedComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(route,
                           .subscriptionPurchaseFlow(expectedComponents),
                           "Expected purchase flow for path \(path.rawValue)")
        }
    }
}

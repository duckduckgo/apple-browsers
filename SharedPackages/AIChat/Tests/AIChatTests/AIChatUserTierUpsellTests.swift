//
//  AIChatUserTierUpsellTests.swift
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

import AIChat
import XCTest

final class AIChatUserTierUpsellTests: XCTestCase {

    func testWhenFreeUserCanPurchase_ThenUpsellIsAllowed() {
        XCTAssertTrue(AIChatUserTier.free.allowsSubscriptionUpsell(isPurchaseEligible: true))
    }

    func testWhenFreeUserCannotPurchase_ThenUpsellIsNotAllowed() {
        XCTAssertFalse(AIChatUserTier.free.allowsSubscriptionUpsell(isPurchaseEligible: false))
    }

    func testWhenSubscriberCannotPurchase_ThenUpsellIsStillAllowed() {
        for tier in [AIChatUserTier.plus, .pro, .internal] {
            XCTAssertTrue(tier.allowsSubscriptionUpsell(isPurchaseEligible: false), "\(tier)")
        }
    }
}

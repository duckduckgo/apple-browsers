//
//  SubscriptionOnboardingPostCheckoutTriggerTests.swift
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

import XCTest
@testable import DuckDuckGo

/// The rule deciding whether a purchase flow offers post-checkout onboarding.
final class SubscriptionOnboardingPostCheckoutTriggerTests: XCTestCase {

    func testWhenAFirstPurchaseCompletesThenOnboardingIsRequested() {
        XCTAssertTrue(shouldRequest())
    }

    func testWhenTheFlowIsAPlanUpdateThenOnboardingIsNotRequested() {
        XCTAssertFalse(shouldRequest(flowType: .planUpdate))
    }

    /// The restore, email, and plan-update flows are built without a store, which is what keeps them out.
    func testWhenTheFlowHasNoOnboardingStoreThenOnboardingIsNotRequested() {
        XCTAssertFalse(shouldRequest(hasOnboardingStore: false))
    }

    func testWhenTheFeatureIsDisabledThenOnboardingIsNotRequested() {
        XCTAssertFalse(shouldRequest(isFeatureEnabled: false))
    }

    /// A defensive re-invocation of the purchase-completed hook must not re-offer the flow.
    func testWhenOnboardingWasAlreadyRequestedThenItIsNotRequestedAgain() {
        XCTAssertFalse(shouldRequest(didAlreadyRequest: true))
    }

    // MARK: - Helper

    /// Defaults describe the one case that should fire, so each test names only the condition it breaks.
    private func shouldRequest(flowType: SubscriptionFlowType = .firstPurchase,
                               hasOnboardingStore: Bool = true,
                               isFeatureEnabled: Bool = true,
                               didAlreadyRequest: Bool = false) -> Bool {
        SubscriptionFlowViewModel.shouldRequestOnboarding(flowType: flowType,
                                                          hasOnboardingStore: hasOnboardingStore,
                                                          isFeatureEnabled: isFeatureEnabled,
                                                          didAlreadyRequest: didAlreadyRequest)
    }
}

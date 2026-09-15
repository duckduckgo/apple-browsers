//
//  SubscriptionOnboardingWelcomeViewTests.swift
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

@MainActor
final class SubscriptionOnboardingWelcomeViewTests: XCTestCase {

    func testWhenEntitledChecklistIsAllCasesThenWidgetIsDropped() {
        XCTAssertEqual(SubscriptionOnboardingWelcomeView.displayedFeatures(entitledChecklist: SubscriptionOnboardingChecklistItem.allCases),
                       [.vpn, .idtr, .duckAI, .pir])
    }

    /// The entitled checklist is the only gate here — this doesn't re-derive entitlement itself, it trusts
    /// whatever it's handed (e.g. `Progress.checklist`).
    func testWhenEntitledChecklistExcludesAnItemThenItIsNotDisplayed() {
        XCTAssertEqual(SubscriptionOnboardingWelcomeView.displayedFeatures(entitledChecklist: [.vpn, .vpnWidget]),
                       [.vpn])
    }

    func testWhenEntitledChecklistIsEmptyThenNoFeaturesAreDisplayed() {
        XCTAssertTrue(SubscriptionOnboardingWelcomeView.displayedFeatures(entitledChecklist: []).isEmpty)
    }

    func testWhenEntitledChecklistIsOnlyWidgetThenNoFeaturesAreDisplayed() {
        // .vpnWidget alone would only happen for a corrupt/impossible checklist, but the filter shouldn't
        // accidentally let it through.
        XCTAssertTrue(SubscriptionOnboardingWelcomeView.displayedFeatures(entitledChecklist: [.vpnWidget]).isEmpty)
    }

    func testWhenEntitledChecklistIsOnlyVpnTipsThenNoFeaturesAreDisplayed() {
        XCTAssertTrue(SubscriptionOnboardingWelcomeView.displayedFeatures(entitledChecklist: [.vpnTips]).isEmpty)
    }
}

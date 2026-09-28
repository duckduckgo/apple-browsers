//
//  SubscriptionOnboardingSectionTests.swift
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
final class SubscriptionOnboardingSectionTests: XCTestCase {

    // MARK: - Kind mapping

    func testWhenSectionIsAnOverviewThenKindIsOverview() {
        XCTAssertEqual(SubscriptionOnboardingSection.orderConfirmation.kind, .overview)
        XCTAssertEqual(SubscriptionOnboardingSection.welcome.kind, .overview)
    }

    func testWhenSectionIsAnActivationThenKindCarriesItsChecklistItem() {
        XCTAssertEqual(SubscriptionOnboardingSection.vpnActivation.kind, .activation(.vpn))
        XCTAssertEqual(SubscriptionOnboardingSection.vpnWidget.kind, .activation(.vpnWidget))
        XCTAssertEqual(SubscriptionOnboardingSection.vpnTips.kind, .activation(.vpnTips))
        XCTAssertEqual(SubscriptionOnboardingSection.idtr.kind, .activation(.idtr))
        XCTAssertEqual(SubscriptionOnboardingSection.duckAI.kind, .activation(.duckAI))
        XCTAssertEqual(SubscriptionOnboardingSection.pir.kind, .activation(.pir))
    }

    func testWhenSectionIsProgressThenKindIsProgressTracker() {
        XCTAssertEqual(SubscriptionOnboardingSection.progress.kind, .progressTracker)
    }

    func testWhenEnumeratingActivationSectionsThenPIRIsExcluded() {
        XCTAssertEqual(SubscriptionOnboardingSection.activationSections,
                       [.vpnActivation, .vpnWidget, .vpnTips, .idtr, .duckAI])
    }

    // MARK: - Navigation button accessibility

    func testWhenNavigationButtonIsBackThenAccessibilityLabelIsBackLabel() {
        XCTAssertEqual(SubscriptionOnboardingNavigationButton.back({}).accessibilityLabel,
                       UserText.subscriptionOnboardingBackButtonAccessibilityLabel)
    }

    func testWhenNavigationButtonIsCloseThenAccessibilityLabelIsCloseLabel() {
        XCTAssertEqual(SubscriptionOnboardingNavigationButton.close({}).accessibilityLabel,
                       UserText.subscriptionOnboardingCloseButtonAccessibilityLabel)
    }

    func testWhenComparingBackAndCloseNavigationButtonsThenAccessibilityLabelsAreDistinct() {
        XCTAssertNotEqual(SubscriptionOnboardingNavigationButton.back({}).accessibilityLabel,
                          SubscriptionOnboardingNavigationButton.close({}).accessibilityLabel)
    }
}

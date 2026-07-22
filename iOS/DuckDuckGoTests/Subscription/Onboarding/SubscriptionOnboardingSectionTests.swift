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

    func testWhenSectionIsVPNThenKindIsVPNActivation() {
        XCTAssertEqual(SubscriptionOnboardingSection.vpn.kind, .activation(.vpn))
    }

    func testWhenSectionIsDuckAIThenKindIsDuckAIActivation() {
        XCTAssertEqual(SubscriptionOnboardingSection.duckAI.kind, .activation(.duckAI))
    }

    func testSectionsAreExactlyVPNAndDuckAI() {
        XCTAssertEqual(SubscriptionOnboardingSection.allCases, [.vpn, .duckAI])
    }

    // MARK: - View factory

    func testWhenMakingViewForEverySectionThenAViewIsReturned() {
        // The factory must be total — it returns a view for every section without trapping.
        let factory = DefaultSubscriptionOnboardingViewFactory()
        let delegate = SpySectionDelegate()
        let prefetcher = SubscriptionOnboardingPrefetcher()
        for section in SubscriptionOnboardingSection.allCases {
            _ = factory.makeView(for: section, delegate: delegate, prefetcher: prefetcher)
        }
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

    func testBackAndCloseNavigationButtonsHaveDistinctAccessibilityLabels() {
        XCTAssertNotEqual(SubscriptionOnboardingNavigationButton.back({}).accessibilityLabel,
                          SubscriptionOnboardingNavigationButton.close({}).accessibilityLabel)
    }
}

private final class SpySectionDelegate: SubscriptionOnboardingSectionDelegate {
    private(set) var completedSections: [SubscriptionOnboardingSection] = []
    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        completedSections.append(section)
    }
    func sectionDidRequestDuckAIChat(modelID: String?) {}
    func sectionDidRequestAdvance() {}
    func sectionDidRequestGoBack() {}
}

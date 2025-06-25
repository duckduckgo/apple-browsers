//
//  PreferencesSectionTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import SubscriptionUI
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class PreferencesSectionTests: XCTestCase {

    func testNoOptionalItemsArePresentWhenDisabled() throws {
        // Given
        let shouldIncludeDuckPlayer = false
        let shouldIncludeSync = false
        let shouldIncludeAIChat = false
        let subscriptionState = PreferencesSidebarSubscriptionState.initial

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: shouldIncludeDuckPlayer,
                                                          includingSync: shouldIncludeSync,
                                                          includingAIChat: shouldIncludeAIChat,
                                                          subscriptionState: subscriptionState)

        // Then
        let regularPanesSection = sections.first { $0.id ==  .regularPreferencePanes }!
        XCTAssertFalse(regularPanesSection.panes.contains(.duckPlayer))
        XCTAssertFalse(regularPanesSection.panes.contains(.sync))
        XCTAssertFalse(regularPanesSection.panes.contains(.aiChat))
    }

    func testDuckPlayerPaneAddedToRegularSectionWhenEnabled() throws {
        // Given
        let shouldIncludeDuckPlayer = true
        let shouldIncludeSync = false
        let shouldIncludeAIChat = false
        let subscriptionState = PreferencesSidebarSubscriptionState.initial

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: shouldIncludeDuckPlayer,
                                                          includingSync: shouldIncludeSync,
                                                          includingAIChat: shouldIncludeAIChat,
                                                          subscriptionState: subscriptionState)

        // Then
        let regularPanesSection = sections.first { $0.id ==  .regularPreferencePanes }!
        XCTAssertTrue(regularPanesSection.panes.contains(.duckPlayer))
        XCTAssertFalse(regularPanesSection.panes.contains(.sync))
        XCTAssertFalse(regularPanesSection.panes.contains(.aiChat))
    }

    func testSyncPaneAddedToRegularSectionWhenEnabled() throws {
        // Given
        let shouldIncludeDuckPlayer = false
        let shouldIncludeSync = true
        let shouldIncludeAIChat = false
        let subscriptionState = PreferencesSidebarSubscriptionState.initial

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: shouldIncludeDuckPlayer,
                                                          includingSync: shouldIncludeSync,
                                                          includingAIChat: shouldIncludeAIChat,
                                                          subscriptionState: subscriptionState)

        // Then
        let regularPanesSection = sections.first { $0.id ==  .regularPreferencePanes }!
        XCTAssertFalse(regularPanesSection.panes.contains(.duckPlayer))
        XCTAssertTrue(regularPanesSection.panes.contains(.sync))
        XCTAssertFalse(regularPanesSection.panes.contains(.aiChat))
    }

    func testAIChatPaneAddedToRegularSectionWhenEnabled() throws {
        // Given
        let shouldIncludeDuckPlayer = false
        let shouldIncludeSync = false
        let shouldIncludeAIChat = true
        let subscriptionState = PreferencesSidebarSubscriptionState.initial

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: shouldIncludeDuckPlayer,
                                                          includingSync: shouldIncludeSync,
                                                          includingAIChat: shouldIncludeAIChat,
                                                          subscriptionState: subscriptionState)

        // Then
        let regularPanesSection = sections.first { $0.id ==  .regularPreferencePanes }!
        XCTAssertFalse(regularPanesSection.panes.contains(.duckPlayer))
        XCTAssertFalse(regularPanesSection.panes.contains(.sync))
        XCTAssertTrue(regularPanesSection.panes.contains(.aiChat))
    }

    func testNoPrivacyProSectionsArePresentWhenNoSubscriptionAndPurchaseOptions() throws {
        // Given
        let subscriptionState = PreferencesSidebarSubscriptionState(hasSubscription: false,
                                                                    subscriptionFeatures: nil,
                                                                    userEntitlements: [],
                                                                    shouldHideSubscriptionPurchase: true,
                                                                    personalInformationRemovalStatus: .off,
                                                                    identityTheftRestorationStatus: .off,
                                                                    paidAIChatStatus: .off,
                                                                    isPaidAIChatEnabled: false)

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: false,
                                                          includingSync: false,
                                                          includingAIChat: false,
                                                          subscriptionState: subscriptionState)

        // Then
        XCTAssertFalse(sections.contains { $0.id ==  .purchasePrivacyPro })
        XCTAssertFalse(sections.contains { $0.id ==  .privacyPro })
    }

    func testPurchasePrivacyProSectionIsPresentWhenNoSubscription() throws {
        // Given
        let subscriptionState = PreferencesSidebarSubscriptionState(hasSubscription: false,
                                                                    subscriptionFeatures: nil,
                                                                    userEntitlements: [],
                                                                    shouldHideSubscriptionPurchase: false,
                                                                    personalInformationRemovalStatus: .off,
                                                                    identityTheftRestorationStatus: .off,
                                                                    paidAIChatStatus: .off,
                                                                    isPaidAIChatEnabled: false)

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: false,
                                                          includingSync: false,
                                                          includingAIChat: false,
                                                          subscriptionState: subscriptionState)

        // Then
        XCTAssertTrue(sections.contains { $0.id ==  .purchasePrivacyPro })
        XCTAssertFalse(sections.contains { $0.id ==  .privacyPro })

        let purchasePrivacyProSection = sections.first { $0.id ==  .purchasePrivacyPro }!
        XCTAssertEqual(purchasePrivacyProSection.panes, [.privacyPro])
    }

    func testPrivacyProSectionIsPresentWhenHasSubscription() throws {
        // Given
        let features: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]
        let subscriptionState = PreferencesSidebarSubscriptionState(hasSubscription: true,
                                                                    subscriptionFeatures: features,
                                                                    userEntitlements: [],
                                                                    shouldHideSubscriptionPurchase: false,
                                                                    personalInformationRemovalStatus: .off,
                                                                    identityTheftRestorationStatus: .off,
                                                                    paidAIChatStatus: .off,
                                                                    isPaidAIChatEnabled: true)

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: false,
                                                          includingSync: false,
                                                          includingAIChat: false,
                                                          subscriptionState: subscriptionState)

        // Then
        XCTAssertFalse(sections.contains { $0.id ==  .purchasePrivacyPro })
        XCTAssertTrue(sections.contains { $0.id ==  .privacyPro })

        let purchasePrivacyProSection = sections.first { $0.id ==  .privacyPro }!
        XCTAssertEqual(purchasePrivacyProSection.panes, [.vpn, .personalInformationRemoval, .paidAIChat, .identityTheftRestoration, .subscriptionSettings])
    }

    func testPrivacyPaidAIChatIsNotPresentWhenHasSubscriptionButFeatureFlagIsOff() throws {
        // Given
        let features: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]
        let subscriptionState = PreferencesSidebarSubscriptionState(hasSubscription: true,
                                                                    subscriptionFeatures: features,
                                                                    userEntitlements: [],
                                                                    shouldHideSubscriptionPurchase: false,
                                                                    personalInformationRemovalStatus: .off,
                                                                    identityTheftRestorationStatus: .off,
                                                                    paidAIChatStatus: .off,
                                                                    isPaidAIChatEnabled: false)

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: false,
                                                          includingSync: false,
                                                          includingAIChat: false,
                                                          subscriptionState: subscriptionState)

        // Then
        XCTAssertFalse(sections.contains { $0.id ==  .purchasePrivacyPro })
        XCTAssertTrue(sections.contains { $0.id ==  .privacyPro })

        let purchasePrivacyProSection = sections.first { $0.id ==  .privacyPro }!
        XCTAssertEqual(purchasePrivacyProSection.panes, [.vpn, .personalInformationRemoval, .identityTheftRestoration, .subscriptionSettings])
    }

    func testPrivacyProSectionContentsIsDependantOnSubscriptionFeatures() throws {
        // Given
        let features: [Entitlement.ProductName] = []
        let subscriptionState = PreferencesSidebarSubscriptionState(hasSubscription: true,
                                                                    subscriptionFeatures: features,
                                                                    userEntitlements: [],
                                                                    shouldHideSubscriptionPurchase: false,
                                                                    personalInformationRemovalStatus: .off,
                                                                    identityTheftRestorationStatus: .off,
                                                                    paidAIChatStatus: .off,
                                                                    isPaidAIChatEnabled: false)

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: false,
                                                          includingSync: false,
                                                          includingAIChat: false,
                                                          subscriptionState: subscriptionState)

        // Then
        XCTAssertFalse(sections.contains { $0.id ==  .purchasePrivacyPro })
        XCTAssertTrue(sections.contains { $0.id ==  .privacyPro })

        let purchasePrivacyProSection = sections.first { $0.id ==  .privacyPro }!
        XCTAssertEqual(purchasePrivacyProSection.panes, [.subscriptionSettings])
    }
}

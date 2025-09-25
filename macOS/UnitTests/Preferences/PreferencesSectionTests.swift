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
        let subscriptionState = PreferencesSidebarSubscriptionState()

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
        let subscriptionState = PreferencesSidebarSubscriptionState()

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
        let subscriptionState = PreferencesSidebarSubscriptionState()

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
        let subscriptionState = PreferencesSidebarSubscriptionState()

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

    func testNoSubscriptionSectionsArePresentWhenNoSubscriptionAndPurchaseOptions() throws {
        // Given
        let subscriptionState = PreferencesSidebarSubscriptionState(hasSubscription: false,
                                                                    shouldHideSubscriptionPurchase: true)

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: false,
                                                          includingSync: false,
                                                          includingAIChat: false,
                                                          subscriptionState: subscriptionState)

        // Then
        XCTAssertFalse(sections.contains { $0.id ==  .purchaseSubscription })
        XCTAssertFalse(sections.contains { $0.id ==  .subscription })
    }

    func testPurchaseSubscriptionSectionIsPresentWhenNoSubscription() throws {
        // Given
        let subscriptionState = PreferencesSidebarSubscriptionState(hasSubscription: false,
                                                                    shouldHideSubscriptionPurchase: false)

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: false,
                                                          includingSync: false,
                                                          includingAIChat: false,
                                                          subscriptionState: subscriptionState)

        // Then
        XCTAssertTrue(sections.contains { $0.id ==  .purchaseSubscription })
        XCTAssertFalse(sections.contains { $0.id ==  .subscription })

        let purchaseSubscriptionSection = sections.first { $0.id ==  .purchaseSubscription }!
        XCTAssertEqual(purchaseSubscriptionSection.panes, [.subscription])
    }

    func testSubscriptionSectionIsPresentWhenHasSubscription() throws {
        // Given
        let subscriptionState = PreferencesSidebarSubscriptionState(hasSubscription: true,
                                                                    shouldHideSubscriptionPurchase: false,
                                                                    isNetworkProtectionRemovalEnabled: true,
                                                                    isPersonalInformationRemovalEnabled: true,
                                                                    isIdentityTheftRestorationEnabled: true,
                                                                    isPaidAIChatEnabled: true,
                                                                    isNetworkProtectionRemovalAvailable: true,
                                                                    isPersonalInformationRemovalAvailable: true,
                                                                    isIdentityTheftRestorationAvailable: true,
                                                                    isPaidAIChatAvailable: true)

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: false,
                                                          includingSync: false,
                                                          includingAIChat: false,
                                                          subscriptionState: subscriptionState)

        // Then
        XCTAssertFalse(sections.contains { $0.id ==  .purchaseSubscription })
        XCTAssertTrue(sections.contains { $0.id ==  .subscription })

        let purchaseSubscriptionSection = sections.first { $0.id ==  .subscription }!
        XCTAssertEqual(purchaseSubscriptionSection.panes, [.vpn, .personalInformationRemoval, .paidAIChat, .identityTheftRestoration, .subscriptionSettings])
    }

    func testSubscriptionSectionContentsIsDependantOnSubscriptionFeatures() throws {
        // Given
        let subscriptionState = PreferencesSidebarSubscriptionState(hasSubscription: true,
                                                                    shouldHideSubscriptionPurchase: false)

        // When
        let sections = PreferencesSection.defaultSections(includingDuckPlayer: false,
                                                          includingSync: false,
                                                          includingAIChat: false,
                                                          subscriptionState: subscriptionState)

        // Then
        XCTAssertFalse(sections.contains { $0.id ==  .purchaseSubscription })
        XCTAssertTrue(sections.contains { $0.id ==  .subscription })

        let purchaseSubscriptionSection = sections.first { $0.id ==  .subscription }!
        XCTAssertEqual(purchaseSubscriptionSection.panes, [.subscriptionSettings])
    }
}

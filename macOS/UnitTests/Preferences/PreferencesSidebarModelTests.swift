//
//  PreferencesSidebarModelTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Combine
import Common
import PixelKitTestingUtilities
@testable import Subscription
import SubscriptionUI
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class PreferencesSidebarModelTests: XCTestCase {

    private var testNotificationCenter: NotificationCenter!
    private var mockSubscriptionManager: SubscriptionAuthV1toV2BridgeMock!
    private var pixelFiringMock: PixelKitMock!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockPrivacyConfigurationManager: MockPrivacyConfigurationManager!
    private var mockSyncService: MockDDGSyncing!
    private var mockVPNGatekeeper: DefaultVPNFeatureGatekeeper!

    var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        testNotificationCenter = NotificationCenter()
        mockSubscriptionManager = SubscriptionAuthV1toV2BridgeMock()

        let startedAt = Date().startOfDay
        let expiresAt = Date().startOfDay.daysAgo(-10)
        let subscription = PrivacyProSubscription(
            productId: "test",
            name: "test",
            billingPeriod: .yearly,
            startedAt: startedAt,
            expiresOrRenewsAt: expiresAt,
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: []
        )
        mockSubscriptionManager.returnSubscription = .success(subscription)
        mockSubscriptionManager.enabledFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat] // All enabled
        mockSubscriptionManager.subscriptionFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat] // All available

        pixelFiringMock = PixelKitMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPrivacyConfigurationManager = MockPrivacyConfigurationManager()
        mockSyncService = MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
        mockVPNGatekeeper = DefaultVPNFeatureGatekeeper(subscriptionManager: mockSubscriptionManager)
        cancellables.removeAll()
    }

    override func tearDownWithError() throws {
        testNotificationCenter = nil
        mockSubscriptionManager = nil
        pixelFiringMock = nil
        mockFeatureFlagger = nil
        mockPrivacyConfigurationManager = nil
        mockSyncService = nil
        mockVPNGatekeeper = nil
        cancellables.removeAll()
        try super.tearDownWithError()
    }

    private func PreferencesSidebarModel(loadSections: [PreferencesSection]? = nil, tabSwitcherTabs: [Tab.TabContent] = Tab.TabContent.displayableTabTypes) -> DuckDuckGo_Privacy_Browser.PreferencesSidebarModel {
        return DuckDuckGo_Privacy_Browser.PreferencesSidebarModel(
            loadSections: { _ in loadSections ?? PreferencesSection.defaultSections(includingDuckPlayer: false, includingSync: false, includingAIChat: false, subscriptionState: PreferencesSidebarSubscriptionState()) },
            tabSwitcherTabs: tabSwitcherTabs,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            syncService: MockDDGSyncing(authState: .inactive, isSyncInProgress: false),
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: pixelFiringMock
        )
    }

    private func PreferencesSidebarModel(loadSections: @escaping (PreferencesSidebarSubscriptionState) -> [PreferencesSection]) -> DuckDuckGo_Privacy_Browser.PreferencesSidebarModel {
        return DuckDuckGo_Privacy_Browser.PreferencesSidebarModel(
            loadSections: loadSections,
            tabSwitcherTabs: [],
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            syncService: MockDDGSyncing(authState: .inactive, isSyncInProgress: false),
            subscriptionManager: mockSubscriptionManager,
            notificationCenter: testNotificationCenter,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: pixelFiringMock
        )
    }

    private func createPreferencesSidebarModelWithDefaults(
        includeDuckPlayer: Bool = false,
        includeAIChat: Bool = false
    ) -> DuckDuckGo_Privacy_Browser.PreferencesSidebarModel {
        return DuckDuckGo_Privacy_Browser.PreferencesSidebarModel(
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            featureFlagger: mockFeatureFlagger,
            syncService: mockSyncService,
            vpnGatekeeper: mockVPNGatekeeper,
            includeDuckPlayer: includeDuckPlayer,
            includeAIChat: includeAIChat,
            subscriptionManager: mockSubscriptionManager
        )
    }

    func testWhenInitializedThenFirstPaneInFirstSectionIsSelected() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .autofill])]
        let model = PreferencesSidebarModel(loadSections: sections)

        XCTAssertEqual(model.selectedPane, .appearance)
    }

    func testWhenResetTabSelectionIfNeededCalledThenPreferencesTabIsSelected() throws {
        let tabs: [Tab.TabContent] = [.anySettingsPane, .bookmarks]
        let model = PreferencesSidebarModel(tabSwitcherTabs: tabs)
        model.selectedTabIndex = 1

        model.resetTabSelectionIfNeeded()

        XCTAssertEqual(model.selectedTabIndex, 0)
    }

    func testWhenSelectPaneIsCalledWithTheSamePaneThenEventIsNotPublished() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance])]
        let model = PreferencesSidebarModel(loadSections: sections)

        var selectedPaneUpdates = [PreferencePaneIdentifier]()
        model.$selectedPane.dropFirst()
            .sink { selectedPaneUpdates.append($0) }
            .store(in: &cancellables)

        model.selectPane(.appearance)
        model.selectPane(.appearance)
        XCTAssertEqual(model.selectedPane, .appearance)
        XCTAssertTrue(selectedPaneUpdates.isEmpty)
    }

    func testWhenSelectPaneIsCalledWithNonexistentPaneThenItHasNoEffect() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .autofill])]
        let model = PreferencesSidebarModel(loadSections: sections)

        model.selectPane(.general)
        XCTAssertEqual(model.selectedPane, .appearance)
    }

    func testWhenSelectedTabIndexIsChangedThenSelectedPaneIsNotAffected() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.general, .appearance, .autofill])]
        let tabs: [Tab.TabContent] = [.anySettingsPane, .bookmarks]
        let model = PreferencesSidebarModel(loadSections: sections, tabSwitcherTabs: tabs)

        var selectedPaneUpdates = [PreferencePaneIdentifier]()
        model.$selectedPane.dropFirst()
            .sink { selectedPaneUpdates.append($0) }
            .store(in: &cancellables)

        model.selectPane(.appearance)

        model.selectedTabIndex = 1
        model.selectedTabIndex = 0
        model.selectedTabIndex = 1
        model.selectedTabIndex = 0

        XCTAssertEqual(selectedPaneUpdates, [.appearance])
    }

    // MARK: Tests for `currentSubscriptionState`

    func testCurrentSubscriptionStateWhenNoSubscriptionPresent() async throws {
        // Given
        mockSubscriptionManager.returnSubscription = .failure(SubscriptionManagerError.noTokenAvailable)
        mockSubscriptionManager.accessTokenResult = .failure(SubscriptionManagerError.noTokenAvailable)
        XCTAssertFalse(mockSubscriptionManager.isUserAuthenticated)
        mockSubscriptionManager.enabledFeatures = []

        // When
        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear() // to trigger `refreshSubscriptionStateAndSectionsIfNeeded()`
        try await Task.sleep(interval: 0.1)

        // Then
        XCTAssertFalse(model.currentSubscriptionState.hasSubscription)
        XCTAssertFalse(model.currentSubscriptionState.hasAnyEntitlement)
    }

    func testCurrentSubscriptionStateForAvailableSubscriptionFeatures() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
        mockSubscriptionManager.accessTokenResult = .success("token")
        XCTAssertTrue(mockSubscriptionManager.isUserAuthenticated)

        mockSubscriptionManager.subscriptionFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]
        mockSubscriptionManager.enabledFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]

        // When
        let model = createPreferencesSidebarModelWithDefaults(includeAIChat: true)
        model.onAppear() // to trigger `refreshSubscriptionStateAndSectionsIfNeeded()`
        try await Task.sleep(interval: 0.1)

        // Then
        XCTAssertTrue(model.currentSubscriptionState.hasSubscription)
        XCTAssertTrue(model.currentSubscriptionState.isPaidAIChatEnabled)
        XCTAssertTrue(model.currentSubscriptionState.isNetworkProtectionRemovalAvailable)
        XCTAssertTrue(model.currentSubscriptionState.isPersonalInformationRemovalAvailable)
        XCTAssertTrue(model.currentSubscriptionState.isIdentityTheftRestorationAvailable)
        XCTAssertTrue(model.currentSubscriptionState.isPaidAIChatAvailable)
    }

    func testCurrentSubscriptionStateIsPaidAIChatEnabledIsFalseWhenFeatureFlagIsOff() async throws {

        mockSubscriptionManager.enabledFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration]

        // When
        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear() // to trigger `refreshSubscriptionStateAndSectionsIfNeeded()`
        try await Task.sleep(interval: 0.1)

        // Then
        XCTAssertFalse(model.currentSubscriptionState.isPaidAIChatEnabled)
    }

    func testCurrentSubscriptionStateForUserEntitlements() async throws {
        // Given
        mockSubscriptionManager.accessTokenResult = .success("token")
        XCTAssertTrue(mockSubscriptionManager.isUserAuthenticated)

        mockSubscriptionManager.enabledFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]

        // When
        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear() // to trigger `refreshSubscriptionStateAndSectionsIfNeeded()`
        try await Task.sleep(interval: 0.1)

        // Then
        XCTAssertTrue(model.currentSubscriptionState.hasSubscription)
        XCTAssertTrue(model.currentSubscriptionState.isNetworkProtectionRemovalEnabled)
        XCTAssertTrue(model.currentSubscriptionState.isPersonalInformationRemovalEnabled)
        XCTAssertTrue(model.currentSubscriptionState.isIdentityTheftRestorationEnabled)
        XCTAssertTrue(model.currentSubscriptionState.isPaidAIChatEnabled)

        XCTAssertTrue(model.isSidebarItemEnabled(for: .vpn))
        XCTAssertTrue(model.isSidebarItemEnabled(for: .personalInformationRemoval))
        XCTAssertTrue(model.isSidebarItemEnabled(for: .identityTheftRestoration))
        XCTAssertTrue(model.isSidebarItemEnabled(for: .paidAIChat))
    }

    func testCurrentSubscriptionStateForMissingUserEntitlements() async throws {
        // Given
        mockSubscriptionManager.accessTokenResult = .success("token")
        XCTAssertTrue(mockSubscriptionManager.isUserAuthenticated)

        mockSubscriptionManager.enabledFeatures = []

        // When
        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear() // to trigger `refreshSubscriptionStateAndSectionsIfNeeded()`
        try await Task.sleep(interval: 0.1)

        // Then
        XCTAssertTrue(model.currentSubscriptionState.hasSubscription)
        XCTAssertFalse(model.currentSubscriptionState.isNetworkProtectionRemovalEnabled)
        XCTAssertFalse(model.currentSubscriptionState.isPersonalInformationRemovalEnabled)
        XCTAssertFalse(model.currentSubscriptionState.isIdentityTheftRestorationEnabled)
        XCTAssertFalse(model.currentSubscriptionState.isPaidAIChatEnabled)

        XCTAssertFalse(model.isSidebarItemEnabled(for: .vpn))
        XCTAssertFalse(model.isSidebarItemEnabled(for: .personalInformationRemoval))
        XCTAssertFalse(model.isSidebarItemEnabled(for: .identityTheftRestoration))
        XCTAssertFalse(model.isSidebarItemEnabled(for: .paidAIChat))
    }

    // MARK: Tests for subscribed refresh notification triggers

    func testModelReloadsSectionsWhenRefreshSectionsCalled() async throws {
        // Given
        var startProcessingFulfilment = false
        let expectation = expectation(description: "Load sections called")

        let model = PreferencesSidebarModel(loadSections: { _ in
            if startProcessingFulfilment {
                expectation.fulfill()
            }
            return []
        })

        model.onAppear() // to trigger `refreshSubscriptionStateAndSectionsIfNeeded()`
        try await Task.sleep(interval: 0.1)
        startProcessingFulfilment = true

        // When
        model.refreshSections()

        // Then
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testModelReloadsSectionsOnNotificationForAccountDidSignIn() async throws {
        try await testModelReloadsSections(on: .accountDidSignIn, timeout: .seconds(1))
    }

    func testModelReloadsSectionsOnNotificationForAccountDidSignOut() async throws {
        try await testModelReloadsSections(on: .accountDidSignOut, timeout: .seconds(1))
    }

    func testModelReloadsSectionsOnNotificationForAvailableAppStoreProductsDidChange() async throws {
        try await testModelReloadsSections(on: .availableAppStoreProductsDidChange, timeout: .seconds(1))
    }

    func testModelReloadsSectionsOnNotificationForSubscriptionDidChange() async throws {
        try await testModelReloadsSections(on: .subscriptionDidChange, timeout: .seconds(1))
    }

    func testModelReloadsSectionsOnNotificationForEntitlementsDidChange() async throws {
        try await testModelReloadsSections(on: .entitlementsDidChange, timeout: .seconds(1))
    }

    func testModelReloadsSectionsOnNotificationForDBPLoginItemEnabled() async throws {
        try await testModelReloadsSections(on: .dbpLoginItemEnabled, timeout: .seconds(3))
    }

    func testModelReloadsSectionsOnNotificationForDBPLoginItemDisabled() async throws {
        try await testModelReloadsSections(on: .dbpLoginItemDisabled, timeout: .seconds(3))
    }

    private func testModelReloadsSections(on notification: Notification.Name, timeout: TimeInterval) async throws {
        // Given
        var startProcessingFulfilment = false
        let expectation = expectation(description: "Load sections called")
        expectation.expectedFulfillmentCount = 1

        let model = PreferencesSidebarModel(loadSections: { _ in
            if startProcessingFulfilment {
                expectation.fulfill()
            }
            return []
        })
        model.onAppear() // to trigger `refreshSubscriptionStateAndSectionsIfNeeded()`
        try await Task.sleep(interval: 0.1)
        startProcessingFulfilment = true

        mockSubscriptionManager.enabledFeatures = [] // Trigger change in all values

        // When
        mockSubscriptionManager.accessTokenResult = .success("state_change_is_required_to_trigger_refresh")
        testNotificationCenter.post(name: notification, object: self, userInfo: nil)

        // Then
        await fulfillment(of: [expectation], timeout: timeout)
    }

    // MARK: - Pixel firing tests

    func testThatSelectedPanePixelIsSentAtInitialization() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .autofill])]
        _ = PreferencesSidebarModel(loadSections: sections)
        pixelFiringMock.expectedFireCalls = [.init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily)]

        pixelFiringMock.verifyExpectations()
    }

    func testWhenSelectedPaneIsUpdatedThenPixelIsSent() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .autofill, .duckPlayer, .general, .accessibility])]
        let model = PreferencesSidebarModel(loadSections: sections)
        model.selectPane(.autofill)
        model.selectPane(.general)
        model.selectPane(.duckPlayer)
        model.selectPane(.accessibility)
        model.selectPane(.appearance)
        pixelFiringMock.expectedFireCalls = [
            .init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily),
            .init(pixel: SettingsPixel.settingsPaneOpened(.autofill), frequency: .daily),
            .init(pixel: SettingsPixel.settingsPaneOpened(.general), frequency: .daily),
            .init(pixel: SettingsPixel.settingsPaneOpened(.duckPlayer), frequency: .daily),
            .init(pixel: SettingsPixel.settingsPaneOpened(.accessibility), frequency: .daily),
            .init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily)
        ]

        pixelFiringMock.verifyExpectations()
    }

    func testWhenSelectedPaneIsUpdatedWithTheSameValueThenPixelIsNotSent() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .autofill, .duckPlayer, .general, .accessibility])]
        let model = PreferencesSidebarModel(loadSections: sections)
        model.selectPane(.appearance)
        model.selectPane(.appearance)
        model.selectPane(.appearance)
        model.selectPane(.appearance)
        pixelFiringMock.expectedFireCalls = [
            .init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily)
        ]

        pixelFiringMock.verifyExpectations()
    }

    func testWhenSelectedPaneIsUpdatedToAIChatThenAIChatPixelIsSent() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .aiChat])]
        let model = PreferencesSidebarModel(loadSections: sections)
        model.selectPane(.aiChat)
        model.selectPane(.appearance)
        model.selectPane(.aiChat)
        model.selectPane(.appearance)
        pixelFiringMock.expectedFireCalls = [
            .init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily),
            .init(pixel: AIChatPixel.aiChatSettingsDisplayed, frequency: .dailyAndCount),
            .init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily),
            .init(pixel: AIChatPixel.aiChatSettingsDisplayed, frequency: .dailyAndCount),
            .init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily)
        ]

        pixelFiringMock.verifyExpectations()
    }

    // MARK: - isPaneNew tests

    func testIsPaneNewReturnsTrueForPaidAIChat() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .paidAIChat])]
        let model = PreferencesSidebarModel(loadSections: sections)

        XCTAssertTrue(model.isPaneNew(pane: .paidAIChat))
    }

    func testIsPaneNewReturnsFalseForOtherPanes() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .autofill, .general, .vpn])]
        let model = PreferencesSidebarModel(loadSections: sections)

        XCTAssertFalse(model.isPaneNew(pane: .appearance))
        XCTAssertFalse(model.isPaneNew(pane: .autofill))
        XCTAssertFalse(model.isPaneNew(pane: .general))
        XCTAssertFalse(model.isPaneNew(pane: .vpn))
        XCTAssertFalse(model.isPaneNew(pane: .personalInformationRemoval))
        XCTAssertFalse(model.isPaneNew(pane: .identityTheftRestoration))
    }
}

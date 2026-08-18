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

import Combine
import Common
import ConcurrencyExtensions
import FoundationExtensions
import NetworkingTestingUtils
import PersistenceTestingUtils
import PixelKitTestingUtilities
import PreferencesUI_macOS
import PrivacyConfig
import PrivacyConfigTestsUtils
import SubscriptionTestingUtilities
import SubscriptionUI
import XCTest
@testable import DuckDuckGo_Privacy_Browser
@testable import Subscription

@MainActor
final class PreferencesSidebarModelTests: XCTestCase {

    private var testNotificationCenter: NotificationCenter!
    private var mockDefaultBrowserPreferences: DefaultBrowserPreferences!
    private var mockSubscriptionManager: SubscriptionManagerMock!
    private var pixelFiringMock: PixelKitMock!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockPrivacyConfigurationManager: MockPrivacyConfigurationManager!
    private var mockSyncService: MockDDGSyncing!
    private var mockVPNGatekeeper: DefaultVPNFeatureGatekeeper!
    private var mockAIChatPreferences: AIChatPreferences!
    private var mockWinBackOfferVisibilityManager: MockWinBackOfferVisibilityManager!
    var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        testNotificationCenter = NotificationCenter()
        mockDefaultBrowserPreferences = DefaultBrowserPreferences(defaultBrowserProvider: DefaultBrowserProviderMock())
        mockSubscriptionManager = SubscriptionManagerMock()
        mockAIChatPreferences = AIChatPreferences(
            storage: MockAIChatPreferencesStorage(),
            aiChatMenuConfiguration: MockAIChatConfig(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: MockFeatureFlagger()
        )
        mockWinBackOfferVisibilityManager = MockWinBackOfferVisibilityManager()
        let startedAt = Date().startOfDay
        let expiresAt = Date().startOfDay.daysAgo(-10)
        let subscription = DuckDuckGoSubscription(
            productId: "test",
            name: "test",
            billingPeriod: .yearly,
            startedAt: startedAt,
            expiresOrRenewsAt: expiresAt,
            platform: .stripe,
            status: .autoRenewable,
            activeOffers: [],
            tier: nil,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionManager.resultSubscription = .success(subscription)
        mockSubscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat] // All enabled
//        mockSubscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat] // All available

        pixelFiringMock = PixelKitMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPrivacyConfigurationManager = MockPrivacyConfigurationManager()
        mockSyncService = MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
        mockVPNGatekeeper = DefaultVPNFeatureGatekeeper(vpnUninstaller: VPNUninstaller(pinningManager: MockPinningManager()), subscriptionManager: mockSubscriptionManager)
        cancellables.removeAll()
    }

    override func tearDownWithError() throws {
        testNotificationCenter = nil
        mockDefaultBrowserPreferences = nil
        mockSubscriptionManager = nil
        pixelFiringMock = nil
        mockFeatureFlagger = nil
        mockPrivacyConfigurationManager = nil
        mockSyncService = nil
        mockVPNGatekeeper = nil
        mockAIChatPreferences = nil
        mockWinBackOfferVisibilityManager = nil
        cancellables.removeAll()
        try super.tearDownWithError()
    }

    private func PreferencesSidebarModel(loadSections: [PreferencesSection]? = nil, tabSwitcherTabs: [Tab.TabContent] = Tab.TabContent.displayableTabTypes) -> DuckDuckGo_Privacy_Browser.PreferencesSidebarModel {
        let windowControllersManager = WindowControllersManagerMock()
        return DuckDuckGo_Privacy_Browser.PreferencesSidebarModel(
            loadSections: { _ in loadSections ?? PreferencesSection.defaultSections(includingDuckPlayer: false, includingSync: false, includingAIChat: false, includingYouTubeAdBlocking: false, subscriptionState: PreferencesSidebarSubscriptionState()) },
            tabSwitcherTabs: tabSwitcherTabs,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            syncService: MockDDGSyncing(authState: .inactive, isSyncInProgress: false),
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: pixelFiringMock,
            defaultBrowserPreferences: mockDefaultBrowserPreferences,
            downloadsPreferences: DownloadsPreferences(persistor: DownloadsPreferencesPersistorMock()),
            searchPreferences: SearchPreferences(persistor: MockSearchPreferencesPersistor(), windowControllersManager: windowControllersManager),
            tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: windowControllersManager),
            webTrackingProtectionPreferences: WebTrackingProtectionPreferences(persistor: MockWebTrackingProtectionPreferencesPersistor(), windowControllersManager: windowControllersManager),
            cookiePopupProtectionPreferences: CookiePopupProtectionPreferences(persistor: MockCookiePopupProtectionPreferencesPersistor(), windowControllersManager: windowControllersManager),
            aiChatPreferences: mockAIChatPreferences,
            aboutPreferences: AboutPreferences(internalUserDecider: mockFeatureFlagger.internalUserDecider, featureFlagger: mockFeatureFlagger, windowControllersManager: windowControllersManager, keyValueStore: InMemoryThrowingKeyValueStore()),
            dockPreferences: DockPreferencesModel(dockCustomizer: DockCustomizerMock(),
                                                  pixelFiring: nil),
            accessibilityPreferences: AccessibilityPreferences(),
            duckPlayerPreferences: {
                let prefs = DuckPlayerPreferences(
                    persistor: DuckPlayerPreferencesPersistorMock(),
                    privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                    internalUserDecider: mockFeatureFlagger.internalUserDecider
                )
                return prefs
            }(),
            youTubeAdBlockingPreferences: {
                let prefs = DuckPlayerPreferences(
                    persistor: DuckPlayerPreferencesPersistorMock(),
                    privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                    internalUserDecider: mockFeatureFlagger.internalUserDecider
                )
                return YouTubeAdBlockingPreferences(duckPlayerPreferences: prefs)
            }(),
            winBackOfferVisibilityManager: mockWinBackOfferVisibilityManager
        )
    }

    private func PreferencesSidebarModel(loadSections: @escaping (PreferencesSidebarSubscriptionState) -> [PreferencesSection]) -> DuckDuckGo_Privacy_Browser.PreferencesSidebarModel {
        let windowControllersManager = WindowControllersManagerMock()
        return DuckDuckGo_Privacy_Browser.PreferencesSidebarModel(
            loadSections: loadSections,
            tabSwitcherTabs: [],
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            syncService: MockDDGSyncing(authState: .inactive, isSyncInProgress: false),
            subscriptionManager: mockSubscriptionManager,
            notificationCenter: testNotificationCenter,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: pixelFiringMock,
            defaultBrowserPreferences: mockDefaultBrowserPreferences,
            downloadsPreferences: DownloadsPreferences(persistor: DownloadsPreferencesPersistorMock()),
            searchPreferences: SearchPreferences(persistor: MockSearchPreferencesPersistor(), windowControllersManager: windowControllersManager),
            tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: windowControllersManager),
            webTrackingProtectionPreferences: WebTrackingProtectionPreferences(persistor: MockWebTrackingProtectionPreferencesPersistor(), windowControllersManager: windowControllersManager),
            cookiePopupProtectionPreferences: CookiePopupProtectionPreferences(persistor: MockCookiePopupProtectionPreferencesPersistor(), windowControllersManager: windowControllersManager),
            aiChatPreferences: mockAIChatPreferences,
            aboutPreferences: AboutPreferences(internalUserDecider: mockFeatureFlagger.internalUserDecider, featureFlagger: mockFeatureFlagger, windowControllersManager: windowControllersManager, keyValueStore: InMemoryThrowingKeyValueStore()),
            dockPreferences: DockPreferencesModel(dockCustomizer: DockCustomizerMock(),
                                                  pixelFiring: nil),
            accessibilityPreferences: AccessibilityPreferences(),
            duckPlayerPreferences: {
                let prefs = DuckPlayerPreferences(
                    persistor: DuckPlayerPreferencesPersistorMock(),
                    privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                    internalUserDecider: mockFeatureFlagger.internalUserDecider
                )
                return prefs
            }(),
            youTubeAdBlockingPreferences: {
                let prefs = DuckPlayerPreferences(
                    persistor: DuckPlayerPreferencesPersistorMock(),
                    privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                    internalUserDecider: mockFeatureFlagger.internalUserDecider
                )
                return YouTubeAdBlockingPreferences(duckPlayerPreferences: prefs)
            }(),
            winBackOfferVisibilityManager: mockWinBackOfferVisibilityManager
        )
    }

    private func createPreferencesSidebarModelWithDefaults(includeDuckPlayer: Bool = false,
                                                           includeAIChat: Bool = false) -> DuckDuckGo_Privacy_Browser.PreferencesSidebarModel {
        let loadSections = { currentSubscriptionFeatures in
            return PreferencesSection.defaultSections(
                includingDuckPlayer: includeDuckPlayer,
                includingSync: false,
                includingAIChat: includeAIChat,
                includingYouTubeAdBlocking: false,
                subscriptionState: currentSubscriptionFeatures
            )
        }

        let windowControllersManager = WindowControllersManagerMock()

        return DuckDuckGo_Privacy_Browser.PreferencesSidebarModel(
            loadSections: loadSections,
            tabSwitcherTabs: [],
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            syncService: mockSyncService,
            subscriptionManager: mockSubscriptionManager,
            featureFlagger: mockFeatureFlagger,
            pixelFiring: pixelFiringMock,
            defaultBrowserPreferences: mockDefaultBrowserPreferences,
            downloadsPreferences: DownloadsPreferences(persistor: DownloadsPreferencesPersistorMock()),
            searchPreferences: SearchPreferences(persistor: MockSearchPreferencesPersistor(), windowControllersManager: windowControllersManager),
            tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: windowControllersManager),
            webTrackingProtectionPreferences: WebTrackingProtectionPreferences(persistor: MockWebTrackingProtectionPreferencesPersistor(), windowControllersManager: windowControllersManager),
            cookiePopupProtectionPreferences: CookiePopupProtectionPreferences(persistor: MockCookiePopupProtectionPreferencesPersistor(), windowControllersManager: windowControllersManager),
            aiChatPreferences: mockAIChatPreferences,
            aboutPreferences: AboutPreferences(internalUserDecider: mockFeatureFlagger.internalUserDecider, featureFlagger: mockFeatureFlagger, windowControllersManager: windowControllersManager, keyValueStore: InMemoryThrowingKeyValueStore()),
            dockPreferences: DockPreferencesModel(dockCustomizer: DockCustomizerMock(),
                                                  pixelFiring: nil),
            accessibilityPreferences: AccessibilityPreferences(),
            duckPlayerPreferences: {
                let prefs = DuckPlayerPreferences(
                    persistor: DuckPlayerPreferencesPersistorMock(),
                    privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                    internalUserDecider: mockFeatureFlagger.internalUserDecider
                )
                return prefs
            }(),
            youTubeAdBlockingPreferences: {
                let prefs = DuckPlayerPreferences(
                    persistor: DuckPlayerPreferencesPersistorMock(),
                    privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                    internalUserDecider: mockFeatureFlagger.internalUserDecider
                )
                return YouTubeAdBlockingPreferences(duckPlayerPreferences: prefs)
            }(),
            winBackOfferVisibilityManager: mockWinBackOfferVisibilityManager
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

    func testWhenVPNPaneIsSelectedBeforeSectionsIncludeItThenItIsRememberedNotDropped() throws {
        // Regression: opening `.vpn` from the VPN status view before entitlement state has loaded
        // must still land on the VPN pane. Sections are built from subscription state, so before it
        // loads they don't contain `.vpn` — previously `selectPane(.vpn)` no-opped because the pane
        // wasn't visible yet and the request was silently dropped, leaving Settings on the default
        // pane. Whether it worked depended on whether the async entitlement load won the race.
        let sectionsWithoutVPN: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .autofill])]
        let model = PreferencesSidebarModel(loadSections: sectionsWithoutVPN)
        XCTAssertNotEqual(model.selectedPane, .vpn)

        model.selectPane(.vpn)

        XCTAssertEqual(model.selectedPane, .vpn, "VPN request must be remembered even though the VPN pane isn't visible yet")

        // A sections refresh occurring before entitlements load must not drop the pending pane.
        model.adjustSelectedPaneIfNeeded()
        XCTAssertEqual(model.selectedPane, .vpn, "VPN pane must survive a refresh until entitlement state loads")
    }

    func testWhenVPNPaneIsSelectedBeforeStateLoadsWithEntitlementThenItStaysSelected() async throws {
        // Completes the race: with the NetP entitlement, the VPN pane becomes visible once state
        // loads, so a `.vpn` request made before the load must remain selected through the async
        // refresh — the actual scenario when a subscriber taps the VPN status pill.
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]

        let model = createPreferencesSidebarModelWithDefaults()
        model.selectPane(.vpn)
        XCTAssertEqual(model.selectedPane, .vpn)

        model.onAppear() // triggers the async subscription-state load
        try await Task.sleep(interval: 0.1)

        XCTAssertTrue(model.currentSubscriptionState.isNetworkProtectionRemovalEnabled)
        XCTAssertEqual(model.selectedPane, .vpn, "VPN pane must stay selected once entitlements load")
    }

    func testWhenVPNPaneIsSelectedBeforeStateLoadsWithoutEntitlementThenItDoesNotStickOnVPN() async throws {
        // Completes the race for the no-entitlement case: the VPN pane never becomes visible, so
        // once state loads the pre-load `.vpn` request must be corrected away from the inaccessible
        // pane rather than sticking on it.
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockSubscriptionManager.resultFeatures = []

        let model = createPreferencesSidebarModelWithDefaults()
        model.selectPane(.vpn)
        XCTAssertEqual(model.selectedPane, .vpn)

        model.onAppear() // triggers the async subscription-state load
        try await Task.sleep(interval: 0.1)

        XCTAssertFalse(model.currentSubscriptionState.isNetworkProtectionRemovalEnabled)
        XCTAssertNotEqual(model.selectedPane, .vpn, "Without the entitlement, selection must not stay on the inaccessible VPN pane")
    }

    func testWhenVPNPaneIsSelectedBeforeStateLoadsAndResolvedStateEqualsDefaultThenItDoesNotStickOnVPN() async throws {
        // Regression: a signed-out user on an App Store build with no products available resolves to
        // a subscription state that equals the default `currentSubscriptionState`. The equality guard
        // in the refresh handler used to return before setting `hasLoadedInitialSubscriptionState`,
        // so `adjustSelectedPaneIfNeeded()` stayed suppressed forever and a pre-load `.vpn` request
        // parked on the inaccessible pane was never corrected. The first settled load must correct it.
        mockSubscriptionManager.resultTokenContainer = nil
        XCTAssertFalse(mockSubscriptionManager.isUserAuthenticated)
        mockSubscriptionManager.hasAppStoreProductsAvailable = false

        let model = createPreferencesSidebarModelWithDefaults()
        model.selectPane(.vpn)
        XCTAssertEqual(model.selectedPane, .vpn)

        model.onAppear() // triggers the async subscription-state load
        try await Task.sleep(interval: 0.1)

        XCTAssertFalse(model.currentSubscriptionState.isNetworkProtectionRemovalEnabled)
        XCTAssertNotEqual(model.selectedPane, .vpn, "A pane parked on the gated VPN pane must be corrected on the first settled load even when the resolved state equals the default")
    }

    // MARK: Tests for `currentSubscriptionState`

    func testCurrentSubscriptionStateWhenNoSubscriptionPresent() async throws {
        // Given
        mockSubscriptionManager.resultSubscription = .failure(SubscriptionManagerError.noTokenAvailable)
        mockSubscriptionManager.resultTokenContainer = nil
        XCTAssertFalse(mockSubscriptionManager.isUserAuthenticated)
        mockSubscriptionManager.resultFeatures = []

        // When
        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear() // to trigger `refreshSubscriptionStateAndSectionsIfNeeded()`
        try await Task.sleep(interval: 0.1)

        // Then
        XCTAssertFalse(model.currentSubscriptionState.hasSubscription)
        XCTAssertFalse(model.currentSubscriptionState.hasAnyEntitlement)
    }

    func testExpiredSubscriptionCacheDoesNotSkipRemoteFetch() async throws {
        // Regression: the outer gate in refreshSubscriptionStateAndSectionsIfNeeded must use
        // isUserAuthenticated, not isSubscriptionPresent(). isSubscriptionPresent() is backed by
        // a TTL cache — when the cache expires, isPresent returns false even for active
        // subscribers. The old code treated an expired cache as "no subscription" and returned
        // immediately without ever calling currentSubscriptionFeatures / hitting the backend.
        // The fix: gate on isUserAuthenticated (token-based, TTL-independent) so an expired cache
        // triggers a remote fetch rather than an immediate signed-out state.

        // Given: authenticated user whose subscription cache has expired (isSubscriptionPresent = false)
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        XCTAssertTrue(mockSubscriptionManager.isUserAuthenticated)
        // resultSubscription = nil → isSubscriptionPresent() returns false (simulates expired TTL)
        mockSubscriptionManager.resultSubscription = nil
        XCTAssertFalse(mockSubscriptionManager.isSubscriptionPresent())
        mockSubscriptionManager.resultFeatures = [.networkProtection]

        // When
        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear()
        try await Task.sleep(interval: 0.1)

        // Then: currentSubscriptionFeatures must have been called — the backend fetch was attempted.
        // (With the old isSubscriptionPresent gate it would have been skipped entirely.)
        XCTAssertEqual(mockSubscriptionManager.currentSubscriptionFeaturesCallCount, 1,
                       "Backend fetch must be attempted even when the subscription cache is expired")
    }

    func testCurrentSubscriptionStateForAvailableSubscriptionFeatures() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        XCTAssertTrue(mockSubscriptionManager.isUserAuthenticated)

        mockSubscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]
//        mockSubscriptionManager.enabledFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]

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

        mockSubscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration]

        // When
        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear() // to trigger `refreshSubscriptionStateAndSectionsIfNeeded()`
        try await Task.sleep(interval: 0.1)

        // Then
        XCTAssertFalse(model.currentSubscriptionState.isPaidAIChatEnabled)
    }

    func testCurrentSubscriptionStateForUserEntitlements() async throws {
        // Given
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        XCTAssertTrue(mockSubscriptionManager.isUserAuthenticated)

        mockSubscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]

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
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        XCTAssertTrue(mockSubscriptionManager.isUserAuthenticated)

        mockSubscriptionManager.resultFeatures = []

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

    func testCurrentSubscriptionStateIsUnchangedOnTransientFeaturesError() async throws {
        // Regression test: a transient currentSubscriptionFeatures error must not flip feature
        // flags to false. The sidebar would otherwise show "Subscription Settings visible,
        // sub-items hidden" until the next successful refresh.

        // Given — model starts with a fully-featured subscription state
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultFeatures = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .paidAIChat]

        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear()
        try await Task.sleep(interval: 0.1)

        // Capture the known-good state
        let stateBeforeError = model.currentSubscriptionState
        XCTAssertTrue(stateBeforeError.hasSubscription)
        XCTAssertTrue(stateBeforeError.isNetworkProtectionRemovalAvailable)
        XCTAssertTrue(stateBeforeError.isPersonalInformationRemovalAvailable)
        XCTAssertTrue(stateBeforeError.isIdentityTheftRestorationAvailable)

        // When — next refresh hits a transient 500
        mockSubscriptionManager.resultFeaturesError = URLError(.badServerResponse)
        model.onAppear()
        try await Task.sleep(interval: 0.1)

        // Then — state must be unchanged
        XCTAssertEqual(model.currentSubscriptionState, stateBeforeError,
                       "Transient error must not overwrite subscription state")
        XCTAssertTrue(model.currentSubscriptionState.isNetworkProtectionRemovalAvailable)
        XCTAssertTrue(model.currentSubscriptionState.isPersonalInformationRemovalAvailable)
        XCTAssertTrue(model.currentSubscriptionState.isIdentityTheftRestorationAvailable)
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

        mockSubscriptionManager.resultFeatures = [] // Trigger change in all values

        // When
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()

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

    func testWhenSelectedPaneIsUpdatedToSubscriptionDuringTheWinBackOfferThenWinBackOfferPixelIsSent() throws {
        // Given
        mockWinBackOfferVisibilityManager.isOfferAvailable = true
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .subscription])]
        let model = PreferencesSidebarModel(loadSections: sections)

        // When
        model.selectPane(.subscription)
        model.selectPane(.appearance)
        model.selectPane(.subscription)
        model.selectPane(.appearance)

        // Then
        pixelFiringMock.expectedFireCalls = [
            .init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily),
            .init(pixel: SubscriptionPixel.subscriptionWinBackOfferSettingsPageShown, frequency: .standard),
            .init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily),
            .init(pixel: SubscriptionPixel.subscriptionWinBackOfferSettingsPageShown, frequency: .standard),
            .init(pixel: SettingsPixel.settingsPaneOpened(.appearance), frequency: .daily)
        ]

        pixelFiringMock.verifyExpectations()
    }

    // MARK: - isPaneNew tests

    func testIsPaneNewReturnsFalseForOtherPanes() throws {
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .autofill, .general, .vpn])]
        let model = PreferencesSidebarModel(loadSections: sections)

        XCTAssertFalse(model.isPaneNew(pane: .appearance))
        XCTAssertFalse(model.isPaneNew(pane: .autofill))
        XCTAssertFalse(model.isPaneNew(pane: .general))
        XCTAssertFalse(model.isPaneNew(pane: .vpn))
        XCTAssertFalse(model.isPaneNew(pane: .personalInformationRemoval))
        XCTAssertFalse(model.isPaneNew(pane: .identityTheftRestoration))
        XCTAssertFalse(model.isPaneNew(pane: .paidAIChat))
    }

    // MARK: - shouldShowWinBackCampaignBadge tests

    func testDoesPaneShowWinBackCampaignBadge() throws {
        // Given
        mockWinBackOfferVisibilityManager.isOfferAvailable = true

        // When
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .subscription])]
        let model = PreferencesSidebarModel(loadSections: sections)

        // Then
        XCTAssertTrue(model.shouldShowWinBackCampaignBadge(pane: .subscription))
    }

    func testDoesPaneNotShowWinBackCampaignBadgeForOtherPanes() throws {
        // Given
        mockWinBackOfferVisibilityManager.isOfferAvailable = false

        // When
        let sections: [PreferencesSection] = [.init(id: .regularPreferencePanes, panes: [.appearance, .autofill, .general, .vpn])]
        let model = PreferencesSidebarModel(loadSections: sections)

        // Then
        XCTAssertFalse(model.shouldShowWinBackCampaignBadge(pane: .appearance))
        XCTAssertFalse(model.shouldShowWinBackCampaignBadge(pane: .autofill))
        XCTAssertFalse(model.shouldShowWinBackCampaignBadge(pane: .general))
        XCTAssertFalse(model.shouldShowWinBackCampaignBadge(pane: .vpn))
        XCTAssertFalse(model.shouldShowWinBackCampaignBadge(pane: .personalInformationRemoval))
        XCTAssertFalse(model.shouldShowWinBackCampaignBadge(pane: .identityTheftRestoration))
    }

    // MARK: - PaidAIChat Status Tests

    func testPaidAIChatStatusWhenBothSubscriptionAndAIFeaturesEnabled() async throws {
        // Given
        mockAIChatPreferences.isAIFeaturesEnabled = true
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
//        mockSubscriptionManager.enabledFeatures = [.paidAIChat]
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultFeatures = [.paidAIChat]
        let model = createPreferencesSidebarModelWithDefaults()

        // When
        model.onAppear()
        try await Task.sleep(interval: 0.1)

        // Then
        let protectionStatus = model.protectionStatus(for: .paidAIChat)
        XCTAssertEqual(protectionStatus?.status, .on)
    }

    func testPaidAIChatStatusWhenSubscriptionEnabledButAIFeaturesDisabled() async throws {
        // Given
        mockAIChatPreferences.isAIFeaturesEnabled = false
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
//        mockSubscriptionManager.enabledFeatures = [.paidAIChat]
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultFeatures = [.paidAIChat]
        let model = createPreferencesSidebarModelWithDefaults()

        // When
        model.onAppear()
        try await Task.sleep(interval: 0.1)

        // Then
        let protectionStatus = model.protectionStatus(for: .paidAIChat)
        XCTAssertEqual(protectionStatus?.status, .off)
    }

    func testPaidAIChatStatusWhenAIFeaturesEnabledButSubscriptionDisabled() async throws {
        // Given
        mockAIChatPreferences.isAIFeaturesEnabled = true
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
//        mockSubscriptionManager.enabledFeatures = [] // No paidAIChat
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        mockSubscriptionManager.resultFeatures = []
        let model = createPreferencesSidebarModelWithDefaults()

        // When
        model.onAppear()
        try await Task.sleep(interval: 0.1)

        // Then
        let protectionStatus = model.protectionStatus(for: .paidAIChat)
        XCTAssertEqual(protectionStatus?.status, .off)
    }

    func testPaidAIChatStatusUpdatesWhenAIFeaturesDisabled() async throws {
        // Given - start with AI features enabled
        mockAIChatPreferences.isAIFeaturesEnabled = true
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
//        mockSubscriptionManager.enabledFeatures = [.paidAIChat]
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultFeatures = [.paidAIChat]

        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear()
        try await Task.sleep(interval: 0.1)
        var protectionStatus = model.protectionStatus(for: .paidAIChat)
        XCTAssertEqual(protectionStatus?.status, .on)

        let expectation = expectation(description: "Status should update to off when AI features disabled")

        model.paidAIChatUpdates
            .sink { status in
                if status == .off {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - disable AI features
        mockAIChatPreferences.isAIFeaturesEnabled = false

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        protectionStatus = model.protectionStatus(for: .paidAIChat)
        XCTAssertEqual(protectionStatus?.status, .off)
    }

    func testPaidAIChatStatusUpdatesWhenAIFeaturesEnabled() async throws {
        // Given - start with AI features disabled
        mockAIChatPreferences.isAIFeaturesEnabled = false
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
//        mockSubscriptionManager.enabledFeatures = [.paidAIChat]
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultFeatures = [.paidAIChat]

        let model = createPreferencesSidebarModelWithDefaults()
        model.onAppear()
        try await Task.sleep(interval: 0.1)
        var protectionStatus = model.protectionStatus(for: .paidAIChat)
        XCTAssertEqual(protectionStatus?.status, .off)

        let expectation = expectation(description: "Status should update to on when AI features enabled")

        model.paidAIChatUpdates
            .sink { status in
                if status == .on {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - enable AI features
        mockAIChatPreferences.isAIFeaturesEnabled = true

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        protectionStatus = model.protectionStatus(for: .paidAIChat)
        XCTAssertEqual(protectionStatus?.status, .on)
    }

    func testPaidAIChatSidebarItemEnabledWhenBothConditionsMet() async throws {
        // Given
        mockAIChatPreferences.isAIFeaturesEnabled = true
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
//        mockSubscriptionManager.enabledFeatures = [.paidAIChat]
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultFeatures = [.paidAIChat]

        let model = createPreferencesSidebarModelWithDefaults()

        // When
        model.onAppear()
        try await Task.sleep(interval: 0.1)

        // Then
        XCTAssertTrue(model.isSidebarItemEnabled(for: .paidAIChat))
        let protectionStatus = model.protectionStatus(for: .paidAIChat)
        XCTAssertEqual(protectionStatus?.status, .on)
    }

    func testPaidAIChatSidebarItemStaysEnabledWhenAIFeaturesOff() async throws {
        // Given
        mockAIChatPreferences.isAIFeaturesEnabled = false
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
//        mockSubscriptionManager.enabledFeatures = [.paidAIChat]
        mockSubscriptionManager.resultTokenContainer = OAuthTokensFactory.makeValidTokenContainerWithEntitlements()
        mockSubscriptionManager.resultFeatures = [.paidAIChat]

        let model = createPreferencesSidebarModelWithDefaults()

        // When
        model.onAppear()
        try await Task.sleep(interval: 0.1)

        // Then - item should remain enabled but status should be off
        XCTAssertTrue(model.isSidebarItemEnabled(for: .paidAIChat))
        let protectionStatus = model.protectionStatus(for: .paidAIChat)
        XCTAssertEqual(protectionStatus?.status, .off)
    }
}

//
//  MoreOptionsMenuTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import VPN
import NetworkProtectionUI
import XCTest
import Subscription
import SubscriptionTestingUtilities
import BrowserServicesKit
import DataBrokerProtection_macOS
import DataBrokerProtectionCore

@testable import DuckDuckGo_Privacy_Browser

final class MoreOptionsMenuTests: XCTestCase {

    var tabCollectionViewModel: TabCollectionViewModel!
    var fireproofDomains: MockFireproofDomains!
    var passwordManagerCoordinator: PasswordManagerCoordinator!
    var networkProtectionVisibilityMock: NetworkProtectionVisibilityMock!
    var capturingActionDelegate: CapturingOptionsButtonMenuDelegate!
    var internalUserDecider: MockInternalUserDecider!
    var defaultBrowserProvider: DefaultBrowserProviderMock!
    var dockCustomizer: DockCustomizerMock!

    var storePurchaseManager: StorePurchaseManager!

    var subscriptionManager: SubscriptionManagerMock!

    private var mockFreemiumDBPPresenter: MockFreemiumDBPPresenter! = .init()
    private var mockFreemiumDBPFeature: MockFreemiumDBPFeature!
    private var mockNotificationCenter: MockNotificationCenter!
    private var mockPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler!
    private var mockFreemiumDBPUserStateManager: MockFreemiumDBPUserStateManager!
    private var mockFeatureFlagger: MockFeatureFlagger!

    var moreOptionsMenu: MoreOptionsMenu!

    @MainActor
    override func setUp() {
        super.setUp()
        tabCollectionViewModel = TabCollectionViewModel(isPopup: false)
        fireproofDomains = MockFireproofDomains(domains: [])
        passwordManagerCoordinator = PasswordManagerCoordinator()
        networkProtectionVisibilityMock = NetworkProtectionVisibilityMock(isInstalled: false, visible: false)
        capturingActionDelegate = CapturingOptionsButtonMenuDelegate()
        internalUserDecider = MockInternalUserDecider()
        defaultBrowserProvider = DefaultBrowserProviderMock()
        dockCustomizer = DockCustomizerMock()
        dockCustomizer.addToDock()
        defaultBrowserProvider.isDefault = true

        storePurchaseManager = StorePurchaseManagerMock()
        mockFeatureFlagger = MockFeatureFlagger()

        subscriptionManager = SubscriptionManagerMock(accountManager: AccountManagerMock(),
                                                      subscriptionEndpointService: SubscriptionEndpointServiceMock(),
                                                      authEndpointService: AuthEndpointServiceMock(),
                                                      storePurchaseManager: storePurchaseManager,
                                                      currentEnvironment: SubscriptionEnvironment(serviceEnvironment: .production,
                                                                                                  purchasePlatform: .appStore),
                                                      canPurchase: false,
                                                      subscriptionFeatureMappingCache: SubscriptionFeatureMappingCacheMock())

        mockFreemiumDBPFeature = MockFreemiumDBPFeature()

        mockNotificationCenter = MockNotificationCenter()
        mockPixelHandler = MockDataBrokerProtectionFreemiumPixelHandler()
        mockFreemiumDBPUserStateManager = MockFreemiumDBPUserStateManager()
    }

    @MainActor
    override func tearDown() {
        tabCollectionViewModel = nil
        passwordManagerCoordinator = nil
        capturingActionDelegate = nil
        subscriptionManager = nil
        moreOptionsMenu = nil
        defaultBrowserProvider = nil
        dockCustomizer = nil
        fireproofDomains = nil
        internalUserDecider = nil
        mockFeatureFlagger = nil
        mockFreemiumDBPFeature = nil
        mockFreemiumDBPPresenter = nil
        mockFreemiumDBPUserStateManager = nil
        mockNotificationCenter = nil
        mockPixelHandler = nil
        networkProtectionVisibilityMock = nil
        storePurchaseManager = nil
    }

    @MainActor
    private func setupMoreOptionsMenu(isFireWindowDefault: Bool = false) {
        let aiChatPreferencesStorage = MockAIChatPreferencesStorage()
        aiChatPreferencesStorage.showShortcutInApplicationMenu = true

        moreOptionsMenu = MoreOptionsMenu(tabCollectionViewModel: tabCollectionViewModel,
                                          bookmarkManager: MockBookmarkManager(),
                                          historyCoordinator: HistoryCoordinatingMock(),
                                          fireproofDomains: fireproofDomains,
                                          passwordManagerCoordinator: passwordManagerCoordinator,
                                          vpnFeatureGatekeeper: networkProtectionVisibilityMock,
                                          subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true, usesUnifiedFeedbackForm: false),
                                          sharingMenu: NSMenu(),
                                          internalUserDecider: internalUserDecider,
                                          subscriptionManager: subscriptionManager,
                                          freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager,
                                          freemiumDBPFeature: mockFreemiumDBPFeature,
                                          freemiumDBPPresenter: mockFreemiumDBPPresenter,
                                          dockCustomizer: dockCustomizer,
                                          defaultBrowserPreferences: .init(defaultBrowserProvider: defaultBrowserProvider),
                                          notificationCenter: mockNotificationCenter,
                                          featureFlagger: mockFeatureFlagger,
                                          dataBrokerProtectionFreemiumPixelHandler: mockPixelHandler,
                                          aiChatMenuConfiguration: AIChatMenuConfiguration(
                                            storage: aiChatPreferencesStorage,
                                            remoteSettings: MockRemoteAISettings(),
                                            featureFlagger: mockFeatureFlagger
                                          ),
                                          isFireWindowDefault: isFireWindowDefault,
                                          isUsingAuthV2: true)

        moreOptionsMenu.actionDelegate = capturingActionDelegate
    }

        /// Helper method to wait for subscription submenu building to complete
    @MainActor
    private func waitForSubscriptionSubmenuBuilding(timeout: TimeInterval = 2.0) async {
        var cancellables = Set<AnyCancellable>()
        let submenuBuilt = expectation(description: "Subscription submenu built")

        moreOptionsMenu.submenuBuildingComplete
            .first { $0 == true }
            .sink { _ in
                submenuBuilt.fulfill()
            }
            .store(in: &cancellables)

        await fulfillment(of: [submenuBuilt], timeout: timeout)
    }

    // MARK: - Subscription & Freemium

    private func mockAuthentication() {
        subscriptionManager.accountManager.storeAuthToken(token: "")
        subscriptionManager.accountManager.storeAccount(token: "", email: "", externalID: "")
    }

    @MainActor
    func testThatPrivacyProIsNotPresentWhenUnauthenticatedAndPurchaseNotAllowedOnAppStore () {
        subscriptionManager.canPurchase = false
        subscriptionManager.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        setupMoreOptionsMenu()

        XCTAssertFalse(subscriptionManager.accountManager.isUserAuthenticated)
        XCTAssertFalse(moreOptionsMenu.items.map { $0.title }.contains(UserText.subscriptionOptionsMenuItem(isSubscriptionRebrandingOn: false)))
    }

    @MainActor
    func testThatPrivacyProIsPresentWhenUnauthenticatedAndPurchaseAllowedOnAppStore () {
        subscriptionManager.canPurchase = true
        subscriptionManager.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .appStore)

        setupMoreOptionsMenu()

        XCTAssertFalse(subscriptionManager.accountManager.isUserAuthenticated)
        XCTAssertTrue(moreOptionsMenu.items.map { $0.title }.contains(UserText.subscriptionOptionsMenuItem(isSubscriptionRebrandingOn: false)))
    }

    @MainActor
    func testThatPrivacyProIsPresentDespiteCanPurchaseFlagOnStripe () {
        subscriptionManager.canPurchase = false
        subscriptionManager.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)

        setupMoreOptionsMenu()

        XCTAssertFalse(subscriptionManager.accountManager.isUserAuthenticated)
        XCTAssertTrue(moreOptionsMenu.items.map { $0.title }.contains(UserText.subscriptionOptionsMenuItem(isSubscriptionRebrandingOn: false)))
    }

    @MainActor
    func testThatMoreOptionMenuHasTheExpectedItemsWhenFreemiumFeatureUnavailable() {
        mockFeatureFlagger.enabledFeatureFlags = [.historyView]

        subscriptionManager.canPurchase = true
        subscriptionManager.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)
        mockFreemiumDBPFeature.featureAvailable = false

        setupMoreOptionsMenu()

        XCTAssertFalse(subscriptionManager.accountManager.isUserAuthenticated)
        XCTAssertTrue(subscriptionManager.canPurchase)

        XCTAssertEqual(moreOptionsMenu.items[0].title, UserText.sendFeedback)
        XCTAssertTrue(moreOptionsMenu.items[1].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[2].title, UserText.plusButtonNewTabMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[3].title, UserText.newWindowMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[4].title, UserText.newBurnerWindowMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[5].title, UserText.newAIChatMenuItem)
        XCTAssertTrue(moreOptionsMenu.items[6].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[7].title, UserText.zoom)
        XCTAssertTrue(moreOptionsMenu.items[8].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[9].title, UserText.bookmarks)
        XCTAssertEqual(moreOptionsMenu.items[10].title, UserText.downloads)
        XCTAssertEqual(moreOptionsMenu.items[11].title, UserText.mainMenuHistory)
        XCTAssertEqual(moreOptionsMenu.items[12].title, UserText.passwordManagementTitle)
        XCTAssertTrue(moreOptionsMenu.items[13].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[14].title, UserText.emailOptionsMenuItem)
        XCTAssertTrue(moreOptionsMenu.items[15].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[16].title, UserText.subscriptionOptionsMenuItem(isSubscriptionRebrandingOn: false))
        XCTAssertFalse(moreOptionsMenu.items[16].hasSubmenu)
        XCTAssertTrue(moreOptionsMenu.items[17].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[18].title, UserText.fireproofSite)
        XCTAssertEqual(moreOptionsMenu.items[19].title, UserText.deleteBrowsingDataMenuItem)
        XCTAssertTrue(moreOptionsMenu.items[20].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[21].title, UserText.findInPageMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[22].title, UserText.shareMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[23].title, UserText.printMenuItem)
        XCTAssertTrue(moreOptionsMenu.items[24].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[25].title, UserText.mainMenuHelp)
        XCTAssertEqual(moreOptionsMenu.items[26].title, UserText.settings)
    }

    @MainActor
    func testThatMoreOptionMenuHasTheExpectedItemsWhenFreemiumFeatureAvailable() {
        mockFeatureFlagger.enabledFeatureFlags = [.historyView]

        subscriptionManager.canPurchase = true
        subscriptionManager.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)
        mockFreemiumDBPFeature.featureAvailable = true

        setupMoreOptionsMenu()

        XCTAssertFalse(subscriptionManager.accountManager.isUserAuthenticated)
        XCTAssertTrue(subscriptionManager.canPurchase)

        XCTAssertEqual(moreOptionsMenu.items[0].title, UserText.sendFeedback)
        XCTAssertTrue(moreOptionsMenu.items[1].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[2].title, UserText.plusButtonNewTabMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[3].title, UserText.newWindowMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[4].title, UserText.newBurnerWindowMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[5].title, UserText.newAIChatMenuItem)
        XCTAssertTrue(moreOptionsMenu.items[6].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[7].title, UserText.zoom)
        XCTAssertTrue(moreOptionsMenu.items[8].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[9].title, UserText.bookmarks)
        XCTAssertEqual(moreOptionsMenu.items[10].title, UserText.downloads)
        XCTAssertEqual(moreOptionsMenu.items[11].title, UserText.mainMenuHistory)
        XCTAssertEqual(moreOptionsMenu.items[12].title, UserText.passwordManagementTitle)
        XCTAssertTrue(moreOptionsMenu.items[13].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[14].title, UserText.emailOptionsMenuItem)
        XCTAssertTrue(moreOptionsMenu.items[15].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[16].title, UserText.subscriptionOptionsMenuItem(isSubscriptionRebrandingOn: false))
        XCTAssertFalse(moreOptionsMenu.items[16].hasSubmenu)
        XCTAssertEqual(moreOptionsMenu.items[17].title, UserText.freemiumDBPOptionsMenuItem)
        XCTAssertTrue(moreOptionsMenu.items[18].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[19].title, UserText.fireproofSite)
        XCTAssertEqual(moreOptionsMenu.items[20].title, UserText.deleteBrowsingDataMenuItem)
        XCTAssertTrue(moreOptionsMenu.items[21].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[22].title, UserText.findInPageMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[23].title, UserText.shareMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[24].title, UserText.printMenuItem)
        XCTAssertTrue(moreOptionsMenu.items[25].isSeparatorItem)
        XCTAssertEqual(moreOptionsMenu.items[26].title, UserText.mainMenuHelp)
        XCTAssertEqual(moreOptionsMenu.items[27].title, UserText.settings)
    }

    @MainActor
    func testWhenClickingFreemiumDBPOptionThenFreemiumPresenterIsCalledAndNotificationIsPostedAndPixelFired() throws {
        // Given
        subscriptionManager.canPurchase = true
        subscriptionManager.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)
        mockFreemiumDBPFeature.featureAvailable = true
        setupMoreOptionsMenu()

        let freemiumItemIndex = try XCTUnwrap(moreOptionsMenu.indexOfItem(withTitle: UserText.freemiumDBPOptionsMenuItem))

        // When
        moreOptionsMenu.performActionForItem(at: freemiumItemIndex)

        // Then
        XCTAssertTrue(mockFreemiumDBPPresenter.didCallShowFreemium)
        XCTAssertTrue(mockNotificationCenter.didCallPostNotification)
        XCTAssertEqual(mockNotificationCenter.lastPostedNotification, .freemiumDBPEntryPointActivated)
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.overFlowScan)
    }

    @MainActor
    func testWhenClickingFreemiumDBPOptionAndFreemiumActivatedThenFreemiumPresenterIsCalledAndNotificationIsPostedAndPixelFired() throws {
        // Given
        mockFreemiumDBPUserStateManager.didPostFirstProfileSavedNotification = true
        subscriptionManager.canPurchase = true
        subscriptionManager.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production, purchasePlatform: .stripe)
        mockFreemiumDBPFeature.featureAvailable = true
        setupMoreOptionsMenu()

        let freemiumItemIndex = try XCTUnwrap(moreOptionsMenu.indexOfItem(withTitle: UserText.freemiumDBPOptionsMenuItem))

        // When
        moreOptionsMenu.performActionForItem(at: freemiumItemIndex)

        // Then
        XCTAssertTrue(mockFreemiumDBPPresenter.didCallShowFreemium)
        XCTAssertTrue(mockNotificationCenter.didCallPostNotification)
        XCTAssertEqual(mockNotificationCenter.lastPostedNotification, .freemiumDBPEntryPointActivated)
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.overFlowResults)
    }

    // MARK: - Paid AI Chat

    @MainActor
    func testWhenUserIsAuthenticatedWithPaidAIChatFeatureAndFeatureFlagEnabledThenPaidAIChatItemAppearsInSubscriptionSubmenu() async throws {
        // Given
        mockAuthentication()
        subscriptionManager.subscriptionFeatures = [.paidAIChat]
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
        setupMoreOptionsMenu()

        // When
        let privacyProItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.subscriptionOptionsMenuItem(isSubscriptionRebrandingOn: false) })
        XCTAssertTrue(privacyProItem.hasSubmenu, "Privacy Pro item should have submenu when user is authenticated")

        await waitForSubscriptionSubmenuBuilding()
        let subscriptionSubmenu = try XCTUnwrap(privacyProItem.submenu)

        // Then
        let paidAIChatItem = subscriptionSubmenu.items.first { $0.title == UserText.paidAIChat }
        XCTAssertNotNil(paidAIChatItem, "Paid AI Chat item should appear in subscription submenu when user has entitlement and feature flag is enabled")
    }

    @MainActor
    func testWhenUserIsAuthenticatedWithPaidAIChatFeatureButFeatureFlagDisabledThenPaidAIChatItemDoesNotAppear() async throws {
        // Given
        mockAuthentication()
        subscriptionManager.subscriptionFeatures = [.paidAIChat]
        setupMoreOptionsMenu()

        // When
        let privacyProItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.subscriptionOptionsMenuItem(isSubscriptionRebrandingOn: false) })
        XCTAssertTrue(privacyProItem.hasSubmenu, "Privacy Pro item should have submenu when user is authenticated")

        await waitForSubscriptionSubmenuBuilding()
        let subscriptionSubmenu = try XCTUnwrap(privacyProItem.submenu)

        // Then
        let paidAIChatItem = subscriptionSubmenu.items.first { $0.title == UserText.paidAIChat }
        XCTAssertNil(paidAIChatItem, "Paid AI Chat item should not appear when feature flag is disabled")
    }

    @MainActor
    func testWhenUserIsAuthenticatedWithoutPaidAIChatFeatureThenPaidAIChatItemDoesNotAppear() async throws {
        // Given
        mockAuthentication()
        subscriptionManager.subscriptionFeatures = []
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
        setupMoreOptionsMenu()

        // When
        let privacyProItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.subscriptionOptionsMenuItem(isSubscriptionRebrandingOn: false) })
        XCTAssertTrue(privacyProItem.hasSubmenu, "Privacy Pro item should have submenu when user is authenticated")

        await waitForSubscriptionSubmenuBuilding()
        let subscriptionSubmenu = try XCTUnwrap(privacyProItem.submenu)

        // Then
        let paidAIChatItem = subscriptionSubmenu.items.first { $0.title == UserText.paidAIChat }
        XCTAssertNil(paidAIChatItem, "Paid AI Chat item should not appear when user doesn't have the entitlement")
    }

    @MainActor
    func testWhenClickingPaidAIChatItemThenActionDelegateIsCalled() async throws {
        // Given
        mockAuthentication()
        subscriptionManager.subscriptionFeatures = [.paidAIChat]
        mockFeatureFlagger.enabledFeatureFlags = [.paidAIChat]
        setupMoreOptionsMenu()
        moreOptionsMenu.actionDelegate = capturingActionDelegate
        let privacyProItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.subscriptionOptionsMenuItem(isSubscriptionRebrandingOn: false) })
        let subscriptionSubmenu = try XCTUnwrap(privacyProItem.submenu)

        await waitForSubscriptionSubmenuBuilding()

        let paidAIChatItem = try XCTUnwrap(subscriptionSubmenu.items.first { $0.title == UserText.paidAIChat })
        let paidAIChatItemIndex = try XCTUnwrap(subscriptionSubmenu.items.firstIndex(of: paidAIChatItem))

        // When
        subscriptionSubmenu.performActionForItem(at: paidAIChatItemIndex)

        // Then
        XCTAssertTrue(capturingActionDelegate.optionsButtonMenuRequestedPaidAIChatCalled, "Action delegate should be called when paid AI chat item is clicked")
    }

    // MARK: Zoom

    @MainActor
    func testWhenClickingDefaultZoomInZoomSubmenuThenTheActionDelegateIsAlerted() {
        setupMoreOptionsMenu()

        guard let zoomSubmenu = moreOptionsMenu.zoomMenuItem.submenu else {
            XCTFail("No zoom submenu available")
            return
        }
        let defaultZoomItemIndex = zoomSubmenu.indexOfItem(withTitle: UserText.defaultZoomPageMoreOptionsItem)

        zoomSubmenu.performActionForItem(at: defaultZoomItemIndex)

        XCTAssertTrue(capturingActionDelegate.optionsButtonMenuRequestedAccessibilityPreferencesCalled)
    }

    // MARK: Preferences
    @MainActor
    func testWhenClickingOnPreferenceMenuItemThenTheActionDelegateIsAlerted() {
        setupMoreOptionsMenu()

        moreOptionsMenu.performActionForItem(at: moreOptionsMenu.items.count - 1)
        XCTAssertTrue(capturingActionDelegate.optionsButtonMenuRequestedPreferencesCalled)
    }

    // MARK: - Bookmarks

    @MainActor
    func testWhenClickingOnBookmarkAllTabsMenuItemThenTheActionDelegateIsAlerted() throws {
        setupMoreOptionsMenu()

        // GIVEN
        let bookmarksMenu = try XCTUnwrap(moreOptionsMenu.item(at: 9)?.submenu)
        let bookmarkAllTabsIndex = try XCTUnwrap(bookmarksMenu.indexOfItem(withTitle: UserText.bookmarkAllTabs))
        let bookmarkAllTabsMenuItem = try XCTUnwrap(bookmarksMenu.items[bookmarkAllTabsIndex])
        bookmarkAllTabsMenuItem.isEnabled = true

        // WHEN
        bookmarksMenu.performActionForItem(at: bookmarkAllTabsIndex)

        // THEN
        XCTAssertTrue(capturingActionDelegate.optionsButtonMenuRequestedBookmarkAllOpenTabsCalled)
    }

    // MARK: - Default Browser Action and Add To Dock

#if SPARKLE
    @MainActor
    func testWhenBrowserIsNotAddedToDockThenMenuItemIsVisible() {
        dockCustomizer.didShowFeatureFromMoreOptionsMenu = true
        dockCustomizer.dockStatus = false

        setupMoreOptionsMenu()
        moreOptionsMenu.update()

        XCTAssertEqual(moreOptionsMenu.items[1].title, UserText.addDuckDuckGoToDock)
    }

    @MainActor
    func testWhenBrowserIsNotInTheDockAndIsNotSetAsDefaultThenTheOrderIsCorrect() {
        dockCustomizer.didShowFeatureFromMoreOptionsMenu = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = false

        setupMoreOptionsMenu()
        moreOptionsMenu.update()

        XCTAssertEqual(moreOptionsMenu.items[1].title, UserText.addDuckDuckGoToDock)
        XCTAssertEqual(moreOptionsMenu.items[2].title, UserText.setAsDefaultBrowser)
    }
#endif

    @MainActor
    func testWhenBrowserIsAddedToDockThenMenuItemIsNotVisible() {
        dockCustomizer.dockStatus = true

        setupMoreOptionsMenu()
        moreOptionsMenu.update()

        XCTAssertNotEqual(moreOptionsMenu.items[1].title, UserText.addDuckDuckGoToDock)
    }

    @MainActor
    func testWhenBrowserIsDefaultThenSetAsDefaultBrowserMenuItemIsHidden() {
        defaultBrowserProvider.isDefault = true

        setupMoreOptionsMenu()
        moreOptionsMenu.update()

        XCTAssertNotEqual(moreOptionsMenu.items[1].title, UserText.setAsDefaultBrowser)
    }

    @MainActor
    func testWhenBrowserIsNotDefaultThenSetAsDefaultBrowserMenuItemIsShown() {
        defaultBrowserProvider.isDefault = false

        setupMoreOptionsMenu()
        moreOptionsMenu.update()

        XCTAssertEqual(moreOptionsMenu.items[1].title, UserText.setAsDefaultBrowser)
    }

    // MARK: - Page Items

    @MainActor
    func testWhenTabIsNotFireproofThenFireproofSiteItemIsPresentAndEnabled() throws {
        let url = try XCTUnwrap("https://example.com".url)
        let tab = Tab(content: .url(url, source: .link))
        tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(tabs: [tab]))
        fireproofDomains = MockFireproofDomains(domains: [])
        tabCollectionViewModel.select(at: .unpinned(0), forceChange: true)

        setupMoreOptionsMenu()
        moreOptionsMenu.update()

        let fireproofingItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.fireproofSite })
        XCTAssertTrue(fireproofingItem.isEnabled)
    }

    @MainActor
    func testWhenTabIsFireproofThenRemoveFireproofingItemIsPresentAndEnabled() throws {
        let url = try XCTUnwrap("https://example.com".url)
        let tab = Tab(content: .url(url, source: .link))
        tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(tabs: [tab]))
        fireproofDomains = MockFireproofDomains(domains: ["example.com"])
        tabCollectionViewModel.select(at: .unpinned(0), forceChange: true)

        setupMoreOptionsMenu()
        moreOptionsMenu.update()

        let fireproofingItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.removeFireproofing })
        XCTAssertTrue(fireproofingItem.isEnabled)
    }

    @MainActor
    func testWhenTabIsDuckDuckGoThenFireproofSiteItemIsPresentAndDisabled() throws {
        let url = try XCTUnwrap("https://duckduckgo.com".url)
        let tab = Tab(content: .url(url, source: .link))
        tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(tabs: [tab]))
        tabCollectionViewModel.select(at: .unpinned(0), forceChange: true)

        setupMoreOptionsMenu()
        moreOptionsMenu.update()

        let fireproofingItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.fireproofSite })
        XCTAssertFalse(fireproofingItem.isEnabled)
    }

    @MainActor
    func testWhenTabSupportsFindInPageThenFindInPageItemIsPresentAndEnabled() throws {
        let tabContentsSupportingFindInPage: [Tab.TabContent] = [
            .url(try XCTUnwrap("https://example.com".url), credential: nil, source: .ui),
            .subscription(.aboutDuckDuckGo),
            .identityTheftRestoration(.aboutDuckDuckGo),
            .releaseNotes,
            .webExtensionUrl(.aboutDuckDuckGo)
        ]
        for tabContent in tabContentsSupportingFindInPage {
            let tab = Tab(content: tabContent)
            tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(tabs: [tab]))
            tabCollectionViewModel.select(at: .unpinned(0), forceChange: true)
            setupMoreOptionsMenu()
            moreOptionsMenu.update()

            let findInPageItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.findInPageMenuItem })
            XCTAssertTrue(findInPageItem.isEnabled)
        }
    }

    @MainActor
    func testWhenTabDoesNotSupportFindInPageThenFindInPageItemIsPresentAndDisabled() throws {
        let tabContentsNotSupportingFindInPage: [Tab.TabContent] = [
            .url(try XCTUnwrap("duck://player/abcde12345".url), credential: nil, source: .ui),
            .url(try XCTUnwrap("duck://favicon/www.example.com".url), credential: nil, source: .ui),
            .newtab,
            .settings(pane: nil),
            .bookmarks,
            .history,
            .onboarding,
            .dataBrokerProtection
        ]
        for tabContent in tabContentsNotSupportingFindInPage {
            let tab = Tab(content: tabContent)
            tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(tabs: [tab]))
            tabCollectionViewModel.select(at: .unpinned(0), forceChange: true)
            setupMoreOptionsMenu()
            moreOptionsMenu.update()

            let findInPageItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.findInPageMenuItem })
            XCTAssertFalse(findInPageItem.isEnabled)
        }
    }

    @MainActor
    func testWhenTabSupportsSharingThenShareItemIsPresentAndEnabled() throws {
        let tabContentsSupportingSharing: [Tab.TabContent] = [
            .url(try XCTUnwrap("https://example.com".url), credential: nil, source: .ui),
            .url(try XCTUnwrap("https://duckduckgo.com".url), credential: nil, source: .ui),
            .url(try XCTUnwrap("https://wikipedia.org".url), credential: nil, source: .ui),
            .url(try XCTUnwrap("duck://player/abcde12345".url), credential: nil, source: .ui)
        ]
        for tabContent in tabContentsSupportingSharing {
            let tab = Tab(content: tabContent)
            tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(tabs: [tab]))
            tabCollectionViewModel.select(at: .unpinned(0), forceChange: true)
            setupMoreOptionsMenu()
            moreOptionsMenu.update()

            let findInPageItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.shareMenuItem })
            XCTAssertTrue(findInPageItem.isEnabled, "\(tabContent) expected to support sharing")
        }
    }

    @MainActor
    func testWhenTabDoesNotSupportSharingThenShareItemIsPresentAndDisabled() throws {
        let tabContentsNotSupportingSharing: [Tab.TabContent] = [
            .url(try XCTUnwrap("duck://favicon/www.example.com".url), credential: nil, source: .ui),
            .subscription(.aboutDuckDuckGo),
            .identityTheftRestoration(.aboutDuckDuckGo),
            .releaseNotes,
            .webExtensionUrl(.aboutDuckDuckGo),
            .newtab,
            .history,
            .bookmarks,
            .settings(pane: nil)
        ]
        for tabContent in tabContentsNotSupportingSharing {
            let tab = Tab(content: tabContent)
            tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(tabs: [tab]))
            tabCollectionViewModel.select(at: .unpinned(0), forceChange: true)
            setupMoreOptionsMenu()
            moreOptionsMenu.update()

            let shareItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.shareMenuItem })
            XCTAssertFalse(shareItem.isEnabled, "\(tabContent) expected to not support sharing")
        }
    }

    @MainActor
    func testWhenTabSupportsPrintingThenPrintItemIsPresentAndEnabled() throws {
        let tabContentsSupportingPrinting: [Tab.TabContent] = [
            .url(try XCTUnwrap("https://example.com".url), credential: nil, source: .ui),
            .url(try XCTUnwrap("https://duckduckgo.com".url), credential: nil, source: .ui),
            .url(try XCTUnwrap("https://wikipedia.org".url), credential: nil, source: .ui)
        ]
        for tabContent in tabContentsSupportingPrinting {
            let tab = Tab(content: tabContent)
            tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(tabs: [tab]))
            tabCollectionViewModel.select(at: .unpinned(0), forceChange: true)
            setupMoreOptionsMenu()
            moreOptionsMenu.update()

            let printItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.printMenuItem })
            XCTAssertTrue(printItem.isEnabled, "\(tabContent) expected to support printing")
        }
    }

    @MainActor
    func testWhenTabDoesNotSupportPrintingThenPrintItemIsPresentAndDisabled() throws {
        let tabContentsSupportingPrinting: [Tab.TabContent] = [
            .url(try XCTUnwrap("duck://player/abcde12345".url), credential: nil, source: .ui),
            .url(try XCTUnwrap("duck://favicon/www.example.com".url), credential: nil, source: .ui),
            .subscription(.aboutDuckDuckGo),
            .identityTheftRestoration(.aboutDuckDuckGo),
            .releaseNotes,
            .webExtensionUrl(.aboutDuckDuckGo),
            .newtab,
            .history,
            .bookmarks,
            .settings(pane: nil)
        ]
        for tabContent in tabContentsSupportingPrinting {
            let tab = Tab(content: tabContent)
            tabCollectionViewModel = TabCollectionViewModel(tabCollection: .init(tabs: [tab]))
            tabCollectionViewModel.select(at: .unpinned(0), forceChange: true)
            setupMoreOptionsMenu()
            moreOptionsMenu.update()

            let printItem = try XCTUnwrap(moreOptionsMenu.items.first { $0.title == UserText.printMenuItem })
            XCTAssertFalse(printItem.isEnabled, "\(tabContent) expected to not support printing")
        }
    }

    // MARK: - Feedback sub-menu tests

    func testCorrectItemsAreShown_whenNotInternalAndNotPrivacyProUser() {
        let sut = FeedbackSubMenu(targetting: self,
                                  authenticationStateProvider: MockSubscriptionAuthenticationStateProvider(),
                                  internalUserDecider: MockInternalUserDecider(),
                                  moreOptionsMenuIconsProvider: CurrentMoreOptionsMenuIcons(),
                                  featureFlagger: MockFeatureFlagger())

        XCTAssertTrue(sut.items.count == 2)
        XCTAssertEqual(sut.item(at: 0)?.title, UserText.browserFeedback)
        XCTAssertEqual(sut.item(at: 1)?.title, UserText.reportBrokenSite)
    }

    func testCorrectItemsAreShown_whenNotInternalUserAndPrivacyProUser() {
        let sut = FeedbackSubMenu(targetting: self,
                                  authenticationStateProvider: MockSubscriptionAuthenticationStateProvider(isUserAuthenticated: true),
                                  internalUserDecider: MockInternalUserDecider(),
                                  moreOptionsMenuIconsProvider: CurrentMoreOptionsMenuIcons(),
                                  featureFlagger: MockFeatureFlagger())

        XCTAssertTrue(sut.items.count == 4)
        XCTAssertEqual(sut.item(at: 0)?.title, UserText.browserFeedback)
        XCTAssertEqual(sut.item(at: 1)?.title, UserText.reportBrokenSite)
        XCTAssertEqual(sut.item(at: 2)?.isSeparatorItem, true)
        XCTAssertEqual(sut.item(at: 3)?.title, UserText.sendSubscriptionFeedback(isSubscriptionRebrandingOn: false))
    }

    func testCorrectItemsAreShown_whenInternalUserAndNotPrivacyProUser() {
        let sut = FeedbackSubMenu(targetting: self,
                                  authenticationStateProvider: MockSubscriptionAuthenticationStateProvider(isUserAuthenticated: false),
                                  internalUserDecider: MockInternalUserDecider(isInternalUser: true),
                                  moreOptionsMenuIconsProvider: CurrentMoreOptionsMenuIcons(),
                                  featureFlagger: MockFeatureFlagger())

        XCTAssertTrue(sut.items.count == 4)
        XCTAssertEqual(sut.item(at: 0)?.title, UserText.browserFeedback)
        XCTAssertEqual(sut.item(at: 1)?.title, UserText.reportBrokenSite)
        XCTAssertEqual(sut.item(at: 2)?.isSeparatorItem, true)
        XCTAssertEqual(sut.item(at: 3)?.title, "Copy Version")
    }

    func testCorrectItemsAreShown_whenInternalUserAndPrivacyProUser() {
        let sut = FeedbackSubMenu(targetting: self,
                                  authenticationStateProvider: MockSubscriptionAuthenticationStateProvider(isUserAuthenticated: true),
                                  internalUserDecider: MockInternalUserDecider(isInternalUser: true),
                                  moreOptionsMenuIconsProvider: CurrentMoreOptionsMenuIcons(),
                                  featureFlagger: MockFeatureFlagger())

        XCTAssertTrue(sut.items.count == 6)
        XCTAssertEqual(sut.item(at: 0)?.title, UserText.browserFeedback)
        XCTAssertEqual(sut.item(at: 1)?.title, UserText.reportBrokenSite)
        XCTAssertEqual(sut.item(at: 2)?.isSeparatorItem, true)
        XCTAssertEqual(sut.item(at: 3)?.title, UserText.sendSubscriptionFeedback(isSubscriptionRebrandingOn: false))
        XCTAssertEqual(sut.item(at: 4)?.isSeparatorItem, true)
        XCTAssertEqual(sut.item(at: 5)?.title, "Copy Version")
    }

    func testCorrectItemsAreShown_whenNewFeedbackFeatureFlagIsOn() {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.newFeedbackForm]
        let sut = FeedbackSubMenu(targetting: self,
                                  authenticationStateProvider: MockSubscriptionAuthenticationStateProvider(isUserAuthenticated: true),
                                  internalUserDecider: MockInternalUserDecider(isInternalUser: true),
                                  moreOptionsMenuIconsProvider: CurrentMoreOptionsMenuIcons(),
                                  featureFlagger: featureFlagger)

        XCTAssertTrue(sut.items.count == 8)
        XCTAssertEqual(sut.item(at: 0)?.title, UserText.reportBrokenSite)
        XCTAssertEqual(sut.item(at: 1)?.isSeparatorItem, true)
        XCTAssertEqual(sut.item(at: 2)?.title, "Report a Browser Problem")
        XCTAssertEqual(sut.item(at: 3)?.title, "Request a New Feature")
        XCTAssertEqual(sut.item(at: 4)?.isSeparatorItem, true)
        XCTAssertEqual(sut.item(at: 5)?.title, UserText.sendSubscriptionFeedback(isSubscriptionRebrandingOn: false))
        XCTAssertEqual(sut.item(at: 6)?.isSeparatorItem, true)
        XCTAssertEqual(sut.item(at: 7)?.title, "Copy Version")
    }

    @MainActor
    func testOpenNewWindowItemsAreInCorrectPosition_whenOpenFireWindowByDefaultChanges() {
        setupMoreOptionsMenu()

        XCTAssertEqual(moreOptionsMenu.items[3].title, UserText.newWindowMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[4].title, UserText.newBurnerWindowMenuItem)

        setupMoreOptionsMenu(isFireWindowDefault: true)

        XCTAssertEqual(moreOptionsMenu.items[3].title, UserText.newBurnerWindowMenuItem)
        XCTAssertEqual(moreOptionsMenu.items[4].title, UserText.newWindowMenuItem)
    }
}

final class MockSubscriptionAuthenticationStateProvider: SubscriptionAuthenticationStateProvider {
    var isUserAuthenticated: Bool = false

    init(isUserAuthenticated: Bool = false) {
        self.isUserAuthenticated = isUserAuthenticated
    }
}

final class NetworkProtectionVisibilityMock: VPNFeatureGatekeeper {

    var onboardStatusPublisher: AnyPublisher<NetworkProtectionUI.OnboardingStatus, Never> {
        Just(.default).eraseToAnyPublisher()
    }

    var isInstalled: Bool
    var visible: Bool

    init(isInstalled: Bool, visible: Bool) {
        self.isInstalled = isInstalled
        self.visible = visible
    }

    func isVPNVisible() -> Bool {
        return visible
    }

    func shouldUninstallAutomatically() -> Bool {
        return !visible
    }

    func canStartVPN() async throws -> Bool {
        return false
    }

    func disableForAllUsers() async {
        // intentional no-op
    }

    func disableIfUserHasNoAccess() async {
        // Intentional no-op
    }
}

final class MockFreemiumDBPFeature: FreemiumDBPFeature {
    var featureAvailable = false {
        didSet {
            isAvailableSubject.send(featureAvailable)
        }
    }
    var isAvailableSubject = PassthroughSubject<Bool, Never>()

    var isAvailable: Bool {
        featureAvailable
    }

    var isAvailablePublisher: AnyPublisher<Bool, Never> {
        return isAvailableSubject.eraseToAnyPublisher()
    }

    func subscribeToDependencyUpdates() {}
}

final class MockFreemiumDBPPresenter: FreemiumDBPPresenter {
    var didCallShowFreemium = false

    func showFreemiumDBPAndSetActivated(windowControllerManager: WindowControllersManagerProtocol? = nil) {
        didCallShowFreemium = true
    }
}

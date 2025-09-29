//
//  FireDialogViewModelTests.swift
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

import Common
import History
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class FireDialogViewModelTests: XCTestCase {

    @MainActor
    override func setUp() {
        super.setUp()
        FireDialogViewModel.resetPersistedDefaults()
    }

    @MainActor
    private func makeViewModel(
        with tabCollectionViewModel: TabCollectionViewModel,
        onboardingContextualDialogsManager: ContextualOnboardingStateUpdater = ContextualDialogsManager(trackerMessageProvider: MockTrackerMessageProvider())
    ) -> FireDialogViewModel {
        let manager = WebCacheManagerMock()
        let historyCoordinator = HistoryCoordinatingMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        tld: Application.appDelegate.tld)
        return FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionViewModel,
            historyCoordinating: HistoryCoordinatingMock(),
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: onboardingContextualDialogsManager
        )
    }

    @MainActor func testOnBurn_OnboardingContextualDialogsManagerFireButtonUsedCalled() {
        // Scenario: Pressing Fire triggers onboarding context hook.
        // Action: Call burn() on the view model.
        // Expectation: Only fireButtonUsed is recorded; no other onboarding actions occur.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let onboardingContextualDialogsManager = CapturingContextualOnboardingStateUpdater()
        let vm = makeViewModel(with: tabCollectionVM, onboardingContextualDialogsManager: onboardingContextualDialogsManager)
        XCTAssertNil(onboardingContextualDialogsManager.updatedForTab)
        XCTAssertFalse(onboardingContextualDialogsManager.gotItPressedCalled)
        XCTAssertFalse(onboardingContextualDialogsManager.fireButtonUsedCalled)

        // When
        vm.burn()

        // Then
        XCTAssertNil(onboardingContextualDialogsManager.updatedForTab)
        XCTAssertFalse(onboardingContextualDialogsManager.gotItPressedCalled)
        XCTAssertTrue(onboardingContextualDialogsManager.fireButtonUsedCalled)
    }

    @MainActor func testBurn_WithIncludeHistoryFalse_DoesNotCallBurnHistory() {
        // Scenario: User disables history clearing.
        // Action: Burn with includeHistory=false.
        // Expectation: No history API is invoked (all burn* flags remain false).
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let historyCoordinator = HistoryCoordinatingMock()

        let manager = WebCacheManagerMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        tld: Application.appDelegate.tld)

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: faviconManager,
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )

        viewModel.clearingOption = .allData
        viewModel.includeHistory = false
        viewModel.burn()

        XCTAssertFalse(historyCoordinator.burnAllCalled)
        XCTAssertFalse(historyCoordinator.burnVisitsCalled)
        XCTAssertFalse(historyCoordinator.burnDomainsCalled)
    }

    @MainActor func testClearingOption_UpdatesSelectableAndFireproofed() {
        // Scenario: Changing scope updates sections.
        // Action: Set clearingOption to .currentWindow.
        // Expectation: Selectable first, fireproofed second; no crashes during refresh.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        // simulate local history domains
        let exampleTab = Tab(content: .url(.duckDuckGo, source: .link))
        tabCollectionVM.append(tab: exampleTab)

        let historyCoordinator = HistoryCoordinatingMock()
        let faviconManager = FaviconManagerMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        tld: Application.appDelegate.tld)

        let fireproofDomains = FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD())
        fireproofDomains.add(domain: URL.duckduckgoDomain)

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: fireproofDomains,
            faviconManagement: faviconManager,
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )

        viewModel.clearingOption = .currentWindow

        // Ensure data sources update without crashing and sections are consistent
        XCTAssertEqual(viewModel.selectableSectionIndex, 0)
        XCTAssertEqual(viewModel.fireproofedSectionIndex, 1)
    }

    @MainActor func testBurn_CurrentTab_WithIncludeHistoryTrue_BurnVisitsCalled() {
        // Scenario: Current Tab scope with history enabled.
        // Action: Burn with includeHistory=true.
        // Expectation: burnVisits is called; no other burn callbacks fire.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        // Ensure selected tab exists
        let exampleTab = Tab(content: .url(.duckDuckGo, source: .link))
        tabCollectionVM.append(tab: exampleTab)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .currentTab
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurn = { XCTFail("onBurn should not be called when expecting onBurnVisits") }
        vm.includeHistory = true
        vm.burn()
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor func testBurn_CurrentWindow_WithIncludeHistoryTrue_BurnVisitsCalled() {
        // Scenario: Current Window scope with history enabled.
        // Action: Burn with includeHistory=true.
        // Expectation: burnVisits is called; others are not.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        // Add a tab to populate local history structure
        let exampleTab = Tab(content: .url(.duckDuckGo, source: .link))
        tabCollectionVM.append(tab: exampleTab)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)
        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .currentWindow
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurn = { XCTFail("onBurn should not be called when expecting onBurnVisits") }
        vm.includeHistory = true
        vm.burn()
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor func testBurn_CurrentTab_WithIncludeHistoryTrue_AndDoNotCloseTabs_BurnVisitsCalled() {
        // Scenario: Current Tab, keep tabs open.
        // Action: Burn with includeTabsAndWindows=false.
        // Expectation: burnVisits still occurs; no tab/window closure required.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .currentTab
        // Ensure selected tab exists
        let exampleTab2 = Tab(content: .url(.duckDuckGo, source: .link))
        tabCollectionVM.append(tab: exampleTab2)
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurn = { XCTFail("onBurn should not be called when expecting onBurnVisits") }
        vm.includeHistory = true
        vm.includeTabsAndWindows = false
        vm.burn()
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor func testBurn_CurrentWindow_WithIncludeHistoryTrue_AndDoNotCloseTabs_BurnVisitsCalled() {
        // Scenario: Current Window, keep tabs open.
        // Action: Burn with includeTabsAndWindows=false.
        // Expectation: burnVisits occurs; no other burn callbacks fire.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)
        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .currentWindow
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurn = { XCTFail("onBurn should not be called when expecting onBurnVisits") }
        vm.includeHistory = true
        vm.includeTabsAndWindows = false
        vm.burn()
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor func testBurn_AllData_WithIncludeHistoryTrue_AndDoNotCloseWindows_BurnAllCalled() {
        // Scenario: All Data scope, keep windows open.
        // Action: Burn with includeTabsAndWindows=false.
        // Expectation: burnAll is called; no visits/domains burns.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)
        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .allData
        let exp = expectation(description: "burnAll called")
        historyCoordinator.onBurnAll = { exp.fulfill() }
        historyCoordinator.onBurnVisits = { XCTFail("onBurnVisits should not be called when expecting onBurnAll") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnAll") }
        historyCoordinator.onBurn = { XCTFail("onBurn should not be called when expecting onBurnAll") }
        vm.includeHistory = true
        vm.includeTabsAndWindows = false
        vm.burn()
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor func testBurn_AllData_WithIncludeHistoryTrue_BurnAllCalled() {
        // Scenario: All Data scope with full clearing.
        // Action: Burn with includeHistory=true.
        // Expectation: burnAll is called; others are not.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)
        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .allData
        let exp = expectation(description: "burnAll called")
        historyCoordinator.onBurnAll = { exp.fulfill() }
        historyCoordinator.onBurnVisits = { XCTFail("onBurnVisits should not be called when expecting onBurnAll") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnAll") }
        historyCoordinator.onBurn = { XCTFail("onBurn should not be called when expecting onBurnAll") }
        vm.includeHistory = true
        vm.burn()
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor func testBurn_CurrentTab_WithCookiesToggleOff_BurnVisitsCalled() {
        // Scenario: Current Tab, cookies/site data excluded.
        // Action: Burn with includeCookiesAndSiteData=false.
        // Expectation: burnVisits is called via (.currentTab, false) path.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let exampleTab = Tab(content: .url(.duckDuckGo, source: .link))
        tabCollectionVM.append(tab: exampleTab)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .currentTab
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurn = { XCTFail("onBurn should not be called when expecting onBurnVisits") }
        vm.includeHistory = true
        vm.includeTabsAndWindows = true
        vm.includeCookiesAndSiteData = false
        vm.burn()
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor func testBurn_CurrentWindow_WithCookiesToggleOff_BurnVisitsCalled() {
        // Scenario: Current Window, cookies/site data excluded.
        // Action: Burn with includeCookiesAndSiteData=false.
        // Expectation: burnVisits is called via (.currentWindow, false) path.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let exampleTab = Tab(content: .url(.duckDuckGo, source: .link))
        tabCollectionVM.append(tab: exampleTab)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)
        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .currentWindow
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurn = { XCTFail("onBurn should not be called when expecting onBurnVisits") }

        vm.includeHistory = true
        vm.includeTabsAndWindows = true
        vm.includeCookiesAndSiteData = false
        vm.burn()
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor func testBurn_AllData_WithCookiesToggleOff_BurnAllCalled() {
        // Scenario: All Data, cookies/site data excluded.
        // Action: Burn with includeCookiesAndSiteData=false.
        // Expectation: burnAll is called via (.allData, false) path; others not.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)
        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .allData
        let exp = expectation(description: "burnAll called")
        historyCoordinator.onBurnAll = { exp.fulfill() }
        historyCoordinator.onBurnVisits = { XCTFail("onBurnVisits should not be called when expecting onBurnAll") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnAll") }
        historyCoordinator.onBurn = { XCTFail("onBurn should not be called when expecting onBurnAll") }
        // includeCookiesAndSiteData: false forces switch path (.allData, false)
        vm.includeHistory = true
        vm.includeTabsAndWindows = true
        vm.includeCookiesAndSiteData = false
        vm.burn()
        wait(for: [exp], timeout: 2.0)
    }

    @MainActor func testBurn_CurrentTab_WithIncludeHistoryFalse_DoesNotBurnHistory() {
        // Scenario: Current Tab but history disabled.
        // Action: Burn with includeHistory=false.
        // Expectation: No history clearing occurs.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let exampleTab = Tab(content: .url(.duckDuckGo, source: .link))
        tabCollectionVM.append(tab: exampleTab)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .currentTab
        vm.includeHistory = false
        vm.burn()
        XCTAssertFalse(historyCoordinator.burnAllCalled)
        XCTAssertFalse(historyCoordinator.burnVisitsCalled)
        XCTAssertFalse(historyCoordinator.burnDomainsCalled)
    }

    @MainActor func testBurn_CurrentWindow_WithIncludeHistoryFalse_DoesNotBurnHistory() {
        // Scenario: Current Window but history disabled.
        // Action: Burn with includeHistory=false.
        // Expectation: No history clearing occurs.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let exampleTab = Tab(content: .url(.duckDuckGo, source: .link))
        tabCollectionVM.append(tab: exampleTab)
        let historyCoordinator = HistoryCoordinatingMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)
        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )
        vm.clearingOption = .currentWindow
        vm.includeHistory = false
        vm.burn()
        XCTAssertFalse(historyCoordinator.burnAllCalled)
        XCTAssertFalse(historyCoordinator.burnVisitsCalled)
        XCTAssertFalse(historyCoordinator.burnDomainsCalled)
    }

    @MainActor func testUpdateItems_InitialAndOnChange_UpdatesHistoryVisitsAndSelection() {
        // Scenario: Items update on init and when scope changes.
        // Action: Initialize with .allData, then change to .currentWindow.
        // Expectations: history count reflects visits; cookiesSitesCount uses visitedDomains; selection stays valid when empty.
        let tabCollectionVM = TabCollectionViewModel(isPopup: false)
        let historyCoordinator = HistoryCoordinatingMock()
        // Two different domains to exercise BrowsingHistory.visitedDomains(tld:)
        let entry1 = HistoryEntry(identifier: UUID(), url: URL(string: "https://duckduckgo.com")!, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: Date(), visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)
        let entry2 = HistoryEntry(identifier: UUID(), url: URL(string: "https://example.com")!, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: Date(), visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)
        historyCoordinator.history = [entry1, entry2]
        historyCoordinator.allHistoryVisits = [
            Visit(date: Date(), identifier: nil, historyEntry: entry1),
            Visit(date: Date(), identifier: nil, historyEntry: entry2)
        ]
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllerManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: Application.appDelegate.tld)

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            clearingOption: .allData,
            tld: Application.appDelegate.tld,
            onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater()
        )

        // Initial update done in init for .allData
        XCTAssertEqual(vm.historyItemsCountForCurrentScope, 2)
        // selectable should include both domains (none fireproofed in this test)
        XCTAssertEqual(vm.cookiesSitesCountForCurrentScope, 2)
        XCTAssertTrue(vm.areAllSelected)

        // Change scope triggers update
        vm.clearingOption = .currentWindow
        // With no tabs, expect 0 and selection to reset (still true for empty set)
        XCTAssertEqual(vm.historyItemsCountForCurrentScope, 0)
        XCTAssertTrue(vm.areAllSelected)
    }
}

class CapturingContextualOnboardingStateUpdater: ContextualOnboardingStateUpdater {

    var state: ContextualOnboardingState = .onboardingCompleted

    @Published var isContextualOnboardingCompleted: Bool = true
    var isContextualOnboardingCompletedPublisher: Published<Bool>.Publisher { $isContextualOnboardingCompleted }

    var updatedForTab: Tab?
    var gotItPressedCalled = false
    var fireButtonUsedCalled = false

    func updateStateFor(tab: Tab) {
        updatedForTab = tab
    }

    func gotItPressed() {
        gotItPressedCalled = true
    }

    func fireButtonUsed() {
        fireButtonUsedCalled = true
    }

    func turnOffFeature() {}

}

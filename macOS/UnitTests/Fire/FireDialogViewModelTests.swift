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
import HistoryView
import PrivacyConfig
import SharedTestUtilities
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@available(macOS 12.0, *)
final class FireDialogViewModelTests: XCTestCase {

    private var historyCoordinator: HistoryCoordinatingMock!
    private var tabCollectionVM: TabCollectionViewModel!
    private var onboardingContextualDialogsManager: CapturingContextualOnboardingStateUpdater!
    private var fireproofDomains: FireproofDomains!
    private var fire: Fire!
    private var fireViewModel: FireViewModel!
    private var fireCoordinator: FireCoordinator!
    private var windowControllersManager: WindowControllersManagerMock!
    private var aiChatHistoryCleaner: MockAIChatHistoryCleaner!
    private var schemeHandler: TestSchemeHandler!

    private var fireDialogViewResponse: FireDialogView.Response!

    @MainActor
    override func setUp() {
        schemeHandler = TestSchemeHandler()
        fireproofDomains = FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD())
        historyCoordinator = HistoryCoordinatingMock()
        windowControllersManager = WindowControllersManagerMock()
        aiChatHistoryCleaner = MockAIChatHistoryCleaner()
        let manager = WebCacheManagerMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()

        fire = Fire(cacheManager: manager,
                    historyCoordinating: historyCoordinator,
                    permissionManager: permissionManager,
                    windowControllersManager: windowControllersManager,
                    faviconManagement: faviconManager,
                    tld: TLD(),
                    isAppActiveProvider: { true })

        fireViewModel = FireViewModel(fire: fire)

        tabCollectionVM = TabCollectionViewModel(isPopup: false)
        onboardingContextualDialogsManager = CapturingContextualOnboardingStateUpdater()
        fireCoordinator = FireCoordinator(tld: TLD(),
                                          featureFlagger: Application.appDelegate.featureFlagger,
                                          historyCoordinating: historyCoordinator,
                                          visualizeFireAnimationDecider: nil,
                                          onboardingContextualDialogsManager: { [unowned self] in self.onboardingContextualDialogsManager },
                                          fireproofDomains: MockFireproofDomains(),
                                          faviconManagement: FaviconManagerMock(),
                                          windowControllersManager: windowControllersManager,
                                          pixelFiring: nil,
                                          historyProvider: MockHistoryViewDataProvider(),
                                          fireViewModel: fireViewModel,
                                          tabViewModelGetter: { [tabCollectionVM] _ in
            tabCollectionVM
        },
                                          fireDialogViewFactory: { [unowned self] config in
            return TestPresenter { [unowned self] _, completion in
                config.onConfirm(self.fireDialogViewResponse)
                completion?()
            }
        })
    }

    override func tearDown() {
        schemeHandler = nil
        fire = nil
        fireViewModel = nil
        windowControllersManager = nil
        fireCoordinator = nil
        onboardingContextualDialogsManager = nil
        fireproofDomains = nil
        fireDialogViewResponse = nil
        tabCollectionVM = nil
        historyCoordinator = nil
        aiChatHistoryCleaner = nil
    }

    @MainActor func testOnBurn_OnboardingContextualDialogsManagerFireButtonUsedCalled() {
        // Scenario: Pressing Fire triggers onboarding context hook.
        // Action: Call burn() on the view model.
        // Expectation: Only fireButtonUsed is recorded; no other onboarding actions occur.

        // Add a tab so there's something to burn
        let tab = makeTab(url: .duckDuckGo)
        tabCollectionVM.append(tab: tab)

        let vm = makeViewModel(with: tabCollectionVM)
        XCTAssertNil(onboardingContextualDialogsManager.updatedForTab)
        XCTAssertFalse(onboardingContextualDialogsManager.gotItPressedCalled)
        XCTAssertFalse(onboardingContextualDialogsManager.fireButtonUsedCalled)
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        // Validate openNewWindow NOT called (window is kept open by inserting new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        // When
        let result = FireDialogResult(clearingOption: vm.clearingOption,
                                      includeHistory: vm.includeHistory,
                                      includeTabsAndWindows: vm.includeTabsAndWindows,
                                      includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                      includeChatHistory: vm.includeChatHistory)

        fireDialogViewResponse = .burn(options: result)

        let window = MockWindow()
        let presentExpectation = XCTestExpectation(description: "presentFireDialog completed")
        Task {
            _ = await fireCoordinator.presentFireDialog(mode: .fireButton, in: window)
            presentExpectation.fulfill()
        }

        // Then
        wait(for: [presentExpectation], timeout: 5.0)
        XCTAssertNil(onboardingContextualDialogsManager.updatedForTab)
        XCTAssertFalse(onboardingContextualDialogsManager.gotItPressedCalled)
        XCTAssertTrue(onboardingContextualDialogsManager.fireButtonUsedCalled)

        // Verify window still exists with a new tab (window was kept open)
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning")

        wait(for: [openNewWindowExp], timeout: 0.5)
    }

    @MainActor func testOnBurn_WhenAppIsNotActive_DoesNotOpenNewWindow() {
        // Scenario: App is not active (e.g., in background)
        // Action: Burn with all options enabled (which would normally close windows)
        // Expectation: openNewWindow should NOT be called when app is inactive

        // Create Fire with isActiveProvider returning false
        let manager = WebCacheManagerMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let inactiveFire = Fire(cacheManager: manager,
                                historyCoordinating: historyCoordinator,
                                permissionManager: permissionManager,
                                windowControllersManager: windowControllersManager,
                                faviconManagement: faviconManager,
                                tld: TLD(),
                                isAppActiveProvider: { false })  // App is NOT active
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let inactiveFireViewModel = FireViewModel(fire: inactiveFire)

        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should NOT be called when app inactive")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        let result = FireDialogResult(clearingOption: .allData,
                                      includeHistory: true,
                                      includeTabsAndWindows: true,
                                      includeCookiesAndSiteData: true,
                                      includeChatHistory: false)

        fireDialogViewResponse = .burn(options: result)

        // Use the inactive fire coordinator
        let inactiveFireCoordinator = FireCoordinator(tld: TLD(),
                                                      featureFlagger: Application.appDelegate.featureFlagger,
                                                      historyCoordinating: historyCoordinator,
                                                      visualizeFireAnimationDecider: nil,
                                                      onboardingContextualDialogsManager: { [unowned self] in self.onboardingContextualDialogsManager },
                                                      fireproofDomains: MockFireproofDomains(),
                                                      faviconManagement: FaviconManagerMock(),
                                                      windowControllersManager: windowControllersManager,
                                                      pixelFiring: nil,
                                                      historyProvider: MockHistoryViewDataProvider(),
                                                      fireViewModel: inactiveFireViewModel,
                                                      tabViewModelGetter: { [tabCollectionVM] _ in tabCollectionVM },
                                                      fireDialogViewFactory: { [unowned self] config in
            return TestPresenter { [unowned self] _, completion in
                config.onConfirm(self.fireDialogViewResponse)
                completion?()
            }
        })

        let window = MockWindow()
        let presentExpectation = XCTestExpectation(description: "presentFireDialog completed")
        Task {
            _ = await inactiveFireCoordinator.presentFireDialog(mode: .fireButton, in: window)
            presentExpectation.fulfill()
        }

        wait(for: [presentExpectation], timeout: 5.0)

        // Validate openNewWindow was NOT called
        wait(for: [openNewWindowExp], timeout: 0.5)
    }

    @MainActor func testBurn_WithIncludeHistoryFalse_DoesNotCallBurnHistory() {
        // Scenario: User disables history clearing, tabs close enabled.
        // Action: Burn with includeHistory=false, includeTabsAndWindows=true.
        // Expectation: No history API is invoked; tabs are closed; window stays open with new tab.

        // Add tabs to burn
        let tab1 = makeTab(url: .duckDuckGo)
        let tab2 = makeTab(url: URL(string: "https://example.com")!)
        tabCollectionVM.append(tab: tab1)
        tabCollectionVM.append(tab: tab2)

        let manager = WebCacheManagerMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: faviconManager,
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: faviconManager,
            tld: TLD(),
        )

        // Validate openNewWindow NOT called (window is kept open with new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        viewModel.clearingOption = .allData
        viewModel.includeHistory = false
        viewModel.includeTabsAndWindows = true
        let result2 = FireDialogResult(clearingOption: viewModel.clearingOption,
                                       includeHistory: viewModel.includeHistory,
                                       includeTabsAndWindows: viewModel.includeTabsAndWindows,
                                       includeCookiesAndSiteData: viewModel.includeCookiesAndSiteData,
                                       includeChatHistory: viewModel.includeChatHistory)

        let handleExpectation = XCTestExpectation(description: "handleDialogResult completed")
        Task {
            let task = handle(viewModel, result2)
            await task.value
            handleExpectation.fulfill()
        }

        wait(for: [handleExpectation], timeout: 5)
        withExtendedLifetime(tabCollectionVM) {}

        XCTAssertFalse(historyCoordinator.burnAllCalled)
        XCTAssertFalse(historyCoordinator.burnVisitsCalled)
        XCTAssertFalse(historyCoordinator.burnDomainsCalled)

        // Verify window still exists with new tab
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning")

        wait(for: [openNewWindowExp], timeout: 0.5)
    }

    @MainActor func testClearingOption_UpdatesSelectableAndFireproofed() {
        // Scenario: Changing scope updates sections.
        // Action: Set clearingOption to .currentWindow.
        // Expectation: Selectable first, fireproofed second; no crashes during refresh.
        // simulate local history domains
        let exampleTab = makeTab(url: .duckDuckGo)
        tabCollectionVM.append(tab: exampleTab)
        tabCollectionVM.select(at: .unpinned(1))

        let faviconManager = FaviconManagerMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: faviconManager,
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let fireproofDomains = FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD())
        fireproofDomains.add(domain: URL.duckduckgoDomain)

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: faviconManager,
            tld: TLD(),
        )

        viewModel.clearingOption = .currentWindow

        // Ensure data sources update without crashing and sections are consistent
        XCTAssertEqual(viewModel.selectableSectionIndex, 0)
        XCTAssertEqual(viewModel.fireproofedSectionIndex, 1)
    }

    @MainActor func testBurn_CurrentTab_WithIncludeHistoryTrue_BurnVisitsCalled() {
        // Scenario: Current Tab scope with history enabled and tabs close enabled.
        // Action: Burn with includeHistory=true and includeTabsAndWindows=true.
        // Expectation: burnVisits is called; current tab is closed; window stays open with new tab.
        // Ensure selected tab exists
        let exampleTab = makeTab(url: .duckDuckGo)
        tabCollectionVM.append(tab: exampleTab)
        tabCollectionVM.select(at: .unpinned(1))

        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )
        vm.clearingOption = .currentTab

        // Set up expectations
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }

        // Validate openNewWindow NOT called (window is kept open with new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.includeHistory = true
        vm.includeTabsAndWindows = true
        let r1 = FireDialogResult(clearingOption: vm.clearingOption,
                                  includeHistory: vm.includeHistory,
                                  includeTabsAndWindows: vm.includeTabsAndWindows,
                                  includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                  includeChatHistory: vm.includeChatHistory)
        _=handle(vm, r1)
        wait(for: [exp], timeout: 5)
        wait(for: [openNewWindowExp], timeout: 0.5)

        // Verify window still exists and old tab was removed, new tab was inserted
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning (old tab removed)")
        XCTAssert(tabCollectionVM.tabs.first?.content.isExternalUrl != true || tabCollectionVM.tabs.first?.content.urlForWebView != .duckDuckGo, "New tab should not be the old burned tab")
    }

    @MainActor func testBurn_CurrentWindow_WithIncludeHistoryTrue_BurnVisitsCalled() {
        // Scenario: Current Window scope with history and tabs close enabled.
        // Action: Burn with includeHistory=true and includeTabsAndWindows=true.
        // Expectation: burnVisits is called; all tabs in window are removed; new tab is inserted; window stays open.
        // Add multiple tabs to populate local history structure
        let exampleTab1 = makeTab(url: .duckDuckGo)
        tabCollectionVM.append(tab: exampleTab1)
        let exampleTab2 = makeTab(url: URL(string: "https://example.com")!)
        tabCollectionVM.append(tab: exampleTab2)
        tabCollectionVM.select(at: .unpinned(1))

        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )
        vm.clearingOption = .currentWindow

        // Set up expectations
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }

        // Validate openNewWindow NOT called (window is kept open with new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.includeHistory = true
        vm.includeTabsAndWindows = true
        let r2 = FireDialogResult(clearingOption: vm.clearingOption,
                                  includeHistory: vm.includeHistory,
                                  includeTabsAndWindows: vm.includeTabsAndWindows,
                                  includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                  includeChatHistory: vm.includeChatHistory)
        _=handle(vm, r2)
        wait(for: [exp], timeout: 5)
        wait(for: [openNewWindowExp], timeout: 0.5)

        // Verify window still exists and all old tabs were removed, new tab was inserted
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning (all old tabs removed)")
        // Verify the new tab is not one of the old tabs
        let newTabURL = tabCollectionVM.tabs.first?.content.urlForWebView
        XCTAssertNotEqual(newTabURL, .duckDuckGo, "New tab should not be the old burned tab 1")
        XCTAssertNotEqual(newTabURL, URL(string: "https://example.com")!, "New tab should not be the old burned tab 2")
    }

    @MainActor func testBurn_CurrentTab_WithIncludeHistoryTrue_AndDoNotCloseTabs_BurnVisitsCalled() {
        // Scenario: Current Tab, keep tabs open.
        // Action: Burn with includeTabsAndWindows=false.
        // Expectation: burnVisits still occurs; no tab/window closure required.

        // Ensure selected tab exists
        let exampleTab = makeTab(url: .duckDuckGo)
        tabCollectionVM.append(tab: exampleTab)
        tabCollectionVM.select(at: .unpinned(1))
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )
        vm.clearingOption = .currentTab

        // Set up expectations
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }

        // Validate openNewWindow not called (tabs/windows not being closed)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        // openNewWindow should not be called even with isAppActiveProvider: { true } when no Tabs closing performed
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.includeHistory = true
        vm.includeTabsAndWindows = false
        let r3 = FireDialogResult(clearingOption: vm.clearingOption,
                                  includeHistory: vm.includeHistory,
                                  includeTabsAndWindows: vm.includeTabsAndWindows,
                                  includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                  includeChatHistory: vm.includeChatHistory)
        _=handle(vm, r3)
        wait(for: [exp], timeout: 5)
        wait(for: [openNewWindowExp], timeout: 0.5)
    }

    @MainActor func testBurn_CurrentWindow_WithIncludeHistoryTrue_AndDoNotCloseTabs_BurnVisitsCalled() {
        // Scenario: Current Window, keep tabs open.
        // Action: Burn with includeTabsAndWindows=false.
        // Expectation: burnVisits occurs; no other burn callbacks fire.
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )
        vm.clearingOption = .currentWindow

        // Set up expectations
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }

        // Validate openNewWindow not called (tabs/windows not being closed)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.includeHistory = true
        vm.includeTabsAndWindows = false
        let r4 = FireDialogResult(clearingOption: vm.clearingOption,
                                  includeHistory: vm.includeHistory,
                                  includeTabsAndWindows: vm.includeTabsAndWindows,
                                  includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                  includeChatHistory: vm.includeChatHistory)
        _=handle(vm, r4)
        wait(for: [exp], timeout: 5)
        wait(for: [openNewWindowExp], timeout: 0.5)
    }

    @MainActor func testBurn_AllData_WithIncludeHistoryTrue_AndDoNotCloseWindows_BurnAllCalled() {
        // Scenario: All Data scope, keep windows open.
        // Action: Burn with includeTabsAndWindows=false.
        // Expectation: burnAll is called; no visits/domains burns.
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )
        vm.clearingOption = .allData

        // Set up expectations
        let exp = expectation(description: "burnAll called")
        historyCoordinator.onBurnAll = { exp.fulfill() }
        historyCoordinator.onBurnVisits = { XCTFail("onBurnVisits should not be called when expecting onBurnAll") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnAll") }

        // Validate openNewWindow not called (tabs/windows not being closed)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.includeHistory = true
        vm.includeTabsAndWindows = false
        let r5 = FireDialogResult(clearingOption: vm.clearingOption,
                                  includeHistory: vm.includeHistory,
                                  includeTabsAndWindows: vm.includeTabsAndWindows,
                                  includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                  includeChatHistory: vm.includeChatHistory)
        _=handle(vm, r5)
        wait(for: [exp], timeout: 5)
        wait(for: [openNewWindowExp], timeout: 0.5)
    }

    @MainActor func testBurn_AllData_WithIncludeHistoryTrue_BurnAllCalled() {
        // Scenario: All Data scope with full clearing, window exists.
        // Action: Burn with includeHistory=true, includeTabsAndWindows=true.
        // Expectation: burnAll is called; window stays open with new tab inserted.

        // Add tabs to burn
        let tab1 = makeTab(url: .duckDuckGo)
        let tab2 = makeTab(url: URL(string: "https://example.com")!)
        tabCollectionVM.append(tab: tab1)
        tabCollectionVM.append(tab: tab2)

        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )
        vm.clearingOption = .allData

        // Set up expectations
        let exp = expectation(description: "burnAll called")
        historyCoordinator.onBurnAll = { exp.fulfill() }
        historyCoordinator.onBurnVisits = { XCTFail("onBurnVisits should not be called when expecting onBurnAll") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnAll") }

        // Validate openNewWindow NOT called (window is kept open with new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.includeHistory = true
        vm.includeTabsAndWindows = true
        let r6 = FireDialogResult(clearingOption: vm.clearingOption,
                                  includeHistory: vm.includeHistory,
                                  includeTabsAndWindows: vm.includeTabsAndWindows,
                                  includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                  includeChatHistory: vm.includeChatHistory)
        _=handle(vm, r6)
        wait(for: [exp], timeout: 5)
        wait(for: [openNewWindowExp], timeout: 0.5)

        // Verify window still exists with new tab
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning all")
    }

    @MainActor func testBurn_CurrentTab_WithCookiesToggleOff_BurnVisitsCalled() {
        // Scenario: Current Tab, cookies/site data excluded, tab close enabled.
        // Action: Burn with includeCookiesAndSiteData=false, includeTabsAndWindows=true.
        // Expectation: burnVisits is called; tab is closed; window stays open with new tab.
        let exampleTab = makeTab(url: .duckDuckGo)
        tabCollectionVM.append(tab: exampleTab)
        tabCollectionVM.select(at: .unpinned(1))
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )
        vm.clearingOption = .currentTab

        // Set up expectations
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }

        // Validate openNewWindow NOT called (window is kept open with new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.includeHistory = true
        vm.includeTabsAndWindows = true
        vm.includeCookiesAndSiteData = false
        let r7 = FireDialogResult(clearingOption: vm.clearingOption,
                                  includeHistory: vm.includeHistory,
                                  includeTabsAndWindows: vm.includeTabsAndWindows,
                                  includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                  includeChatHistory: vm.includeChatHistory)
        _=handle(vm, r7)
        wait(for: [exp], timeout: 5)
        wait(for: [openNewWindowExp], timeout: 0.5)

        // Verify window still exists with new tab
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning")
    }

    @MainActor func testBurn_CurrentWindow_WithCookiesToggleOff_BurnVisitsCalled() {
        // Scenario: Current Window, cookies/site data excluded, tabs close enabled.
        // Action: Burn with includeCookiesAndSiteData=false, includeTabsAndWindows=true.
        // Expectation: burnVisits is called; all window tabs are closed; window stays open with new tab.
        let exampleTab1 = makeTab(url: .duckDuckGo)
        let exampleTab2 = makeTab(url: URL(string: "https://example.com")!)
        tabCollectionVM.append(tab: exampleTab1)
        tabCollectionVM.append(tab: exampleTab2)
        tabCollectionVM.select(at: .unpinned(1))

        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )
        vm.clearingOption = .currentWindow

        // Set up expectations
        let exp = expectation(description: "burnVisits called")
        historyCoordinator.onBurnVisits = { exp.fulfill() }
        historyCoordinator.onBurnAll = { XCTFail("onBurnAll should not be called when expecting onBurnVisits") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnVisits") }

        // Validate openNewWindow NOT called (window is kept open with new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.includeHistory = true
        vm.includeTabsAndWindows = true
        vm.includeCookiesAndSiteData = false
        let r8 = FireDialogResult(clearingOption: vm.clearingOption,
                                  includeHistory: vm.includeHistory,
                                  includeTabsAndWindows: vm.includeTabsAndWindows,
                                  includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                  includeChatHistory: vm.includeChatHistory)
        _=handle(vm, r8)
        wait(for: [exp], timeout: 5)
        wait(for: [openNewWindowExp], timeout: 0.5)

        // Verify window still exists with new tab
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning")
    }

    @MainActor func testBurn_AllData_WithCookiesToggleOff_BurnAllCalled() {
        // Scenario: All Data, cookies/site data excluded, window exists, tabs close enabled.
        // Action: Burn with includeCookiesAndSiteData=false, includeTabsAndWindows=true.
        // Expectation: burnAll is called; window stays open with new tab inserted.

        // Add tabs to burn
        let tab1 = makeTab(url: .duckDuckGo)
        let tab2 = makeTab(url: URL(string: "https://example.com")!)
        tabCollectionVM.append(tab: tab1)
        tabCollectionVM.append(tab: tab2)

        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )
        vm.clearingOption = .allData

        // Set up expectations
        let exp = expectation(description: "burnAll called")
        historyCoordinator.onBurnAll = { exp.fulfill() }
        historyCoordinator.onBurnVisits = { XCTFail("onBurnVisits should not be called when expecting onBurnAll") }
        historyCoordinator.onBurnDomains = { XCTFail("onBurnDomains should not be called when expecting onBurnAll") }

        // Validate openNewWindow NOT called (window is kept open with new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        // includeCookiesAndSiteData: false forces switch path (.allData, false)
        vm.includeHistory = true
        vm.includeTabsAndWindows = true
        vm.includeCookiesAndSiteData = false
        let r9 = FireDialogResult(clearingOption: vm.clearingOption,
                                  includeHistory: vm.includeHistory,
                                  includeTabsAndWindows: vm.includeTabsAndWindows,
                                  includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                  includeChatHistory: vm.includeChatHistory)
        _=handle(vm, r9)
        wait(for: [exp], timeout: 5)
        wait(for: [openNewWindowExp], timeout: 0.5)

        // Verify window still exists with new tab
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning all")
    }

    @MainActor func testBurn_CurrentTab_WithIncludeHistoryFalse_DoesNotBurnHistory() {
        // Scenario: Current Tab but history disabled, tabs close enabled.
        // Action: Burn with includeHistory=false, includeTabsAndWindows=true.
        // Expectation: No history clearing occurs; tab is closed; window stays open with new tab.
        let exampleTab = makeTab(url: .duckDuckGo)
        tabCollectionVM.append(tab: exampleTab)
        tabCollectionVM.select(at: .unpinned(1))

        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )

        // Validate openNewWindow NOT called (window is kept open with new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.clearingOption = .currentTab
        vm.includeHistory = false
        vm.includeTabsAndWindows = true
        let result = FireDialogResult(clearingOption: vm.clearingOption,
                                      includeHistory: vm.includeHistory,
                                      includeTabsAndWindows: vm.includeTabsAndWindows,
                                      includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                      includeChatHistory: vm.includeChatHistory)

        let handleExpectation = XCTestExpectation(description: "handleDialogResult completed")
        Task {
            let task = handle(vm, result)
            await task.value
            handleExpectation.fulfill()
        }

        wait(for: [handleExpectation], timeout: 5)
        withExtendedLifetime(tabCollectionVM) {}

        XCTAssertFalse(historyCoordinator.burnAllCalled)
        XCTAssertFalse(historyCoordinator.burnVisitsCalled)
        XCTAssertFalse(historyCoordinator.burnDomainsCalled)

        // Verify window still exists with new tab
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning")

        wait(for: [openNewWindowExp], timeout: 0.5)
    }

    @MainActor func testBurn_CurrentWindow_WithIncludeHistoryFalse_DoesNotBurnHistory() {
        // Scenario: Current Window but history disabled, tabs close enabled.
        // Action: Burn with includeHistory=false, includeTabsAndWindows=true.
        // Expectation: No history clearing occurs; all window tabs are closed; window stays open with new tab.
        let exampleTab1 = makeTab(url: .duckDuckGo)
        let exampleTab2 = makeTab(url: URL(string: "https://example.com")!)
        tabCollectionVM.append(tab: exampleTab1)
        tabCollectionVM.append(tab: exampleTab2)
        tabCollectionVM.select(at: .unpinned(1))

        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            tld: TLD(),
        )

        // Validate openNewWindow NOT called (window is kept open with new tab)
        let openNewWindowExp = XCTestExpectation(description: "openNewWindow should not be called")
        openNewWindowExp.isInverted = true
        windowControllersManager.onOpenNewWindow = { _ in
            openNewWindowExp.fulfill()
        }

        vm.clearingOption = .currentWindow
        vm.includeHistory = false
        vm.includeTabsAndWindows = true
        let resultB = FireDialogResult(clearingOption: vm.clearingOption,
                                       includeHistory: vm.includeHistory,
                                       includeTabsAndWindows: vm.includeTabsAndWindows,
                                       includeCookiesAndSiteData: vm.includeCookiesAndSiteData,
                                       includeChatHistory: vm.includeChatHistory)

        let handleExpectation = XCTestExpectation(description: "handleDialogResult completed")
        Task {
            let task = handle(vm, resultB)
            await task.value
            handleExpectation.fulfill()
        }

        wait(for: [handleExpectation], timeout: 5)
        withExtendedLifetime(tabCollectionVM) {}

        XCTAssertFalse(historyCoordinator.burnAllCalled)
        XCTAssertFalse(historyCoordinator.burnVisitsCalled)
        XCTAssertFalse(historyCoordinator.burnDomainsCalled)

        // Verify window still exists with new tab
        XCTAssertEqual(windowControllersManager.mainWindowControllers.count, 1, "Window should be kept open")
        XCTAssertEqual(tabCollectionVM.tabs.count, 1, "Should have 1 new tab after burning")

        wait(for: [openNewWindowExp], timeout: 0.5)
    }

    @MainActor func testUpdateItems_InitialAndOnChange_UpdatesHistoryVisitsAndSelection() {
        // Scenario: Items update on init and when scope changes.
        // Action: Initialize with .allData, then change to .currentWindow.
        // Expectations: history count reflects visits; cookiesSitesCount uses visitedDomains; selection stays valid when empty.

        // Two different domains to exercise BrowsingHistory.visitedDomains(tld:)
        let entry1 = HistoryEntry(identifier: UUID(), url: URL(string: "https://duckduckgo.com")!, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: Date(), visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)
        let entry2 = HistoryEntry(identifier: UUID(), url: URL(string: "https://example.com")!, failedToLoad: false, numberOfTotalVisits: 1, lastVisit: Date(), visits: [], numberOfTrackersBlocked: 0, blockedTrackingEntities: [], trackersFound: false)
        historyCoordinator.history = [entry1, entry2]
        historyCoordinator.allHistoryVisits = [
            Visit(date: Date(), identifier: nil, historyEntry: entry1),
            Visit(date: Date(), identifier: nil, historyEntry: entry2)
        ]
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: FaviconManagerMock(),
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let vm = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: FaviconManagerMock(),
            clearingOption: .allData,
            tld: TLD(),
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

    // MARK: - Domain Selection Tests

    @MainActor func testCurrentTab_SelectsOnlyCurrentTabDomains() {
        // Scenario: Window with multiple tabs, verify currentTab scope only selects current tab's domains
        // Setup: Window with 2 tabs, each visiting different domains

        // Tab 1 (current): visits example.com and test.com
        let historyMock1 = HistoryTabExtensionMock()
        let entry1 = makeHistoryEntry(url: "https://example.com")
        let entry2 = makeHistoryEntry(url: "https://test.com")
        historyMock1.localHistory = [
            Visit(date: Date(), identifier: entry1.url, historyEntry: entry1),
            Visit(date: Date(), identifier: entry2.url, historyEntry: entry2)
        ]
        let tab1 = makeTab(url: "https://example.com".url!, historyMock: historyMock1)

        // Tab 2: visits duckduckgo.com
        let historyMock2 = HistoryTabExtensionMock()
        let entry3 = makeHistoryEntry(url: "https://duckduckgo.com")
        historyMock2.localHistory = [
            Visit(date: Date(), identifier: entry3.url, historyEntry: entry3)
        ]
        let tab2 = makeTab(url: "https://duckduckgo.com".url!, historyMock: historyMock2)

        tabCollectionVM.append(tab: tab1)
        tabCollectionVM.append(tab: tab2)
        tabCollectionVM.select(at: .unpinned(1))  // Select tab1

        let viewModel = makeViewModel(with: tabCollectionVM, clearingOption: .currentTab)

        // Verify: Selectable should ONLY contain example.com and test.com
        let selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, Set(["example.com", "test.com"]),
                       "CurrentTab scope should only select domains from current tab")

        // Verify: Should NOT include duckduckgo.com from tab2
        XCTAssertFalse(selectableDomains.contains("duckduckgo.com"),
                       "CurrentTab scope should not include domains from other tabs")
    }

    @MainActor func testCurrentTab_ExcludesFireproofedDomains() {
        // Scenario: Current tab has both regular and fireproofed domains
        // Expectation: Fireproofed domains should be in separate list, not selectable
        makeFireproofDomains(["duckduckgo.com"])

        // Current tab visits both regular and fireproofed domains
        let historyMock = HistoryTabExtensionMock()
        let entry1 = makeHistoryEntry(url: "https://example.com")
        let entry2 = makeHistoryEntry(url: "https://duckduckgo.com")
        historyMock.localHistory = [
            Visit(date: Date(), identifier: entry1.url, historyEntry: entry1),
            Visit(date: Date(), identifier: entry2.url, historyEntry: entry2)
        ]
        let tab = makeTab(url: "https://example.com".url!, historyMock: historyMock)

        tabCollectionVM.append(tab: tab)
        tabCollectionVM.select(at: .unpinned(1))
        let viewModel = makeViewModel(with: tabCollectionVM, clearingOption: .currentTab)

        // Verify: Selectable should only contain example.com
        let selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, Set(["example.com"]),
                       "CurrentTab selectable should exclude fireproofed domains")

        // Verify: Fireproofed list should contain duckduckgo.com
        let fireproofedDomains = Set(viewModel.fireproofed.map(\.domain))
        XCTAssertEqual(fireproofedDomains, Set(["duckduckgo.com"]),
                       "Fireproofed list should contain fireproofed domains from current tab")
    }

    @MainActor func testCurrentWindow_SelectsAllWindowTabsDomains() {
        // Scenario: Window with multiple tabs, verify currentWindow scope includes all tabs
        // Setup: Window with 3 tabs visiting different domains

        // Tab 1: visits example.com
        let historyMock1 = HistoryTabExtensionMock()
        let entry1 = makeHistoryEntry(url: "https://example.com")
        historyMock1.localHistory = [Visit(date: Date(), identifier: entry1.url, historyEntry: entry1)]
        let tab1 = makeTab(url: "https://example.com".url!, historyMock: historyMock1)

        // Tab 2: visits test.com
        let historyMock2 = HistoryTabExtensionMock()
        let entry2 = makeHistoryEntry(url: "https://test.com")
        historyMock2.localHistory = [Visit(date: Date(), identifier: entry2.url, historyEntry: entry2)]
        let tab2 = makeTab(url: "https://test.com".url!, historyMock: historyMock2)

        // Tab 3: visits duck.com
        let historyMock3 = HistoryTabExtensionMock()
        let entry3 = makeHistoryEntry(url: "https://duck.com")
        historyMock3.localHistory = [Visit(date: Date(), identifier: entry3.url, historyEntry: entry3)]
        let tab3 = makeTab(url: "https://duck.com".url!, historyMock: historyMock3)

        tabCollectionVM.append(tab: tab1)
        tabCollectionVM.append(tab: tab2)
        tabCollectionVM.append(tab: tab3)
        tabCollectionVM.select(at: .unpinned(1))
        let viewModel = makeViewModel(with: tabCollectionVM, clearingOption: .currentWindow)

        // Verify: Selectable should contain ALL domains from all tabs in window
        let selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, Set(["example.com", "test.com", "duck.com"]),
                       "CurrentWindow scope should select domains from all tabs in window")
    }

    @MainActor func testCurrentWindow_ExcludesFireproofedDomains() {
        // Scenario: Window tabs have mix of regular and fireproofed domains
        // Expectation: Only non-fireproofed domains in selectable list
        makeFireproofDomains(["duckduckgo.com", "github.com"])

        // Tab 1: visits regular domains
        let historyMock1 = HistoryTabExtensionMock()
        let entry1 = makeHistoryEntry(url: "https://example.com")
        let entry2 = makeHistoryEntry(url: "https://test.com")
        historyMock1.localHistory = [
            Visit(date: Date(), identifier: entry1.url, historyEntry: entry1),
            Visit(date: Date(), identifier: entry2.url, historyEntry: entry2)
        ]
        let tab1 = makeTab(url: "https://example.com".url!, historyMock: historyMock1)

        // Tab 2: visits fireproofed domains
        let historyMock2 = HistoryTabExtensionMock()
        let entry3 = makeHistoryEntry(url: "https://duckduckgo.com")
        let entry4 = makeHistoryEntry(url: "https://github.com")
        historyMock2.localHistory = [
            Visit(date: Date(), identifier: entry3.url, historyEntry: entry3),
            Visit(date: Date(), identifier: entry4.url, historyEntry: entry4)
        ]
        let tab2 = makeTab(url: "https://duckduckgo.com".url!, historyMock: historyMock2)

        tabCollectionVM.append(tab: tab1)
        tabCollectionVM.append(tab: tab2)
        tabCollectionVM.select(at: .unpinned(1))
        let viewModel = makeViewModel(with: tabCollectionVM, clearingOption: .currentWindow)

        // Verify: Selectable should only contain non-fireproofed domains
        let selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, Set(["example.com", "test.com"]),
                       "CurrentWindow selectable should exclude fireproofed domains")

        // Verify: Fireproofed list should contain both fireproofed domains
        let fireproofedDomains = Set(viewModel.fireproofed.map(\.domain))
        XCTAssertEqual(fireproofedDomains, Set(["duckduckgo.com", "github.com"]),
                       "Fireproofed list should contain all fireproofed domains from window tabs")
    }

    @MainActor func testAllData_WithScopeCookieDomains_UsesProvidedDomains() { // <-- this
        // Scenario: AllData mode with explicit scopeCookieDomains provided
        // Expectation: Uses provided domains, not tab domains

        // Tab only has example.com
        let historyMock = HistoryTabExtensionMock()
        let entry1 = makeHistoryEntry(url: "https://example.com")
        historyMock.localHistory = [Visit(date: Date(), identifier: entry1.url, historyEntry: entry1)]
        let tab = makeTab(url: "https://example.com".url!, historyMock: historyMock)
        tabCollectionVM.append(tab: tab)
        tabCollectionVM.select(at: .unpinned(1))

        // But scopeCookieDomains provides a broader set
        let scopeCookieDomains = Set(["example.com", "test.com", "duck.com"])

        let viewModel = makeViewModel(with: tabCollectionVM,
                                      clearingOption: .allData,
                                      scopeCookieDomains: scopeCookieDomains)

        // Verify: Should use scopeCookieDomains, not tab domains
        let selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, scopeCookieDomains,
                       "AllData scope should use provided scopeCookieDomains")
    }

    @MainActor func testAllData_WithScopeCookieDomains_ExcludesFireproofed() {
        // Scenario: AllData with scopeCookieDomains including fireproofed domains
        // Expectation: Fireproofed domains separated from selectable
        makeFireproofDomains(["duckduckgo.com"])

        let scopeCookieDomains = Set(["example.com", "duckduckgo.com", "test.com"])

        let viewModel = makeViewModel(with: tabCollectionVM,
                                      clearingOption: .allData,
                                      scopeCookieDomains: scopeCookieDomains)

        // Verify: Selectable excludes fireproofed
        let selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, Set(["example.com", "test.com"]),
                       "AllData selectable should exclude fireproofed domains")

        // Verify: Fireproofed contains fireproofed domain
        let fireproofedDomains = Set(viewModel.fireproofed.map(\.domain))
        XCTAssertEqual(fireproofedDomains, Set(["duckduckgo.com"]),
                       "Fireproofed list should contain fireproofed domains from scope")
    }

    @MainActor func testAllData_WithoutScopeCookieDomains_FallsBackToGlobalHistory() {
        // Scenario: AllData mode without scopeCookieDomains
        // Expectation: Falls back to global history domains

        // Setup global history with multiple entries
        let entry1 = makeHistoryEntry(url: "https://example.com")
        let entry2 = makeHistoryEntry(url: "https://test.com")
        let entry3 = makeHistoryEntry(url: "https://duck.com")
        historyCoordinator.history = [entry1, entry2, entry3]

        let viewModel = makeViewModel(with: tabCollectionVM,
                                      clearingOption: .allData,
                                      scopeCookieDomains: nil)  // No scope provided

        // Verify: Should use global history domains
        let selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, Set(["example.com", "test.com", "duck.com"]),
                       "AllData without scopeCookieDomains should use global history")
    }

    @MainActor func testSwitchingScope_UpdatesDomainLists() {
        // Scenario: Switching between scopes updates domain lists correctly
        // Expectation: Domain lists reflect current scope
        makeFireproofDomains(["duckduckgo.com"])

        // Tab 1 (current): only example.com
        let historyMock1 = HistoryTabExtensionMock()
        let entry1 = makeHistoryEntry(url: "https://example.com")
        historyMock1.localHistory = [Visit(date: Date(), identifier: entry1.url, historyEntry: entry1)]
        let tab1 = makeTab(url: "https://example.com".url!, historyMock: historyMock1)

        // Tab 2: test.com and duckduckgo.com
        let historyMock2 = HistoryTabExtensionMock()
        let entry2 = makeHistoryEntry(url: "https://test.com")
        let entry3 = makeHistoryEntry(url: "https://duckduckgo.com")
        historyMock2.localHistory = [
            Visit(date: Date(), identifier: entry2.url, historyEntry: entry2),
            Visit(date: Date(), identifier: entry3.url, historyEntry: entry3)
        ]
        let tab2 = makeTab(url: "https://test.com".url!, historyMock: historyMock2)

        tabCollectionVM.append(tab: tab1)
        tabCollectionVM.append(tab: tab2)
        tabCollectionVM.select(at: .unpinned(1))  // Select tab1
        let viewModel = makeViewModel(with: tabCollectionVM, clearingOption: .currentTab)

        // Initially: CurrentTab should only have example.com
        var selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, Set(["example.com"]),
                       "CurrentTab should initially only show current tab's domain")

        // Switch to CurrentWindow
        viewModel.clearingOption = .currentWindow

        // Now: Should include all window domains except fireproofed
        selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, Set(["example.com", "test.com"]),
                       "CurrentWindow should show all window domains except fireproofed")

        // Verify fireproofed updated too
        let fireproofedDomains = Set(viewModel.fireproofed.map(\.domain))
        XCTAssertEqual(fireproofedDomains, Set(["duckduckgo.com"]),
                       "Fireproofed should update when scope changes")
    }

    @MainActor func testAllData_ScopeCookieDomainsRemainUnchanged_WhenScopeNotChanged() {
        // Scenario: When scopeCookieDomains are provided, they should not be altered unless scope changes
        // Expectation: Original scopeCookieDomains persist across operations

        // Tab only has example.com
        let historyMock = HistoryTabExtensionMock()
        let entry1 = makeHistoryEntry(url: "https://example.com")
        historyMock.localHistory = [Visit(date: Date(), identifier: entry1.url, historyEntry: entry1)]
        let tab = makeTab(url: "https://example.com".url!, historyMock: historyMock)
        tabCollectionVM.append(tab: tab)
        tabCollectionVM.select(at: .unpinned(1))

        // Coordinator provides broader scope from history query
        let originalScopeCookieDomains = Set(["example.com", "test.com", "duck.com", "github.com"])

        let viewModel = makeViewModel(with: tabCollectionVM,
                                      clearingOption: .allData,
                                      scopeCookieDomains: originalScopeCookieDomains)

        // Verify: Initial state uses provided scope
        var selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, originalScopeCookieDomains,
                       "AllData should use provided scopeCookieDomains initially")

        // Perform selection changes (should not affect scope domains)
        viewModel.deselect(index: 0)
        viewModel.select(index: 1)

        // Verify: Scope domains unchanged, still using original set
        selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, originalScopeCookieDomains,
                       "AllData scopeCookieDomains should not change when only selection changes")

        // Verify: Count is still from original scope, not tab
        XCTAssertEqual(viewModel.cookiesSitesCountForCurrentScope, 4,
                       "Count should reflect original scope, not tab domains")
    }

    @MainActor func testAllData_ScopeCookieDomainsPreserved_WhenSwitchingScopesAndBack() {
        // Scenario: When scopeCookieDomains provided, switching away and back to .allData should preserve them
        // Expectation: Original scopeCookieDomains are reused when returning to .allData

        // Tab has example.com
        let historyMock = HistoryTabExtensionMock()
        let entry1 = makeHistoryEntry(url: "https://example.com")
        historyMock.localHistory = [Visit(date: Date(), identifier: entry1.url, historyEntry: entry1)]
        let tab = makeTab(url: "https://example.com".url!, historyMock: historyMock)
        tabCollectionVM.append(tab: tab)
        tabCollectionVM.select(at: .unpinned(1))

        // Original scope from coordinator (broader than tab)
        let originalScopeCookieDomains = Set(["example.com", "test.com", "duck.com"])

        let viewModel = makeViewModel(with: tabCollectionVM,
                                      clearingOption: .allData,
                                      scopeCookieDomains: originalScopeCookieDomains)

        // Verify: Initially uses provided scope (3 domains)
        var selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, originalScopeCookieDomains,
                       "AllData should initially use provided scopeCookieDomains")
        XCTAssertEqual(viewModel.cookiesSitesCountForCurrentScope, 3)

        // Switch to CurrentTab (should use tab domains - only 1)
        viewModel.clearingOption = .currentTab
        selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, Set(["example.com"]),
                       "CurrentTab should use only tab domains")
        XCTAssertEqual(viewModel.cookiesSitesCountForCurrentScope, 1)

        // Switch back to AllData - should restore original scope, not tab scope!
        viewModel.clearingOption = .allData
        selectableDomains = Set(viewModel.selectable.map(\.domain))
        XCTAssertEqual(selectableDomains, originalScopeCookieDomains,
                       "AllData should restore original scopeCookieDomains, not use tab domains")
        XCTAssertEqual(viewModel.cookiesSitesCountForCurrentScope, 3,
                       "Count should be from original scope, proving scopeCookieDomains were preserved")
    }

    @MainActor func testAllData_ScopeVisitsRemainUnchanged_WhenScopeNotChanged() {
        // Scenario: When scopeVisits are provided, they should not be altered unless scope changes
        // Expectation: historyVisits reflects provided scopeVisits for .allData

        // Create scope visits from coordinator (representing history query results)
        let entry1 = makeHistoryEntry(url: "https://example.com")
        let entry2 = makeHistoryEntry(url: "https://test.com")
        let scopeVisits = [
            Visit(date: Date(), identifier: entry1.url, historyEntry: entry1),
            Visit(date: Date(), identifier: entry2.url, historyEntry: entry2)
        ]

        let manager = WebCacheManagerMock()
        let permissionManager = PermissionManagerMock()
        let faviconManager = FaviconManagerMock()
        let fire = Fire(cacheManager: manager,
                        historyCoordinating: historyCoordinator,
                        permissionManager: permissionManager,
                        windowControllersManager: windowControllersManager,
                        faviconManagement: faviconManager,
                        tld: TLD(),
                        isAppActiveProvider: { true })
        registerMainWindow(with: tabCollectionVM)
        defer { windowControllersManager.mainWindowControllers = [] }

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
            faviconManagement: faviconManager,
            clearingOption: .allData,
            scopeVisits: scopeVisits,  // Provided by coordinator
            tld: TLD()
        )

        // Verify: historyVisits uses provided scopeVisits
        XCTAssertNotNil(viewModel.historyVisits)
        XCTAssertEqual(viewModel.historyVisits.count, 2,
                       "AllData should use provided scopeVisits")
        XCTAssertEqual(viewModel.historyItemsCountForCurrentScope, 2)

        // Perform selection changes (should not affect visits)
        if !viewModel.selectable.isEmpty {
            viewModel.deselect(index: 0)
        }

        // Verify: historyVisits still uses provided scopeVisits
        XCTAssertEqual(viewModel.historyVisits.count, 2,
                       "AllData scopeVisits should not change when only selection changes")
        XCTAssertEqual(viewModel.historyItemsCountForCurrentScope, 2)
    }

    // MARK: - Clearing Chat History

    @MainActor func testIncludeChatHistory_OffByDefault() {
        // Scenario: ViewModel initialized with chat history toggle visible.
        // Expectation: Chat history toggle is off by default.
        let mockSettings = MockFireDialogViewSettings()

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            clearingOption: .allData,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertTrue(viewModel.shouldShowChatHistoryToggle)
        XCTAssertFalse(viewModel.includeChatHistory)
        XCTAssertFalse(viewModel.includeChatHistorySetting)
    }

    @MainActor func testClearingOption_UpdatesIncludeChatHistory_AndPersistsUserSelection() {
        // Scenario: Changing scope updates when chat history is cleared while persisting the user selection.
        // Action: Set clearingOption from .allData to .currentWindow and back.
        // Expectation: includeChatHistory only true when scope is .allData and persists user choice.
        let historyCoordinator = HistoryCoordinatingMock()
        let faviconManager = FaviconManagerMock()
        let fire = Fire(historyCoordinating: historyCoordinator,
                        windowControllersManager: Application.appDelegate.windowControllersManager,
                        faviconManagement: faviconManager,
                        tld: Application.appDelegate.tld)
        let fireproofDomains = FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD())
        let aiChatHistoryCleaner = MockAIChatHistoryCleaner(showCleanOption: true)
        let mockSettings = MockFireDialogViewSettings()

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: TabCollectionViewModel(isPopup: false),
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: faviconManager,
            clearingOption: .allData,
            settings: mockSettings,
            tld: Application.appDelegate.tld
        )

        // User makes selection to clear chat history.
        viewModel.includeChatHistorySetting = true
        XCTAssertTrue(viewModel.includeChatHistory)

        // User changes scope to .currentWindow, which disables chat history clearing.
        viewModel.clearingOption = .currentWindow
        XCTAssertFalse(viewModel.includeChatHistory)

        // User changes scope to .allData, which re-enables chat history clearing with previous selection.
        viewModel.clearingOption = .allData
        XCTAssertTrue(viewModel.includeChatHistory)
    }

    @MainActor func testHistoryCleaner_UpdatesChatHistoryToggleVisibility() {
        // Scenario: ViewModel initialized with History Cleaner not showing clean history option.
        // Action: History Cleaner enabled clean history option.
        // Expectation: Chat history toggle is now visible.
        let aiChatHistoryCleaner = MockAIChatHistoryCleaner(showCleanOption: false)
        let mockSettings = MockFireDialogViewSettings()

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            clearingOption: .allData,
            settings: mockSettings,
            tld: TLD()
        )

        // Check precondition
        XCTAssertFalse(viewModel.shouldShowChatHistoryToggle)

        aiChatHistoryCleaner.shouldDisplayCleanAIChatHistoryOption = true

        XCTAssertTrue(viewModel.shouldShowChatHistoryToggle)
    }

    @MainActor func testClearingOption_UpdatesChatHistoryToggleVisibility() {
        // Scenario: Changing scope updates chat history toggle.
        // Action: Set clearingOption to each option.
        // Expectation: Chat history toggle is only visible for .allData.
        let mockSettings = MockFireDialogViewSettings()

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            clearingOption: .currentTab,
            settings: mockSettings,
            tld: TLD()
        )

        // Check precondition (false for current tab)
        XCTAssertFalse(viewModel.shouldShowChatHistoryToggle)

        viewModel.clearingOption = .currentWindow

        // Check still false for current window
        XCTAssertFalse(viewModel.shouldShowChatHistoryToggle)

        viewModel.clearingOption = .allData

        // Now true for all data
        XCTAssertTrue(viewModel.shouldShowChatHistoryToggle)
    }

    @MainActor func testInitWithLimitedScopeMode_DisablesChatHistoryToggleVisibility() {
        // Scenario: ViewModel initialized with limited scope mode.
        // Expectation: Chat history toggle is not visible.
        let mockSettings = MockFireDialogViewSettings()

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            clearingOption: .allData,
            mode: .historyView(query: .rangeFilter(.today)),
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertFalse(viewModel.shouldShowChatHistoryToggle)
    }

    // MARK: - Settings Persistence Tests

    @MainActor func testWhenClearingOptionChanged_ThenSettingIsPersisted() {
        // Scenario: User changes the clearing option (scope).
        // Action: Change clearingOption using mock settings.
        // Expectation: Mock settings are updated and used by subsequent ViewModel.

        let mockSettings = MockFireDialogViewSettings()

        let viewModel1 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        viewModel1.clearingOption = .allData

        XCTAssertEqual(mockSettings.lastSelectedClearingOption, .allData, "Mock settings should be updated")

        // Create new ViewModel with same mock settings
        let viewModel2 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertEqual(viewModel2.clearingOption, .allData, "clearingOption should be loaded from mock settings")

        // Change to different option
        viewModel2.clearingOption = .currentWindow

        XCTAssertEqual(mockSettings.lastSelectedClearingOption, .currentWindow, "Mock settings should reflect new value")

        // Create third ViewModel
        let viewModel3 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertEqual(viewModel3.clearingOption, .currentWindow, "Updated clearingOption should persist in mock settings")
    }

    @MainActor func testWhenIncludeTabsAndWindowsChanged_ThenSettingIsPersisted() {
        // Scenario: User toggles includeTabsAndWindows setting.
        // Action: Change includeTabsAndWindows value using mock settings.
        // Expectation: Mock settings are updated and used by subsequent ViewModel.

        let mockSettings = MockFireDialogViewSettings()

        let viewModel1 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        viewModel1.includeTabsAndWindows = false

        XCTAssertEqual(mockSettings.lastIncludeTabsAndWindowsState, false, "Mock settings should be updated")

        let viewModel2 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertFalse(viewModel2.includeTabsAndWindows, "includeTabsAndWindows should be loaded from mock settings")

        viewModel2.includeTabsAndWindows = true

        XCTAssertEqual(mockSettings.lastIncludeTabsAndWindowsState, true, "Mock settings should reflect new value")

        let viewModel3 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertTrue(viewModel3.includeTabsAndWindows, "Updated includeTabsAndWindows should persist in mock settings")
    }

    @MainActor func testWhenIncludeHistoryChanged_ThenSettingIsPersisted() {
        // Scenario: User toggles includeHistory setting.
        // Action: Change includeHistory value using mock settings.
        // Expectation: Mock settings are updated and used by subsequent ViewModel.

        let mockSettings = MockFireDialogViewSettings()

        let viewModel1 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        viewModel1.includeHistory = false

        XCTAssertEqual(mockSettings.lastIncludeHistoryState, false, "Mock settings should be updated")

        let viewModel2 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertFalse(viewModel2.includeHistory, "includeHistory should be loaded from mock settings")

        viewModel2.includeHistory = true

        XCTAssertEqual(mockSettings.lastIncludeHistoryState, true, "Mock settings should reflect new value")

        let viewModel3 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertTrue(viewModel3.includeHistory, "Updated includeHistory should persist in mock settings")
    }

    @MainActor func testWhenIncludeCookiesAndSiteDataChanged_ThenSettingIsPersisted() {
        // Scenario: User toggles includeCookiesAndSiteData setting.
        // Action: Change includeCookiesAndSiteData value using mock settings.
        // Expectation: Mock settings are updated and used by subsequent ViewModel.

        let mockSettings = MockFireDialogViewSettings()

        let viewModel1 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        viewModel1.includeCookiesAndSiteData = false

        XCTAssertEqual(mockSettings.lastIncludeCookiesAndSiteDataState, false, "Mock settings should be updated")

        let viewModel2 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertFalse(viewModel2.includeCookiesAndSiteData, "includeCookiesAndSiteData should be loaded from mock settings")

        viewModel2.includeCookiesAndSiteData = true

        XCTAssertEqual(mockSettings.lastIncludeCookiesAndSiteDataState, true, "Mock settings should reflect new value")

        let viewModel3 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertTrue(viewModel3.includeCookiesAndSiteData, "Updated includeCookiesAndSiteData should persist in mock settings")
    }

    @MainActor func testWhenIncludeChatHistoryChanged_ThenSettingIsPersisted() {
        // Scenario: User toggles includeChatHistory setting.
        // Action: Change includeChatHistorySetting value using mock settings.
        // Expectation: Mock settings are updated and used by subsequent ViewModel.

        let mockSettings = MockFireDialogViewSettings()

        let viewModel1 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            clearingOption: .allData,
            settings: mockSettings,
            tld: TLD()
        )

        viewModel1.includeChatHistorySetting = true

        XCTAssertEqual(mockSettings.lastIncludeChatHistoryState, true, "Mock settings should be updated")

        let viewModel2 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            clearingOption: .allData,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertTrue(viewModel2.includeChatHistorySetting, "includeChatHistorySetting should be loaded from mock settings")

        viewModel2.includeChatHistorySetting = false

        XCTAssertEqual(mockSettings.lastIncludeChatHistoryState, false, "Mock settings should reflect new value")

        let viewModel3 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            clearingOption: .allData,
            settings: mockSettings,
            tld: TLD()
        )

        XCTAssertFalse(viewModel3.includeChatHistorySetting, "Updated includeChatHistorySetting should persist in mock settings")
    }

    @MainActor func testWhenAllSettingsChanged_ThenAllSettingsPersist() {
        // Scenario: User changes all settings at once.
        // Action: Modify all dialog settings using mock settings.
        // Expectation: All mock settings are updated and used by subsequent ViewModel.

        let mockSettings = MockFireDialogViewSettings()

        let viewModel1 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        // Change all settings
        viewModel1.clearingOption = .currentWindow
        viewModel1.includeTabsAndWindows = false
        viewModel1.includeHistory = false
        viewModel1.includeCookiesAndSiteData = false
        viewModel1.includeChatHistorySetting = true

        // Verify all mock settings were updated
        XCTAssertEqual(mockSettings.lastSelectedClearingOption, .currentWindow)
        XCTAssertEqual(mockSettings.lastIncludeTabsAndWindowsState, false)
        XCTAssertEqual(mockSettings.lastIncludeHistoryState, false)
        XCTAssertEqual(mockSettings.lastIncludeCookiesAndSiteDataState, false)
        XCTAssertEqual(mockSettings.lastIncludeChatHistoryState, true)

        // Create new ViewModel with same mock settings
        let viewModel2 = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        // Verify all settings were loaded from mock settings
        XCTAssertEqual(viewModel2.clearingOption, .currentWindow, "clearingOption should be loaded from mock settings")
        XCTAssertFalse(viewModel2.includeTabsAndWindows, "includeTabsAndWindows should be loaded from mock settings")
        XCTAssertFalse(viewModel2.includeHistory, "includeHistory should be loaded from mock settings")
        XCTAssertFalse(viewModel2.includeCookiesAndSiteData, "includeCookiesAndSiteData should be loaded from mock settings")
        XCTAssertTrue(viewModel2.includeChatHistorySetting, "includeChatHistorySetting should be loaded from mock settings")
    }

    @MainActor func testWhenViewModelInitializedWithExplicitSettings_ThenExplicitSettingsOverridePersisted() {
        // Scenario: ViewModel initialized with explicit parameters should override mock settings values.
        // Action: Create ViewModel with mock settings, then create new one with explicit overrides.
        // Expectation: Explicit parameters take precedence over mock settings.

        let mockSettings = MockFireDialogViewSettings(
            lastSelectedClearingOption: .allData,
            lastIncludeTabsAndWindowsState: false,
            lastIncludeHistoryState: false,
            lastIncludeCookiesAndSiteDataState: false,
            lastIncludeChatHistoryState: true
        )

        // Create ViewModel with explicit overrides
        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            clearingOption: .currentTab,
            includeTabsAndWindows: true,
            includeHistory: true,
            includeCookiesAndSiteData: true,
            includeChatHistory: false,
            settings: mockSettings,
            tld: TLD()
        )

        // Verify explicit parameters override mock settings
        XCTAssertEqual(viewModel.clearingOption, .currentTab, "Explicit clearingOption should override mock settings")
        XCTAssertTrue(viewModel.includeTabsAndWindows, "Explicit includeTabsAndWindows should override mock settings")
        XCTAssertTrue(viewModel.includeHistory, "Explicit includeHistory should override mock settings")
        XCTAssertTrue(viewModel.includeCookiesAndSiteData, "Explicit includeCookiesAndSiteData should override mock settings")
        XCTAssertFalse(viewModel.includeChatHistorySetting, "Explicit includeChatHistory should override mock settings")
    }

    @MainActor func testWhenSettingsPersisted_ThenDefaultsUsedWhenNoPersistedValues() {
        // Scenario: Fresh start with no persisted settings (empty mock).
        // Action: Create ViewModel with empty mock settings.
        // Expectation: Default values are used.

        let mockSettings = MockFireDialogViewSettings()

        let viewModel = FireDialogViewModel(
            fireViewModel: .init(fire: fire),
            tabCollectionViewModel: tabCollectionVM,
            historyCoordinating: historyCoordinator,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner(showCleanOption: true),
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            settings: mockSettings,
            tld: TLD()
        )

        // Verify default values
        XCTAssertEqual(viewModel.clearingOption, .currentTab, "Default clearingOption should be .currentTab")
        XCTAssertTrue(viewModel.includeTabsAndWindows, "Default includeTabsAndWindows should be true")
        XCTAssertTrue(viewModel.includeHistory, "Default includeHistory should be true")
        XCTAssertTrue(viewModel.includeCookiesAndSiteData, "Default includeCookiesAndSiteData should be true")
        XCTAssertFalse(viewModel.includeChatHistorySetting, "Default includeChatHistorySetting should be false")
    }

    // MARK: - Helper Methods

    @MainActor
    private func makeViewModel(with tabCollectionViewModel: TabCollectionViewModel,
                               clearingOption: FireDialogViewModel.ClearingOption? = nil,
                               scopeCookieDomains: Set<String>? = nil) -> FireDialogViewModel {

        return FireDialogViewModel(
            fireViewModel: fireViewModel,
            tabCollectionViewModel: tabCollectionViewModel,
            historyCoordinating: fire.historyCoordinating,
            aiChatHistoryCleaner: aiChatHistoryCleaner,
            fireproofDomains: fireproofDomains,
            faviconManagement: fire.faviconManagement,
            clearingOption: clearingOption,
            scopeCookieDomains: scopeCookieDomains,
            tld: TLD()
        )
    }

    @MainActor
    private func registerMainWindow(with tabCollectionViewModel: TabCollectionViewModel) {
        let mainViewController = MainViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(),
            aiChatSidebarProvider: AIChatSidebarProvider(featureFlagger: MockFeatureFlagger()),
            fireCoordinator: fireCoordinator
        )
        let window = MockWindow(isVisible: false)
        let mainWindowController = MainWindowController(
            window: window,
            mainViewController: mainViewController,
            fireViewModel: fireViewModel,
            themeManager: MockThemeManager()
        )
        windowControllersManager.mainWindowControllers = [mainWindowController]
    }

    @MainActor
    private func handle(_ vm: FireDialogViewModel,
                        _ result: FireDialogResult,
                        onboarding: ContextualOnboardingStateUpdater? = nil) -> Task<Void, Never> {
        let isAllHistorySelected: Bool
        if vm.scopeCookieDomains != nil  {
            isAllHistorySelected = false
        } else {
            // no specific domains passed initially
            isAllHistorySelected = result.selectedCookieDomains == nil || result.selectedCookieDomains?.count == vm.selectable.count
        }

        return Task {
            await fireCoordinator.handleDialogResult(result, tabCollectionViewModel: vm.tabCollectionViewModel, isAllHistorySelected: isAllHistorySelected)
        }
    }

    private func makeFireproofDomains(_ domains: [String]) {
        domains.forEach { fireproofDomains.add(domain: $0) }
    }

    private func makeHistoryEntry(url: String) -> HistoryEntry {
        HistoryEntry(identifier: UUID(),
                     url: URL(string: url)!,
                     failedToLoad: false,
                     numberOfTotalVisits: 1,
                     lastVisit: Date(),
                     visits: [],
                     numberOfTrackersBlocked: 0,
                     blockedTrackingEntities: [],
                     trackersFound: false)
    }

    @MainActor
    private func makeTab(url: URL, historyMock: HistoryTabExtensionMock? = nil) -> Tab {
        let mock = historyMock ?? {
            let mock = HistoryTabExtensionMock()
            let entry = makeHistoryEntry(url: url.absoluteString)
            mock.localHistory = [Visit(date: Date(), identifier: entry.url, historyEntry: entry)]
            return mock
        }()
        let extensionBuilder = TestTabExtensionsBuilder(load: [HistoryTabExtensionMock.self]) { builder in { _, _ in
            builder.override {
                mock
            }
        }}
        return Tab(content: .url(url, source: .link), webViewConfiguration: schemeHandler.webViewConfiguration(), extensionsBuilder: extensionBuilder)
    }

}

class MockFireDialogViewSettings: FireDialogViewSettings {
    var lastSelectedClearingOption: FireDialogViewModel.ClearingOption?
    var lastIncludeTabsAndWindowsState: Bool?
    var lastIncludeHistoryState: Bool?
    var lastIncludeCookiesAndSiteDataState: Bool?
    var lastIncludeChatHistoryState: Bool?

    init(lastSelectedClearingOption: FireDialogViewModel.ClearingOption? = nil, lastIncludeTabsAndWindowsState: Bool? = nil, lastIncludeHistoryState: Bool? = nil, lastIncludeCookiesAndSiteDataState: Bool? = nil, lastIncludeChatHistoryState: Bool? = nil) {
        self.lastSelectedClearingOption = lastSelectedClearingOption
        self.lastIncludeTabsAndWindowsState = lastIncludeTabsAndWindowsState
        self.lastIncludeHistoryState = lastIncludeHistoryState
        self.lastIncludeCookiesAndSiteDataState = lastIncludeCookiesAndSiteDataState
        self.lastIncludeChatHistoryState = lastIncludeChatHistoryState
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

final class WebCacheManagerMock: WebCacheManager {

    init() {
        super.init(fireproofDomains: MockFireproofDomains(domains: []))
    }

    var clearCalled = false
    override func clear(baseDomains: Set<String>? = nil) async {
        clearCalled = true
    }
}
private final class TestPresenter: FireDialogViewPresenting {
    private let handler: (NSWindow?, (() -> Void)?) -> Void
    init(handler: @escaping (NSWindow?, (() -> Void)?) -> Void) { self.handler = handler }
    func present(in window: NSWindow, completion: (() -> Void)?) { handler(window, completion) }
}

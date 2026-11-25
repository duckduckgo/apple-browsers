//
//  WindowControllersManagerOnboardingTests.swift
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

import AppKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Covers how onboarding hands its tab over to browsing when it ends.
@MainActor
final class WindowControllersManagerOnboardingTests: XCTestCase {

    private var sut: WindowControllersManager!

    override func setUp() {
        super.setUp()
        sut = WindowControllersManager(
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true, usesUnifiedFeedbackForm: false),
            internalUserDecider: MockInternalUserDecider(),
            pinningManager: MockPinningManager()
        )
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testReplaceTabWith_WhenOnboardingIsTheOnlyTab_ReplacesItWithoutEmptyingTheWindow() {
        let onboardingTab = Tab(content: .onboarding)
        let viewModel = registerWindow(tabs: [onboardingTab], selectedIndex: 0)
        var tabCounts: [Int] = []
        let cancellable = viewModel.tabCollection.$tabs.sink { tabCounts.append($0.count) }
        let replacement = Tab(content: .newtab)

        sut.replaceTabWith(replacement)

        XCTAssertEqual(viewModel.tabCollection.tabs.count, 1)
        XCTAssertTrue(viewModel.tabCollection.contains(tab: replacement))
        XCTAssertFalse(tabCounts.contains(0), "The window closes if it ever has no tabs")
        cancellable.cancel()
    }

    func testReplaceTabWith_ReplacesTheSelectedTabAndKeepsTheOthers() {
        let otherTab = Tab(content: .newtab)
        let onboardingTab = Tab(content: .onboarding)
        let viewModel = registerWindow(tabs: [otherTab, onboardingTab], selectedIndex: 1)
        let replacement = Tab(content: .newtab)

        sut.replaceTabWith(replacement)

        XCTAssertTrue(viewModel.tabCollection.contains(tab: otherTab))
        XCTAssertTrue(viewModel.tabCollection.contains(tab: replacement))
        XCTAssertFalse(viewModel.tabCollection.contains(tab: onboardingTab))
        XCTAssertEqual(viewModel.tabCollection.tabs.count, 2)
    }

    func testDuckAILock_LocksTheWindowButLeavesFireEnabled() {
        let windowController = registerLoadedWindow()

        sut.setUILock(.locked(except: [.fire]))

        XCTAssertEqual(sut.userInteractionLock, .locked(except: [.fire]))
        XCTAssertFalse(windowController.mainViewController.tabCollectionViewModel.changesEnabled)
        XCTAssertTrue(windowController.mainViewController.tabBarViewController.fireButton.isEnabled)
    }

    func testOnboardingLock_LocksFireToo() {
        let windowController = registerLoadedWindow()

        sut.updatePreventUserInteraction(prevent: true)

        XCTAssertEqual(sut.userInteractionLock, .locked())
        XCTAssertFalse(windowController.mainViewController.tabBarViewController.fireButton.isEnabled)
    }

    func testLock_DisablesTheWindowMenuItemsUntilUnlocked() {
        let mainViewController = registerLoadedWindow().mainViewController
        let newTab = NSMenuItem(title: "", action: #selector(MainViewController.newTab(_:)), keyEquivalent: "")
        let sidebar = NSMenuItem(title: "", action: #selector(MainViewController.toggleDuckAISidebar(_:)), keyEquivalent: "")

        sut.setUILock(.locked(except: [.fire]))

        XCTAssertFalse(mainViewController.validateMenuItem(newTab))
        XCTAssertFalse(mainViewController.validateMenuItem(sidebar))

        sut.setUILock(.unlocked)

        XCTAssertTrue(mainViewController.validateMenuItem(newTab))
        XCTAssertTrue(mainViewController.validateMenuItem(sidebar))
    }

    func testLockAndUnlock_ReachEveryWindow() {
        let first = registerLoadedWindow()
        let second = registerLoadedWindow()

        sut.setUILock(.locked(except: [.fire]))

        XCTAssertFalse(first.mainViewController.tabCollectionViewModel.changesEnabled)
        XCTAssertFalse(second.mainViewController.tabCollectionViewModel.changesEnabled)

        sut.setUILock(.unlocked)

        XCTAssertTrue(first.mainViewController.tabCollectionViewModel.changesEnabled)
        XCTAssertTrue(second.mainViewController.tabCollectionViewModel.changesEnabled)
    }

    func testWindowOpenedWhileLocked_StartsLocked() {
        sut.setUILock(.locked(except: [.fire]))

        let windowController = registerLoadedWindow()

        XCTAssertFalse(windowController.mainViewController.tabCollectionViewModel.changesEnabled)
        XCTAssertTrue(windowController.mainViewController.tabBarViewController.fireButton.isEnabled)
    }
}

private extension WindowControllersManagerOnboardingTests {

    /// Loads the views before registering, as the app does when a window is first shown.
    func registerLoadedWindow() -> MainWindowController {
        let windowController = makeWindowController(tabs: [Tab(content: .newtab)], selectedIndex: 0)
        _ = windowController.mainViewController.view
        sut.register(windowController)
        return windowController
    }

    func registerWindow(tabs: [Tab], selectedIndex: Int) -> TabCollectionViewModel {
        let windowController = makeWindowController(tabs: tabs, selectedIndex: selectedIndex)
        sut.register(windowController)
        return windowController.mainViewController.tabCollectionViewModel
    }

    func makeWindowController(tabs: [Tab], selectedIndex: Int) -> MainWindowController {
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs), windowControllersManager: WindowControllersManagerMock())
        tabCollectionViewModel.select(at: .unpinned(selectedIndex))
        let mainViewController = MainViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
            aiChatSessionStore: AIChatSessionStore(featureFlagger: MockFeatureFlagger())
        )
        let window = MockWindow(isVisible: false)
        let windowController = MainWindowController(
            window: window,
            mainViewController: mainViewController,
            fireViewModel: Application.appDelegate.fireCoordinator.fireViewModel,
            themeManager: MockThemeManager()
        )
        windowController.window = window
        return windowController
    }
}

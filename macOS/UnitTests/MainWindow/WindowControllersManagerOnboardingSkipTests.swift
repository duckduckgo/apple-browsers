//
//  WindowControllersManagerOnboardingSkipTests.swift
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

import Combine
import FeatureFlags_macOS
import PrivacyConfig
@_spi(Testing) import PixelKit
import PrivacyConfigTestsUtils
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Covers how `WindowControllersManager` decides that onboarding was skipped. Every way of leaving
/// onboarding is a skip, including burn on exit. Ordinary quit cleanup detaches tracking first
/// so unfinished onboarding can appear again on the next launch.
@MainActor
final class WindowControllersManagerOnboardingSkipTests: XCTestCase {

    private var sut: WindowControllersManager!
    private var featureFlagger: MockFeatureFlagger!
    private var closeCount = 0
    private var skipInPlaceCount = 0

    override func setUp() {
        super.setUp()

        closeCount = 0
        skipInPlaceCount = 0
        featureFlagger = MockFeatureFlagger()

        sut = WindowControllersManager(
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true, usesUnifiedFeedbackForm: false),
            internalUserDecider: MockInternalUserDecider(),
            featureFlagger: featureFlagger,
            pinningManager: MockPinningManager()
        )
    }

    override func tearDown() {
        sut = nil
        featureFlagger = nil

        super.tearDown()
    }

    // MARK: - Closing the window

    func testClosingTheWindowHostingOnboardingRecordsSkipInPlace() {
        let (windowController, _) = startOnboarding()

        sut.unregister(windowController)

        XCTAssertEqual(skipInPlaceCount, 1)
        XCTAssertEqual(closeCount, 0)
        XCTAssertFalse(sut.hasOnboardingTab)
    }

    func testClosingTheWindowWhileQuittingRecordsNothing() {
        let (windowController, _) = startOnboarding()
        sut.setOnboardingTab(nil)

        sut.unregister(windowController)

        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertFalse(sut.hasOnboardingTab)
    }

    func testClosingAWindowThatDoesNotHostOnboardingRecordsNothing() {
        _ = startOnboarding()
        let (otherWindowController, _) = makeWindowController(initialTab: Tab(content: .newtab))
        sut.register(otherWindowController)

        sut.unregister(otherWindowController)

        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertTrue(sut.hasOnboardingTab)
    }

    // MARK: - Removing the tab

    func testBulkCloseNotifiesOnlyRemovedTabsAndRecordsSkipOnce() {
        let (window, onboardingTab) = startOnboarding()
        let viewModel = window.mainViewController.tabCollectionViewModel
        let keptTab = Tab(content: .newtab)
        keptTab.onClose = { XCTFail("The preserved tab must not receive a close notification") }
        viewModel.append(tab: keptTab)

        viewModel.removeAllTabs(except: 1)
        sut.unregister(window)

        XCTAssertFalse(viewModel.tabCollection.contains(tab: onboardingTab))
        XCTAssertTrue(viewModel.tabCollection.contains(tab: keptTab))
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertFalse(sut.hasOnboardingTab)
    }

    func testBulkCloseWhileQuittingRecordsNothing() {
        let (window, _) = startOnboarding()
        sut.setOnboardingTab(nil)

        window.mainViewController.tabCollectionViewModel.removeAllTabs()

        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertFalse(sut.hasOnboardingTab)
    }

    func testUserInitiatedCloseRecordsSkipAndRemovesLastTabWithoutReplacement() throws {
        let (window, onboardingTab) = startOnboarding()
        let viewModel = window.mainViewController.tabCollectionViewModel
        let index = try XCTUnwrap(viewModel.indexInAllTabs(of: onboardingTab))

        viewModel.close(at: index)

        XCTAssertTrue(viewModel.tabCollection.tabs.isEmpty)
        XCTAssertFalse(sut.hasOnboardingTab)
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(skipInPlaceCount, 0)
    }

    // MARK: - Only the first outcome counts

    func testQuitCleanupDetachesNavigationAndRejectsLateHandlerInstallation() {
        let (_, onboardingTab) = startOnboarding()
        sut.setOnboardingTab(nil)

        sut.setOnboardingHandlers(onClose: { _ in XCTFail("Late close handler") },
                                  onSkipInPlace: { XCTFail("Late skip handler") })
        onboardingTab.setContent(.newtab)

        XCTAssertNil(onboardingTab.onClose)
        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertEqual(closeCount, 0)
    }

    func testClosingAnotherTabLeavesOnboardingAvailableForStartBrowsing() throws {
        let (window, onboardingTab) = startOnboarding()
        let viewModel = window.mainViewController.tabCollectionViewModel
        let browsingTab = Tab(content: .newtab)
        viewModel.append(tab: browsingTab)
        let index = try XCTUnwrap(viewModel.indexInAllTabs(of: browsingTab))
        viewModel.close(at: index)

        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(sut.onboardingTab(for: onboardingTab.webView) === onboardingTab)
        let replacement = Tab(content: .newtab)
        XCTAssertTrue(sut.replaceOnboardingTab(onboardingTab, with: replacement))
        XCTAssertFalse(viewModel.tabCollection.contains(tab: onboardingTab))
        XCTAssertTrue(viewModel.tabCollection.contains(tab: replacement))
        XCTAssertEqual(skipInPlaceCount, 0)
    }

    func testOldCloseCallbackCannotSkipOrClearAnotherOnboardingTab() {
        let (_, oldTab) = startOnboarding()
        let oldOnClose = oldTab.onClose
        let (_, newTab) = startOnboarding()

        oldOnClose?()
        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(sut.onboardingTab(for: newTab.webView) === newTab)
        XCTAssertTrue(sut.hasOnboardingTab)
    }

    func testSourceScopedReplacementRejectsTabThatAlreadyNavigatedAway() {
        let (window, tab) = startOnboarding()
        tab.setContent(.newtab)
        XCTAssertFalse(sut.replaceOnboardingTab(tab, with: Tab(content: .newtab)))
        XCTAssertTrue(window.mainViewController.tabCollectionViewModel.tabCollection.contains(tab: tab))
    }
}

private extension WindowControllersManagerOnboardingSkipTests {

    /// Registers a window whose selected tab hosts onboarding and wires it up the way
    /// `MainWindowController` does, returning both for the test to act on.
    func startOnboarding() -> (MainWindowController, Tab) {
        let onboardingTab = Tab(content: .onboarding)
        let (windowController, _) = makeWindowController(initialTab: onboardingTab)
        sut.register(windowController)
        sut.setOnboardingTab(onboardingTab)
        sut.setOnboardingHandlers(
            onClose: { [weak self] _ in self?.closeCount += 1 },
            onSkipInPlace: { [weak self] in self?.skipInPlaceCount += 1 }
        )

        return (windowController, onboardingTab)
    }

    /// Builds a real `MainWindowController` hosting a `TabCollectionViewModel` seeded with
    /// `initialTab`, mirroring the fixture `FullscreenControllerTests.swift` uses — everything
    /// `MainViewController` doesn't need for these tests defaults to the live app's own dependencies.
    func makeWindowController(initialTab: Tab) -> (MainWindowController, TabCollectionViewModel) {
        let tabCollection = TabCollection(tabs: [initialTab])
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: tabCollection, windowControllersManager: WindowControllersManagerMock())
        let mainViewController = MainViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
            aiChatSessionStore: AIChatSessionStore(featureFlagger: featureFlagger)
        )

        let window = MockWindow(isVisible: false)
        let windowController = MainWindowController(
            window: window,
            mainViewController: mainViewController,
            fireViewModel: Application.appDelegate.fireCoordinator.fireViewModel,
            themeManager: MockThemeManager()
        )
        windowController.window = window

        return (windowController, tabCollectionViewModel)
    }
}

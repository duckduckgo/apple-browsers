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
/// onboarding is a skip except quitting, which records nothing so that onboarding shows again on the
/// next launch, matching what the blocking flow does today. Quit cleanup detaches tracking first.
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

    func testCancelingAutoClearLeavesWindowSkipTrackingActive() {
        let (windowController, _) = startOnboarding()
        let preferences = DataClearingPreferences(
            persistor: MockFireButtonPreferencesPersistor(),
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: featureFlagger,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner())
        preferences.isAutoClearEnabled = true
        preferences.isWarnBeforeClearingEnabled = true
        let alert = MockAutoClearAlertPresenter()
        alert.responseToReturn = .alertThirdButtonReturn
        let handler = AutoClearHandler(
            dataClearingPreferences: preferences,
            startupPreferences: Application.appDelegate.startupPreferences,
            fireViewModel: Application.appDelegate.fireCoordinator.fireViewModel,
            stateRestorationManager: MockAppStateRestorationManager(),
            aiChatSyncCleaner: nil, wideEvent: WideEventMock(), pixelFiring: nil,
            alertPresenter: alert,
            willPerformAutoClear: { [sut] in sut?.setOnboardingTab(nil) })

        guard case .sync(.cancel) = handler.shouldTerminate(isAsync: false) else {
            return XCTFail("Expected canceled quit")
        }
        sut.unregister(windowController)

        XCTAssertEqual(skipInPlaceCount, 1)
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

    func testBulkRemovalRecordsSkipInPlaceAndLeavesTheTabAlone() {
        let (_, onboardingTab) = startOnboarding()

        let allowsRemoval = onboardingTab.closeInterceptor?(.bulk)

        XCTAssertEqual(allowsRemoval, false)
        XCTAssertEqual(skipInPlaceCount, 1)
        XCTAssertFalse(sut.hasOnboardingTab)
    }

    func testBulkRemovalWhileQuittingRecordsNothingAndReleasesTracking() {
        let (_, onboardingTab) = startOnboarding()
        sut.setOnboardingTab(nil)

        let allowsRemoval = onboardingTab.closeInterceptor?(.bulk)

        XCTAssertNil(allowsRemoval)
        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertFalse(sut.hasOnboardingTab)
    }

    func testUserInitiatedCloseRecordsSkipAndRemovesLastTabWithoutReplacement() throws {
        let (window, onboardingTab) = startOnboarding()
        let viewModel = window.mainViewController.tabCollectionViewModel
        let index = try XCTUnwrap(viewModel.indexInAllTabs(of: onboardingTab))

        viewModel.remove(at: index, reason: .userInitiated)

        XCTAssertTrue(viewModel.tabCollection.tabs.isEmpty)
        XCTAssertFalse(sut.hasOnboardingTab)
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(skipInPlaceCount, 0)
    }

    // MARK: - Only the first outcome counts

    func testSkipIsRecordedOnceWhenSeveralPathsFireForTheSameSession() {
        let (windowController, onboardingTab) = startOnboarding()

        // The tab is swept up in a bulk close and its window then closes behind it.
        _ = onboardingTab.closeInterceptor?(.bulk)
        sut.unregister(windowController)

        XCTAssertEqual(skipInPlaceCount, 1)
    }

    func testQuitCleanupDetachesNavigationAndRejectsLateHandlerInstallation() {
        let (_, onboardingTab) = startOnboarding()
        sut.setOnboardingTab(nil)

        sut.setOnboardingHandlers(onClose: { _ in XCTFail("Late close handler") },
                                  onSkipInPlace: { XCTFail("Late skip handler") })
        onboardingTab.setContent(.newtab)

        XCTAssertNil(onboardingTab.closeInterceptor)
        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertEqual(closeCount, 0)
    }

    func testClosingAnotherTabLeavesOnboardingAvailableForStartBrowsing() throws {
        let (window, onboardingTab) = startOnboarding()
        let viewModel = window.mainViewController.tabCollectionViewModel
        let browsingTab = Tab(content: .newtab)
        viewModel.append(tab: browsingTab)
        let index = try XCTUnwrap(viewModel.indexInAllTabs(of: browsingTab))
        viewModel.remove(at: index, reason: .userInitiated)

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
        let oldInterceptor = oldTab.closeInterceptor
        let (_, newTab) = startOnboarding()

        XCTAssertEqual(oldInterceptor?(.bulk), false)
        XCTAssertEqual(oldInterceptor?(.userInitiated), false)
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

    func testRetrackingOnboardingDiscardsTheOldTabsInterceptor() {
        let (_, onboardingTab) = startOnboarding()

        sut.setOnboardingTab(nil)
        let allowsRemoval = onboardingTab.closeInterceptor?(.bulk)

        XCTAssertNil(allowsRemoval)
        XCTAssertEqual(skipInPlaceCount, 0)
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

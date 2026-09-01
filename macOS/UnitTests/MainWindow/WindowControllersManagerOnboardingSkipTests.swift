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
import PrivacyConfigTestsUtils
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Covers how `WindowControllersManager` decides that onboarding was skipped. Every way of leaving
/// onboarding is a skip except quitting, which records nothing so that onboarding shows again on the
/// next launch, matching what the blocking flow does today. Closing a window and quitting both close
/// windows, so `isTerminating` is the only thing separating them.
@MainActor
final class WindowControllersManagerOnboardingSkipTests: XCTestCase {

    private var sut: WindowControllersManager!
    private var featureFlagger: MockFeatureFlagger!
    private var isTerminating = false
    private var closeCount = 0
    private var skipInPlaceCount = 0

    override func setUp() {
        super.setUp()

        isTerminating = false
        closeCount = 0
        skipInPlaceCount = 0
        featureFlagger = MockFeatureFlagger()

        sut = WindowControllersManager(
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true, usesUnifiedFeedbackForm: false),
            internalUserDecider: MockInternalUserDecider(),
            featureFlagger: featureFlagger,
            pinningManager: MockPinningManager(),
            isTerminating: { [weak self] in self?.isTerminating == true }
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
        isTerminating = true

        sut.unregister(windowController)

        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertTrue(sut.hasOnboardingTab, "Quitting leaves tracking in place; the app is going away regardless.")
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
        isTerminating = true

        let allowsRemoval = onboardingTab.closeInterceptor?(.bulk)

        XCTAssertEqual(allowsRemoval, false)
        XCTAssertEqual(skipInPlaceCount, 0)
        XCTAssertFalse(sut.hasOnboardingTab)
    }

    func testUserInitiatedCloseHandsOverToOnCloseAndAllowsRemoval() {
        let (_, onboardingTab) = startOnboarding()

        let allowsRemoval = onboardingTab.closeInterceptor?(.userInitiated)

        XCTAssertEqual(allowsRemoval, true)
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(skipInPlaceCount, 0, "Closing the tab is reported by the onClose path, not as a skip in place.")
    }

    // MARK: - Only the first outcome counts

    func testSkipIsRecordedOnceWhenSeveralPathsFireForTheSameSession() {
        let (windowController, onboardingTab) = startOnboarding()

        // The tab is swept up in a bulk close and its window then closes behind it.
        _ = onboardingTab.closeInterceptor?(.bulk)
        sut.unregister(windowController)

        XCTAssertEqual(skipInPlaceCount, 1)
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
            onClose: { [weak self] in self?.closeCount += 1 },
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

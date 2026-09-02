//
//  WindowControllersManagerBrowsingBeforeCompletionTests.swift
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
import PixelExperimentKit
import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Covers `WindowControllersManager`'s `.browsingBeforeCompletion` detection: it should fire the
/// first time the user completes a navigation to a real URL in a tab other than the onboarding
/// tab, while onboarding is unfinished — in any window, including ones opened after tracking
/// started — and it should stop watching once onboarding tracking is torn down.
@MainActor
final class WindowControllersManagerBrowsingBeforeCompletionTests: XCTestCase {

    private var firedEvents: [PixelKit.Event]!
    private var featureFlagger: MockFeatureFlagger!
    private var sut: WindowControllersManager!
    private var isOnboardingFinishedDefault: UserDefaultsWrapper<Bool>!

    override func setUp() {
        super.setUp()

        firedEvents = []
        featureFlagger = MockFeatureFlagger(resolveCohortStub: FeatureFlag.OnboardingNonBlockingCohort.treatment)
        configureExperimentKit(cohort: .treatment)

        isOnboardingFinishedDefault = UserDefaultsWrapper(key: .onboardingFinished, defaultValue: false)
        isOnboardingFinishedDefault.wrappedValue = false

        sut = WindowControllersManager(
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true, usesUnifiedFeedbackForm: false),
            internalUserDecider: MockInternalUserDecider(),
            featureFlagger: featureFlagger,
            pinningManager: MockPinningManager(),
            isTerminating: { false }
        )
    }

    override func tearDown() {
        // The experiment kit's fire closure is global and outlives this class, so hand it back a
        // sink that captures nothing — otherwise a later test firing an experiment pixel would
        // reach into this instance after its properties are gone.
        PixelKit.configureExperimentKit(featureFlagger: MockFeatureFlagger(),
                                        eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()),
                                        fire: { _, _, _ in })

        isOnboardingFinishedDefault.wrappedValue = false
        isOnboardingFinishedDefault = nil
        sut = nil
        featureFlagger = nil
        firedEvents = nil

        super.tearDown()
    }

    // MARK: - Fires

    func testFiresOnFirstNavigationInNonOnboardingTabWhileOnboardingUnfinished() {
        let onboardingTab = Tab(content: .onboarding)
        let (windowController, tabCollectionViewModel) = makeWindowController(initialTab: onboardingTab)
        sut.register(windowController)
        sut.setOnboardingTab(onboardingTab)
        sut.setOnboardingHandlers(onClose: {}, onSkipInPlace: {})

        let browsingTab = Tab(content: .url(URL(string: "https://example.com")!, source: .ui))
        tabCollectionViewModel.tabCollection.append(tab: browsingTab)

        browsingTab.navigationDidEndPublisher.send(browsingTab)

        XCTAssertTrue(firedEvents.contains { $0.parameters?["metric"] == "browsingBeforeCompletion" })
    }

    func testObservesTabsInWindowsRegisteredAfterOnboardingStarted() {
        let onboardingTab = Tab(content: .onboarding)
        let (firstWindowController, _) = makeWindowController(initialTab: onboardingTab)
        sut.register(firstWindowController)
        sut.setOnboardingTab(onboardingTab)
        sut.setOnboardingHandlers(onClose: {}, onSkipInPlace: {})

        // A second window, opened after tracking had already started.
        let (secondWindowController, secondTabCollectionViewModel) = makeWindowController(initialTab: Tab(content: .newtab))
        sut.register(secondWindowController)

        let browsingTab = Tab(content: .url(URL(string: "https://example.com")!, source: .ui))
        secondTabCollectionViewModel.tabCollection.append(tab: browsingTab)

        browsingTab.navigationDidEndPublisher.send(browsingTab)

        XCTAssertTrue(firedEvents.contains { $0.parameters?["metric"] == "browsingBeforeCompletion" })
    }

    // MARK: - Does not fire

    /// Navigating the onboarding tab away is itself recorded as a skip, and a skip retires tracking,
    /// so no later navigation counts as browsing before completion. The onboarding tab is also
    /// excluded by identity, but that guard is unreachable in practice: while the tab is tracked its
    /// content is `.onboarding`, which the content check already rejects.
    func testDoesNotFireOnceOnboardingWasSkippedByNavigatingAway() {
        let onboardingTab = Tab(content: .onboarding)
        let (windowController, tabCollectionViewModel) = makeWindowController(initialTab: onboardingTab)
        sut.register(windowController)
        sut.setOnboardingTab(onboardingTab)
        sut.setOnboardingHandlers(onClose: {}, onSkipInPlace: {})

        onboardingTab.setContent(.url(URL(string: "https://duckduckgo.com")!, source: .ui))

        let browsingTab = Tab(content: .url(URL(string: "https://example.com")!, source: .ui))
        tabCollectionViewModel.tabCollection.append(tab: browsingTab)

        browsingTab.navigationDidEndPublisher.send(browsingTab)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testDoesNotFireForNonUrlContent() {
        let onboardingTab = Tab(content: .onboarding)
        let (windowController, tabCollectionViewModel) = makeWindowController(initialTab: onboardingTab)
        sut.register(windowController)
        sut.setOnboardingTab(onboardingTab)
        sut.setOnboardingHandlers(onClose: {}, onSkipInPlace: {})

        let newTab = Tab(content: .newtab)
        tabCollectionViewModel.tabCollection.append(tab: newTab)

        newTab.navigationDidEndPublisher.send(newTab)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testDoesNotFireWhenOnboardingAlreadyFinished() {
        isOnboardingFinishedDefault.wrappedValue = true

        let onboardingTab = Tab(content: .onboarding)
        let (windowController, tabCollectionViewModel) = makeWindowController(initialTab: onboardingTab)
        sut.register(windowController)
        sut.setOnboardingTab(onboardingTab)
        sut.setOnboardingHandlers(onClose: {}, onSkipInPlace: {})

        let browsingTab = Tab(content: .url(URL(string: "https://example.com")!, source: .ui))
        tabCollectionViewModel.tabCollection.append(tab: browsingTab)

        browsingTab.navigationDidEndPublisher.send(browsingTab)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testStopsObservingOnceOnboardingTrackingIsCleared() {
        let onboardingTab = Tab(content: .onboarding)
        let (windowController, tabCollectionViewModel) = makeWindowController(initialTab: onboardingTab)
        sut.register(windowController)
        sut.setOnboardingTab(onboardingTab)
        sut.setOnboardingHandlers(onClose: {}, onSkipInPlace: {})

        // Onboarding tracking ends (e.g. completion replaced the tab, or the tab was closed).
        sut.setOnboardingTab(nil)

        let browsingTab = Tab(content: .url(URL(string: "https://example.com")!, source: .ui))
        tabCollectionViewModel.tabCollection.append(tab: browsingTab)

        browsingTab.navigationDidEndPublisher.send(browsingTab)

        XCTAssertTrue(firedEvents.isEmpty)
    }
}

private extension WindowControllersManagerBrowsingBeforeCompletionTests {

    /// Builds a real `MainWindowController` hosting a `TabCollectionViewModel` seeded with
    /// `initialTab`, mirroring the fixture `MainViewControllerDefaultBrowserPromptTests` uses in
    /// `FullscreenControllerTests.swift` — everything `MainViewController` doesn't need for this
    /// test defaults to the live app's own dependencies.
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

    func configureExperimentKit(cohort: FeatureFlag.OnboardingNonBlockingCohort?) {
        if let cohort {
            let subfeatureID = MacOSBrowserConfigSubfeature.onboardingNonBlocking.rawValue
            featureFlagger.allActiveExperiments = [
                subfeatureID: ExperimentData(
                    parentID: PrivacyFeature.macOSBrowserConfig.rawValue,
                    cohortID: cohort.rawValue,
                    enrollmentDate: Date()
                )
            ]
        }
        PixelKit.configureExperimentKit(
            featureFlagger: featureFlagger,
            eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()),
            fire: { [weak self] event, _, _ in self?.firedEvents?.append(event) }
        )
    }
}

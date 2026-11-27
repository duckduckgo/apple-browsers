//
//  ContextualDaxDialogsFactoryTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import FoundationExtensions
import History
import HistoryView
import Onboarding
import PrivacyConfig
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class ContextualDaxDialogsFactoryTests: XCTestCase {
    private var factory: ContextualDaxDialogsFactory!
    private var delegate: CapturingOnboardingNavigationDelegate!
    private var reporter: CapturingOnboardingPixelReporter!
    private var featureFlagger: MockFeatureFlagger!
    private var fireCoordinator: FireCoordinator!
    private var windowControllersManager: WindowControllersManagerMock!

    @MainActor
    override func setUpWithError() throws {
        reporter = CapturingOnboardingPixelReporter()
        windowControllersManager = WindowControllersManagerMock()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.contextualOnboarding]

        let fireproofDomains = MockFireproofDomains()
        let faviconManager = FaviconManagerMock()
        let dataClearingPreferences = DataClearingPreferences(persistor: MockFireButtonPreferencesPersistor(),
                                                              fireproofDomains: fireproofDomains,
                                                              faviconManager: faviconManager,
                                                              windowControllersManager: windowControllersManager,
                                                              featureFlagger: featureFlagger,
                                                              aiChatHistoryCleaner: MockAIChatHistoryCleaner())

        fireCoordinator = FireCoordinator(tld: TLD(),
                                          featureFlagger: featureFlagger,
                                          historyCoordinating: HistoryCoordinatingMock(),
                                          visualizeFireAnimationDecider: nil,
                                          onboardingContextualDialogsManager: nil,
                                          fireproofDomains: fireproofDomains,
                                          faviconManagement: faviconManager,
                                          windowControllersManager: windowControllersManager,
                                          dataClearingPreferences: dataClearingPreferences,
                                          pixelFiring: nil,
                                          historyProvider: MockHistoryViewDataProvider())
        factory = DefaultContextualDaxDialogViewFactory(onboardingPixelReporter: reporter, fireCoordinator: fireCoordinator)
        delegate = CapturingOnboardingNavigationDelegate()
    }

    @MainActor override func tearDownWithError() throws {
        factory = nil
        delegate = nil
        reporter = nil
        featureFlagger = nil
        windowControllersManager = nil
        fireCoordinator = nil
    }

    // MARK: - Rebranded Onboarding

    func testWhenMakeRebrandedViewThenDialogShownPixelIsFiredForDialogType() {
        // GIVEN
        let dialogType = ContextualDialogType.tryASearch
        let factory = RebrandedContextualDaxDialogsFactory(onboardingPixelReporter: reporter, fireCoordinator: fireCoordinator)

        // WHEN
        _ = factory.makeView(for: dialogType, delegate: delegate, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {}, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        XCTAssertEqual(reporter.shownDialog, dialogType)
    }

    func testWhenMakeRebrandedViewForThatsDuckAIThenDialogShownPixelIsFired() {
        // GIVEN
        let factory = RebrandedContextualDaxDialogsFactory(onboardingPixelReporter: reporter, fireCoordinator: fireCoordinator)

        // WHEN
        _ = factory.makeView(for: .thatsDuckAI, delegate: delegate, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {}, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        XCTAssertEqual(reporter.shownDialog, .thatsDuckAI)
    }

    func testWhenMakeRebrandedBubbleForThatsDuckAIThenThatsDuckAIDialogIsUsedInsteadOfFireDialog() {
        // GIVEN
        let factory = RebrandedContextualDaxDialogsFactory(onboardingPixelReporter: reporter, fireCoordinator: fireCoordinator)

        // WHEN
        let result = factory.makeBubbleView(for: .thatsDuckAI, delegate: delegate, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {}, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        XCTAssertNotNil(find(OnboardingRebranding.OnboardingThatsDuckAIDialog.self, in: result))
        XCTAssertNil(find(OnboardingRebranding.OnboardingFireDialog.self, in: result))
    }

    func testWhenMakeRebrandedBubbleForTryDuckAIThenTryDuckAIDialogIsUsedInsteadOfHighFive() {
        // GIVEN
        let factory = RebrandedContextualDaxDialogsFactory(onboardingPixelReporter: reporter, fireCoordinator: fireCoordinator)

        // WHEN
        let result = factory.makeBubbleView(for: .tryDuckAI, delegate: delegate, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {}, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        XCTAssertNotNil(find(OnboardingRebranding.OnboardingTryDuckAIDialogContent.self, in: result))
        XCTAssertNil(find(OnboardingRebranding.OnboardingEndOfJourneyDialogContent.self, in: result))
    }

    func testWhenTryDuckAIShownThenOnboardingFinishedIsMeasured() {
        // WHEN
        _ = factory.makeBubbleView(for: .tryDuckAI, delegate: delegate, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {}, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        XCTAssertTrue(reporter.measureLastDialogShownCalled)
    }

    func testWhenTryDuckAIThenTheDialogClosesAndDuckAIOpens() {
        // GIVEN
        var dismissed = false

        // WHEN
        RebrandedContextualDaxDialogsFactory.tryDuckAIAction(delegate: delegate, onboardingPixelReporter: reporter, onDismiss: { dismissed = true })()

        // THEN
        XCTAssertTrue(reporter.measureTryDuckAIPressedCalled)
        XCTAssertTrue(dismissed)
        XCTAssertTrue(delegate.didNavigateToCalled)
        XCTAssertEqual(delegate.capturedUrlString, AIChatRemoteSettings().aiChatURL.absoluteString)
    }

    // MARK: - Default Onboarding

    func testWhenMakeViewForTryASearchThenOnboardingTrySearchDialogViewCreatedAndOnActionExpectedSearchOccurs() throws {
        // GIVEN
        let dialogType = ContextualDialogType.tryASearch
        var onSuggestionPressedRun = false
        let onSuggestionPressed = { onSuggestionPressedRun = true }
        var onDismissRun = false
        let onDismiss = { onDismissRun = true }
        var onManualDismissRun = false
        let onManualDismiss = { onManualDismissRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: {}, onFireButtonPressed: {}, onSuggestionPressed: onSuggestionPressed)

        // THEN
        let view = try XCTUnwrap(find(OnboardingTrySearchDialog.self, in: result))
        XCTAssertTrue(view.viewModel.delegate === delegate)
        XCTAssertEqual(reporter.shownDialog, dialogType)

        // WHEN
        let query = "some search"
        view.viewModel.listItemPressed(ContextualOnboardingListItem.search(title: query))
        view.onManualDismiss()

        // THEN
        XCTAssertTrue(delegate.didCallSearchFor)
        XCTAssertEqual(delegate.capturedQuery, query)
        XCTAssertTrue(onSuggestionPressedRun)
        XCTAssertFalse(onDismissRun)
        XCTAssertTrue(onManualDismissRun)
    }

    func testWhenMakeViewForSearchDoneWithShouldFollowUpThenOnboardingsearchDoneViewCreatedAndOnActionNothingOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let dialogType = ContextualDialogType.searchDone(shouldFollowUp: true)
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }
        var onManualDismissRun = false
        let onManualDismiss = { onManualDismissRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingFirstSearchDoneDialog.self, in: result))
        let subView = find(OnboardingTryVisitingSiteDialogContent.self, in: result)
        XCTAssertNil(subView)
        XCTAssertEqual(reporter.shownDialog, dialogType)

        // WHEN
        view.gotItAction()

        // THEN
        XCTAssertFalse(onDismissRun)
        XCTAssertTrue(onGotItPressedRun)

        // WHEN
        onDismissRun = false
        view.onManualDismiss()

        // THEN
        XCTAssertFalse(onDismissRun)
        XCTAssertTrue(onManualDismissRun)
    }

    func testWhenMakeViewForSearchDoneWithoutShouldFollowUpThenOnboardingsearchDoneViewCreatedAndOnActionOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let dialogType = ContextualDialogType.searchDone(shouldFollowUp: false)
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }
        var onManualDismissRun = false
        let onManualDismiss = { onManualDismissRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingFirstSearchDoneDialog.self, in: result))
        let subView = find(OnboardingTryVisitingSiteDialogContent.self, in: result)
        XCTAssertNil(subView)
        XCTAssertEqual(reporter.shownDialog, dialogType)

        // WHEN
        view.gotItAction()

        // THEN
        XCTAssertTrue(onDismissRun)
        XCTAssertFalse(onGotItPressedRun)
        XCTAssertEqual(reporter.gotItPressedDialog, dialogType)
        XCTAssertFalse(onManualDismissRun)
    }

    func testWhenMakeViewForTryASiteThenOnboardingTrySiteDialogViewCreatedAndOnActionExpectedSearchOccurs() throws {
        // GIVEN
        let dialogType = ContextualDialogType.tryASite
        var onSuggestionPressedRun = false
        let onSuggestionPressed = { onSuggestionPressedRun = true }
        var onDismissRun = false
        let onDismiss = { onDismissRun = true }
        var onManualDismissRun = false
        let onManualDismiss = { onManualDismissRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: {}, onFireButtonPressed: {}, onSuggestionPressed: onSuggestionPressed)

        // THEN
        let view = try XCTUnwrap(find(OnboardingTryVisitingASiteDialog.self, in: result))
        XCTAssertTrue(view.viewModel.delegate === delegate)
        XCTAssertEqual(reporter.shownDialog, dialogType)

        // WHEN
        let urlString = "some.site"
        view.viewModel.listItemPressed(ContextualOnboardingListItem.site(title: urlString))
        view.onManualDismiss()

        // THEN
        XCTAssertTrue(delegate.didNavigateToCalled)
        XCTAssertEqual(delegate.capturedUrlString, urlString)
        XCTAssertTrue(onSuggestionPressedRun)
        XCTAssertFalse(onDismissRun)
        XCTAssertTrue(onManualDismissRun)
    }

    func testWhenMakeViewForTrackerBlockerWithShouldFollowUpThenTrackerBlockerViewCreatedAndOnActionNothingOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let trackerMessage = NSMutableAttributedString(string: "some trackers")
        let dialogType = ContextualDialogType.trackers(message: trackerMessage, shouldFollowUp: true)
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }
        var onManualDismissRun = false
        let onManualDismiss = { onManualDismissRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingTrackersDoneDialog.self, in: result))
        let subView = find(OnboardingFireButtonDialogContent.self, in: result)
        XCTAssertNil(subView)
        XCTAssertEqual(reporter.shownDialog, dialogType)

        // WHEN
        view.blockedTrackersCTAAction()

        // THEN
        XCTAssertFalse(onDismissRun)
        XCTAssertFalse(onManualDismissRun)
        XCTAssertTrue(onGotItPressedRun)

        // WHEN
        onDismissRun = false
        view.onManualDismiss()

        // THEN
        XCTAssertFalse(onDismissRun)
        XCTAssertTrue(onManualDismissRun)
    }

    func testWhenMakeViewForTrackerBlockerWithoutShouldFollowUpThenTrackerBlockerViewCreatedAndOnActionOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let trackerMessage = NSMutableAttributedString(string: "some trackers")
        let dialogType = ContextualDialogType.trackers(message: trackerMessage, shouldFollowUp: false)
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }
        var onManualDismissRun = false
        let onManualDismiss = { onManualDismissRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingTrackersDoneDialog.self, in: result))
        let subView = find(OnboardingFireButtonDialogContent.self, in: result)
        XCTAssertNil(subView)
        XCTAssertEqual(reporter.shownDialog, dialogType)

        // WHEN
        view.blockedTrackersCTAAction()

        // THEN
        XCTAssertTrue(onDismissRun)
        XCTAssertFalse(onManualDismissRun)
        XCTAssertFalse(onGotItPressedRun)
        XCTAssertEqual(reporter.gotItPressedDialog, dialogType)
    }

    func testWhenMakeViewForHighFiveThenFinalDialogViewCreatedAndOnActionExpectedSearchOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let dialogType = ContextualDialogType.highFive
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }
        var onManualDismissRun = false
        let onManualDismiss = { onManualDismissRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingFinalDialog.self, in: result))
        XCTAssertEqual(reporter.shownDialog, dialogType)

        // WHEN
        view.highFiveAction()

        // THEN
        XCTAssertTrue(onDismissRun)
        XCTAssertFalse(onManualDismissRun)
        XCTAssertTrue(onGotItPressedRun)

        // WHEN
        onDismissRun = false
        view.onManualDismiss()

        // THEN
        XCTAssertFalse(onDismissRun)
        XCTAssertTrue(onManualDismissRun)
    }

    @MainActor
    func testWhenMakeViewForTryFireButtonAndFireButtonIsPressedThenOnFireButtonPressedActionIsCalled() async throws {
        // GIVEN
        var onFireButtonRun = false
        var onDismissRun = false
        let dialogType = ContextualDialogType.tryFireButton
        let onFireButtonPressed = { onFireButtonRun = true }
        let onDismiss = { onDismissRun = true }
        var onManualDismissRun = false
        let onManualDismiss = { onManualDismissRun = true }

        let mainViewController = MainViewController(
            tabCollectionViewModel: TabCollectionViewModel(tabCollection: TabCollection()),
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
            aiChatSessionStore: AIChatSessionStore(featureFlagger: MockFeatureFlagger()),
            fireCoordinator: fireCoordinator
        )
        let window = MockWindow(isVisible: false)
        let sheetPresented = expectation(description: "Fire dialog presentation completed")
        window.onBeginSheet = { sheetPresented.fulfill() }
        let mainWindowController = MainWindowController(
            window: window,
            mainViewController: mainViewController,
            fireViewModel: fireCoordinator.fireViewModel,
            themeManager: MockThemeManager()
        )
        mainWindowController.window = window
        windowControllersManager.mainWindowControllers = [mainWindowController]
        defer {
            windowControllersManager.mainWindowControllers = []
        }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: {}, onFireButtonPressed: onFireButtonPressed, onSuggestionPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingFireDialog.self, in: result))
        XCTAssertEqual(reporter.shownDialog, dialogType)

        // WHEN
        window.isVisible = true
        view.viewModel.tryFireButton()
        await fulfillment(of: [sheetPresented], timeout: 5)

        // THEN
        XCTAssertTrue(onFireButtonRun)
        XCTAssertTrue(onDismissRun)
        XCTAssertFalse(onManualDismissRun)

        // WHEN
        onDismissRun = false
        view.onManualDismiss()

        // THEN
        XCTAssertFalse(onDismissRun)
        XCTAssertTrue(onManualDismissRun)
    }

    func testWhenMakeViewForTryFireButtonAndSkipButtonIsPressedThenmeasureFireButtonSkippedCalled() throws {
        // GIVEN
        let dialogType = ContextualDialogType.highFive

        // WHEN
        _=factory.makeView(for: dialogType, delegate: delegate, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {}, onFireButtonPressed: {}, onSuggestionPressed: {})

        // THEN
        XCTAssertTrue(reporter.measureLastDialogShownCalled)
        XCTAssertEqual(reporter.shownDialog, dialogType)
    }

    @MainActor
    func testWhenSubscriptionUpsellAccepted_ThenAcceptanceIsMeasured() {
        let dialog = DefaultContextualDaxDialogViewFactory.subscriptionUpsellDialog(delegate: delegate, pixelReporter: reporter, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {})
        dialog.acceptAction()
        XCTAssertTrue(reporter.subscriptionUpsellAcceptedCalled)
        XCTAssertFalse(reporter.subscriptionUpsellDeclinedCalled)
    }

    @MainActor
    func testWhenSubscriptionUpsellDeclined_ThenDeclineIsMeasured() {
        let dialog = DefaultContextualDaxDialogViewFactory.subscriptionUpsellDialog(delegate: delegate, pixelReporter: reporter, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {})
        dialog.declineAction()
        XCTAssertTrue(reporter.subscriptionUpsellDeclinedCalled)
        XCTAssertFalse(reporter.subscriptionUpsellAcceptedCalled)
    }

    @MainActor
    func testWhenRebrandedSubscriptionUpsellAccepted_ThenAcceptanceIsMeasured() {
        let dialog = RebrandedContextualDaxDialogsFactory.subscriptionUpsellDialog(delegate: delegate, pixelReporter: reporter, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {})
        dialog.acceptAction()
        XCTAssertTrue(reporter.subscriptionUpsellAcceptedCalled)
        XCTAssertFalse(reporter.subscriptionUpsellDeclinedCalled)
    }

    @MainActor
    func testWhenRebrandedSubscriptionUpsellDeclined_ThenDeclineIsMeasured() {
        let dialog = RebrandedContextualDaxDialogsFactory.subscriptionUpsellDialog(delegate: delegate, pixelReporter: reporter, onDismiss: {}, onManualDismiss: {}, onGotItPressed: {})
        dialog.declineAction()
        XCTAssertTrue(reporter.subscriptionUpsellDeclinedCalled)
        XCTAssertFalse(reporter.subscriptionUpsellAcceptedCalled)
    }

}

class CapturingOnboardingPixelReporter: OnboardingPixelReporting {
    var measureFireButtonSkippedCalled = false
    var measureFireButtonTryItCalled = false
    var measureLastDialogShownCalled = false
    var measureSiteVisitedCalled = false
    var dismissedDialog: ContextualDialogType?
    var shownDialog: ContextualDialogType?
    var gotItPressedDialog: ContextualDialogType?
    var subscriptionUpsellAcceptedCalled = false
    var subscriptionUpsellDeclinedCalled = false
    var measureTryDuckAIPressedCalled = false

    func measureFireButtonSkipped() {
        measureFireButtonSkippedCalled = true
    }

    func measureLastDialogShown() {
        measureLastDialogShownCalled = true
    }

    func measureSearchSuggestionOptionTapped() {
    }

    func measureSiteSuggestionOptionTapped() {
    }

    func measureFireButtonTryIt() {
        measureFireButtonTryItCalled = true
    }

    func measureAddressBarTypedIn() {
    }

    func measurePrivacyDashboardOpened() {
    }

    func measureSiteVisited() {
        measureSiteVisitedCalled = true
    }

    func measureDialogDismissed(dialogType: ContextualDialogType) {
        dismissedDialog = dialogType
    }

    func measureDialogManuallyDismissed(dialogType: ContextualDialogType) {
    }

    func measureSuggestionPressed() {
    }

    func measureDialogShown(dialogType: ContextualDialogType) {
        shownDialog = dialogType
    }

    func measureGotItPressed(dialogType: ContextualDialogType) {
        gotItPressedDialog = dialogType
    }

    func measureSubscriptionUpsellAccepted() {
        subscriptionUpsellAcceptedCalled = true
    }

    func measureSubscriptionUpsellDeclined() {
        subscriptionUpsellDeclinedCalled = true
    }

    func measureTryDuckAIPressed() {
        measureTryDuckAIPressedCalled = true
    }
}
extension CapturingOnboardingNavigationDelegate: OnboardingNavigationDelegate {}

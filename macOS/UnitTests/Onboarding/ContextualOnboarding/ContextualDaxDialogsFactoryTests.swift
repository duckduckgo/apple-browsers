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

import XCTest
import Onboarding
@testable import DuckDuckGo_Privacy_Browser

final class ContextualDaxDialogsFactoryTests: XCTestCase {
    private var factory: ContextualDaxDialogsFactory!
    private var delegate: CapturingOnboardingNavigationDelegate!
    private var reporter: CapturingOnboardingPixelReporter!

    @MainActor
    override func setUpWithError() throws {
        reporter = CapturingOnboardingPixelReporter()
        let fireCoordinator = FireCoordinator(tld: Application.appDelegate.tld)
        factory = DefaultContextualDaxDialogViewFactory(onboardingPixelReporter: reporter, fireCoordinator: fireCoordinator)
        delegate = CapturingOnboardingNavigationDelegate()
    }

    @MainActor override func tearDownWithError() throws {
        factory = nil
        delegate = nil
        reporter = nil
        Application.appDelegate.windowControllersManager.lastKeyMainWindowController = nil
    }

    func testWhenMakeViewForTryASearchThenOnboardingTrySearchDialogViewCreatedAndOnActionExpectedSearchOccurs() throws {
        // GIVEN
        let dialogType = ContextualDialogType.tryASearch
        var onDismissRun = false
        let onDismiss = { onDismissRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onGotItPressed: {}, onFireButtonPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingTrySearchDialog.self, in: result))
        XCTAssertTrue(view.viewModel.delegate === delegate)

        // WHEN
        let query = "some search"
        view.viewModel.listItemPressed(ContextualOnboardingListItem.search(title: query))
        view.onManualDismiss()

        // THEN
        XCTAssertTrue(delegate.didCallSearchFor)
        XCTAssertEqual(delegate.capturedQuery, query)
        XCTAssertTrue(onDismissRun)
    }

    func testWhenMakeViewForSearchDoneWithShouldFollowUpThenOnboardingsearchDoneViewCreatedAndOnActionNothingOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let dialogType = ContextualDialogType.searchDone(shouldFollowUp: true)
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingFirstSearchDoneDialog.self, in: result))
        let subView = find(OnboardingTryVisitingSiteDialogContent.self, in: result)
        XCTAssertNil(subView)

        // WHEN
        view.gotItAction()

        // THEN
        XCTAssertFalse(onDismissRun)
        XCTAssertTrue(onGotItPressedRun)

        // WHEN
        onDismissRun = false
        view.onManualDismiss()

        // THEN
        XCTAssertTrue(onDismissRun)
    }

    func testWhenMakeViewForSearchDoneWithoutShouldFollowUpThenOnboardingsearchDoneViewCreatedAndOnActionOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let dialogType = ContextualDialogType.searchDone(shouldFollowUp: false)
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingFirstSearchDoneDialog.self, in: result))
        let subView = find(OnboardingTryVisitingSiteDialogContent.self, in: result)
        XCTAssertNil(subView)

        // WHEN
        view.gotItAction()

        // THEN
        XCTAssertTrue(onDismissRun)
        XCTAssertFalse(onGotItPressedRun)
    }

    func testWhenMakeViewForTryASiteThenOnboardingTrySiteDialogViewCreatedAndOnActionExpectedSearchOccurs() throws {
        // GIVEN
        let dialogType = ContextualDialogType.tryASite
        var onDismissRun = false
        let onDismiss = { onDismissRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onGotItPressed: {}, onFireButtonPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingTryVisitingASiteDialog.self, in: result))
        XCTAssertTrue(view.viewModel.delegate === delegate)

        // WHEN
        let urlString = "some.site"
        view.viewModel.listItemPressed(ContextualOnboardingListItem.site(title: urlString))
        view.onManualDismiss()

        // THEN
        XCTAssertTrue(delegate.didNavigateToCalled)
        XCTAssertEqual(delegate.capturedUrlString, urlString)
        XCTAssertTrue(onDismissRun)
    }

    func testWhenMakeViewForTrackerBlockerWithShouldFollowUpThenTrackerBlockerViewCreatedAndOnActionNothingOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let trackerMessage = NSMutableAttributedString(string: "some trackers")
        let dialogType = ContextualDialogType.trackers(message: trackerMessage, shouldFollowUp: true)
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingTrackersDoneDialog.self, in: result))
        let subView = find(OnboardingFireButtonDialogContent.self, in: result)
        XCTAssertNil(subView)

        // WHEN
        view.blockedTrackersCTAAction()

        // THEN
        XCTAssertFalse(onDismissRun)
        XCTAssertTrue(onGotItPressedRun)

        // WHEN
        onDismissRun = false
        view.onManualDismiss()

        // THEN
        XCTAssertTrue(onDismissRun)
    }

    func testWhenMakeViewForTrackerBlockerWithoutShouldFollowUpThenTrackerBlockerViewCreatedAndOnActionOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let trackerMessage = NSMutableAttributedString(string: "some trackers")
        let dialogType = ContextualDialogType.trackers(message: trackerMessage, shouldFollowUp: false)
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingTrackersDoneDialog.self, in: result))
        let subView = find(OnboardingFireButtonDialogContent.self, in: result)
        XCTAssertNil(subView)

        // WHEN
        view.blockedTrackersCTAAction()

        // THEN
        XCTAssertTrue(onDismissRun)
        XCTAssertFalse(onGotItPressedRun)
    }

    func testWhenMakeViewForHighFiveThenFinalDialogViewCreatedAndOnActionExpectedSearchOccurs() throws {
        // GIVEN
        var onDismissRun = false
        var onGotItPressedRun = false
        let dialogType = ContextualDialogType.highFive
        let onDismiss = { onDismissRun = true }
        let onGotItPressed = { onGotItPressedRun = true }

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: {})

        // THEN
        let view = try XCTUnwrap(find(OnboardingFinalDialog.self, in: result))

        // WHEN
        view.highFiveAction()

        // THEN
        XCTAssertTrue(onDismissRun)
        XCTAssertTrue(onGotItPressedRun)

        // WHEN
        onDismissRun = false
        view.onManualDismiss()

        // THEN
        XCTAssertTrue(onDismissRun)
    }

    @MainActor
    func testWhenMakeViewForTryFireButtonAndFireButtonIsPressedThenOnFireButtonPressedActionIsCalled() throws {
        // GIVEN
        var onFireButtonRun = false
        var onDismissRun = false
        let dialogType = ContextualDialogType.tryFireButton
        let onFireButtonPressed = { onFireButtonRun = true }
        let onDismiss = { onDismissRun = true }

        let fireCoordinator = FireCoordinator(tld: Application.appDelegate.tld)
        let mainViewController = MainViewController(
            tabCollectionViewModel: TabCollectionViewModel(tabCollection: TabCollection(tabs: [])),
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(),
            aiChatSidebarProvider: AIChatSidebarProvider(),
            fireCoordinator: fireCoordinator
        )
        let window = MockWindow(isVisible: false)
        let mainWindowController = MainWindowController(
            window: window,
            mainViewController: mainViewController,
            popUp: false,
            fireViewModel: fireCoordinator.fireViewModel
        )
        mainWindowController.window = window
        Application.appDelegate.windowControllersManager.lastKeyMainWindowController = mainWindowController

        // WHEN
        let result = factory.makeView(for: dialogType, delegate: delegate, onDismiss: onDismiss, onGotItPressed: {}, onFireButtonPressed: onFireButtonPressed)

        // THEN
        let view = try XCTUnwrap(find(OnboardingFireDialog.self, in: result))

        // WHEN
        window.isVisible = true
        view.viewModel.tryFireButton()

        // THEN
        XCTAssertTrue(onFireButtonRun)

        // WHEN
        onDismissRun = false
        view.onManualDismiss()

        // THEN
        XCTAssertTrue(onDismissRun)
    }

    func testWhenMakeViewForTryFireButtonAndSkipButtonIsPressedThenmeasureFireButtonSkippedCalled() throws {
        // GIVEN
        let dialogType = ContextualDialogType.highFive

        // WHEN
        _=factory.makeView(for: dialogType, delegate: delegate, onDismiss: {}, onGotItPressed: {}, onFireButtonPressed: {})

        // THEN
        XCTAssertTrue(reporter.measureLastDialogShownCalled)
    }

}

class CapturingOnboardingPixelReporter: OnboardingPixelReporting {
    var measureFireButtonSkippedCalled = false
    var measureFireButtonTryItCalled = false
    var measureLastDialogShownCalled = false
    var measureSiteVisitedCalled = false
    var dismissedDialog: ContextualDialogType?

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
}

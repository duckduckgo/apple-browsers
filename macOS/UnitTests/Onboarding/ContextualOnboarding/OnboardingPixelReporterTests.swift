//
//  OnboardingPixelReporterTests.swift
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
import PixelKit
import Navigation
import Onboarding
import PrivacyDashboard
@testable import DuckDuckGo_Privacy_Browser

final class OnboardingPixelReporterTests: XCTestCase {

    var reporter: OnboardingPixelReporter!
    var onboardingState: MockContextualOnboardingState!
    var eventSent: PixelKitEvent?
    var frequency: PixelKit.Frequency?
    var userDefaults: UserDefaults?
    private var sharedPixelHandler: MockOnboardingSharedPixelHandler!

    override func setUpWithError() throws {
        onboardingState = MockContextualOnboardingState()
        userDefaults = UserDefaults(suiteName: "OnboardingPixelReporterTests") ?? UserDefaults.standard
        sharedPixelHandler = MockOnboardingSharedPixelHandler()
        reporter = OnboardingPixelReporter(onboardingStateProvider: onboardingState,
                                           userDefaults: userDefaults!,
                                           fireAction: { [weak self] event, frequency  in
            self?.eventSent = event
            self?.frequency = frequency
        },
                                           onboardingSharedPixelHandler: sharedPixelHandler)
    }

    override func tearDownWithError() throws {
        onboardingState = nil
        reporter = nil
        eventSent = nil
        frequency = nil
        userDefaults?.removePersistentDomain(forName: "OnboardingPixelReporterTests")
        userDefaults = nil
        sharedPixelHandler = nil
    }

    func test_WhenMeasureAddressBarTypedIn_ThenDependingOnTheState_CorrectPixelsAreSent() throws {
        onboardingState.lastDialog = .tryASearch
        reporter.measureAddressBarTypedIn()
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.onboardingSearchCustom.name)
        XCTAssertEqual(frequency, .uniqueByName)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.search(.clicked(.custom))])

        eventSent = nil
        frequency = nil
        sharedPixelHandler.reset()
        onboardingState.lastDialog = .tryASite
        reporter.measureAddressBarTypedIn()
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.onboardingVisitSiteCustom.name)
        XCTAssertEqual(frequency, .uniqueByName)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.visitSite(.clicked(.custom))])

        eventSent = nil
        frequency = nil
        sharedPixelHandler.reset()
        onboardingState.lastDialog = .highFive
        reporter.measureAddressBarTypedIn()
        XCTAssertNil(eventSent)
        XCTAssertNil(frequency)
        XCTAssertTrue(sharedPixelHandler.eventsReceived.isEmpty)
    }

    func test_WhenMeasureSuggestionPressed_ThenDependingOnTheState_CorrectPixelsAreSent() {
        onboardingState.lastDialog = .tryASearch
        reporter.measureSuggestionPressed()
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.search(.clicked(.suggested))])

        sharedPixelHandler.reset()
        onboardingState.lastDialog = .tryASite
        reporter.measureSuggestionPressed()
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.visitSite(.clicked(.suggested))])
    }

    func test_WhenMeasureFireButtonTryIt_ThenOnboardingFireButtonTryItPressedSent() {
        reporter.measureFireButtonTryIt()
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.onboardingFireButtonTryItPressed.name)
        XCTAssertEqual(frequency, .uniqueByName)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [])
    }

    func test_WhenMeasureLastDialogShown_ThenOnboardingFinishedSent() {
        reporter.measureLastDialogShown()
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.onboardingFinished.name)
        XCTAssertEqual(frequency, .uniqueByName)
    }

    func test_WhenMeasureFireButtonPressed_AndOnboardingNotCompleted_ThenOnboardingFireButtonPressedSent() {
        onboardingState.state = .ongoing
        reporter.measureFireButtonPressed()
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.onboardingFireButtonPressed.name)
        XCTAssertEqual(frequency, .uniqueByName)
    }

    func test_WhenMeasureFireButtonPressed_AndOnboardingCompleted_ThenNoPixelSent() {
        onboardingState.state = .onboardingCompleted
        reporter.measureFireButtonPressed()
        XCTAssertNil(eventSent)
        XCTAssertNil(frequency)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [])
    }

    func test_WhenMeasureFireDialogBurnAction_AndOnboardingNotCompleted_ThenFireButtonEngageSent() {
        onboardingState.state = .ongoing
        reporter.measureFireDialogBurnAction()
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.fireButton(.clicked(.engage))])
    }

    func test_WhenMeasureFireDialogBurnAction_AndOnboardingCompleted_ThenNoPixelSent() {
        onboardingState.state = .onboardingCompleted
        reporter.measureFireDialogBurnAction()
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [])
    }

    func test_WhenMeasureFireDialogDismissed_AndOnboardingNotCompleted_ThenFireButtonDismissedSent() {
        onboardingState.state = .ongoing
        reporter.measureFireDialogDismissed()
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.fireButton(.clicked(.dismiss))])
    }

    func test_WhenMeasureFireDialogDismissed_AndOnboardingCompleted_ThenNoPixelSent() {
        onboardingState.state = .onboardingCompleted
        reporter.measureFireDialogDismissed()
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [])
    }

    func test_WhenMeasurePrivacyDashboardOpened_AndOnboardingNotCompleted_ThenOnboardingPrivacyDashboardOpenedSent() {
        onboardingState.state = .ongoing
        reporter.measurePrivacyDashboardOpened()
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.onboardingPrivacyDashboardOpened.name)
        XCTAssertEqual(frequency, .uniqueByName)
    }

    func test_WhenMeasurePrivacyDashboardOpened_AndOnboardingCompleted_ThenNoPixelSent() {
        onboardingState.state = .onboardingCompleted
        reporter.measurePrivacyDashboardOpened()
        XCTAssertNil(eventSent)
        XCTAssertNil(frequency)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [])
    }

    func test_WhenMeasureSiteVisited_ThenSecondSiteVisitedSentOnlyTheSecondTime() {
        reporter.measureSiteVisited()
        XCTAssertNil(eventSent)
        XCTAssertNil(frequency)

        reporter.measureSiteVisited()
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.secondSiteVisited.name)
        XCTAssertEqual(frequency, .uniqueByName)
        eventSent = nil
        frequency = nil
    }

    func test_WhenMeasureTrySearchShown_ThenSearchShownEventSent() throws {
        reporter.measureDialogShown(dialogType: .tryASearch)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.search(.shown)])
    }

    func test_WhenMeasureSearchResultShown_ThenSearchResultShownEventSent() throws {
        reporter.measureDialogShown(dialogType: .defaultSearchDone)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.searchResults(.shown)])
    }

    func test_WhenMeasureTryVisitSiteShown_ThenVisitSiteShownEventSent() throws {
        reporter.measureDialogShown(dialogType: .tryASite)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.visitSite(.shown)])
    }

    func test_WhenMeasureTrackersBlockedShown_ThenTrackersBlockedShownEventSent() throws {
        reporter.measureDialogShown(dialogType: .defaultTrackers)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.trackersBlocked(.shown)])
    }

    func test_WhenMeasureTryFireButtonShown_ThenFireButtonShownEventSent() throws {
        reporter.measureDialogShown(dialogType: .tryFireButton)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.fireButton(.shown)])
    }

    func test_WhenMeasureFinalShown_ThenEndShownEventSent() throws {
        reporter.measureDialogShown(dialogType: .highFive)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.end(.shown)])
    }

    func test_WhenMeasureTrySearchDismissed_ThenTrySearchDismissedEventSent() throws {
        reporter.measureDialogDismissed(dialogType: .tryASearch)
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.trySearchDismissed.name)
        XCTAssertEqual(frequency, .uniqueByName)
    }

    func test_WhenMeasureSearchResultDismissed_ThenSearchResultDismissedEventSent() throws {
        reporter.measureDialogDismissed(dialogType: .defaultSearchDone)
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.searchResultDismissed.name)
        XCTAssertEqual(frequency, .uniqueByName)
    }

    func test_WhenMeasureTryVisitSiteDismissed_ThenTryVisitSiteDismissedEventSent() throws {
        reporter.measureDialogDismissed(dialogType: .tryASite)
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.tryVisitSiteDismissed.name)
        XCTAssertEqual(frequency, .uniqueByName)
    }

    func test_WhenMeasureTrackersBlockedDismissed_ThenTrackersBlockedDismissedEventSent() throws {
        reporter.measureDialogDismissed(dialogType: .defaultTrackers)
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.trackersBlockedDismissed.name)
        XCTAssertEqual(frequency, .uniqueByName)
    }

    func test_WhenMeasureTryFireButtonDismissed_ThenTryFireButtonDismissedEventSent() throws {
        reporter.measureDialogDismissed(dialogType: .tryFireButton)
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.tryFireButtonDismissed.name)
        XCTAssertEqual(frequency, .uniqueByName)
    }

    func test_WhenMeasureFinalDismissed_ThenFinalDialogDismissedEventSent() throws {
        reporter.measureDialogDismissed(dialogType: .highFive)
        XCTAssertEqual(eventSent?.name, ContextualOnboardingPixel.finalDialogDismissed.name)
        XCTAssertEqual(frequency, .uniqueByName)
    }

    func test_WhenMeasureTrySearchManuallyDismissed_ThenTrySearchDismissClickedEventSent() throws {
        reporter.measureDialogManuallyDismissed(dialogType: .tryASearch)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.search(.clicked(.dismiss))])
    }

    func test_WhenMeasureSearchResultManuallyDismissed_ThenSearchResultDismissClickedEventSent() throws {
        reporter.measureDialogManuallyDismissed(dialogType: .defaultSearchDone)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.searchResults(.clicked(.dismiss))])
    }

    func test_WhenMeasureTryVisitSiteManuallyDismissed_ThenTryVisitSiteDismissClickedEventSent() throws {
        reporter.measureDialogManuallyDismissed(dialogType: .tryASite)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.visitSite(.clicked(.dismiss))])
    }

    func test_WhenMeasureTrackersBlockedManuallyDismissed_ThenTrackersBlockedDismissClickedEventSent() throws {
        reporter.measureDialogManuallyDismissed(dialogType: .defaultTrackers)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.trackersBlocked(.clicked(.dismiss))])
    }

    func test_WhenMeasureTryFireButtonManuallyDismissed_ThenTryFireButtonDismissClickedEventSent() throws {
        reporter.measureDialogManuallyDismissed(dialogType: .tryFireButton)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.fireButton(.clicked(.dismiss))])
    }

    func test_WhenMeasureFinalManuallyDismissed_ThenFinalDialogDismissClickedEventSent() throws {
        reporter.measureDialogManuallyDismissed(dialogType: .highFive)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.end(.clicked(.dismiss))])
    }

    // Tab Onboarding Pixel test
    @MainActor
    func test_WhenNavigationDidFinish_ThenReporterMeasureSiteVisitedCalled() {
        let capturingReporter = CapturingOnboardingPixelReporter()
        let tab = Tab(content: .newtab, onboardingPixelReporter: capturingReporter)

        tab.navigationDidFinish(Navigation(identity: .expected, responders: .init(), state: .approved, isCurrent: true))

        XCTAssertTrue(capturingReporter.measureSiteVisitedCalled)
    }

    func test_WhenGotItPressed_OnSearchDoneDialog_ThenExpectedPixelsSent() {
        reporter.measureGotItPressed(dialogType: .searchDone(shouldFollowUp: false))
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.searchResults(.clicked(.engage))])

        sharedPixelHandler.reset()
        reporter.measureGotItPressed(dialogType: .searchDone(shouldFollowUp: true))
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [
            .searchResults(.clicked(.engage)),
            .visitSite(.shown)
        ])
    }

    func test_WhenGotItPressed_OnTrackersDialog_ThenExpectedPixelsSent() {
        reporter.measureGotItPressed(dialogType: .trackers(message: .init(), shouldFollowUp: false))
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.trackersBlocked(.clicked(.engage))])

        sharedPixelHandler.reset()
        reporter.measureGotItPressed(dialogType: .trackers(message: .init(), shouldFollowUp: true))
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [
            .trackersBlocked(.clicked(.engage)),
            .fireButton(.shown)
        ])
    }

    func test_WhenGotItPressed_OnFinalDialog_ThenEndClickedEngageEventSent() {
        reporter.measureGotItPressed(dialogType: .highFive)
        XCTAssertEqual(sharedPixelHandler.eventsReceived, [.end(.clicked(.engage))])
    }

}

class MockContextualOnboardingState: ContextualOnboardingStateUpdater, ContextualOnboardingDialogTypeProviding {
    func lastDialogForTab(_ tab: Tab) -> DuckDuckGo_Privacy_Browser.ContextualDialogType? {
        return lastDialog
    }

    func dialogTypeForTab(_ tab: Tab, privacyInfo: PrivacyInfo?) -> ContextualDialogType? {
        return lastDialog
    }

    var lastDialog: ContextualDialogType?

    var state: ContextualOnboardingState = .onboardingCompleted

    @Published var isContextualOnboardingCompleted: Bool = true
    var isContextualOnboardingCompletedPublisher: Published<Bool>.Publisher { $isContextualOnboardingCompleted }

    func updateStateFor(tab: Tab) {
    }

    func gotItPressed() {
    }

    func fireButtonUsed() {
    }

    func turnOffFeature() {}

}

final class MockOnboardingSharedPixelHandler: OnboardingSharedPixelHandling {
    var eventsReceived: [OnboardingSharedPixelEvent] = []

    func fire(_ event: OnboardingSharedPixelEvent,
              source: OnboardingPixelParameter.Source?,
              flow: OnboardingPixelParameter.Flow?,
              variant: OnboardingPixelParameter.Variant?) {
        eventsReceived.append(event)
    }

    func reset() {
        eventsReceived = []
    }
}

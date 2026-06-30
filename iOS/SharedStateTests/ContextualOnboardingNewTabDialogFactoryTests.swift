//
//  ContextualOnboardingNewTabDialogFactoryTests.swift
//  DuckDuckGo
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
import SwiftUI
import Core
import Onboarding
@testable import DuckDuckGo

class ContextualOnboardingNewTabDialogFactoryTests: XCTestCase {

    var factory: NewTabDaxDialogFactory!
    var mockDelegate: CapturingOnboardingNavigationDelegate!
    var contextualOnboardingLogicMock: ContextualOnboardingLogicMock!
    var pixelReporterMock: OnboardingPixelReporterMock!
    var onDismissCalled: Bool!
    var window: UIWindow!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockDelegate = CapturingOnboardingNavigationDelegate()
        contextualOnboardingLogicMock = ContextualOnboardingLogicMock()
        onDismissCalled = false
        pixelReporterMock = OnboardingPixelReporterMock()
        factory = NewTabDaxDialogFactory(
            delegate: mockDelegate,
            daxDialogsFlowCoordinator: contextualOnboardingLogicMock,
            onboardingPixelReporter: pixelReporterMock
        )
        window = UIWindow(frame: UIScreen.main.bounds)
        window.isHidden = false
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        factory = nil
        mockDelegate = nil
        onDismissCalled = nil
        contextualOnboardingLogicMock = nil
        pixelReporterMock = nil
        super.tearDown()
    }

    func testCreateInitialDialogCreatesAnOnboardingTrySearchDialog() {
        // Given
        let homeDialog = DaxDialogs.HomeScreenSpec.initial

        // When
        let view = factory.createDaxDialog(for: homeDialog, onCompletion: { _ in }, onManualDismiss: { })
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view)

        // Then
        let trySearchDialog = find(OnboardingRebranding.OnboardingTrySearchDialog.self, in: host)
        XCTAssertNotNil(trySearchDialog)
        XCTAssertTrue(trySearchDialog?.viewModel.delegate === mockDelegate)
    }

    func testCreateSubsequentDialogCreatesAnOnboardingTryVisitingSiteDialog() {
        // Given
        let homeDialog = DaxDialogs.HomeScreenSpec.subsequent

        // When
        let view = factory.createDaxDialog(for: homeDialog, onCompletion: { _ in }, onManualDismiss: { })
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view)

        // Then
        let trySiteDialog = find(OnboardingRebranding.OnboardingTrySiteDialog.self, in: host)
        XCTAssertNotNil(trySiteDialog)
        XCTAssertTrue(trySiteDialog?.viewModel.delegate === mockDelegate)
    }

    func testCreateFinalDialogCreatesAnOnboardingFinalDialog() {
        // Given
        let expectation = XCTestExpectation(description: "action triggered")
        contextualOnboardingLogicMock.expectation = expectation
        var onDismissedRun = false
        let homeDialog = DaxDialogs.HomeScreenSpec.final
        let onDimsiss: (Bool) -> Void = { _ in onDismissedRun = true }

        // When
        let view = factory.createDaxDialog(for: homeDialog, onCompletion: onDimsiss, onManualDismiss: { })
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        XCTAssertNotNil(host.view)

        // Then
        let finalDialog = find(OnboardingRebranding.OnboardingEndOfJourneyDialog.self, in: host)
        XCTAssertNotNil(finalDialog)
        finalDialog?.dismissAction()
        XCTAssertTrue(onDismissedRun)
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(contextualOnboardingLogicMock.didCallSetFinalOnboardingDialogSeen)
    }

    func testCreateAddFavoriteDialogCreatesAContextualDaxDialog() {
        // Given
        let homeDialog = DaxDialogs.HomeScreenSpec.addFavorite

        // When
        let view = factory.createDaxDialog(for: homeDialog, onCompletion: { _ in }, onManualDismiss: { })
        let host = UIHostingController(rootView: view)
        XCTAssertNotNil(host.view)

        // Then
        let addFavoriteDialog = find(OnboardingRebranding.OnboardingAddFavorite.self, in: host)
        XCTAssertNotNil(addFavoriteDialog)
        XCTAssertEqual(addFavoriteDialog?.message, UserText.Onboarding.ContextualOnboarding.daxDialogHomeAddFavorite)
    }

    // MARK: - Pixels

    func testWhenOnboardingTrySearchDialogAppearForTheFirstTime_ThenFireExpectedPixel() {
        // GIVEN
        let spec = DaxDialogs.HomeScreenSpec.initial
        let pixelEvent = Pixel.Event.onboardingContextualTrySearchUnique
        // TEST
        testDialogDefinedBy(spec: spec, firesEvent: pixelEvent)
    }

    func testWhenOnboardingTryVisitSiteDialogAppearForTheFirstTime_ThenFireExpectedPixel() {
        // GIVEN
        let spec = DaxDialogs.HomeScreenSpec.subsequent
        let pixelEvent = Pixel.Event.onboardingContextualTryVisitSiteUnique
        // TEST
        testDialogDefinedBy(spec: spec, firesEvent: pixelEvent)
    }

    func testWhenOnboardingFinalDialogAppearForTheFirstTime_ThenFireExpectedPixel() {
        // GIVEN
        let spec = DaxDialogs.HomeScreenSpec.final
        let pixelEvent = Pixel.Event.daxDialogsEndOfJourneyNewTabUnique
        // TEST
        testDialogDefinedBy(spec: spec, firesEvent: pixelEvent)
    }

    func testWhenOnboardingFinalDialogCTAIsTapped_ThenFireExpectedPixel() throws {
        // GIVEN
        let view = factory.createDaxDialog(for: DaxDialogs.HomeScreenSpec.final, onCompletion: { _ in }, onManualDismiss: { })
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        let finalDialog = try XCTUnwrap(find(OnboardingRebranding.OnboardingEndOfJourneyDialog.self, in: host))
        XCTAssertFalse(pixelReporterMock.didCallMeasureEndOfJourneyDialogDismiss)

        // WHEN
        finalDialog.dismissAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureEndOfJourneyDialogDismiss)
    }

    // MARK: - Chat Path – Subsequent Dialog

    func testWhenChatPathPostFireState_AndSubsequentDialogAppears_ThenFiresChatPathVisitSitePixel() {
        // GIVEN
        contextualOnboardingLogicMock.chatPathPhase = .visitSite
        let spec = DaxDialogs.HomeScreenSpec.subsequent
        let pixelEvent = Pixel.Event.onboardingChatPathTryVisitSiteUnique
        // TEST
        testDialogDefinedBy(spec: spec, firesEvent: pixelEvent)
    }

    func testWhenChatPathPostFireState_AndSubsequentDialogAppears_ThenSetsChatPathVisitSiteSeen() {
        // GIVEN
        contextualOnboardingLogicMock.chatPathPhase = .visitSite
        XCTAssertFalse(contextualOnboardingLogicMock.didCallSetChatPathVisitSiteSeen)

        // WHEN
        waitForDialogDefinedBy(spec: .subsequent) {
            // THEN
            XCTAssertTrue(self.contextualOnboardingLogicMock.didCallSetChatPathVisitSiteSeen)
            XCTAssertFalse(self.contextualOnboardingLogicMock.didCallSetTryVisitSiteMessageSeen)
        }
    }

    func testWhenNotChatPath_AndSubsequentDialogAppears_ThenFiresStandardVisitSitePixel() {
        // GIVEN
        contextualOnboardingLogicMock.chatPathPhase = .none
        let spec = DaxDialogs.HomeScreenSpec.subsequent
        let pixelEvent = Pixel.Event.onboardingContextualTryVisitSiteUnique
        // TEST
        testDialogDefinedBy(spec: spec, firesEvent: pixelEvent)
    }

    func testWhenNotChatPath_AndSubsequentDialogAppears_ThenSetsStandardVisitSiteSeen() {
        // GIVEN
        contextualOnboardingLogicMock.chatPathPhase = .none
        XCTAssertFalse(contextualOnboardingLogicMock.didCallSetTryVisitSiteMessageSeen)

        // WHEN
        waitForDialogDefinedBy(spec: .subsequent) {
            // THEN
            XCTAssertTrue(self.contextualOnboardingLogicMock.didCallSetTryVisitSiteMessageSeen)
            XCTAssertFalse(self.contextualOnboardingLogicMock.didCallSetChatPathVisitSiteSeen)
        }
    }

    // MARK: - Final Dialog

    func testWhenFinalDialogAppears_ThenFiresStandardEOJPixel() {
        let spec = DaxDialogs.HomeScreenSpec.final
        let pixelEvent = Pixel.Event.daxDialogsEndOfJourneyNewTabUnique
        testDialogDefinedBy(spec: spec, firesEvent: pixelEvent)
    }

    func testWhenFinalDialogAppears_ThenSetsFinalOnboardingDialogSeen() {
        // GIVEN
        contextualOnboardingLogicMock.expectation = expectation(description: "setFinalOnboardingDialogSeen called")

        // WHEN
        let view = factory.createDaxDialog(for: .final, onCompletion: { _ in }, onManualDismiss: { })
        let host = OnboardingHostingControllerMock(rootView: AnyView(view))
        window.rootViewController = host

        // THEN
        waitForExpectations(timeout: 2.0)
        XCTAssertTrue(contextualOnboardingLogicMock.didCallSetFinalOnboardingDialogSeen)
    }

}

private extension ContextualOnboardingNewTabDialogFactoryTests {

    func testDialogDefinedBy(spec: DaxDialogs.HomeScreenSpec, firesEvent event: Pixel.Event) {
        waitForDialogDefinedBy(spec: spec) {
            // THEN
            XCTAssertTrue(self.pixelReporterMock.didCallMeasureScreenImpressionCalled)
            XCTAssertEqual(self.pixelReporterMock.capturedScreenImpression, event)
            XCTAssertTrue(self.pixelReporterMock.didCallMeasureSharedOnboardingScreenImpression)
            XCTAssertEqual(self.pixelReporterMock.capturedSharedOnboardingScreenImpression, Self.expectedSharedScreenImpression(forLegacyPixel: event))
        }
    }

    static func expectedSharedScreenImpression(forLegacyPixel event: Pixel.Event) -> OnboardingSharedPixelEvent {
        switch event {
        case .onboardingContextualTrySearchUnique:
            return .search(.shown)
        case .onboardingContextualTryVisitSiteUnique, .onboardingChatPathTryVisitSiteUnique:
            return .visitSite(.shown)
        case .daxDialogsEndOfJourneyNewTabUnique:
            return .end(.shown)
        default:
            XCTFail("Update expectedSharedScreenImpression mapping for \(event)")
            return .search(.shown)
        }
    }

    func waitForDialogDefinedBy(spec: DaxDialogs.HomeScreenSpec, completionHandler: @escaping () -> Void) {
        // GIVEN
        let expectation = self.expectation(description: #function)
        XCTAssertFalse(pixelReporterMock.didCallMeasureScreenImpressionCalled)
        XCTAssertNil(pixelReporterMock.capturedScreenImpression)
        XCTAssertFalse(pixelReporterMock.didCallMeasureSharedOnboardingScreenImpression)
        XCTAssertNil(pixelReporterMock.capturedSharedOnboardingScreenImpression)

        // WHEN
        let view = factory.createDaxDialog(for: spec, onCompletion: { _ in }, onManualDismiss: { })
        let host = OnboardingHostingControllerMock(rootView: AnyView(view))
        host.onAppearExpectation = expectation
        window.rootViewController = host
        XCTAssertNotNil(host.view)

        // THEN
        waitForExpectations(timeout: 2.0)
        completionHandler()
    }

}

class CapturingOnboardingNavigationDelegate: OnboardingNavigationDelegate {
    var suggestedSearchQuery: String?
    var urlToNavigateTo: URL?

    func searchFromOnboarding(for query: String) {
        suggestedSearchQuery = query
    }

    func navigateFromOnboarding(to url: URL) {
        urlToNavigateTo = url
    }
}

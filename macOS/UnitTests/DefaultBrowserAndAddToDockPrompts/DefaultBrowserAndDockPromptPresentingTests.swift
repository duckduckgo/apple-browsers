//
//  DefaultBrowserAndDockPromptPresentingTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptPresentingTests: XCTestCase {
    private var coordinatorMock: MockDefaultBrowserAndDockPromptCoordinator!
    private var statusUpdateNotifierMock: MockDefaultBrowserAndDockPromptStatusUpdateNotifier!
    private var sut: DefaultBrowserAndDockPromptPresenter!
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()

        coordinatorMock = MockDefaultBrowserAndDockPromptCoordinator()
        statusUpdateNotifierMock = MockDefaultBrowserAndDockPromptStatusUpdateNotifier()
        sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinatorMock, statusUpdateNotifier: statusUpdateNotifierMock)
        cancellables = []
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        coordinatorMock = nil
        statusUpdateNotifierMock = nil
        sut = nil
        cancellables = nil
    }

    func testTryToShowPromptDoesNothingWhenPromptTypeIsNil() {
        // GIVEN
        var popoverAnchorProviderCalled = false
        var bannerViewHandlerCalled = false
        coordinatorMock.getPromptTypeResult = nil

        // WHEN
        sut.tryToShowPrompt(
            popoverAnchorProvider: {
                popoverAnchorProviderCalled = true
                return nil
            },
            bannerViewHandler: { _ in
                bannerViewHandlerCalled = true
            }
        )

        // THEN
        XCTAssertFalse(popoverAnchorProviderCalled)
        XCTAssertFalse(bannerViewHandlerCalled)
    }

    func testTryToShowPromptShowsBannerWhenPromptTypeIsBanner() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        var bannerShown = false
        let bannerViewHandler: (BannerMessageViewController) -> Void = { _ in
            bannerShown = true
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        // THEN
        XCTAssertTrue(bannerShown)
    }

    func testTryToShowPromptShowsPopoverWhenPromptTypeIsPopover() {
        // GIVEN
        var popoverShown = false
        coordinatorMock.getPromptTypeResult = .popover

        let popoverAnchorProvider: () -> NSView? = {
            popoverShown = true
            return NSView()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: popoverAnchorProvider, bannerViewHandler: { _ in })

        // THEN
        XCTAssertTrue(popoverShown)
    }

    func testTryToShowPromptKeepsTrackOfPromptShownWhenPopoverIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .popover
        XCTAssertNil(sut.currentShownPrompt)

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { NSView() }, bannerViewHandler: { _ in })

        // THEN
        XCTAssertEqual(sut.currentShownPrompt, .popover)
    }

    func testTryToShowPromptKeepsTrackOfPromptShownWhenBannerIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        XCTAssertNil(sut.currentShownPrompt)

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: { _ in })

        // THEN
        XCTAssertEqual(sut.currentShownPrompt, .banner)
    }

    func testTryToShowPromptStartsUpdateNotifierWhenPopoverIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .popover

        let popoverAnchorProvider: () -> NSView? = {
            return NSView()
        }
        XCTAssertFalse(statusUpdateNotifierMock.didCallStartNotifyingStatus)

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: popoverAnchorProvider, bannerViewHandler: { _ in })

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
    }

    func testTryToShowPromptStartsUpdateNotifierWhenBannerIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        XCTAssertFalse(statusUpdateNotifierMock.didCallStartNotifyingStatus)

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: { _ in })

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
    }

    func testBannerConfirmationCallsCoordinatorConfirmationActionForBannerPrompt() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.primaryAction.action()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        // THEN
        XCTAssertTrue(coordinatorMock.wasPromptConfirmationCalled)
        XCTAssertEqual(coordinatorMock.capturedConfirmationPrompt, .banner)
    }

    // MARK: - Status Updates

    func testSubscribeToStatusUpdatesStopMonitoringAndResetShowPromptWhenReceiveEvent() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: { _ in })
        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: false))
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
        XCTAssertFalse(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertEqual(sut.currentShownPrompt, .banner)

        // WHEN
        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: true))

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertNil(sut.currentShownPrompt)
    }

    func testSubscribeToStatusUpdatesDoesDismissBannerWhenReceiveEvent() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: { _ in })
        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: false))

        var didReceiveBannerDismissed = false
        var didReceiveBannerDismissedCount = 0
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
            didReceiveBannerDismissedCount += 1
        }
        .store(in: &cancellables)

        // WHEN
        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: true))

        // THEN
        XCTAssertTrue(didReceiveBannerDismissed)
        XCTAssertEqual(didReceiveBannerDismissedCount, 1)
    }

    func testSubscribeToStatusUpdatesDispatchesDismissActionStatusUpdate() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: { _ in })
        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: false))
        XCTAssertNil(coordinatorMock.capturedDismissAction)

        // WHEN
        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: true))

        // THEN
        XCTAssertEqual(coordinatorMock.capturedDismissAction, .statusUpdate(prompt: .banner))
    }

    // MARK: - Dismissal

    func testBannerConfirmationStopMonitoringNotifierAndCleanCurrentShownPrompt() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
        XCTAssertFalse(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertEqual(sut.currentShownPrompt, .banner)

        // WHEN
        bannerVC?.viewModel.primaryAction.action()

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertNil(sut.currentShownPrompt)
    }

    func testBannerCloseActionStopMonitoringNotifierAndCleanCurrentShownPrompt() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
        XCTAssertFalse(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertEqual(sut.currentShownPrompt, .banner)

        // WHEN
        bannerVC?.viewModel.closeAction()

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertNil(sut.currentShownPrompt)
    }

    func testBannerCloseActionCallsDismissActionOnCoordinatorWithUserinputBannerAndShouldHidePermanentlyFalse() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)
        XCTAssertFalse(coordinatorMock.wasDismissPromptCalled)
        XCTAssertNil(coordinatorMock.capturedDismissAction)

        // WHEN
        bannerVC?.viewModel.closeAction()

        // THEN
        XCTAssertTrue(coordinatorMock.wasDismissPromptCalled)
        XCTAssertEqual(coordinatorMock.capturedDismissAction, .userInput(prompt: .banner, shouldHidePermanently: false))
    }

    func testBannerSecondaryActionStopMonitoringNotifierAndClearnCurrentShownPrompt() throws {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
        XCTAssertFalse(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertEqual(sut.currentShownPrompt, .banner)

        // WHEN
        bannerVC?.viewModel.secondaryAction?.action()

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertNil(sut.currentShownPrompt)
    }

    func testBannerSecondaryActionCallsDismissActionOnCoordinatorWithUserinputBannerAndShouldHidePermanentlyTrue() throws {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)
        XCTAssertFalse(coordinatorMock.wasDismissPromptCalled)
        XCTAssertNil(coordinatorMock.capturedDismissAction)

        // WHEN
        let secondaryAction = try XCTUnwrap(bannerVC?.viewModel.secondaryAction)
        secondaryAction.action()

        // THEN
        XCTAssertTrue(coordinatorMock.wasDismissPromptCalled)
        XCTAssertEqual(coordinatorMock.capturedDismissAction, .userInput(prompt: .banner, shouldHidePermanently: true))
    }

    func testBannerDismissedPublisherEmitsWhenBannerPrimaryActionIsCalled() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        var didReceiveBannerDismissed = false
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
        }.store(in: &cancellables)

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.primaryAction.action()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        // THEN
        XCTAssertTrue(didReceiveBannerDismissed)
    }

    func testBannerDismissedPublisherEmitsWhenSecondaryActionIsCalled() throws {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)
        var didReceiveBannerDismissed = false
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
        }.store(in: &cancellables)
        XCTAssertFalse(didReceiveBannerDismissed)

        // WHEN
        let secondaryAction = try XCTUnwrap(bannerVC?.viewModel.secondaryAction)
        secondaryAction.action()

        // THEN
        XCTAssertTrue(didReceiveBannerDismissed)
    }

    func testBannerDismissedPublisherEmitsWhenBannerCloseActionIsCalled() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .banner
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        var didReceiveBannerDismissed = false
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
        }.store(in: &cancellables)

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.closeAction()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        // THEN
        XCTAssertTrue(didReceiveBannerDismissed)
    }

}

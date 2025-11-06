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
import SharedTestUtilities

final class DefaultBrowserAndDockPromptPresentingTests: XCTestCase {
    private var coordinatorMock: MockDefaultBrowserAndDockPromptCoordinator!
    private var statusUpdateNotifierMock: MockDefaultBrowserAndDockPromptStatusUpdateNotifier!
    private var sut: DefaultBrowserAndDockPromptPresenter!
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()

        coordinatorMock = MockDefaultBrowserAndDockPromptCoordinator()
        statusUpdateNotifierMock = MockDefaultBrowserAndDockPromptStatusUpdateNotifier()
        let uiProviderMock = MockDefaultBrowserAndDockPromptUIProvider()
        sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinatorMock, statusUpdateNotifier: statusUpdateNotifierMock, uiProvider: uiProviderMock)
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
        var inactiveUserModalWindowProviderCalled = false
        coordinatorMock.getPromptTypeResult = nil

        // WHEN
        sut.tryToShowPrompt(
            popoverAnchorProvider: {
                popoverAnchorProviderCalled = true
                return nil
            },
            bannerViewHandler: { _ in
                bannerViewHandlerCalled = true
            },
            inactiveUserModalWindowProvider: {
                inactiveUserModalWindowProviderCalled = true
                return nil
            }
        )

        // THEN
        XCTAssertFalse(popoverAnchorProviderCalled)
        XCTAssertFalse(bannerViewHandlerCalled)
        XCTAssertFalse(inactiveUserModalWindowProviderCalled)
    }

    func testTryToShowPromptShowsBannerWhenPromptTypeIsBanner() {
        // GIVEN
        var bannerShown = false
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { _ in
            bannerShown = true
            expectation.fulfill()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertTrue(bannerShown)
    }

    func testTryToShowPromptShowsPopoverWhenPromptTypeIsPopover() {
        // GIVEN
        var popoverShown = false
        coordinatorMock.getPromptTypeResult = .active(.popover)

        let expectation = expectation(description: "Popover shown")
        let popoverAnchorProvider: () -> NSView? = {
            popoverShown = true
            expectation.fulfill()
            return NSView()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: popoverAnchorProvider, bannerViewHandler: { _ in }, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertTrue(popoverShown)
    }

    func testTryToShowPromptShowsInactiveUserModalWhenPromptTypeIsInactive() {
        // GIVEN
        var inactiveUserModalShown = false
        coordinatorMock.getPromptTypeResult = .inactive

        let expectation = expectation(description: "Inactive user modal shown")
        let inactiveUserModalWindowProvider: () -> NSWindow? = {
            inactiveUserModalShown = true
            expectation.fulfill()
            return MockWindow()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: { _ in }, inactiveUserModalWindowProvider: inactiveUserModalWindowProvider)
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertTrue(inactiveUserModalShown)
    }

    func testTryToShowPromptKeepsTrackOfPromptShownWhenPopoverIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.popover)
        XCTAssertNil(sut.currentShownPrompt)

        let expectation = expectation(description: "Popover shown")
        let popoverAnchorProvider: () -> NSView? = {
            expectation.fulfill()
            return NSView()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: popoverAnchorProvider, bannerViewHandler: { _ in }, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertEqual(sut.currentShownPrompt, .active(.popover))
    }

    func testTryToShowPromptKeepsTrackOfPromptShownWhenBannerIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        XCTAssertNil(sut.currentShownPrompt)

        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { _ in
            expectation.fulfill()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertEqual(sut.currentShownPrompt, .active(.banner))
    }

    func testTryToShowPromptKeepsTrackOfPromptShownWhenInactiveIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .inactive
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        XCTAssertNil(sut.currentShownPrompt)

        let expectation = expectation(description: "Inactive user modal shown")
        let inactiveUserModalWindowProvider: () -> NSWindow? = {
            expectation.fulfill()
            return MockWindow()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: { _ in }, inactiveUserModalWindowProvider: inactiveUserModalWindowProvider)
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertEqual(sut.currentShownPrompt, .inactive)
    }

    func testTryToShowPromptStartsUpdateNotifierWhenPopoverIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.popover)
        XCTAssertFalse(statusUpdateNotifierMock.didCallStartNotifyingStatus)

        let expectation = expectation(description: "Popover shown")
        let popoverAnchorProvider: () -> NSView? = {
            expectation.fulfill()
            return NSView()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: popoverAnchorProvider, bannerViewHandler: { _ in }, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
    }

    func testTryToShowPromptStartsUpdateNotifierWhenBannerIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        XCTAssertFalse(statusUpdateNotifierMock.didCallStartNotifyingStatus)

        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { _ in
            expectation.fulfill()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
    }

    func testTryToShowPromptStartsUpdateNotifierWhenInactiveIsReturned() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .inactive
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        XCTAssertFalse(statusUpdateNotifierMock.didCallStartNotifyingStatus)

        let expectation = expectation(description: "Inactive user modal shown")
        let inactiveUserModalWindowProvider: () -> NSWindow? = {
            expectation.fulfill()
            return MockWindow()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: { _ in }, inactiveUserModalWindowProvider: inactiveUserModalWindowProvider)
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
    }

    func testBannerConfirmationCallsCoordinatorConfirmationActionForBannerPrompt() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        let expectation = expectation(description: "Banner confirmation action called")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.primaryAction.action()
            expectation.fulfill()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        // THEN
        XCTAssertTrue(coordinatorMock.wasPromptConfirmationCalled)
        XCTAssertEqual(coordinatorMock.capturedConfirmationPrompt, .active(.banner))
    }

    // MARK: - Status Updates

    func testSubscribeToStatusUpdatesStopMonitoringAndResetShowPromptWhenReceiveEvent() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { _ in
            expectation.fulfill()
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: false))
        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
        XCTAssertFalse(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertEqual(sut.currentShownPrompt, .active(.banner))

        // WHEN
        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: true))

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertNil(sut.currentShownPrompt)
    }

    func testSubscribeToStatusUpdatesDoesDismissBannerWhenReceiveEvent() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { _ in
            expectation.fulfill()
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

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
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { _ in
            expectation.fulfill()
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: false))
        XCTAssertNil(coordinatorMock.capturedDismissAction)

        // WHEN
        statusUpdateNotifierMock.sendValue(.init(isDefaultBrowser: false, isAddedToDock: true))

        // THEN
        XCTAssertEqual(coordinatorMock.capturedDismissAction, .statusUpdate(prompt: .active(.banner)))
    }

    // MARK: - Dismissal

    func testBannerConfirmationStopMonitoringNotifierAndCleanCurrentShownPrompt() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
            expectation.fulfill()
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
        XCTAssertFalse(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertEqual(sut.currentShownPrompt, .active(.banner))

        // WHEN
        bannerVC?.viewModel.primaryAction.action()

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertNil(sut.currentShownPrompt)
    }

    func testBannerCloseActionStopMonitoringNotifierAndCleanCurrentShownPrompt() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
            expectation.fulfill()
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
        XCTAssertFalse(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertEqual(sut.currentShownPrompt, .active(.banner))

        // WHEN
        bannerVC?.viewModel.closeAction()

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertNil(sut.currentShownPrompt)
    }

    func testBannerCloseActionCallsDismissActionOnCoordinatorWithUserinputBannerAndShouldHidePermanentlyFalse() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
            expectation.fulfill()
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        XCTAssertFalse(coordinatorMock.wasDismissPromptCalled)
        XCTAssertNil(coordinatorMock.capturedDismissAction)

        // WHEN
        bannerVC?.viewModel.closeAction()

        // THEN
        XCTAssertTrue(coordinatorMock.wasDismissPromptCalled)
        XCTAssertEqual(coordinatorMock.capturedDismissAction, .userInput(prompt: .active(.banner), shouldHidePermanently: false))
    }

    func testBannerSecondaryActionStopMonitoringNotifierAndClearnCurrentShownPrompt() throws {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
            expectation.fulfill()
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        XCTAssertTrue(statusUpdateNotifierMock.didCallStartNotifyingStatus)
        XCTAssertFalse(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertEqual(sut.currentShownPrompt, .active(.banner))

        // WHEN
        bannerVC?.viewModel.secondaryAction?.action()

        // THEN
        XCTAssertTrue(statusUpdateNotifierMock.didCallStopNotifyingStatus)
        XCTAssertNil(sut.currentShownPrompt)
    }

    func testBannerSecondaryActionCallsDismissActionOnCoordinatorWithUserinputBannerAndShouldHidePermanentlyTrue() throws {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
            expectation.fulfill()
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

        XCTAssertFalse(coordinatorMock.wasDismissPromptCalled)
        XCTAssertNil(coordinatorMock.capturedDismissAction)

        // WHEN
        let secondaryAction = try XCTUnwrap(bannerVC?.viewModel.secondaryAction)
        secondaryAction.action()

        // THEN
        XCTAssertTrue(coordinatorMock.wasDismissPromptCalled)
        XCTAssertEqual(coordinatorMock.capturedDismissAction, .userInput(prompt: .active(.banner), shouldHidePermanently: true))
    }

    func testBannerDismissedPublisherEmitsWhenBannerPrimaryActionIsCalled() {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        var didReceiveBannerDismissed = false
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
        }.store(in: &cancellables)

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.primaryAction.action()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })

        // THEN
        XCTAssertTrue(didReceiveBannerDismissed)
    }

    func testBannerDismissedPublisherEmitsWhenSecondaryActionIsCalled() throws {
        // GIVEN
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        var bannerVC: BannerMessageViewController?
        let expectation = expectation(description: "Banner shown")
        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            bannerVC = banner
            expectation.fulfill()
        }
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })
        wait(for: [expectation], timeout: 1)

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
        coordinatorMock.getPromptTypeResult = .active(.banner)
        coordinatorMock.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        var didReceiveBannerDismissed = false
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
        }.store(in: &cancellables)

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.closeAction()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler, inactiveUserModalWindowProvider: { nil })

        // THEN
        XCTAssertTrue(didReceiveBannerDismissed)
    }

}

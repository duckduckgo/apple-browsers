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

    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        try super.setUpWithError()

        cancellables = []
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        cancellables = nil
    }

    func testTryToShowPromptDoesNothingWhenPromptTypeIsNil() {
        // GIVEN
        var popoverAnchorProviderCalled = false
        var bannerViewHandlerCalled = false
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator)
        coordinator.getPromptTypeResult = nil

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
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator)

        coordinator.getPromptTypeResult = .banner
        coordinator.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

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
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator)

        coordinator.getPromptTypeResult = .popover

        let popoverAnchorProvider: () -> NSView? = {
            popoverShown = true
            return NSView()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: popoverAnchorProvider, bannerViewHandler: { _ in })

        // THEN
        XCTAssertTrue(popoverShown)
    }

    func testBannerConfirmationCallsCoordinatorConfirmationActionForBannerPrompt() {
        // GIVEN
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator)

        coordinator.getPromptTypeResult = .banner
        coordinator.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.buttonAction()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        // THEN
        XCTAssertTrue(coordinator.wasPromptConfirmationCalled)
        XCTAssertEqual(coordinator.capturedPrompt, .banner)
    }

    func testPromptShouldBeDismissedBeforePresentingNewOne() {
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator)
        let expectation = expectation(description: "Banner dismissed")

        coordinator.getPromptTypeResult = .banner
        coordinator.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        var didReceiveBannerDismissed = false
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
            expectation.fulfill()
        }.store(in: &cancellables)

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: { banner in })

        // THEN
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(didReceiveBannerDismissed)
    }

    func testBannerDismissedPublisherEmitsWhenBannerIsDismissed() {
        // GIVEN
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator)
        let expectation = expectation(description: "Banner dismissed")
        expectation.expectedFulfillmentCount = 2 // When we present a prompt we ensure we dismiss any already presented ones.

        coordinator.getPromptTypeResult = .banner
        coordinator.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        var didReceiveBannerDismissed = false
        var didReceiveBannerDismissedCount = 0
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
            didReceiveBannerDismissedCount += 1
            expectation.fulfill()
        }.store(in: &cancellables)

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.closeAction()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        // THEN
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(didReceiveBannerDismissed)
        XCTAssertEqual(didReceiveBannerDismissedCount, 2)
    }

    func testBannerDismissedPublisherEmitsWhenBannerIsActioned() {
        // GIVEN
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator)
        let expectation = expectation(description: "Banner dismissed")
        expectation.expectedFulfillmentCount = 2 // When we present a prompt we ensure we dismiss any already presented ones.

        coordinator.getPromptTypeResult = .banner
        coordinator.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt

        var didReceiveBannerDismissed = false
        var didReceiveBannerDismissedCount = 0
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
            didReceiveBannerDismissedCount += 1
            expectation.fulfill()
        }.store(in: &cancellables)

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.buttonAction()
        }

        // WHEN
        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        // THEN
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(didReceiveBannerDismissed)
        XCTAssertEqual(didReceiveBannerDismissedCount, 2)
    }
}

final class MockDefaultBrowserAndDockPromptCoordinator: DefaultBrowserAndDockPrompt {
    var getPromptTypeResult: DefaultBrowserAndDockPromptPresentationType?
    var evaluatePromptEligibility: DefaultBrowserAndDockPromptType?

    private(set) var wasPromptConfirmationCalled = false
    private(set) var wasDismissPromptCalled = false
    private(set) var capturedPrompt: DefaultBrowserAndDockPromptPresentationType?
    private(set) var capturedShouldHidePermanently = false

    func getPromptType() -> DefaultBrowserAndDockPromptPresentationType? {
        getPromptTypeResult
    }

    func confirmAction(for prompt: DefaultBrowserAndDockPromptPresentationType) {
        wasPromptConfirmationCalled = true
        capturedPrompt = prompt
    }

    func dismissAction(for prompt: DefaultBrowserAndDockPromptPresentationType, shouldHidePermanently: Bool) {
        wasDismissPromptCalled = true
        capturedPrompt = prompt
        capturedShouldHidePermanently = shouldHidePermanently
    }
}

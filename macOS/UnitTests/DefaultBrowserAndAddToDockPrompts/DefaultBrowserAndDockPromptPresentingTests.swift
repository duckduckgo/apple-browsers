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

    private var cancellables = Set<AnyCancellable>()

    func testTryToShownPromptDoesNothingWhenPromptWasShown() {
        var popoverAnchorProviderCalled = false
        var bannerViewHandlerCalled = false
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let repository = MockDefaultBrowserAndDockPromptRepository()
        let featureFlagger = MockFeatureFlagger()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, repository: repository, featureFlagger: featureFlagger)

        repository.setPromptShown(true)
        coordinator.getPromptTypeResult = .banner

        sut.tryToShowPrompt(
            popoverAnchorProvider: {
                popoverAnchorProviderCalled = true
                return nil
            },
            bannerViewHandler: { _ in
                bannerViewHandlerCalled = true
            }
        )

        XCTAssertFalse(popoverAnchorProviderCalled)
        XCTAssertFalse(bannerViewHandlerCalled)
        XCTAssertTrue(repository.wasPromptShownCalled)
    }

    func testTryToShowPromptDoesNothingWhenPromptTypeIsNil() {
        var popoverAnchorProviderCalled = false
        var bannerViewHandlerCalled = false
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let repository = MockDefaultBrowserAndDockPromptRepository()
        let featureFlagger = MockFeatureFlagger()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, repository: repository, featureFlagger: featureFlagger)

        repository.setPromptShown(false)
        coordinator.getPromptTypeResult = nil

        sut.tryToShowPrompt(
            popoverAnchorProvider: {
                popoverAnchorProviderCalled = true
                return nil
            },
            bannerViewHandler: { _ in
                bannerViewHandlerCalled = true
            }
        )

        XCTAssertFalse(popoverAnchorProviderCalled)
        XCTAssertFalse(bannerViewHandlerCalled)
        XCTAssertTrue(repository.wasPromptShownCalled)
    }

    func testTryToShowPromptShowsBannerWhenPromptTypeIsBanner() {
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let repository = MockDefaultBrowserAndDockPromptRepository()
        let featureFlagger = MockFeatureFlagger()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, repository: repository, featureFlagger: featureFlagger)

        coordinator.getPromptTypeResult = .banner
        coordinator.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        repository.setPromptShown(false)

        var bannerShown = false
        let bannerViewHandler: (BannerMessageViewController) -> Void = { _ in
            bannerShown = true
        }

        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        XCTAssertTrue(bannerShown)
        XCTAssertTrue(repository.wasPromptShownCalled)
    }

    func testTryToShowPromptShowsPopoverWhenPromptTypeIsPopover() {
        var popoverShown = false
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let repository = MockDefaultBrowserAndDockPromptRepository()
        let featureFlagger = MockFeatureFlagger()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, repository: repository, featureFlagger: featureFlagger)

        coordinator.getPromptTypeResult = .popover
        repository.setPromptShown(false)

        let popoverAnchorProvider: () -> NSView? = {
            popoverShown = true
            return NSView()
        }

        sut.tryToShowPrompt(popoverAnchorProvider: popoverAnchorProvider, bannerViewHandler: { _ in })

        XCTAssertTrue(popoverShown)
        XCTAssertTrue(repository.wasPromptShownCalled)
    }

    func testBannerConfirmationCallsCoordinatorPromptConfirmation() {
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let repository = MockDefaultBrowserAndDockPromptRepository()
        let featureFlagger = MockFeatureFlagger()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, repository: repository, featureFlagger: featureFlagger)

        coordinator.getPromptTypeResult = .banner
        coordinator.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        repository.setPromptShown(false)

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.buttonAction()
        }

        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        XCTAssertTrue(coordinator.wasPromptConfirmationCalled)
    }

    func testBannerDismissedPublisherEmitsWhenBannerIsDismissed() {
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let repository = MockDefaultBrowserAndDockPromptRepository()
        let featureFlagger = MockFeatureFlagger()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, repository: repository, featureFlagger: featureFlagger)
        let expectation = expectation(description: "Banner dismissed")

        coordinator.getPromptTypeResult = .banner
        coordinator.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        repository.setPromptShown(false)

        var didReceiveBannerDismissed = false
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
            expectation.fulfill()
        }.store(in: &cancellables)

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.closeAction()
        }

        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(didReceiveBannerDismissed)
    }

    func testBannerDismissedPublisherEmitsWhenBannerIsActioned() {
        let coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        let repository = MockDefaultBrowserAndDockPromptRepository()
        let featureFlagger = MockFeatureFlagger()
        let sut = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, repository: repository, featureFlagger: featureFlagger)
        let expectation = expectation(description: "Banner dismissed")

        coordinator.getPromptTypeResult = .banner
        coordinator.evaluatePromptEligibility = .bothDefaultBrowserAndDockPrompt
        repository.setPromptShown(false)

        var didReceiveBannerDismissed = false
        sut.bannerDismissedPublisher.sink { _ in
            didReceiveBannerDismissed = true
            expectation.fulfill()
        }.store(in: &cancellables)

        let bannerViewHandler: (BannerMessageViewController) -> Void = { banner in
            banner.viewModel.buttonAction()
        }

        sut.tryToShowPrompt(popoverAnchorProvider: { nil }, bannerViewHandler: bannerViewHandler)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(didReceiveBannerDismissed)
    }
}

final class MockDefaultBrowserAndDockPromptCoordinator: DefaultBrowserAndDockPrompt {
    var getPromptTypeResult: DefaultBrowserAndDockPromptPresentationType?
    var evaluatePromptEligibility: DefaultBrowserAndDockPromptType?
    var wasPromptConfirmationCalled = false

    func getPromptType(experimentDecider: DefaultBrowserAndDockPromptExperimentDeciding) -> DefaultBrowserAndDockPromptPresentationType? {
        return getPromptTypeResult
    }

    func onPromptConfirmation() {
        wasPromptConfirmationCalled = true
    }
}

final class MockDefaultBrowserAndDockPromptRepository: DefaultBrowserAndDockPromptStoring {
    var wasPromptShownCalled = false
    var wasSetPromptShownCalled = false
    private var wasPromptShownInternal = false

    func didShowPrompt() -> Bool {
        wasPromptShownCalled = true
        return wasPromptShownInternal
    }

    func setPromptShown(_ shown: Bool) {
        wasSetPromptShownCalled = true
        wasPromptShownInternal = shown
    }
}

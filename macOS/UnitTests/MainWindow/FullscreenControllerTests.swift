//
//  FullscreenControllerTests.swift
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

import Combine
import Common
import History
import HistoryView
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class FullscreenControllerTests: XCTestCase {

    @MainActor
    func testWhenHandleEscapePressIsCalledWithAllowedHostThenFlagIsSet() {
        let controller = FullscreenController()
        controller.handleEscapePress(host: "docs.google.com")
        XCTAssertTrue(controller.shouldPreventFullscreenExit)
    }

    @MainActor
    func testWhenHandleEscapePressIsCalledWithNonMatchingHostThenFlagIsNotSet() {
        let controller = FullscreenController()
        controller.handleEscapePress(host: "example.com")
        XCTAssertFalse(controller.shouldPreventFullscreenExit)
    }

    @MainActor
    func testWhenResetFullscreenExitFlagIsCalledThenFlagIsReset() {
        let controller = FullscreenController()
        controller.handleEscapePress(host: "docs.google.com")
        XCTAssertTrue(controller.shouldPreventFullscreenExit)

        controller.resetFullscreenExitFlag()
        XCTAssertFalse(controller.shouldPreventFullscreenExit)
    }

    @MainActor
    func testWhenManuallyExitFullscreenIsCalledWhileInFullscreenThenWindowExitsFullscreen() async throws {
        let controller = FullscreenController()
        let window = MockWindow(styleMask: .fullScreen)

        controller.manuallyExitFullscreen(window: window)

        XCTAssertFalse(window.styleMask.contains(.fullScreen))
    }

    @MainActor
    func testWhenManuallyExitFullscreenIsCalledWhileNotInFullscreenThenWindowStaysInNormalState() async throws {
        let controller = FullscreenController()
        let window = MockWindow()

        controller.manuallyExitFullscreen(window: window)

        XCTAssertFalse(window.styleMask.contains(.fullScreen))
    }
}

final class MainViewControllerDefaultBrowserPromptTests: XCTestCase, MainViewControllerFactory {

    @MainActor
    func testDefaultBrowserPromptNotTriggeredInPopupWindow() {
        let presenter = DefaultBrowserAndDockPromptPresentingMock()
        let sut = makeMainViewController(isPopup: true, defaultBrowserPromptPresenter: presenter)

        _ = sut.view
        sut.windowDidBecomeKey()

        XCTAssertEqual(presenter.tryToShowPromptCallCount, 0)
    }

    @MainActor
    func testDefaultBrowserPromptShownInRegularWindow() {
        let presenter = DefaultBrowserAndDockPromptPresentingMock()
        let sut = makeMainViewController(isPopup: false, defaultBrowserPromptPresenter: presenter)

        _ = sut.view
        sut.windowDidBecomeKey()

        XCTAssertEqual(presenter.tryToShowPromptCallCount, 1)
    }

}

private final class DefaultBrowserAndDockPromptPresentingMock: DefaultBrowserAndDockPromptPresenting {

    private let bannerSubject = PassthroughSubject<Void, Never>()
    private(set) var tryToShowPromptCallCount = 0

    var bannerDismissedPublisher: AnyPublisher<Void, Never> {
        bannerSubject.eraseToAnyPublisher()
    }

    func tryToShowPrompt(popoverAnchorProvider: @escaping () -> NSView?,
                         bannerViewHandler: @escaping (BannerMessageViewController) -> Void,
                         inactiveUserModalWindowProvider: @escaping () -> NSWindow?) {
        tryToShowPromptCallCount += 1
    }
}

private final class WinBackOfferPromptPresentingMock: WinBackOfferPromptPresenting {
    private(set) var tryToShowPromptCallCount = 0

    func tryToShowPrompt(in window: NSWindow?) {
        tryToShowPromptCallCount += 1
    }
}

private protocol MainViewControllerFactory {}

extension MainViewControllerFactory {

    @MainActor
    func makeMainViewController(isPopup: Bool,
                                defaultBrowserPromptPresenter: DefaultBrowserAndDockPromptPresenting,
                                winBackOfferPromptPresenter: WinBackOfferPromptPresenting = WinBackOfferPromptPresentingMock()) -> MainViewController {
        let windowControllersManager = WindowControllersManagerMock()
        let tabCollectionViewModel = TabCollectionViewModel(isPopup: isPopup, windowControllersManager: windowControllersManager)
        let featureFlagger = MockFeatureFlagger()
        let fireCoordinator = makeFireCoordinator(windowControllersManager: windowControllersManager, featureFlagger: featureFlagger)
        let aiChatSidebarProvider = AIChatSidebarProvider(featureFlagger: featureFlagger)

        return MainViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(),
            aiChatSidebarProvider: aiChatSidebarProvider,
            defaultBrowserAndDockPromptPresenting: defaultBrowserPromptPresenter,
            fireCoordinator: fireCoordinator,
            winBackOfferPromptPresenting: winBackOfferPromptPresenter
        )
    }

    @MainActor
    func makeFireCoordinator(windowControllersManager: WindowControllersManagerMock,
                             featureFlagger: MockFeatureFlagger) -> FireCoordinator {
        FireCoordinator(
            tld: TLD(),
            featureFlagger: featureFlagger,
            historyCoordinating: HistoryCoordinatingMock(),
            visualizeFireAnimationDecider: nil,
            onboardingContextualDialogsManager: nil,
            fireproofDomains: MockFireproofDomains(),
            faviconManagement: FaviconManagerMock(),
            windowControllersManager: windowControllersManager,
            pixelFiring: nil,
            historyProvider: MockHistoryViewDataProvider()
        )
    }
}

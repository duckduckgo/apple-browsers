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
import FeatureFlags_macOS
import FoundationExtensions
import History
import HistoryView
import PrivacyConfig
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

final class MainViewControllerDefaultBrowserPromptUIHostingTests: XCTestCase, MainViewControllerFactory {

    @MainActor
    func testWhenInPopUpWindowThenUIHostingReportsIsInPopUpWindow() {
        let sut: DefaultBrowserAndDockPromptUIHosting = makeMainViewController(isPopup: true, defaultBrowserPromptPresenter: DefaultBrowserAndDockPromptPresentingMock())

        XCTAssertTrue(sut.isInPopUpWindow)
    }

    @MainActor
    func testWhenInRegularWindowThenUIHostingDoesNotReportIsInPopUpWindow() {
        let sut: DefaultBrowserAndDockPromptUIHosting = makeMainViewController(isPopup: false, defaultBrowserPromptPresenter: DefaultBrowserAndDockPromptPresentingMock())

        XCTAssertFalse(sut.isInPopUpWindow)
    }

    @MainActor
    func testWhenViewIsNotInKeyWindowThenNoAnchorIsProvided() {
        let viewController = makeMainViewController(isPopup: false, defaultBrowserPromptPresenter: DefaultBrowserAndDockPromptPresentingMock())
        _ = viewController.view
        let sut: DefaultBrowserAndDockPromptUIHosting = viewController

        XCTAssertNil(sut.providePopoverAnchor())
        XCTAssertNil(sut.provideModalAnchor())
    }

}

@MainActor
final class MainViewControllerVerticalTabsTests: XCTestCase, MainViewControllerFactory {

    func testClosingTabWithFloatingChatWaitsForConfirmationAndUsesTheOriginalTabAfterReordering() throws {
        let sessions = AIChatSessionStore(featureFlagger: MockFeatureFlagger())
        let controller = makeVerticalTabsController(aiChatSessionStore: sessions)
        let collection = controller.tabCollectionViewModel
        let tabID = try XCTUnwrap(collection.tabCollection.tabs.first?.uuid)
        collection.append(tab: Tab(content: .newtab))
        sessions.getOrCreateSession(for: tabID, burnerMode: .regular).state.setFloating()

        controller.tabBarViewController.requestCloseTab(at: .unpinned(0))
        guard collection.tabCollection.tabs.count == 2 else {
            return XCTFail("Closing a tab with a floating chat must wait for confirmation")
        }
        XCTAssertTrue(controller.aiChatCoordinator.isChatFloating(for: tabID))

        collection.moveTab(at: .unpinned(0), to: .unpinned(1))
        controller.tabBarViewController.closeTabAfterConfirmation(id: tabID)
        XCTAssertEqual(collection.tabCollection.tabs.count, 1)
        XCTAssertNotEqual(collection.tabCollection.tabs.first?.uuid, tabID)
    }

    func testNarrowWindowShowsTabsOverThePageAndRestoresDockingWhenWidened() throws {
        let controller = makeVerticalTabsController()
        let presenter = try XCTUnwrap(controller.verticalTabsSidebarPresenter)
        let view = controller.mainView
        let dockingThreshold = MainView.minimumWebContentWidth + VerticalTabsViewController.minimumWidth
        let sidebar = try XCTUnwrap(controller.children.compactMap { $0 as? VerticalTabsViewController }.first).view

        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        window.setContentSize(NSSize(width: MainWindow.minWindowWidth, height: 650))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.bounds.width, MainWindow.minWindowWidth, accuracy: 0.5)
        XCTAssertEqual(presenter.layout, .collapsed)
        XCTAssertEqual(view.webContainerView.frame.width, view.bounds.width, accuracy: 0.5)

        controller.toggleVerticalTabsSidebar(nil)
        XCTAssertEqual(presenter.layout, .peeking)
        XCTAssertTrue(view.contentLeadingConstraints.allSatisfy(\.isActive))

        window.setContentSize(NSSize(width: dockingThreshold, height: 650))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.bounds.width, dockingThreshold, accuracy: 0.5)
        XCTAssertEqual(presenter.layout, .docked)
        XCTAssertEqual(sidebar.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(sidebar.frame.width, VerticalTabsViewController.minimumWidth, accuracy: 0.5)
        XCTAssertEqual(view.webContainerView.frame.minX, sidebar.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(view.webContainerView.frame.width, MainView.minimumWebContentWidth, accuracy: 0.5)
    }

    func testFullscreenRestoresDockedAndCollapsedSidebars() throws {
        let controller = makeVerticalTabsController()
        let presenter = try XCTUnwrap(controller.verticalTabsSidebarPresenter)
        let view = controller.mainView
        let sidebar = try XCTUnwrap(controller.children.compactMap { $0 as? VerticalTabsViewController }.first).view
        view.layoutSubtreeIfNeeded()
        let initialWidth = sidebar.frame.width
        XCTAssertEqual(presenter.layout, .docked)
        XCTAssertGreaterThanOrEqual(initialWidth, VerticalTabsViewController.minimumWidth)
        XCTAssertEqual(view.webContainerView.frame.minX, sidebar.frame.maxX, accuracy: 0.5)

        controller.setTabBarShownInFullScreen(false)
        XCTAssertEqual(presenter.layout, .hidden)
        controller.toggleVerticalTabsSidebar(nil)
        XCTAssertEqual(presenter.layout, .hidden)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.webContainerView.frame.width, view.bounds.width, accuracy: 0.5)

        controller.setTabBarShownInFullScreen(true)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(presenter.layout, .docked)
        XCTAssertEqual(sidebar.frame.width, initialWidth, accuracy: 0.5)
        XCTAssertEqual(view.webContainerView.frame.minX, sidebar.frame.maxX, accuracy: 0.5)
        controller.toggleVerticalTabsSidebar(nil)
        controller.setTabBarShownInFullScreen(false)
        controller.setTabBarShownInFullScreen(true)
        XCTAssertEqual(presenter.layout, .collapsed)
    }

    func testEnablingVerticalTabsWhileHiddenInFullscreenDefersTheSidebar() throws {
        let preferences = makeVerticalTabsPreferences(enabled: false)
        let controller = makeVerticalTabsController(preferences: preferences)
        controller.setTabBarShownInFullScreen(false)

        preferences.useVerticalTabs = true
        let presenter = try XCTUnwrap(controller.verticalTabsSidebarPresenter)
        XCTAssertEqual(presenter.layout, .hidden)

        controller.setTabBarShownInFullScreen(true)
        XCTAssertEqual(presenter.layout, .docked)
    }

    private func makeVerticalTabsController(preferences: AppearancePreferences? = nil, aiChatSessionStore: AIChatSessionStore? = nil) -> MainViewController {
        let controller = makeMainViewController(isPopup: false,
                                                defaultBrowserPromptPresenter: DefaultBrowserAndDockPromptPresentingMock(),
                                                appearancePreferences: preferences ?? makeVerticalTabsPreferences(enabled: true),
                                                aiChatSessionStore: aiChatSessionStore)
        _ = controller.view
        return controller
    }

    private func makeVerticalTabsPreferences(enabled: Bool) -> AppearancePreferences {
        AppearancePreferences(persistor: AppearancePreferencesPersistorMock(useVerticalTabs: enabled),
                              privacyConfigurationManager: nil,
                              featureFlagger: MockFeatureFlagger(featuresStub: [FeatureFlag.verticalTabs.rawValue: true]),
                              aiChatMenuConfig: MockAIChatConfig())
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
                                appearancePreferences: AppearancePreferences? = nil,
                                aiChatSessionStore: AIChatSessionStore? = nil,
                                winBackOfferPromptPresenter: WinBackOfferPromptPresenting = WinBackOfferPromptPresentingMock()) -> MainViewController {
        let windowControllersManager = WindowControllersManagerMock()
        let tabCollectionViewModel = TabCollectionViewModel(isPopup: isPopup, windowControllersManager: windowControllersManager)
        let featureFlagger = MockFeatureFlagger()
        let fireCoordinator = makeFireCoordinator(windowControllersManager: windowControllersManager, featureFlagger: featureFlagger)
        return MainViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
            aiChatSessionStore: aiChatSessionStore ?? AIChatSessionStore(featureFlagger: featureFlagger),
            defaultBrowserAndDockPromptPresenting: defaultBrowserPromptPresenter,
            appearancePreferences: appearancePreferences ?? NSApp.delegateTyped.appearancePreferences,
            fireCoordinator: fireCoordinator,
            winBackOfferPromptPresenting: winBackOfferPromptPresenter
        )
    }

    @MainActor
    func makeFireCoordinator(windowControllersManager: WindowControllersManagerMock,
                             featureFlagger: MockFeatureFlagger) -> FireCoordinator {

        let fireproofDomains = MockFireproofDomains()
        let faviconManager = FaviconManagerMock()
        let dataClearingPreferences = DataClearingPreferences(persistor: MockFireButtonPreferencesPersistor(),
                                                              fireproofDomains: fireproofDomains,
                                                              faviconManager: faviconManager,
                                                              windowControllersManager: windowControllersManager,
                                                              featureFlagger: featureFlagger,
                                                              aiChatHistoryCleaner: MockAIChatHistoryCleaner())

        return FireCoordinator(
            tld: TLD(),
            featureFlagger: featureFlagger,
            historyCoordinating: HistoryCoordinatingMock(),
            visualizeFireAnimationDecider: nil,
            onboardingContextualDialogsManager: nil,
            fireproofDomains: fireproofDomains,
            faviconManagement: faviconManager,
            windowControllersManager: windowControllersManager,
            dataClearingPreferences: dataClearingPreferences,
            pixelFiring: nil,
            historyProvider: MockHistoryViewDataProvider()
        )
    }
}

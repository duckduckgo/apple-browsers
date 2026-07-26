//
//  BrowserTabViewControllerContentOverlayDismissalTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AppKit
import BrowserServicesKit
import Combine
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BrowserTabViewControllerContentOverlayDismissalTests: XCTestCase {

    func testWhenBackgroundTabStateChangesThenContentOverlayIsNotDismissed() {
        let selectedTab = Tab(content: .none)
        let backgroundTab = Tab(content: .none)
        let spy = ContentOverlayDismissalSpy()
        let context = makeContext(tabs: [selectedTab, backgroundTab], spy: spy)

        backgroundTab.title = "Countdown 00:19"
        XCTAssertEqual(spy.callCount, 0)

        backgroundTab.favicon = NSImage(size: NSSize(width: 16, height: 16))
        XCTAssertEqual(spy.callCount, 0)

        backgroundTab.setContent(.newtab)
        XCTAssertEqual(spy.callCount, 0)
        withExtendedLifetime(context) {}
    }

    func testWhenSelectedTabTitleOrFaviconChangesThenContentOverlayIsNotDismissed() {
        let selectedTab = Tab(content: .none)
        let spy = ContentOverlayDismissalSpy()
        let context = makeContext(tabs: [selectedTab], spy: spy)

        selectedTab.title = "Countdown 00:18"
        XCTAssertEqual(spy.callCount, 0)

        selectedTab.favicon = NSImage(size: NSSize(width: 16, height: 16))
        XCTAssertEqual(spy.callCount, 0)
        withExtendedLifetime(context) {}
    }

    func testWhenSelectedTabContentChangesThenContentOverlayIsDismissed() {
        let selectedTab = Tab(content: .none)
        let spy = ContentOverlayDismissalSpy()
        let context = makeContext(tabs: [selectedTab], spy: spy)

        selectedTab.setContent(.newtab)

        XCTAssertEqual(spy.callCount, 1)
        withExtendedLifetime(context) {}
    }

    func testWhenSelectedTabChangesThenContentOverlayIsDismissed() {
        let selectedTab = Tab(content: .none)
        let backgroundTab = Tab(content: .none)
        let spy = ContentOverlayDismissalSpy()
        let context = makeContext(tabs: [selectedTab, backgroundTab], spy: spy)

        XCTAssertTrue(context.tabCollectionViewModel.select(tab: backgroundTab))

        XCTAssertEqual(spy.callCount, 1)
    }

    func testWhenDismissalIsRequestedBeforeContentOverlayIsCreatedThenObserverIsNotCalled() {
        let selectedTab = Tab(content: .none)
        let backgroundTab = Tab(content: .none)
        let spy = ContentOverlayDismissalSpy()
        let context = makeContext(tabs: [selectedTab, backgroundTab], spy: spy, initializeContentOverlay: false)

        XCTAssertTrue(context.tabCollectionViewModel.select(tab: backgroundTab))

        XCTAssertEqual(spy.callCount, 0)
    }

    func testWhenWindowMovesOrAnotherWindowResizesThenContentOverlayIsNotDismissed() {
        let spy = ContentOverlayDismissalSpy()
        let context = makeContext(tabs: [Tab(content: .none)], spy: spy)

        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: context.window)
        XCTAssertEqual(spy.callCount, 0)

        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: MockWindow())
        XCTAssertEqual(spy.callCount, 0)
    }

    func testWhenOwningWindowResizesThenContentOverlayIsDismissed() {
        let spy = ContentOverlayDismissalSpy()
        let context = makeContext(tabs: [Tab(content: .none)], spy: spy)

        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: context.window)

        XCTAssertEqual(spy.callCount, 1)
    }

    func testWhenContentOverlayIsRequestedMultipleTimesThenWindowResizeSubscriptionIsNotDuplicated() {
        let spy = ContentOverlayDismissalSpy()
        let context = makeContext(tabs: [Tab(content: .none)], spy: spy)
        context.viewController.websiteAutofillUserScriptCloseOverlay(nil)
        context.viewController.websiteAutofillUserScriptCloseOverlay(nil)
        spy.reset()

        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: context.window)

        XCTAssertEqual(spy.callCount, 1)
    }

    func testWhenOwningWindowClosesThenContentOverlayIsDismissed() {
        let spy = ContentOverlayDismissalSpy()
        let context = makeContext(tabs: [Tab(content: .none)], spy: spy)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: context.window)

        XCTAssertEqual(spy.callCount, 1)
    }

    private func makeContext(tabs: [Tab],
                             spy: ContentOverlayDismissalSpy,
                             initializeContentOverlay: Bool = true) -> TestContext {
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs, isPopup: false))
        let windowControllersManager = WindowControllersManagerMock()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = [:]

        let viewController = BrowserTabViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            featureFlagger: featureFlagger,
            defaultBrowserPreferences: DefaultBrowserPreferences(defaultBrowserProvider: MockDefaultBrowserProvider()),
            downloadsPreferences: DownloadsPreferences(persistor: MockDownloadsPreferencesPersistor()),
            searchPreferences: SearchPreferences(
                persistor: MockSearchPreferencesPersistor(),
                windowControllersManager: windowControllersManager),
            tabsPreferences: TabsPreferences(
                persistor: MockTabsPreferencesPersistor(),
                windowControllersManager: windowControllersManager),
            webTrackingProtectionPreferences: WebTrackingProtectionPreferences(
                persistor: MockWebTrackingProtectionPreferencesPersistor(),
                windowControllersManager: windowControllersManager),
            cookiePopupProtectionPreferences: CookiePopupProtectionPreferences(
                persistor: MockCookiePopupProtectionPreferencesPersistor(),
                windowControllersManager: windowControllersManager),
            aiChatPreferences: AIChatPreferences(
                storage: MockAIChatPreferencesStorage(),
                aiChatMenuConfiguration: MockAIChatConfig(),
                windowControllersManager: windowControllersManager,
                featureFlagger: featureFlagger),
            aboutPreferences: AboutPreferences(
                internalUserDecider: featureFlagger.internalUserDecider,
                featureFlagger: featureFlagger,
                windowControllersManager: windowControllersManager,
                keyValueStore: InMemoryThrowingKeyValueStore()),
            dockPreferences: DockPreferencesModel(
                dockCustomizer: ContentOverlayDockCustomizerMock(),
                pixelFiring: nil),
            accessibilityPreferences: AccessibilityPreferences(),
            duckPlayer: DuckPlayer(
                preferencesPersistor: DuckPlayerPreferencesPersistorMock(),
                privacyConfigurationManager: MockPrivacyConfigurationManager(),
                internalUserDecider: featureFlagger.internalUserDecider),
            pinningManager: MockPinningManager(),
            onContentOverlayDismissalRequested: { spy.record() })

        let window = MockWindow()
        window.contentViewController = viewController
        viewController.viewWillAppear()
        viewController.viewDidAppear()
        if initializeContentOverlay {
            viewController.websiteAutofillUserScriptCloseOverlay(nil)
        }
        spy.reset()

        return TestContext(
            viewController: viewController,
            tabCollectionViewModel: tabCollectionViewModel,
            window: window)
    }
}

@MainActor
private final class ContentOverlayDismissalSpy {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }

    func reset() {
        callCount = 0
    }
}

private final class ContentOverlayDockCustomizerMock: DockCustomization {
    var supportsAddingToDock: Bool { false }
    var isAddedToDock: Bool { false }
    var shouldShowNotification: Bool { false }
    var shouldShowNotificationPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    @discardableResult
    func addToDock() -> Bool { false }

    func didCloseMoreOptionsMenu() {}

    func synchronizeNotificationVisibilityWithFirstLaunchDate() {}

    func resetData() {}
}

private struct TestContext {
    let viewController: BrowserTabViewController
    let tabCollectionViewModel: TabCollectionViewModel
    let window: MockWindow
}

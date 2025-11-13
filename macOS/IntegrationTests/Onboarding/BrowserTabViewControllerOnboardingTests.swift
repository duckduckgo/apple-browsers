//
//  BrowserTabViewControllerOnboardingTests.swift
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

import AIChat
import BrowserServicesKit
import Combine
import Common
import FeatureFlags
import History
import HistoryView
import Onboarding
import PrivacyDashboard
import SharedTestUtilities
import struct SwiftUI.AnyView
import XCTest

@testable import DuckDuckGo_Privacy_Browser

class MockDefaultBrowserProvider: DefaultBrowserProvider {
    var bundleIdentifier: String = "test"
    var defaultBrowserURL: URL?
    var isDefault: Bool = false

    func presentDefaultBrowserPrompt() throws {}
    func openSystemPreferences() {}
}

class MockDownloadsPreferencesPersistor: DownloadsPreferencesPersistor {

    var selectedDownloadLocation: String?
    var alwaysRequestDownloadLocation: Bool
    var defaultDownloadLocation: URL?
    var lastUsedCustomDownloadLocation: String?
    var shouldOpenPopupOnCompletion: Bool

    var _isDownloadLocationValid: (URL) -> Bool

    func isDownloadLocationValid(_ location: URL) -> Bool {
        _isDownloadLocationValid(location)
    }

    init(
        selectedDownloadLocation: String? = nil,
        alwaysRequestDownloadLocation: Bool = false,
        shouldOpenPopupOnCompletion: Bool = true,
        defaultDownloadLocation: URL? = FileManager.default.temporaryDirectory,
        lastUsedCustomDownloadLocation: String? = nil,
        isDownloadLocationValid: @escaping (URL) -> Bool = { _ in true }
    ) {
        self.selectedDownloadLocation = selectedDownloadLocation
        self.alwaysRequestDownloadLocation = alwaysRequestDownloadLocation
        self.shouldOpenPopupOnCompletion = shouldOpenPopupOnCompletion
        self.defaultDownloadLocation = defaultDownloadLocation
        self.lastUsedCustomDownloadLocation = lastUsedCustomDownloadLocation
        self._isDownloadLocationValid = isDownloadLocationValid
    }
}

class MockWebTrackingProtectionPreferencesPersistor: WebTrackingProtectionPreferencesPersistor {
    var gpcEnabled: Bool = false
}

class MockCookiePopupProtectionPreferencesPersistor: CookiePopupProtectionPreferencesPersistor {
    var autoconsentEnabled: Bool = false
}

class MockAIChatPreferencesStorage: AIChatPreferencesStorage {
    var isAIFeaturesEnabled: Bool = true
    var didDisplayAIChatAddressBarOnboarding: Bool = true
    var showShortcutOnNewTabPage: Bool = true
    var showShortcutInApplicationMenu: Bool = true
    var showShortcutInAddressBar: Bool = true
    var showShortcutInAddressBarWhenTyping: Bool = true
    var openAIChatInSidebar: Bool = true
    var shouldAutomaticallySendPageContext: Bool = true

    let isAIFeaturesEnabledPublisher: AnyPublisher<Bool, Never> = Empty().eraseToAnyPublisher()
    let showShortcutOnNewTabPagePublisher: AnyPublisher<Bool, Never> = Empty().eraseToAnyPublisher()
    let showShortcutInApplicationMenuPublisher: AnyPublisher<Bool, Never> = Empty().eraseToAnyPublisher()
    let showShortcutInAddressBarPublisher: AnyPublisher<Bool, Never> = Empty().eraseToAnyPublisher()
    let showShortcutInAddressBarWhenTypingPublisher: AnyPublisher<Bool, Never> = Empty().eraseToAnyPublisher()
    let openAIChatInSidebarPublisher: AnyPublisher<Bool, Never> = Empty().eraseToAnyPublisher()
    let shouldAutomaticallySendPageContextPublisher: AnyPublisher<Bool, Never> = Empty().eraseToAnyPublisher()

    func reset() {
        isAIFeaturesEnabled = true
        showShortcutOnNewTabPage = true
        showShortcutInApplicationMenu = true
        showShortcutInAddressBar = true
        showShortcutInAddressBarWhenTyping = true
        didDisplayAIChatAddressBarOnboarding = true
        openAIChatInSidebar = true
        shouldAutomaticallySendPageContext = true
    }
}

final class MockAIChatConfig: AIChatMenuVisibilityConfigurable {
    var shouldDisplayNewTabPageShortcut = false
    var shouldDisplayApplicationMenuShortcut = false
    var shouldDisplayAddressBarShortcut = false
    var shouldDisplayAnyAIChatFeature = false
    var shouldOpenAIChatInSidebar = false
    var shouldDisplaySummarizationMenuItem = false
    var shouldDisplayTranslationMenuItem = false
    var shouldAutomaticallySendPageContext = false
    var shouldDisplayAddressBarShortcutWhenTyping: Bool = false
    var shouldShowSettingsImprovements: Bool = false
    var shouldAutomaticallySendPageContextTelemetryValue: Bool?
    let valuesChangedPublisher = PassthroughSubject<Void, Never>()
}

@available(macOS 12.0, *)
final class BrowserTabViewControllerOnboardingTests: XCTestCase {

    var window: MockWindow!
    var viewController: BrowserTabViewController!
    var dialogProvider: MockDialogsProvider!
    private var pixelReporter: CapturingOnboardingPixelReporter!
    var factory: CapturingDialogFactory!
    var featureFlagger: MockFeatureFlagger!
    var schemeHandler: TestSchemeHandler!
    var tab: Tab!
    var cancellables: Set<AnyCancellable> = []
    lazy var expectation: XCTestExpectation! = XCTestExpectation(description: "CapturingDialogFactory.makeView called")
    var dialogTypeForTabExpectation: XCTestExpectation!

    @MainActor override func setUp() {
        autoreleasepool {
            let tabCollectionViewModel = TabCollectionViewModel(isPopup: false)
            featureFlagger = MockFeatureFlagger()
            featureFlagger.featuresStub = [
                FeatureFlag.contextualOnboarding.rawValue: true,
                FeatureFlag.newTabPagePerTab.rawValue: true
            ]
            pixelReporter = CapturingOnboardingPixelReporter()
            dialogProvider = MockDialogsProvider()
            factory = CapturingDialogFactory(expectation: expectation)
            schemeHandler = TestSchemeHandler { _ in
                return .ok(.html("hello"))
            }

            // tests return debugDescription instead of localizedDescription
            NSError.disableSwizzledDescription = true

            tab = Tab(content: .url(URL.duckDuckGo, credential: nil, source: .appOpenUrl), webViewConfiguration: schemeHandler.webViewConfiguration())
            let tabViewModel = TabViewModel(tab: tab)
            let windowControllersManager = WindowControllersManagerMock()
            viewController = BrowserTabViewController(
                tabCollectionViewModel: tabCollectionViewModel,
                onboardingPixelReporter: pixelReporter,
                onboardingDialogTypeProvider: dialogProvider,
                onboardingDialogFactory: factory,
                featureFlagger: featureFlagger,
                defaultBrowserPreferences: DefaultBrowserPreferences(defaultBrowserProvider: MockDefaultBrowserProvider()),
                downloadsPreferences: DownloadsPreferences(persistor: MockDownloadsPreferencesPersistor()),
                searchPreferences: SearchPreferences(persistor: MockSearchPreferencesPersistor(), windowControllersManager: windowControllersManager),
                tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: windowControllersManager),
                webTrackingProtectionPreferences: WebTrackingProtectionPreferences(persistor: MockWebTrackingProtectionPreferencesPersistor(), windowControllersManager: windowControllersManager),
                cookiePopupProtectionPreferences: CookiePopupProtectionPreferences(persistor: MockCookiePopupProtectionPreferencesPersistor(), windowControllersManager: windowControllersManager),
                aiChatPreferences: AIChatPreferences(
                    storage: MockAIChatPreferencesStorage(),
                    aiChatMenuConfiguration: MockAIChatConfig(),
                    windowControllersManager: windowControllersManager,
                    featureFlagger: MockFeatureFlagger()
                )
            )
            viewController.tabViewModel = tabViewModel
            _=viewController.view
            window = MockWindow()
            window.contentViewController = viewController

            viewController.viewWillAppear()
            viewController.viewDidAppear()
            viewController.tabViewModel?.tab.setContent(.url(URL.duckDuckGo, credential: nil, source: .ui))
        }
    }

    override func tearDownWithError() throws {
        autoreleasepool {
            dialogProvider = nil
            factory = nil
            tab = nil
            viewController = nil
            cancellables = []
            expectation = nil
            dialogTypeForTabExpectation = nil
            featureFlagger = nil
            window = nil
            schemeHandler = nil
            expectation = nil
            pixelReporter = nil
        }
    }

    func testWhenNavigationCompletedAndFeatureIsOffThenTurnOffFeature() throws {
        featureFlagger.featuresStub = [FeatureFlag.newTabPagePerTab.rawValue: true]
        let expectation = self.expectation(description: "Wait for turnOffFeatureCalled to be called")
        dialogProvider.turnOffFeatureCalledExpectation = expectation

        tab.navigateFromOnboarding(to: .duckDuckGo)

        wait(for: [expectation], timeout: 3.0)
    }

    func testWhenNavigationCompletedAndNoDialogTypeThenOnlyWebViewVisible() throws {
        let expectation = self.expectation(description: "Wait for webViewDidFinishNavigationPublisher to emit")
        tab.navigateFromOnboarding(to: .duckDuckGo)

        tab.webViewDidFinishNavigationPublisher
            .sink {
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)
        XCTAssertNil(factory.capturedType)
    }

    func testWhenNavigationCompletedAndHighFiveDialogTypeThenCorrectDialogCapturedInFactory() throws {
        dialogProvider.dialog = .highFive
        tab.navigateFromOnboarding(to: .duckDuckGo)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(factory.capturedType, .highFive)
        XCTAssertIdentical(factory.capturedDelegate, viewController.tabViewModel?.tab)
    }

    func testWhenNavigationCompletedAndSearchDoneDialogTypeThenCorrectDialogCapturedInFactory() throws {
        dialogProvider.dialog = .searchDone(shouldFollowUp: true)
        tab.navigateFromOnboarding(to: .duckDuckGo)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(factory.capturedType, .searchDone(shouldFollowUp: true))
        XCTAssertIdentical(factory.capturedDelegate, viewController.tabViewModel?.tab)
    }

    func testWhenNavigationCompletedAndTrackersDialogTypeThenCorrectDialogCapturedInFactory() throws {
        dialogProvider.dialog = .trackers(message: NSMutableAttributedString(string: ""), shouldFollowUp: true)
        tab.navigateFromOnboarding(to: .duckDuckGo)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(factory.capturedType, .trackers(message: NSMutableAttributedString(string: ""), shouldFollowUp: true))
        XCTAssertIdentical(factory.capturedDelegate, viewController.tabViewModel?.tab)
    }

    func testWhenNavigationCompletedAndTryASearchDialogTypeThenCorrectDialogCapturedInFactory() throws {
        dialogProvider.dialog = .tryASearch
        tab.navigateFromOnboarding(to: .duckDuckGo)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(factory.capturedType, .tryASearch)
        XCTAssertIdentical(factory.capturedDelegate, viewController.tabViewModel?.tab)
    }

    func testWhenNavigationCompletedAndTryASiteDialogTypeThenCorrectDialogCapturedInFactory() throws {
        dialogProvider.dialog = .tryASite
        tab.navigateFromOnboarding(to: .duckDuckGo)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(factory.capturedType, .tryASite)
        XCTAssertIdentical(factory.capturedDelegate, viewController.tabViewModel?.tab)
    }

    func testWhenNavigationCompletedAndTryFireButtonDialogTypeThenCorrectDialogCapturedInFactory() throws {
        dialogProvider.dialog = .tryFireButton
        tab.navigateFromOnboarding(to: .duckDuckGo)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(factory.capturedType, .tryFireButton)
        XCTAssertIdentical(factory.capturedDelegate, viewController.tabViewModel?.tab)
    }

    func testWhenNavigationCompletedAndIsAReloadThenNoDialogCapturedInFactory() throws {
        dialogProvider.dialog = .tryFireButton

        let expectation1 = expectation(description: "webViewDidFinishNavigation 1")
        var cancellable: AnyCancellable! = tab.webViewDidFinishNavigationPublisher
            .sink {
                expectation1.fulfill()
            }
        tab.navigateFromOnboarding(to: .duckDuckGo)

        wait(for: [expectation, expectation1], timeout: 3.0)
        XCTAssertEqual(factory.capturedType, .tryFireButton)
        XCTAssertIdentical(factory.capturedDelegate, viewController.tabViewModel?.tab)
        cancellable = nil

        factory.capturedType = nil
        let expectation2 = expectation(description: "webViewDidFinishNavigation 2")
        cancellable = tab.webViewDidFinishNavigationPublisher
            .sink {
                expectation2.fulfill()
            }

        tab.reload()

        wait(for: [expectation2], timeout: 5.0)
        XCTAssertNil(factory.capturedType)
        withExtendedLifetime(cancellable) {}
    }

    func testWhenNavigationCompletedAndWindowDidBecomeActiveCorrectDialogCapturedInFactory() throws {
        dialogProvider.state = .ongoing
        dialogProvider.dialog = .tryFireButton
        tab.navigateFromOnboarding(to: .duckDuckGo)

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(factory.capturedType, .tryFireButton)
        XCTAssertIdentical(factory.capturedDelegate, viewController.tabViewModel?.tab)

        factory.capturedType = nil
        viewController.windowDidBecomeKey()

        XCTAssertEqual(factory.capturedType, .tryFireButton)
    }

    func testWhenDialogIsDismissedViewHighlightsAreDismissed() throws {
        throw XCTSkip("Temporarily Disabled")

        dialogProvider.dialog = .tryFireButton
        tab.navigateFromOnboarding(to: .duckDuckGo)
        let delegate = BrowserTabViewControllerDelegateSpy()
        viewController.delegate = delegate

        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(factory.capturedType, .tryFireButton)
        XCTAssertIdentical(factory.capturedDelegate, viewController.tabViewModel?.tab)

        factory.performOnManualDismiss()

        XCTAssertTrue(delegate.didCallDismissViewHighlight)
        XCTAssertEqual(pixelReporter.dismissedDialog, .tryFireButton)

    }

    func testWhenNavigationCompletedAndDialogTypeNilThenAskDelegateToRemoveViewHighlights() throws {
        // GIVEN
        let expectation = self.expectation(description: "Wait for webViewDidFinishNavigationPublisher to emit")
        let delegate = BrowserTabViewControllerDelegateSpy()
        let url = URL.duckDuckGo
        dialogProvider.dialogTypeForTabExpectation = expectation
        dialogProvider.dialog = nil
        viewController.delegate = delegate

        // WHEN
        tab.navigateFromOnboarding(to: url)

        // THEN
        wait(for: [expectation], timeout: 3.0)
        XCTAssertTrue(delegate.didCallDismissViewHighlight)
    }

    func testWhenNavigationCompletedAndStateIsShowFireButtonThenAskDelegateToHighlightFireButton() throws {
        // GIVEN
        dialogProvider.dialog = .tryFireButton
        let url = URL.duckDuckGo
        let delegate = BrowserTabViewControllerDelegateSpy()
        viewController.delegate = delegate
        XCTAssertFalse(delegate.didCallHighlightFireButton)

        // WHEN
        tab.navigateFromOnboarding(to: url)

        // THEN
        wait(for: [expectation], timeout: 3.0)
        XCTAssertTrue(delegate.didCallHighlightFireButton)
    }

    func testWhenNavigationCompletedAndStateIsShowBlockedTrackersThenAskDelegateToHighlightPrivacyShield() throws {
        // GIVEN
        dialogProvider.dialog = .trackers(message: .init(string: ""), shouldFollowUp: true)
        let url = URL.duckDuckGo
        let delegate = BrowserTabViewControllerDelegateSpy()
        viewController.delegate = delegate
        XCTAssertFalse(delegate.didCallHighlightPrivacyShield)

        // WHEN
        tab.navigateFromOnboarding(to: url)

        // THEN
        wait(for: [expectation], timeout: 3.0)
        XCTAssertTrue(delegate.didCallHighlightPrivacyShield)
    }

    func testWhenNavigationCompletedViewHighlightsAreRemoved() throws {
        // GIVEN
        dialogProvider.dialog = .searchDone(shouldFollowUp: false)
        let url = URL.duckDuckGo
        let delegate = BrowserTabViewControllerDelegateSpy()
        viewController.delegate = delegate
        XCTAssertFalse(delegate.didCallDismissViewHighlight)

        // WHEN
        tab.navigateFromOnboarding(to: url)

        // THEN
        wait(for: [expectation], timeout: 3.0)
        XCTAssertTrue(delegate.didCallDismissViewHighlight)
    }

    func testWhenGotItButtonPressedThenAskDelegateToRemoveViewHighlights() throws {
        throw XCTSkip("Flaky Test")
        // GIVEN
        let expectation = self.expectation(description: "Wait for webViewDidFinishNavigationPublisher to emit")
        let delegate = BrowserTabViewControllerDelegateSpy()
        let url = URL.duckDuckGo
        dialogProvider.dialogTypeForTabExpectation = expectation
        dialogProvider.dialog = nil
        viewController.delegate = delegate
        tab.navigateFromOnboarding(to: url)
        XCTAssertFalse(delegate.didCallDismissViewHighlight)
        wait(for: [expectation], timeout: 3.0)

        // WHEN
        factory.performOnGotItPressed()

        // THEN
        XCTAssertTrue(delegate.didCallDismissViewHighlight)
    }

    func testWhenGotItButtonPressedAndStateIsShowFireButtonThenAskDelegateToHighlightFireButton() throws {
        // GIVEN
        dialogProvider.dialog = .tryFireButton
        let url = URL.duckDuckGo
        let delegate = BrowserTabViewControllerDelegateSpy()
        viewController.delegate = delegate
        XCTAssertFalse(delegate.didCallHighlightFireButton)
        tab.navigateFromOnboarding(to: url)
        wait(for: [expectation], timeout: 3.0)

        // WHEN
        factory.performOnGotItPressed()

        // THEN
        XCTAssertTrue(delegate.didCallHighlightFireButton)
    }

    @MainActor
    func testWhenFireButtonPressedThenAskDelegateToRemoveViewHighlights() throws {

        // GIVEN
        dialogProvider.dialog = .tryFireButton
        let url = URL.duckDuckGo
        let delegate = BrowserTabViewControllerDelegateSpy()
        viewController.delegate = delegate
        XCTAssertFalse(delegate.didCallDismissViewHighlight)
        tab.navigateFromOnboarding(to: url)
        wait(for: [expectation], timeout: 3.0)

        let windowControllersManager = WindowControllersManagerMock()
        let fireCoordinator = FireCoordinator(tld: TLD(),
                                              featureFlagger: Application.appDelegate.featureFlagger,
                                              historyCoordinating: HistoryCoordinatingMock(),
                                              visualizeFireAnimationDecider: nil,
                                              onboardingContextualDialogsManager: nil,
                                              fireproofDomains: MockFireproofDomains(),
                                              faviconManagement: FaviconManagerMock(),
                                              windowControllersManager: windowControllersManager,
                                              pixelFiring: nil,
                                              historyProvider: MockHistoryViewDataProvider())
        let mainViewController = MainViewController(
            tabCollectionViewModel: TabCollectionViewModel(tabCollection: TabCollection(tabs: [])),
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(),
            aiChatSidebarProvider: AIChatSidebarProvider(featureFlagger: MockFeatureFlagger()),
            fireCoordinator: fireCoordinator
        )
        window.isVisible = false
        let mainWindowController = MainWindowController(
            window: window,
            mainViewController: mainViewController,
            fireViewModel: fireCoordinator.fireViewModel,
            themeManager: MockThemeManager()
        )
        mainWindowController.window = window
        windowControllersManager.mainWindowControllers = [mainWindowController]
        defer {
            windowControllersManager.mainWindowControllers = []
        }

        // WHEN
        window.isVisible = true
        factory.performOnFireButtonPressed()

        // THEN
        XCTAssertTrue(delegate.didCallDismissViewHighlight)
    }

}

class MockDialogsProvider: ContextualOnboardingDialogTypeProviding, ContextualOnboardingStateUpdater {
    func lastDialogForTab(_ tab: DuckDuckGo_Privacy_Browser.Tab) -> DuckDuckGo_Privacy_Browser.ContextualDialogType? {
        return lastDialog
    }

    var lastDialog: DuckDuckGo_Privacy_Browser.ContextualDialogType?

    var state: ContextualOnboardingState = .onboardingCompleted
    @Published var isContextualOnboardingCompleted: Bool = true
    var isContextualOnboardingCompletedPublisher: Published<Bool>.Publisher { $isContextualOnboardingCompleted }
    var turnOffFeatureCalledExpectation: XCTestExpectation?

    func updateStateFor(tab: DuckDuckGo_Privacy_Browser.Tab) {}

    var dialogTypeForTabExpectation: XCTestExpectation?

    var dialog: ContextualDialogType?

    func dialogTypeForTab(_ tab: Tab, privacyInfo: PrivacyInfo?) -> ContextualDialogType? {
        dialogTypeForTabExpectation?.fulfill()
        lastDialog = dialog
        return dialog
    }

    func gotItPressed() {}

    func fireButtonUsed() {}

    func turnOffFeature() {
        turnOffFeatureCalledExpectation?.fulfill()
    }
}

class CapturingDialogFactory: ContextualDaxDialogsFactory {
    var expectation: XCTestExpectation
    var capturedType: ContextualDialogType?
    var capturedDelegate: OnboardingNavigationDelegate?

    private var onGotItPressed: (() -> Void)?
    private var onFireButtonPressed: (() -> Void)?
    private var onManualDismissPressed: (() -> Void)?

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func makeView(for type: ContextualDialogType, delegate: OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> AnyView {
        capturedType = type
        capturedDelegate = delegate
        self.onGotItPressed = onGotItPressed
        self.onFireButtonPressed = onFireButtonPressed
        self.onManualDismissPressed = onDismiss
        expectation.fulfill()
        return AnyView(OnboardingFinalDialog(highFiveAction: {}, onManualDismiss: {}))
    }

    func performOnGotItPressed() {
        onGotItPressed?()
    }

    func performOnFireButtonPressed() {
        onFireButtonPressed?()
    }

    func performOnManualDismiss() {
        onManualDismissPressed?()
    }

}

final class BrowserTabViewControllerDelegateSpy: BrowserTabViewControllerDelegate {
    private(set) var didCallHighlightFireButton = false
    private(set) var didCallHighlightPrivacyShield = false
    private(set) var didCallDismissViewHighlight = false
    private(set) var didCallCloseWindowIfNeeded = false

    func highlightFireButton() {
        didCallHighlightFireButton = true
    }

    func highlightPrivacyShield() {
        didCallHighlightPrivacyShield = true
    }

    func dismissViewHighlight() {
        didCallDismissViewHighlight = true
    }

    func closeWindowIfNeeded() -> Bool {
        didCallCloseWindowIfNeeded = true
        return false
    }

}

private class CapturingOnboardingPixelReporter: OnboardingPixelReporting {
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

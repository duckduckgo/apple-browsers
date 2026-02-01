//
//  AutoconsentStatsPopoverCoordinatorTests.swift
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

import AutoconsentStats
import BrowserServicesKit
import Combine
import Common
import FeatureFlags
import PersistenceTestingUtils
import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class MockAutoconsentStatsPopoverPresenter: AutoconsentStatsPopoverPresenting {
    var isPopoverBeingPresentedValue = false
    var showPopoverCalled = false
    var showPopoverViewController: PopoverMessageViewController?
    var dismissPopoverCalled = false

    func isPopoverBeingPresented() -> Bool {
        return isPopoverBeingPresentedValue
    }

    func showPopover(viewController: PopoverMessageViewController) {
        showPopoverCalled = true
        showPopoverViewController = viewController
        isPopoverBeingPresentedValue = true
    }

    func dismissPopover() {
        dismissPopoverCalled = true
        isPopoverBeingPresentedValue = false
    }
}

@MainActor
final class MockOnboardingStateUpdater: ContextualOnboardingStateUpdater {
    private var _state: ContextualOnboardingState = .onboardingCompleted
    var state: ContextualOnboardingState {
        get {
            return _state
        }
        set {
            _state = newValue
            isContextualOnboardingCompleted = newValue == .onboardingCompleted
        }
    }
    @Published var isContextualOnboardingCompleted: Bool = true
    var isContextualOnboardingCompletedPublisher: Published<Bool>.Publisher { $isContextualOnboardingCompleted }
    func gotItPressed() {}
    func fireButtonUsed() {}
    func turnOffFeature() {}
}

@MainActor
final class AutoconsentStatsPopoverCoordinatorTests: XCTestCase {
    var coordinator: AutoconsentStatsPopoverCoordinator!
    var mockKeyValueStore: MockKeyValueFileStore!
    var mockWindowControllersManager: WindowControllersManagerMock!
    var mockCookiePopupProtectionPreferences: CookiePopupProtectionPreferences!
    var mockAppearancePreferences: AppearancePreferences!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockAutoconsentStats: MockAutoconsentStats!
    var mockPresenter: MockAutoconsentStatsPopoverPresenter!
    var mockOnboardingStateUpdater: MockOnboardingStateUpdater!

    override func setUpWithError() throws {
        try super.setUpWithError()

        mockKeyValueStore = try MockKeyValueFileStore()
        mockWindowControllersManager = WindowControllersManagerMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockAutoconsentStats = MockAutoconsentStats()

        let cookiePopupProtectionPreferencesPersistor = MockCookiePopupProtectionPreferencesPersistor()
        mockCookiePopupProtectionPreferences = CookiePopupProtectionPreferences(
            persistor: cookiePopupProtectionPreferencesPersistor,
            windowControllersManager: mockWindowControllersManager
        )
        mockCookiePopupProtectionPreferences.isAutoconsentEnabled = true

        let persistor = MockTabsPreferencesPersistor()
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(), pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
                                                            tabsPreferences: TabsPreferences(persistor: persistor, windowControllersManager: WindowControllersManagerMock()))
        tabCollectionViewModel.append(tab: Tab(uuid: "tab1", content: .url(URL.duckDuckGo, source: .ui)))
        tabCollectionViewModel.append(tab: Tab(uuid: "tab2", content: .url(URL.duckDuckGo, source: .ui)))

        mockWindowControllersManager.customAllTabCollectionViewModels = [tabCollectionViewModel]

        let appearancePreferencesPersistor = AppearancePreferencesPersistorMock()
        mockAppearancePreferences = AppearancePreferences(
            persistor: appearancePreferencesPersistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: mockFeatureFlagger,
            aiChatMenuConfig: MockAIChatConfig()
        )
        mockAppearancePreferences.isProtectionsReportVisible = true

        mockFeatureFlagger.featuresStub[FeatureFlag.newTabPageAutoconsentStats.rawValue] = true

        mockPresenter = MockAutoconsentStatsPopoverPresenter()
        mockOnboardingStateUpdater = MockOnboardingStateUpdater()
    }

    override func tearDown() {
        coordinator = nil
        mockKeyValueStore = nil
        mockWindowControllersManager = nil
        mockCookiePopupProtectionPreferences = nil
        mockAppearancePreferences = nil
        mockFeatureFlagger = nil
        mockAutoconsentStats = nil
        mockPresenter = nil
        mockOnboardingStateUpdater = nil
        super.tearDown()
    }

    func makeCoordinator() -> AutoconsentStatsPopoverCoordinator {
        return AutoconsentStatsPopoverCoordinator(
            autoconsentStats: mockAutoconsentStats,
            keyValueStore: mockKeyValueStore,
            windowControllersManager: mockWindowControllersManager,
            cookiePopupProtectionPreferences: mockCookiePopupProtectionPreferences,
            appearancePreferences: mockAppearancePreferences,
            featureFlagger: mockFeatureFlagger,
            onboardingStateUpdater: mockOnboardingStateUpdater,
            presenter: mockPresenter
        )
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_DoesNotShow_WhenFeatureFlagDisabled() async {
        mockFeatureFlagger.featuresStub[FeatureFlag.newTabPageAutoconsentStats.rawValue] = false
        coordinator = makeCoordinator()
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_DoesNotShow_WhenPopoverAlreadyPresented() async {
        coordinator = makeCoordinator()
        mockPresenter.isPopoverBeingPresentedValue = true
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_DoesNotShow_WhenCPMDisabled() async {
        coordinator = makeCoordinator()
        mockCookiePopupProtectionPreferences.isAutoconsentEnabled = false
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_DoesNotShow_WhenOnNewTabPage() async {
        coordinator = makeCoordinator()
        let tabCollectionViewModel = TabCollectionViewModel(isPopup: false, windowControllersManager: mockWindowControllersManager)
        tabCollectionViewModel.appendNewTab(with: .newtab)
        mockWindowControllersManager.customAllTabCollectionViewModels = [tabCollectionViewModel]
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_DoesNotShow_WhenProtectionsReportDisabled() async {
        coordinator = makeCoordinator()
        mockAppearancePreferences.isProtectionsReportVisible = false
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_DoesNotShow_WhenOnboardingNotFinished() async {
        coordinator = makeCoordinator()
        mockOnboardingStateUpdater.state = .ongoing
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_DoesNotShow_WhenOnboardingNotStarted() async {
        coordinator = makeCoordinator()
        mockOnboardingStateUpdater.state = .notStarted
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_DoesNotShow_WhenAlreadyPresented() async throws {
        coordinator = makeCoordinator()
        try mockKeyValueStore.set(true, forKey: "com.duckduckgo.autoconsent.blocked.cookies.popover.seen")
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_DoesNotShow_WhenNotEnoughCookiePopupsBlocked() async {
        coordinator = makeCoordinator()
        mockAutoconsentStats.totalCookiePopUpsBlocked = 3

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testCheckAndShowDialogIfNeeded_ShowsDialog_WhenAllConditionsMet() async {
        coordinator = makeCoordinator()
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertTrue(mockPresenter.showPopoverCalled)
        XCTAssertNotNil(mockPresenter.showPopoverViewController)
    }

    @MainActor
    func testDismissDialogDueToNewTabBeingShown_Dismisses_WhenPopoverPresented() {
        coordinator = makeCoordinator()
        mockPresenter.isPopoverBeingPresentedValue = true

        coordinator.dismissDialogDueToNewTabBeingShown()

        XCTAssertTrue(mockPresenter.dismissPopoverCalled)
    }

    @MainActor
    func testDismissDialogDueToNewTabBeingShown_DoesNotDismiss_WhenPopoverNotPresented() {
        coordinator = makeCoordinator()
        mockPresenter.isPopoverBeingPresentedValue = false

        coordinator.dismissDialogDueToNewTabBeingShown()

        XCTAssertFalse(mockPresenter.dismissPopoverCalled)
    }

    @MainActor
    func testDismissDialogDueToNewTabBeingShown_SavesFlag() throws {
        coordinator = makeCoordinator()
        mockPresenter.isPopoverBeingPresentedValue = true

        coordinator.dismissDialogDueToNewTabBeingShown()

        let flag = try mockKeyValueStore.object(forKey: "com.duckduckgo.autoconsent.blocked.cookies.popover.seen") as? Bool
        XCTAssertEqual(flag, true)
    }

    @MainActor
    func testShowDialogForDebug_ShowsDialog_WhenPopoverNotPresented() async {
        coordinator = makeCoordinator()
        mockPresenter.isPopoverBeingPresentedValue = false

        await coordinator.showDialogForDebug()

        XCTAssertTrue(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testShowDialogForDebug_DoesNotShow_WhenPopoverAlreadyPresented() async {
        coordinator = makeCoordinator()
        mockPresenter.isPopoverBeingPresentedValue = true

        await coordinator.showDialogForDebug()

        XCTAssertFalse(mockPresenter.showPopoverCalled)
    }

    @MainActor
    func testClearBlockedCookiesPopoverSeenFlag_RemovesFlag() throws {
        coordinator = makeCoordinator()
        try mockKeyValueStore.set(true, forKey: "com.duckduckgo.autoconsent.blocked.cookies.popover.seen")

        coordinator.clearBlockedCookiesPopoverSeenFlag()

        let flag = try? mockKeyValueStore.object(forKey: "com.duckduckgo.autoconsent.blocked.cookies.popover.seen") as? Bool
        XCTAssertNil(flag)
    }

    @MainActor
    func testShowPopoverOnClose_SavesFlag() async {
        coordinator = makeCoordinator()
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        mockPresenter.showPopoverViewController?.viewModel.onClose?()

        let flag = try? mockKeyValueStore.object(forKey: "com.duckduckgo.autoconsent.blocked.cookies.popover.seen") as? Bool
        XCTAssertEqual(flag, true)
    }

    @MainActor
    func testShowPopoverOnClick_SavesFlag() async {
        coordinator = makeCoordinator()
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        mockPresenter.showPopoverViewController?.viewModel.clickAction?()

        let flag = try? mockKeyValueStore.object(forKey: "com.duckduckgo.autoconsent.blocked.cookies.popover.seen") as? Bool
        XCTAssertEqual(flag, true)
    }

    @MainActor
    func testShowPopoverOnAutoDismiss_ConfiguresViewController() async {
        coordinator = makeCoordinator()
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        let viewController = mockPresenter.showPopoverViewController
        XCTAssertNotNil(viewController)
        XCTAssertNotNil(viewController?.autoDismissDuration)
        XCTAssertEqual(viewController?.autoDismissDuration, 8.0)
    }

    @MainActor
    func testShowDialog_CreatesViewControllerWithCorrectConfiguration() async {
        coordinator = makeCoordinator()
        mockAutoconsentStats.totalCookiePopUpsBlocked = 15

        await coordinator.checkAndShowDialogIfNeeded()

        let viewController = mockPresenter.showPopoverViewController
        XCTAssertNotNil(viewController)
        guard let viewController = viewController else {
            XCTFail("ViewController should not be nil")
            return
        }
        XCTAssertEqual(viewController.viewModel.title, UserText.autoconsentStatsPopoverTitle(count: 15))
        XCTAssertEqual(viewController.viewModel.message, UserText.autoconsentStatsPopoverMessage)
        if case .featureDiscovery = viewController.viewModel.popoverStyle {
            // Correct style
        } else {
            XCTFail("Expected featureDiscovery popover style")
        }
        XCTAssertEqual(viewController.viewModel.shouldShowCloseButton, true)
        XCTAssertNotNil(viewController.viewModel.image)
    }

    @MainActor
    func testShowDialog_CallsPresenterWithViewController() async {
        coordinator = makeCoordinator()
        mockAutoconsentStats.totalCookiePopUpsBlocked = 10

        await coordinator.checkAndShowDialogIfNeeded()

        XCTAssertTrue(mockPresenter.showPopoverCalled)
        XCTAssertNotNil(mockPresenter.showPopoverViewController)
    }
}

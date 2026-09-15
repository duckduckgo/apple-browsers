//
//  CookiePopupsBlockedPromoDelegateTests.swift
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

import AutoconsentStats
import Combine
@_spi(Testing) import Persistence
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

    var showPopoverReturnValue = true

    @discardableResult
    func showPopover(viewController: PopoverMessageViewController) -> Bool {
        showPopoverCalled = true
        showPopoverViewController = viewController
        if showPopoverReturnValue {
            isPopoverBeingPresentedValue = true
        }
        return showPopoverReturnValue
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
final class CookiePopupsBlockedPromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var keyValueStore: InMemoryThrowingKeyValueStore!
    private var windowControllersManager: WindowControllersManagerMock!
    private var cookiePopupProtectionPreferences: CookiePopupProtectionPreferences!
    private var appearancePreferences: AppearancePreferences!
    private var onboardingStateUpdater: MockOnboardingStateUpdater!
    private var autoconsentStats: MockAutoconsentStats!
    private var presenter: MockAutoconsentStatsPopoverPresenter!
    private var sut: CookiePopupsBlockedPromoDelegate!

    override func setUp() {
        super.setUp()

        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueCookiePopupsBlockedPromo]
        keyValueStore = InMemoryThrowingKeyValueStore()
        windowControllersManager = WindowControllersManagerMock()
        setSelectedTabContent(.url(URL.duckDuckGo, source: .ui))

        cookiePopupProtectionPreferences = CookiePopupProtectionPreferences(
            persistor: MockCookiePopupProtectionPreferencesPersistor(),
            windowControllersManager: windowControllersManager
        )
        cookiePopupProtectionPreferences.isAutoconsentEnabled = true

        appearancePreferences = AppearancePreferences(
            persistor: AppearancePreferencesPersistorMock(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )
        appearancePreferences.isProtectionsReportVisible = true

        onboardingStateUpdater = MockOnboardingStateUpdater()
        onboardingStateUpdater.state = .onboardingCompleted

        autoconsentStats = MockAutoconsentStats()
        setBlockedCount(10)

        presenter = MockAutoconsentStatsPopoverPresenter()

        sut = makeSUT()
    }

    override func tearDown() {
        sut = nil
        presenter = nil
        autoconsentStats = nil
        onboardingStateUpdater = nil
        appearancePreferences = nil
        cookiePopupProtectionPreferences = nil
        windowControllersManager = nil
        keyValueStore = nil
        featureFlagger = nil
        super.tearDown()
    }

    private func makeSUT() -> CookiePopupsBlockedPromoDelegate {
        CookiePopupsBlockedPromoDelegate(
            featureFlagger: featureFlagger,
            keyValueStore: keyValueStore,
            windowControllersManager: windowControllersManager,
            cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
            appearancePreferences: appearancePreferences,
            onboardingStateUpdater: onboardingStateUpdater,
            autoconsentStats: autoconsentStats,
            presenter: presenter
        )
    }

    private func setSelectedTabContent(_ content: TabContent) {
        let tabCollectionViewModel = TabCollectionViewModel(
            tabCollection: TabCollection(),
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock())
        )
        tabCollectionViewModel.append(tab: Tab(uuid: "tab1", content: content))
        windowControllersManager.customAllTabCollectionViewModels = [tabCollectionViewModel]
    }

    private func setBlockedCount(_ count: Int64) {
        autoconsentStats.totalCookiePopUpsBlocked = count
        try? keyValueStore.set(count, forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
    }

    // MARK: - isEligible

    func testWhenAllGatesPassThenEligible() {
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenFeatureFlagDisabledThenNotEligible() {
        featureFlagger.enabledFeatureFlags = []
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenAutoconsentDisabledThenNotEligible() {
        cookiePopupProtectionPreferences.isAutoconsentEnabled = false
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenProtectionsReportNotVisibleThenNotEligible() {
        appearancePreferences.isProtectionsReportVisible = false
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenOnboardingNotCompletedThenNotEligible() {
        onboardingStateUpdater.state = .ongoing
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenLegacyFlagSetThenNotEligible() {
        try? keyValueStore.set(true, forKey: CookiePopupsBlockedPromoDelegate.StorageKey.blockedCookiesPopoverSeen)
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenBelowThresholdThenNotEligible() {
        setBlockedCount(4)
        XCTAssertFalse(sut.isEligible)
    }

    // MARK: - isEligiblePublisher

    func testWhenRefreshEligibilityCalledThenPublisherReemits() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        setBlockedCount(0)
        sut.refreshEligibility()

        cancellable.cancel()
        XCTAssertEqual(received, [true, false])
    }

    // MARK: - show() — presentation failure

    func testWhenPresenterCannotShowThenShowReturnsNoChange() async {
        presenter.showPopoverReturnValue = false

        let result = await sut.show(history: PromoHistoryRecord(id: "cookie-popups-blocked"), force: false)

        XCTAssertEqual(result, .noChange)
    }

    func testWhenOnNewTabPageThenShowReturnsNoChange() async {
        setSelectedTabContent(.newtab)
        presenter.showPopoverReturnValue = false

        let result = await sut.show(history: PromoHistoryRecord(id: "cookie-popups-blocked"), force: false)

        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(presenter.showPopoverCalled)
    }

    // MARK: - dismissDueToNewTabBeingShown()

    func testWhenNewTabButtonClickedWhileShowingThenResolvesIgnored() async {
        let task = Task { await sut.show(history: PromoHistoryRecord(id: "cookie-popups-blocked"), force: false) }
        try? await Task.sleep(nanoseconds: 50_000_000)

        sut.dismissDueToNewTabBeingShown()

        let result = await task.value
        XCTAssertEqual(result, .ignored())
        XCTAssertTrue(presenter.dismissPopoverCalled)
    }

    func testWhenNewTabButtonClickedWhileNotShowingThenNoOp() {
        sut.dismissDueToNewTabBeingShown()

        XCTAssertFalse(presenter.dismissPopoverCalled)
    }

    // MARK: - hide()

    func testWhenHiddenTwiceThenNoCrash() {
        sut.hide()
        sut.hide()
    }

    func testWhenHiddenWhileShowPendingThenShowResolvesNoChange() async {
        let task = Task { await sut.show(history: PromoHistoryRecord(id: "cookie-popups-blocked"), force: false) }
        try? await Task.sleep(nanoseconds: 50_000_000)

        sut.hide()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(presenter.dismissPopoverCalled)
    }
}

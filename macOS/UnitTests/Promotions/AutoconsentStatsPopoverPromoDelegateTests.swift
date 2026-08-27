//
//  AutoconsentStatsPopoverPromoDelegateTests.swift
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
final class AutoconsentStatsPopoverPromoDelegateTests: XCTestCase {

    private var keyValueStore: InMemoryThrowingKeyValueStore!
    private var windowControllersManager: WindowControllersManagerMock!
    private var cookiePopupProtectionPreferences: CookiePopupProtectionPreferences!
    private var appearancePreferences: AppearancePreferences!
    private var onboardingStateUpdater: MockOnboardingStateUpdater!
    private var autoconsentStats: MockAutoconsentStats!
    private var presenter: MockAutoconsentStatsPopoverPresenter!
    private var stateChangedSubject: PassthroughSubject<Void, Never>!
    private var sut: AutoconsentStatsPopoverPromoDelegate!

    override func setUp() {
        super.setUp()

        keyValueStore = InMemoryThrowingKeyValueStore()
        windowControllersManager = WindowControllersManagerMock()
        setSelectedTabContent(.url(URL.duckDuckGo, source: .ui))

        stateChangedSubject = PassthroughSubject<Void, Never>()
        windowControllersManager.stateChanged = stateChangedSubject.eraseToAnyPublisher()

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
        stateChangedSubject = nil
        windowControllersManager = nil
        keyValueStore = nil
        super.tearDown()
    }

    private func makeSUT() -> AutoconsentStatsPopoverPromoDelegate {
        AutoconsentStatsPopoverPromoDelegate(
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

    /// `isEligible` reads the blocked-pop-up count directly from `keyValueStore` (bypassing the
    /// `AutoconsentStats` actor for a synchronous read) - so tests must seed the store directly,
    /// not the `MockAutoconsentStats.totalCookiePopUpsBlocked` property, which only backs the async
    /// `fetchTotalCookiePopUpsBlocked()` path used by `show()` for the popover title.
    private func setBlockedCount(_ count: Int64) {
        autoconsentStats.totalCookiePopUpsBlocked = count
        try? keyValueStore.set(count, forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)
    }

    // MARK: - isEligible

    func testWhenAllGatesPassThenEligible() {
        XCTAssertTrue(sut.isEligible)
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

    func testWhenBelowThresholdThenNotEligible() {
        setBlockedCount(4)
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenOnNewTabPageThenNotEligible() {
        setSelectedTabContent(.newtab)
        sut = makeSUT()
        XCTAssertFalse(sut.isEligible)
    }

    // MARK: - isEligiblePublisher

    func testWhenTabStateChangesToNTPThenEligibilityPublisherEmitsFalse() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        setSelectedTabContent(.newtab)
        stateChangedSubject.send(())

        cancellable.cancel()
        XCTAssertEqual(received, [true, false])
    }

    func testWhenRefreshEligibilityCalledThenPublisherReemits() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        setBlockedCount(0)
        sut.refreshEligibility()

        cancellable.cancel()
        XCTAssertEqual(received, [true, false])
    }

    // MARK: - show() — migration bridge

    /// Users who already saw the pre-Promo-Queue popover must not see it again: the legacy flag is a
    /// one-time migration bridge, checked in `show()` (not `isEligible`) so the queue's own history
    /// remains the sole ongoing source of truth going forward.
    func testWhenLegacyFlagAlreadySetThenShowRetiresThePromo() async {
        try? keyValueStore.set(true, forKey: AutoconsentStatsPopoverCoordinator.StorageKey.blockedCookiesPopoverSeen)

        let result = await sut.show(history: PromoHistoryRecord(id: "cookie-popups-blocked"), force: false)

        XCTAssertEqual(result, .retired)
        XCTAssertFalse(presenter.showPopoverCalled)
    }

    /// `presenter.showPopoverReturnValue = false` here is just to make `show()` resolve immediately
    /// (via the presentation-failure path) instead of hanging on an unresolved continuation — the
    /// thing under test is that `force` gets past the legacy-flag retirement check at all.
    func testWhenForcedThenLegacyFlagIsIgnored() async {
        try? keyValueStore.set(true, forKey: AutoconsentStatsPopoverCoordinator.StorageKey.blockedCookiesPopoverSeen)
        presenter.showPopoverReturnValue = false

        let result = await sut.show(history: PromoHistoryRecord(id: "cookie-popups-blocked"), force: true)

        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(presenter.showPopoverCalled)
    }

    // MARK: - show() — presentation failure

    /// No anchor to present against: the promo must end its session rather than leave the queue
    /// waiting on an unresolved continuation.
    func testWhenPresenterCannotShowThenShowReturnsNoChange() async {
        presenter.showPopoverReturnValue = false

        let result = await sut.show(history: PromoHistoryRecord(id: "cookie-popups-blocked"), force: false)

        XCTAssertEqual(result, .noChange)
    }

    // MARK: - hide()

    /// `PromoService` calls `hide()` unconditionally after recording any result, even post-teardown — it must not crash.
    func testWhenHiddenTwiceThenNoCrash() {
        sut.hide()
        sut.hide()
    }

    /// If `hide()` is called while `show()`'s continuation is still pending (the promo queue's own
    /// timeout fired, or eligibility was retracted), the continuation must still resolve so the
    /// awaiting task doesn't leak.
    func testWhenHiddenWhileShowPendingThenShowResolvesNoChange() async {
        let task = Task { await sut.show(history: PromoHistoryRecord(id: "cookie-popups-blocked"), force: false) }
        try? await Task.sleep(nanoseconds: 50_000_000)

        sut.hide()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(presenter.dismissPopoverCalled)
    }
}

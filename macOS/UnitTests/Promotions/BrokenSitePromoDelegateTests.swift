//
//  BrokenSitePromoDelegateTests.swift
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

import BrokenSitePrompt
import Combine
@_spi(Testing) import PixelKit
import PrivacyConfig
import SharedTestUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BrokenSitePromoDelegateTests: XCTestCase {

    private static let promoId = "broken-site"

    private var configManager: MockPrivacyConfigurationManaging!
    private var limiterStore: MockBrokenSitePromptLimiterStore!
    private var limiter: BrokenSitePromptLimiter!
    private var onboardingStateUpdater: MockOnboardingStateUpdater!
    private var windowControllersManager: WindowControllersManagerMock!
    private var presenter: MockBrokenSitePromoPresenter!
    private var pixelFiring: PixelKitMock!
    private var sut: BrokenSitePromoDelegate!

    override func setUp() {
        super.setUp()
        configManager = MockPrivacyConfigurationManaging()
        configManager.mockConfig.isFeatureEnabledCheck = { feature, _ in feature == .brokenSitePrompt }
        limiterStore = MockBrokenSitePromptLimiterStore()
        limiter = BrokenSitePromptLimiter(privacyConfigManager: configManager, store: limiterStore)
        onboardingStateUpdater = MockOnboardingStateUpdater()
        onboardingStateUpdater.state = .onboardingCompleted
        windowControllersManager = WindowControllersManagerMock()
        presenter = MockBrokenSitePromoPresenter()
        pixelFiring = PixelKitMock()
        sut = BrokenSitePromoDelegate(privacyConfigManager: configManager,
                                      limiter: limiter,
                                      onboardingStateUpdater: onboardingStateUpdater,
                                      windowControllersManager: windowControllersManager,
                                      presenter: presenter,
                                      pixelFiring: pixelFiring)
    }

    override func tearDown() {
        sut = nil
        pixelFiring = nil
        presenter = nil
        windowControllersManager = nil
        onboardingStateUpdater = nil
        limiter = nil
        limiterStore = nil
        configManager = nil
        super.tearDown()
    }

    private var history: PromoHistoryRecord { PromoHistoryRecord(id: Self.promoId) }

    private var dismissStreak: Int { limiterStore.toastDismissStreakCounter }

    /// The result `show()` resolves with for a regular (non-forced) show.
    private var cooldownResult: PromoResult { .ignored(cooldown: limiter.coolDownInterval) }

    private func selectTab(with url: URL) {
        let tabCollectionViewModel = TabCollectionViewModel(
            tabCollection: TabCollection(),
            pinnedTabsManagerProvider: PinnedTabsManagerProvidingMock(),
            tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(),
                                             windowControllersManager: WindowControllersManagerMock())
        )
        tabCollectionViewModel.append(tab: Tab(content: .url(url, source: .ui)))
        windowControllersManager.customAllTabCollectionViewModels = [tabCollectionViewModel]
    }

    private func showPromo(force: Bool = false) async -> Task<PromoResult, Never> {
        let task = Task { await sut.show(history: history, force: force) }

        var yields = 0
        while presenter.presentCallCount == 0, yields < 100 {
            await Task.yield()
            yields += 1
        }

        XCTAssertEqual(presenter.presentCallCount, 1, "show() never reached the presenter")
        return task
    }

    // MARK: - Eligibility

    func testWhenOnboardingCompleteAndLimiterAllowsThenEligible() {
        XCTAssertTrue(limiter.shouldShowToast())
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenOnboardingNotCompletedThenNotEligible() {
        onboardingStateUpdater.state = .ongoing

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenFeatureDisabledThenNotEligible() {
        configManager.mockConfig.isFeatureEnabledCheck = { _, _ in false }

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenLimiterDoesNotAllowThenNotEligible() {
        limiter.didShowToast()

        XCTAssertFalse(limiter.shouldShowToast())
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenLimiterDismissStreakExceededThenNotEligible() {
        limiter.didShowToast()
        limiter.didDismissToast()
        limiter.didDismissToast()
        limiter.didDismissToast()

        // Advance date beyond regular cooldown interval
        limiter.debugAdvanceDate(by: limiter.coolDownInterval + .day)

        XCTAssertFalse(sut.isEligible)
    }

    func testEligibilityPublisherReplaysCurrentValue() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        XCTAssertEqual(received, [true])
        cancellable.cancel()
    }

    func testWhenFeatureDisabledEligibilityPublisherEmitsFalse() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        configManager.mockConfig.isFeatureEnabledCheck = { _, _ in false }
        configManager.updatesSubject.send(())

        XCTAssertEqual(received.last, false)
        cancellable.cancel()
    }

    func testWhenLimiterEntersCooldownThenEligibilityPublisherDoesNotEmitFalse() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        // Showing the promo puts the limiter into its cooldown, so `isEligible` is false from here on.
        limiter.didShowToast()
        XCTAssertFalse(sut.isEligible)
        configManager.updatesSubject.send(())

        // Retraction is driven by the feature flag alone: a promo must not retract itself the
        // moment it appears just because the limiter has recorded the show.
        XCTAssertEqual(received, [true])
        cancellable.cancel()
    }

    // MARK: - Presentation failure

    func testWhenSelectedTabIsDuckDuckGoThenResolvesWithNoChangeAndDoesNotPresent() async {
        selectTab(with: .duckDuckGo)

        let result = await sut.show(history: history, force: false)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(presenter.presentCallCount, 0)
        XCTAssertEqual(limiterStore.lastToastShownDate, .distantPast)
        XCTAssertEqual(dismissStreak, 0)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenPresenterCannotPresentThenResolvesWithNoChangeAndDoesNotTouchLimiter() async {
        selectTab(with: URL(string: "https://example.com")!)
        presenter.canPresent = false

        let result = await sut.show(history: history, force: false)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(limiterStore.lastToastShownDate, .distantPast)
        XCTAssertEqual(dismissStreak, 0)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - User dismissal

    func testWhenUserDismissesPromoThenDismissIsRecorded() async {
        selectTab(with: URL(string: "https://example.com")!)
        let showTask = await showPromo()

        presenter.simulatePopoverDidDisappear()

        let result = await showTask.value
        XCTAssertEqual(result, cooldownResult)
        XCTAssertEqual(dismissStreak, 1)
    }

    // MARK: - Opening the report

    func testWhenUserOpensReportThenDismissStreakIsResetAndNotRecordedAsDismiss() async {
        limiterStore.toastDismissStreakCounter = 2
        selectTab(with: URL(string: "https://example.com")!)
        let showTask = await showPromo()

        presenter.simulateUserTappingReportButton()

        let result = await showTask.value
        XCTAssertEqual(result, cooldownResult)
        XCTAssertEqual(presenter.openPrivacyDashboardReportCallCount, 1)
        // The popover disappears as part of opening the report; that must not undo the reset.
        XCTAssertEqual(dismissStreak, 0)
    }

    // MARK: - hide()

    func testWhenHideCalledBeforeShowThenItIsANoOp() {
        sut.hide()
        sut.hide()

        XCTAssertEqual(dismissStreak, 0)
    }

    func testWhenPromoIsRetractedThenDismissIsNotRecorded() async {
        selectTab(with: URL(string: "https://example.com")!)
        let showTask = await showPromo()

        sut.hide()
        presenter.simulatePopoverDidDisappear()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(presenter.dismissCallCount, 1)
        // The queue retracted the promo. The user never closed it, so the streak must not move.
        XCTAssertEqual(dismissStreak, 0)
    }

    func testWhenPromoIsRetractedAndPopoverDisappearsSynchronouslyThenDismissIsNotRecorded() async {
        selectTab(with: URL(string: "https://example.com")!)
        presenter.deliversDisappearanceSynchronouslyOnDismiss = true
        let showTask = await showPromo()

        sut.hide()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(dismissStreak, 0)
    }
}

// MARK: - Mocks

@MainActor
private final class MockBrokenSitePromoPresenter: BrokenSitePromoPresenting {

    var canPresent = true
    /// Mirrors an AppKit dismissal that tears the popover down before `dismiss()` returns.
    var deliversDisappearanceSynchronouslyOnDismiss = false

    private(set) var presentCallCount = 0
    private(set) var dismissCallCount = 0
    private(set) var openPrivacyDashboardReportCallCount = 0

    private var buttonAction: (() -> Void)?
    private var onDismiss: (() -> Void)?

    func present(buttonAction: @escaping () -> Void, onDismiss: @escaping () -> Void) -> Bool {
        presentCallCount += 1
        guard canPresent else { return false }
        self.buttonAction = buttonAction
        self.onDismiss = onDismiss
        return true
    }

    func dismiss() {
        dismissCallCount += 1
        if deliversDisappearanceSynchronouslyOnDismiss {
            simulatePopoverDidDisappear()
        }
    }

    func openPrivacyDashboardReport() {
        openPrivacyDashboardReportCallCount += 1
    }

    /// Mirrors `PopoverMessageView`, whose button runs its action and then dismisses the popover.
    func simulateUserTappingReportButton() {
        buttonAction?()
        simulatePopoverDidDisappear()
    }

    /// Mirrors `PopoverMessageViewController.viewDidDisappear()`, which runs for every dismissal —
    /// user-initiated or not — and only ever runs once.
    func simulatePopoverDidDisappear() {
        let onDismiss = self.onDismiss
        self.onDismiss = nil
        onDismiss?()
    }
}

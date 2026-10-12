//
//  BookmarksBarSyncPromoDelegateTests.swift
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

import Combine
@testable import DDGSync
import FeatureFlags_macOS
@_spi(Testing) import Persistence
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarksBarSyncPromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var syncService: MockDDGSyncing!
    private var notificationCenter: NotificationCenter!
    private var legacyStorage: KeyedStorage<BookmarksBarSyncPromoLegacySettings>!
    private var isBookmarksBarSettingOn = true
    private var now = Date()
    private var recordedResults: [(promoID: String, result: PromoResult)] = []

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueBookmarksBarSyncPromo, .newSyncEntryPoints, .syncFeatureLevel3]
        syncService = MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
        notificationCenter = NotificationCenter()
        legacyStorage = KeyedStorage(storage: InMemoryKeyValueStore())
        isBookmarksBarSettingOn = true
        now = Date()
        recordedResults = []
    }

    override func tearDown() {
        recordedResults = []
        legacyStorage = nil
        notificationCenter = nil
        syncService = nil
        featureFlagger = nil
        super.tearDown()
    }

    // Refreshes eligibility once, as `PromoService` does before reading it.
    private func makeSUT(hasSyncService: Bool = true) -> BookmarksBarSyncPromoDelegate {
        let sut = BookmarksBarSyncPromoDelegate(
            featureFlagger: featureFlagger,
            syncService: hasSyncService ? syncService : nil,
            isBookmarksBarSettingOn: { [unowned self] in isBookmarksBarSettingOn },
            notificationCenter: notificationCenter,
            legacyStorage: legacyStorage,
            dateProvider: { [unowned self] in now },
            recordResult: { [unowned self] in recordedResults.append(($0, $1)) }
        )
        sut.refreshEligibility()
        return sut
    }

    private func eligibility(of sut: BookmarksBarSyncPromoDelegate, becomes value: Bool) async {
        let eligibilityExpectation = expectation(description: "eligibility is \(value)")
        let cancellable = sut.isEligiblePublisher
            .first(where: { $0 == value })
            .sink { _ in eligibilityExpectation.fulfill() }
        await fulfillment(of: [eligibilityExpectation], timeout: 1)
        cancellable.cancel()
    }

    // Starts `show()` and returns once the promo is active, so the caller can resolve it.
    private func startShowing(_ sut: BookmarksBarSyncPromoDelegate, force: Bool = false) async -> Task<PromoResult, Never> {
        let activeExpectation = expectation(description: "promo active")
        let cancellable = sut.isPromoActivePublisher
            .first(where: { $0 })
            .sink { _ in activeExpectation.fulfill() }
        let task = Task { await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarksBarSyncPromoID), force: force) }
        await fulfillment(of: [activeExpectation], timeout: 1)
        cancellable.cancel()
        return task
    }

    private func recordedResults(become expected: [PromoResult]) async {
        let deadline = Date().addingTimeInterval(1)
        while recordedResults.map(\.result) != expected, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(recordedResults.map(\.result), expected)
    }

    // MARK: - Eligibility

    func testWhenCreatedThenItIsNotEligibleUntilEligibilityIsRefreshed() {
        let sut = BookmarksBarSyncPromoDelegate(
            featureFlagger: featureFlagger,
            syncService: syncService,
            isBookmarksBarSettingOn: { true },
            notificationCenter: notificationCenter,
            legacyStorage: legacyStorage,
            recordResult: { _, _ in }
        )

        XCTAssertFalse(sut.isEligible)

        sut.refreshEligibility()

        XCTAssertTrue(sut.isEligible)
    }

    func testWhenAllConditionsMetThenPromoIsEligible() {
        XCTAssertTrue(makeSUT().isEligible)
    }

    func testWhenKillSwitchIsOffThenPromoIsNotEligible() {
        featureFlagger.enabledFeatureFlags = [.newSyncEntryPoints, .syncFeatureLevel3]

        XCTAssertFalse(makeSUT().isEligible)
    }

    func testWhenNewSyncEntryPointsAreOffThenPromoIsNotEligible() {
        for enabledFeatureFlags in [[FeatureFlag.promoQueueBookmarksBarSyncPromo, .syncFeatureLevel3],
                                    [FeatureFlag.promoQueueBookmarksBarSyncPromo, .newSyncEntryPoints]] {
            featureFlagger.enabledFeatureFlags = enabledFeatureFlags

            XCTAssertFalse(makeSUT().isEligible, "Enabled flags: \(enabledFeatureFlags)")
        }
    }

    func testWhenSyncServiceIsMissingThenPromoIsNotEligible() {
        XCTAssertFalse(makeSUT(hasSyncService: false).isEligible)
    }

    func testWhenSyncIsNotInactiveThenPromoIsNotEligible() {
        for authState in [SyncAuthState.initializing, .active, .addingNewDevice] {
            syncService.authState = authState

            XCTAssertFalse(makeSUT().isEligible, "Auth state: \(authState)")
        }
    }

    func testWhenBookmarksBarSettingIsOffThenPromoIsNotEligible() {
        isBookmarksBarSettingOn = false

        XCTAssertFalse(makeSUT().isEligible)
    }

    func testWhenLegacyButtonWasFirstSeenLessThanSevenDaysAgoThenPromoIsEligible() {
        legacyStorage.legacyFirstPresentedDate = now.addingTimeInterval(-.days(3))

        XCTAssertTrue(makeSUT().isEligible)
    }

    func testWhenLegacyButtonWasFirstSeenMoreThanSevenDaysAgoThenPromoIsNotEligible() {
        legacyStorage.legacyFirstPresentedDate = now.addingTimeInterval(-.days(8))

        XCTAssertFalse(makeSUT().isEligible)
    }

    func testWhenLegacyButtonPeriodExpiresThenPromoIsNotEligibleAtNextRefresh() {
        legacyStorage.legacyFirstPresentedDate = now.addingTimeInterval(-.days(6))
        let sut = makeSUT()
        XCTAssertTrue(sut.isEligible)

        now = now.addingTimeInterval(.days(1))
        XCTAssertTrue(sut.isEligible)

        sut.refreshEligibility()
        XCTAssertFalse(sut.isEligible)
    }

    // MARK: - Eligibility updates

    func testWhenSyncTurnsOnThenPromoBecomesNotEligible() async {
        let sut = makeSUT()
        XCTAssertTrue(sut.isEligible)

        syncService.authState = .active

        await eligibility(of: sut, becomes: false)
    }

    func testWhenBookmarksBarSettingChangesThenEligibilityIsRecomputed() async {
        let sut = makeSUT()
        XCTAssertTrue(sut.isEligible)

        isBookmarksBarSettingOn = false
        notificationCenter.post(name: AppearancePreferences.Notifications.showBookmarksBarSettingChanged, object: nil)

        await eligibility(of: sut, becomes: false)

        isBookmarksBarSettingOn = true
        notificationCenter.post(name: AppearancePreferences.Notifications.showBookmarksBarSettingChanged, object: nil)

        await eligibility(of: sut, becomes: true)
    }

    // MARK: - show() / hide()

    func testWhenLegacyButtonWasDismissedThenShowRetiresThePromo() async {
        legacyStorage.didDismissLegacyButton = true
        let sut = makeSUT()

        let result = await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarksBarSyncPromoID), force: false)

        XCTAssertEqual(result, .retired)
        XCTAssertFalse(sut.isPromoActive)
    }

    func testWhenLegacyButtonWasDismissedThenForceShowBypassesRetirement() async {
        legacyStorage.didDismissLegacyButton = true
        let sut = makeSUT()

        let showTask = await startShowing(sut, force: true)

        XCTAssertTrue(sut.isPromoActive)
        sut.hide()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
    }

    func testWhenShownThenPromoIsActiveUntilHidden() async {
        let sut = makeSUT()
        XCTAssertFalse(sut.isPromoActive)

        let showTask = await startShowing(sut)
        XCTAssertTrue(sut.isPromoActive)

        sut.hide()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(sut.isPromoActive)
    }

    func testWhenHiddenTwiceThenShowReturnsNoChangeOnce() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        sut.hide()
        sut.hide()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(sut.isPromoActive)
    }

    func testWhenHiddenBeforeShowingThenNothingHappens() {
        let sut = makeSUT()

        sut.hide()
        sut.hide()

        XCTAssertFalse(sut.isPromoActive)
    }

    // MARK: - CTA

    func testWhenSyncSetupStartedThenPromoIsNotResolved() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        sut.syncSetupStarted()

        XCTAssertTrue(sut.isPromoActive, "Tapping the CTA alone doesn't resolve the promo")
        XCTAssertTrue(recordedResults.isEmpty)

        sut.hide()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
    }

    func testWhenSyncSetupStartedAndSyncTurnsOnThenActionedIsRecorded() async {
        let sut = makeSUT()
        _ = await startShowing(sut)

        sut.syncSetupStarted()
        syncService.authState = .active

        await recordedResults(become: [.actioned])
        XCTAssertEqual(recordedResults.map(\.promoID), [PromoServiceFactory.bookmarksBarSyncPromoID])
        await eligibility(of: sut, becomes: false)
    }

    func testWhenSyncSetupStartedAndSyncIsSetUpWithAnExistingAccountThenActionedIsRecorded() async {
        let sut = makeSUT()
        _ = await startShowing(sut)

        sut.syncSetupStarted()
        syncService.authState = .addingNewDevice

        await recordedResults(become: [.actioned])
        XCTAssertEqual(recordedResults.map(\.promoID), [PromoServiceFactory.bookmarksBarSyncPromoID])
    }

    func testWhenPromoIsHiddenBecauseSyncTurnedOnAfterSetupStartedThenActionedIsStillRecorded() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)
        sut.syncSetupStarted()

        syncService.authState = .active
        sut.hide()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        await recordedResults(become: [.actioned])
    }

    func testWhenSyncTurnsOnWithoutSetupStartedThenNothingIsRecorded() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        syncService.authState = .active

        await eligibility(of: sut, becomes: false)
        sut.hide()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(recordedResults.isEmpty)
    }

    func testWhenPromoWasHiddenAfterSetupStartedThenSyncTurningOnLaterIsNotActioned() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)
        sut.syncSetupStarted()
        sut.hide()
        _ = await showTask.value

        syncService.authState = .active

        await eligibility(of: sut, becomes: false)
        XCTAssertTrue(recordedResults.isEmpty)
    }

    // MARK: - Trigger wiring

    func testWhenBookmarksBarShownNotificationPostedThenPromoTriggerFires() {
        let triggerExpectation = expectation(description: "trigger fired")
        let cancellable = PromoTrigger.triggerPublisher
            .filter { $0 == .bookmarksBarShown }
            .sink { _ in triggerExpectation.fulfill() }

        NotificationCenter.default.post(name: .bookmarksBarShown, object: nil)

        wait(for: [triggerExpectation], timeout: 1)
        cancellable.cancel()
    }
}

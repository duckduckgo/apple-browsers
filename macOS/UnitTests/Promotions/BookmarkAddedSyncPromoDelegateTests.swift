//
//  BookmarkAddedSyncPromoDelegateTests.swift
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
final class BookmarkAddedSyncPromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var syncService: MockDDGSyncing!
    private var storage: KeyedStorage<BookmarkAddedSyncPromoSettings>!
    private var recordedResults: [(promoID: String, result: PromoResult)] = []

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueBookmarkAddedSyncPromo, .newSyncEntryPoints, .syncFeatureLevel3]
        syncService = MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
        storage = KeyedStorage(storage: InMemoryKeyValueStore())
        recordedResults = []
    }

    override func tearDown() {
        recordedResults = []
        storage = nil
        syncService = nil
        featureFlagger = nil
        super.tearDown()
    }

    // Refreshes eligibility once, as `PromoService` does before reading it.
    private func makeSUT(hasSyncService: Bool = true) -> BookmarkAddedSyncPromoDelegate {
        let sut = BookmarkAddedSyncPromoDelegate(
            featureFlagger: featureFlagger,
            syncService: hasSyncService ? syncService : nil,
            storage: storage,
            recordResult: { [unowned self] in recordedResults.append(($0, $1)) }
        )
        sut.refreshEligibility()
        return sut
    }

    private func eligibility(of sut: BookmarkAddedSyncPromoDelegate, becomes value: Bool) async {
        let eligibilityExpectation = expectation(description: "eligibility is \(value)")
        let cancellable = sut.isEligiblePublisher
            .first(where: { $0 == value })
            .sink { _ in eligibilityExpectation.fulfill() }
        await fulfillment(of: [eligibilityExpectation], timeout: 1)
        cancellable.cancel()
    }

    // Starts `show()` and returns once the promo is active, so the caller can resolve it.
    private func startShowing(_ sut: BookmarkAddedSyncPromoDelegate, force: Bool = false) async -> Task<PromoResult, Never> {
        let activeExpectation = expectation(description: "promo active")
        let cancellable = sut.isPromoActivePublisher
            .first(where: { $0 })
            .sink { _ in activeExpectation.fulfill() }
        let task = Task { await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarkAddedSyncPromoID), force: force) }
        await fulfillment(of: [activeExpectation], timeout: 1)
        cancellable.cancel()
        return task
    }

    // Shows the promo and closes the surface that displayed it.
    private func showAndCloseSurface(_ sut: BookmarkAddedSyncPromoDelegate, force: Bool = false) async -> PromoResult {
        let showTask = await startShowing(sut, force: force)
        sut.syncButtonSurfaceClosed()
        return await showTask.value
    }

    private func show(_ sut: BookmarkAddedSyncPromoDelegate, force: Bool = false) async -> PromoResult {
        await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarkAddedSyncPromoID), force: force)
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
        let sut = BookmarkAddedSyncPromoDelegate(
            featureFlagger: featureFlagger,
            syncService: syncService,
            storage: storage,
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

    func testWhenOnlyTheBookmarksBarKillSwitchIsOnThenPromoIsNotEligible() {
        featureFlagger.enabledFeatureFlags = [.promoQueueBookmarksBarSyncPromo, .newSyncEntryPoints, .syncFeatureLevel3]

        XCTAssertFalse(makeSUT().isEligible)
    }

    func testWhenNewSyncEntryPointsAreOffThenPromoIsNotEligible() {
        for enabledFeatureFlags in [[FeatureFlag.promoQueueBookmarkAddedSyncPromo, .syncFeatureLevel3],
                                    [FeatureFlag.promoQueueBookmarkAddedSyncPromo, .newSyncEntryPoints]] {
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

    func testWhenLegacyButtonWasDismissedThenPromoIsStillEligible() {
        storage.didDismissLegacyButton = true
        storage.presentedCount = 5

        XCTAssertTrue(makeSUT().isEligible, "Legacy state retires the promo in show(), not through eligibility")
    }

    // MARK: - Eligibility updates

    func testWhenSyncTurnsOnThenPromoBecomesNotEligible() async {
        let sut = makeSUT()
        XCTAssertTrue(sut.isEligible)

        syncService.authState = .active

        await eligibility(of: sut, becomes: false)
    }

    func testWhenKillSwitchTurnsOffThenPromoBecomesNotEligible() async {
        let sut = makeSUT()
        XCTAssertTrue(sut.isEligible)

        featureFlagger.enabledFeatureFlags = [.newSyncEntryPoints, .syncFeatureLevel3]
        featureFlagger.triggerUpdate()

        await eligibility(of: sut, becomes: false)
    }

    func testWhenEligibilityIsLostWhileShowingThenHideResolvesWithNoChange() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        syncService.authState = .active
        await eligibility(of: sut, becomes: false)
        sut.hide()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(sut.isPromoActive)
        XCTAssertNil(storage.presentedCount)
    }

    // MARK: - Legacy migration

    func testWhenLegacyButtonWasDismissedThenShowRetiresThePromo() async {
        storage.didDismissLegacyButton = true
        let sut = makeSUT()

        let result = await show(sut)

        XCTAssertEqual(result, .retired)
        XCTAssertFalse(sut.isPromoActive)
    }

    func testWhenLegacyButtonWasDismissedThenForceShowBypassesRetirement() async {
        storage.didDismissLegacyButton = true
        let sut = makeSUT()

        let showTask = await startShowing(sut, force: true)

        XCTAssertTrue(sut.isPromoActive)
        sut.hide()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
    }

    func testWhenLegacyButtonWasSeenTheMaximumNumberOfTimesThenShowRetiresThePromo() async {
        for presentedCount in [5, 7] {
            storage.presentedCount = presentedCount
            let sut = makeSUT()

            let result = await show(sut)

            XCTAssertEqual(result, .retired, "Presented count: \(presentedCount)")
            XCTAssertFalse(sut.isPromoActive)
        }
    }

    func testWhenLegacyButtonWasSeenTheMaximumNumberOfTimesThenForceShowBypassesRetirement() async {
        storage.presentedCount = 5
        let sut = makeSUT()

        let showTask = await startShowing(sut, force: true)

        XCTAssertTrue(sut.isPromoActive)
        sut.hide()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
    }

    func testWhenLegacyButtonWasSeenThreeTimesThenThePromoRetiresAfterTwoMoreViews() async {
        storage.presentedCount = 3
        let sut = makeSUT()

        let fourthViewResult = await showAndCloseSurface(sut)
        XCTAssertEqual(fourthViewResult, .noChange)
        XCTAssertEqual(storage.presentedCount, 4)

        let fifthViewResult = await showAndCloseSurface(sut)
        XCTAssertEqual(fifthViewResult, .ignored())
        XCTAssertEqual(storage.presentedCount, 5)

        let nextShowResult = await show(sut)
        XCTAssertEqual(nextShowResult, .retired)
    }

    // MARK: - Dismiss (✕)

    func testWhenSyncButtonIsDismissedThenPromoIsIgnored() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        sut.syncButtonDismissed()

        let result = await showTask.value
        XCTAssertEqual(result, .ignored())
        XCTAssertFalse(sut.isPromoActive)
    }

    func testWhenSyncButtonIsDismissedThenLegacyStateIsNotWritten() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        sut.syncButtonDismissed()
        _ = await showTask.value

        XCTAssertNil(storage.didDismissLegacyButton)
        XCTAssertNil(storage.presentedCount)
    }

    func testWhenSyncButtonIsDismissedAndItsSurfaceClosesThenTheViewIsNotCounted() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        sut.syncButtonDismissed()
        sut.syncButtonSurfaceClosed()

        let result = await showTask.value
        XCTAssertEqual(result, .ignored())
        XCTAssertNil(storage.presentedCount)
    }

    // MARK: - Surface closed

    func testWhenSurfaceClosesForTheFirstFourViewsThenEachViewIsCountedWithNoChange() async {
        let sut = makeSUT()

        for view in 1...4 {
            let result = await showAndCloseSurface(sut)

            XCTAssertEqual(result, .noChange, "View \(view)")
            XCTAssertEqual(storage.presentedCount, view)
            XCTAssertFalse(sut.isPromoActive)
        }
    }

    func testWhenSurfaceClosesOnTheFifthViewThenPromoIsIgnored() async {
        let sut = makeSUT()
        for _ in 1...4 {
            _ = await showAndCloseSurface(sut)
        }

        let result = await showAndCloseSurface(sut)

        XCTAssertEqual(result, .ignored())
        XCTAssertEqual(storage.presentedCount, 5)
    }

    func testWhenSurfaceClosesDuringAForcedShowingThenNoChangeAndTheViewIsNotCounted() async {
        storage.presentedCount = 4
        let sut = makeSUT()

        let result = await showAndCloseSurface(sut, force: true)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(storage.presentedCount, 4)
    }

    func testWhenSurfaceClosesAfterAForcedShowingThenTheNextViewIsCounted() async {
        let sut = makeSUT()
        _ = await showAndCloseSurface(sut, force: true)

        let result = await showAndCloseSurface(sut)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(storage.presentedCount, 1)
    }

    func testWhenShownWithoutASurfaceClosingThenTheViewIsNotCounted() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        XCTAssertTrue(sut.isPromoActive)
        XCTAssertNil(storage.presentedCount)

        sut.hide()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertNil(storage.presentedCount)
    }

    func testWhenSurfaceClosesWithNoShowingPendingThenNothingIsCounted() async {
        let sut = makeSUT()

        sut.syncButtonSurfaceClosed()
        XCTAssertNil(storage.presentedCount)

        let showTask = await startShowing(sut)
        XCTAssertTrue(sut.isPromoActive, "A showing that starts after the surface closed stays pending for the next surface")

        sut.syncButtonSurfaceClosed()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(storage.presentedCount, 1)
    }

    func testWhenSurfaceClosesTwiceThenTheViewIsCountedOnce() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        sut.syncButtonSurfaceClosed()
        sut.syncButtonSurfaceClosed()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(storage.presentedCount, 1)
    }

    // MARK: - hide()

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
        XCTAssertEqual(recordedResults.map(\.promoID), [PromoServiceFactory.bookmarkAddedSyncPromoID])
        await eligibility(of: sut, becomes: false)
    }

    func testWhenSyncSetupStartedAndSyncIsSetUpWithAnExistingAccountThenActionedIsRecorded() async {
        let sut = makeSUT()
        _ = await startShowing(sut)

        sut.syncSetupStarted()
        syncService.authState = .addingNewDevice

        await recordedResults(become: [.actioned])
        XCTAssertEqual(recordedResults.map(\.promoID), [PromoServiceFactory.bookmarkAddedSyncPromoID])
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

    func testWhenSurfaceClosesAfterSetupStartedAndSyncTurnsOnLaterThenActionedIsRecorded() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)
        sut.syncSetupStarted()

        sut.syncButtonSurfaceClosed()
        let result = await showTask.value
        XCTAssertEqual(result, .noChange)

        syncService.authState = .active

        await recordedResults(become: [.actioned])
        XCTAssertEqual(recordedResults.map(\.promoID), [PromoServiceFactory.bookmarkAddedSyncPromoID])
    }

    func testWhenSyncSetupStartedButSyncDoesNotTurnOnThenNothingIsRecorded() async {
        let sut = makeSUT()
        let showTask = await startShowing(sut)

        sut.syncSetupStarted()
        sut.syncButtonSurfaceClosed()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(recordedResults.isEmpty)
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
}

//
//  BookmarksEmptyStatePromoDelegateTests.swift
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
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarksEmptyStatePromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var bookmarksChanged: PassthroughSubject<Void, Never>!
    private var dataImportCompleted: PassthroughSubject<Void, Never>!
    private var syncService: MockDDGSyncing!
    private var hasTopLevelEntities = false
    private var recordedResults: [(promoID: String, result: PromoResult)] = []
    private var resultRecordedExpectation: XCTestExpectation?

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueBookmarksEmptyStatePromo]
        bookmarksChanged = PassthroughSubject()
        dataImportCompleted = PassthroughSubject()
        syncService = MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
        hasTopLevelEntities = false
        recordedResults = []
    }

    override func tearDown() {
        resultRecordedExpectation = nil
        recordedResults = []
        syncService = nil
        dataImportCompleted = nil
        bookmarksChanged = nil
        featureFlagger = nil
        super.tearDown()
    }

    // Refreshes eligibility once, as `PromoService` does before reading it.
    private func makeSUT() -> BookmarksEmptyStatePromoDelegate {
        let sut = BookmarksEmptyStatePromoDelegate(
            featureFlagger: featureFlagger,
            hasTopLevelEntitiesProvider: { [unowned self] in hasTopLevelEntities },
            bookmarksChangedPublisher: bookmarksChanged.eraseToAnyPublisher(),
            dataImportCompletedPublisher: dataImportCompleted.eraseToAnyPublisher(),
            syncService: syncService,
            recordResult: { [unowned self] in
                recordedResults.append(($0, $1))
                resultRecordedExpectation?.fulfill()
            }
        )
        sut.refreshEligibility()
        return sut
    }

    /// Fulfilled by the next recorded result. An inverted expectation fails if anything is recorded.
    private func expectResult(isInverted: Bool = false) -> XCTestExpectation {
        let expectation = expectation(description: isInverted ? "no result recorded" : "result recorded")
        expectation.isInverted = isInverted
        resultRecordedExpectation = expectation
        return expectation
    }

    private func waitForNoResult(_ expectation: XCTestExpectation) async {
        await fulfillment(of: [expectation], timeout: 0.2)
        XCTAssertTrue(recordedResults.isEmpty)
    }

    private func startShowing(_ sut: BookmarksEmptyStatePromoDelegate) async -> Task<PromoResult, Never> {
        let activeExpectation = expectation(description: "promo is active")
        let cancellable = sut.isPromoActivePublisher
            .first(where: { $0 })
            .sink { _ in activeExpectation.fulfill() }
        let task = Task { await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.bookmarksEmptyStateImportSyncPromoID), force: false) }
        await fulfillment(of: [activeExpectation], timeout: 1)
        cancellable.cancel()
        return task
    }

    private func isPromoActive(_ sut: BookmarksEmptyStatePromoDelegate) -> Bool {
        var value = false
        _ = sut.isPromoActivePublisher.first().sink { value = $0 }
        return value
    }

    // MARK: - Eligibility

    func testWhenThereAreNoBookmarksThenEligible() {
        XCTAssertTrue(makeSUT().isEligible)
    }

    func testWhenThereAreTopLevelBookmarksOrFoldersThenNotEligible() {
        hasTopLevelEntities = true

        XCTAssertFalse(makeSUT().isEligible)
    }

    func testWhenKillSwitchIsOffThenNotEligible() {
        featureFlagger.enabledFeatureFlags = []

        XCTAssertFalse(makeSUT().isEligible)
    }

    func testWhenBookmarkIsAddedThenEligibilityIsLost() async {
        let sut = makeSUT()
        let ineligibleExpectation = expectation(description: "eligibility is false")
        let cancellable = sut.isEligiblePublisher
            .first(where: { !$0 })
            .sink { _ in ineligibleExpectation.fulfill() }

        hasTopLevelEntities = true
        bookmarksChanged.send()

        await fulfillment(of: [ineligibleExpectation], timeout: 1)
        cancellable.cancel()
    }

    // MARK: - Display

    func testWhenShownThenPromoIsActive() async {
        let sut = makeSUT()

        let task = await startShowing(sut)

        XCTAssertTrue(isPromoActive(sut))
        sut.hide()
        _ = await task.value
    }

    func testWhenHiddenThenResolvesWithNoChangeAndPromoIsInactive() async {
        let sut = makeSUT()
        let task = await startShowing(sut)

        sut.hide()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(isPromoActive(sut))
    }

    func testWhenHiddenTwiceThenSecondHideIsIgnored() async {
        let sut = makeSUT()
        let task = await startShowing(sut)

        sut.hide()
        sut.hide()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
    }

    func testWhenHiddenBeforeShownThenPromoStaysInactive() {
        let sut = makeSUT()

        sut.hide()

        XCTAssertFalse(isPromoActive(sut))
    }

    // MARK: - Actioned

    func testWhenImportFromEmptyStateCompletesWithBookmarksThenRecordsRepeatableActioned() async {
        let sut = makeSUT()
        let recorded = expectResult()

        sut.importStarted()
        hasTopLevelEntities = true
        dataImportCompleted.send()

        await fulfillment(of: [recorded], timeout: 1)
        XCTAssertEqual(recordedResults.map(\.result), [.actioned(cooldown: 0)])
        XCTAssertEqual(recordedResults.map(\.promoID), [PromoServiceFactory.bookmarksEmptyStateImportSyncPromoID])
    }

    func testWhenImportFromEmptyStateCompletesWithoutBookmarksThenRecordsOnceBookmarksAppear() async {
        let sut = makeSUT()
        let notRecorded = expectResult(isInverted: true)

        sut.importStarted()
        dataImportCompleted.send()
        await waitForNoResult(notRecorded)

        let recorded = expectResult()
        hasTopLevelEntities = true
        bookmarksChanged.send()

        await fulfillment(of: [recorded], timeout: 1)
        XCTAssertEqual(recordedResults.map(\.result), [.actioned(cooldown: 0)])
    }

    func testWhenImportFromEmptyStateCompletesTwiceThenRecordsOnce() async {
        let sut = makeSUT()
        let recorded = expectResult()

        sut.importStarted()
        hasTopLevelEntities = true
        dataImportCompleted.send()
        dataImportCompleted.send()
        bookmarksChanged.send()
        await fulfillment(of: [recorded], timeout: 1)

        let notRecordedAgain = expectResult(isInverted: true)
        await fulfillment(of: [notRecordedAgain], timeout: 0.2)
        XCTAssertEqual(recordedResults.map(\.result), [.actioned(cooldown: 0)])
    }

    func testWhenImportIsNotStartedFromEmptyStateThenNothingIsRecorded() async {
        let sut = makeSUT()
        let task = await startShowing(sut)
        let notRecorded = expectResult(isInverted: true)

        hasTopLevelEntities = true
        dataImportCompleted.send()
        bookmarksChanged.send()

        await waitForNoResult(notRecorded)
        sut.hide()
        _ = await task.value
    }

    func testWhenEmptyStateImportFinishesWithoutCompletingThenALaterImportIsNotRecorded() async {
        let sut = makeSUT()
        let notRecorded = expectResult(isInverted: true)

        sut.importStarted()
        sut.importFinished()
        hasTopLevelEntities = true
        dataImportCompleted.send()
        bookmarksChanged.send()

        await waitForNoResult(notRecorded)
    }

    func testWhenSyncIsSetUpFromEmptyStateThenRecordsOnceBookmarksAppear() async {
        let sut = makeSUT()
        let notRecorded = expectResult(isInverted: true)

        sut.syncSetupStarted()
        syncService.authState = .active
        await waitForNoResult(notRecorded)

        let recorded = expectResult()
        hasTopLevelEntities = true
        bookmarksChanged.send()

        await fulfillment(of: [recorded], timeout: 1)
        XCTAssertEqual(recordedResults.map(\.result), [.actioned(cooldown: 0)])
    }

    func testWhenSyncIsNotSetUpFromEmptyStateThenNothingIsRecorded() async {
        let sut = makeSUT()
        let task = await startShowing(sut)
        let notRecorded = expectResult(isInverted: true)

        syncService.authState = .active
        hasTopLevelEntities = true
        bookmarksChanged.send()

        await waitForNoResult(notRecorded)
        sut.hide()
        _ = await task.value
    }

    func testWhenEmptyStateSyncSetupFinishesWithoutSyncThenALaterSyncSetupIsNotRecorded() async {
        let sut = makeSUT()
        let notRecorded = expectResult(isInverted: true)

        sut.syncSetupStarted()
        sut.syncSetupFinished()
        syncService.authState = .active
        hasTopLevelEntities = true
        bookmarksChanged.send()

        await waitForNoResult(notRecorded)
    }

    func testWhenBookmarkIsAddedWithoutImportOrSyncThenNothingIsRecorded() async {
        let sut = makeSUT()
        let task = await startShowing(sut)
        let notRecorded = expectResult(isInverted: true)

        hasTopLevelEntities = true
        bookmarksChanged.send()

        await waitForNoResult(notRecorded)
        sut.hide()
        _ = await task.value
    }
}

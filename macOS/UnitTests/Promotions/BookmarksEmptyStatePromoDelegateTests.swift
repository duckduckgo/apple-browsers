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
import FeatureFlags_macOS
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarksEmptyStatePromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var bookmarksChanged: PassthroughSubject<Void, Never>!
    private var bookmarksCount = 0

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueBookmarksEmptyStatePromo]
        bookmarksChanged = PassthroughSubject()
        bookmarksCount = 0
    }

    override func tearDown() {
        bookmarksChanged = nil
        featureFlagger = nil
        super.tearDown()
    }

    // Refreshes eligibility once, as `PromoService` does before reading it.
    private func makeSUT() -> BookmarksEmptyStatePromoDelegate {
        let sut = BookmarksEmptyStatePromoDelegate(
            featureFlagger: featureFlagger,
            bookmarksCountProvider: { [unowned self] in bookmarksCount },
            bookmarksChangedPublisher: bookmarksChanged.eraseToAnyPublisher()
        )
        sut.refreshEligibility()
        return sut
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

    func testWhenThereAreBookmarksThenNotEligible() {
        bookmarksCount = 3

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

        bookmarksCount = 1
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
}

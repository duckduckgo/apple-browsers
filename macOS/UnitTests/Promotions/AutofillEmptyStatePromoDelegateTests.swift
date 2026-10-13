//
//  AutofillEmptyStatePromoDelegateTests.swift
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
final class AutofillEmptyStatePromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var isAnyCategoryEmpty = true

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.promoQueueAutofillEmptyStatePromo]
        isAnyCategoryEmpty = true
    }

    override func tearDown() {
        featureFlagger = nil
        super.tearDown()
    }

    // Refreshes eligibility once, as `PromoService` does before reading it.
    private func makeSUT() -> AutofillEmptyStatePromoDelegate {
        let sut = AutofillEmptyStatePromoDelegate(
            featureFlagger: featureFlagger,
            isAnyCategoryEmptyProvider: { [unowned self] in isAnyCategoryEmpty }
        )
        sut.refreshEligibility()
        return sut
    }

    private func startShowing(_ sut: AutofillEmptyStatePromoDelegate) async -> Task<PromoResult, Never> {
        let activeExpectation = expectation(description: "promo is active")
        let cancellable = sut.isPromoActivePublisher
            .first(where: { $0 })
            .sink { _ in activeExpectation.fulfill() }
        let task = Task { await sut.show(history: PromoHistoryRecord(id: PromoServiceFactory.autofillEmptyStateImportSyncPromoID), force: false) }
        await fulfillment(of: [activeExpectation], timeout: 1)
        cancellable.cancel()
        return task
    }

    // MARK: - Eligibility

    func testWhenACategoryIsEmptyThenEligible() {
        XCTAssertTrue(makeSUT().isEligible)
    }

    func testWhenEveryCategoryHasItemsThenNotEligible() {
        isAnyCategoryEmpty = false

        XCTAssertFalse(makeSUT().isEligible)
    }

    func testWhenKillSwitchIsOffThenNotEligible() {
        featureFlagger.enabledFeatureFlags = []

        XCTAssertFalse(makeSUT().isEligible)
    }

    func testWhenLastEmptyCategoryGetsItemsThenRefreshLosesEligibility() {
        let sut = makeSUT()

        isAnyCategoryEmpty = false
        sut.refreshEligibility()

        XCTAssertFalse(sut.isEligible)
    }

    // MARK: - Display

    func testWhenShownThenPromoIsActive() async {
        let sut = makeSUT()

        let task = await startShowing(sut)

        XCTAssertTrue(sut.isPromoActive)
        sut.hide()
        _ = await task.value
    }

    func testWhenHiddenThenResolvesWithNoChangeAndPromoIsInactive() async {
        let sut = makeSUT()
        let task = await startShowing(sut)

        sut.hide()

        let result = await task.value
        XCTAssertEqual(result, .noChange)
        XCTAssertFalse(sut.isPromoActive)
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

        XCTAssertFalse(sut.isPromoActive)
    }

    // MARK: - Trigger

    func testWhenEmptyStateShownNotificationIsPostedThenPromoTriggerIsEmitted() {
        var triggers: [PromoTrigger] = []
        let cancellable = PromoTrigger.triggerPublisher.sink { triggers.append($0) }

        NotificationCenter.default.post(name: .passwordsPanelEmptyStateShown, object: nil)

        XCTAssertEqual(triggers, [.passwordsPanelEmptyStateShown])
        cancellable.cancel()
    }
}

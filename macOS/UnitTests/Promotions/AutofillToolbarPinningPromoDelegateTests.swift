//
//  AutofillToolbarPinningPromoDelegateTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AutofillToolbarPinningPromoDelegateTests: XCTestCase {

    private static let promoID = "autofill-toolbar-pinning"

    private var featureFlagger: MockFeatureFlagger!
    private var pinningManager: MockPinningManager!
    private var presenter: MockAutofillToolbarPinningPromoPresenter!
    private var sut: AutofillToolbarPinningPromoDelegate!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger(
            featuresStub: [FeatureFlag.promoQueueAutofillToolbarPinningPromo.rawValue: true])
        pinningManager = MockPinningManager()
        presenter = MockAutofillToolbarPinningPromoPresenter()
        sut = makeSUT(presenter: presenter)
    }

    override func tearDown() {
        sut = nil
        presenter = nil
        pinningManager = nil
        featureFlagger = nil
        super.tearDown()
    }

    private func makeSUT(presenter: AutofillToolbarPinningPromoPresenting?) -> AutofillToolbarPinningPromoDelegate {
        AutofillToolbarPinningPromoDelegate(featureFlagger: featureFlagger,
                                            pinningManager: pinningManager,
                                            presenterProvider: { presenter })
    }

    private func record() -> PromoHistoryRecord {
        PromoHistoryRecord(id: Self.promoID)
    }

    // MARK: - Eligibility

    func testWhenFlagOnAndNotPinnedThenEligible() {
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenFlagOffThenNotEligible() {
        featureFlagger.featuresStub = [FeatureFlag.promoQueueAutofillToolbarPinningPromo.rawValue: false]

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenAlreadyPinnedThenNotEligible() {
        pinningManager.pin(.autofill)

        XCTAssertFalse(sut.isEligible)
    }

    // MARK: - Eligibility Publisher

    func testWhenRefreshedWhileEligibleThenPublisherEmitsTrue() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        sut.refreshEligibility()

        cancellable.cancel()
        XCTAssertEqual(received, [false, true])
    }

    func testWhenEligibilityRefreshedAfterPinnedThenPublisherEmitsFalse() {
        sut.refreshEligibility()

        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        pinningManager.pin(.autofill)
        sut.refreshEligibility()

        cancellable.cancel()
        XCTAssertEqual(received, [true, false])
    }

    // MARK: - Resolution paths

    func testWhenShortcutAddedThenResultIsActioned() async {
        presenter.result = .actioned

        let result = await sut.show(history: record(), force: false)

        XCTAssertEqual(result, .actioned)
        XCTAssertEqual(presenter.presentCallCount, 1)
    }

    func testWhenShortcutDeclinedThenResultIsIgnored() async {
        presenter.result = .ignored()

        let result = await sut.show(history: record(), force: false)

        XCTAssertEqual(result, .ignored())
    }

    func testWhenPresenterUnavailableThenShowReturnsNoChange() async {
        sut = makeSUT(presenter: nil)

        let result = await sut.show(history: record(), force: false)

        XCTAssertEqual(result, .noChange)
    }

    func testWhenHiddenAfterResolvingThenResultIsUnchanged() async {
        presenter.result = .actioned
        let result = await sut.show(history: record(), force: false)

        sut.hide()

        XCTAssertEqual(result, .actioned)
        XCTAssertEqual(presenter.retractCallCount, 1)
    }

    func testWhenHiddenWithoutShowingThenNoCrash() {
        sut.hide()

        XCTAssertEqual(presenter.retractCallCount, 1)
    }
}
